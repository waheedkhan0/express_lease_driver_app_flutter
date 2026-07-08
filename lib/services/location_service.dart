import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'odoo_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// Check and request all necessary permissions for foreground and background location tracking.
  Future<bool> requestPermissions(BuildContext context) async {
    // 1. Request Notification permission (required for foreground service on Android 13+)
    if (await Permission.notification.isDenied) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        return false;
      }
    }

    // 2. Check location service status
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable GPS/location services on your device.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }

    // 3. Request Foreground Location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. Please enable them in settings.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }

    // 4. Request Background Location permission (required for background tracking)
    // On Android 10+ and iOS, background location is required to receive updates when app is minimized.
    if (permission == LocationPermission.always) {
      return true;
    }

    // If it is 'whileInUse', we try to request 'always'
    if (await Permission.locationAlways.isDenied) {
      final status = await Permission.locationAlways.request();
      return status.isGranted;
    }

    return true;
  }

  /// Initialize background service configuration. Should be called in main.dart.
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'express_lease_tracking_channel', // id
      'Express Lease Location Tracking', // title
      description: 'Used for persistent foreground tracking service of vehicles.', // description
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    // Create notifications channel for Android foreground service
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true, // Auto-start service on boot/app launch
        isForegroundMode: true,
        notificationChannelId: 'express_lease_tracking_channel',
        initialNotificationTitle: 'EXPRESS LEASE MOTORCYCLES RENTAL',
        initialNotificationContent: 'Preparing vehicle location tracking...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true, // Auto-start service on iOS
        onForeground: onStart,
        onBackground: onStart,
      ),
    );
  }

  /// Start background tracking service
  Future<bool> startTracking() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    if (!isRunning) {
      return await service.startService();
    }
    return true;
  }

  /// Stop background tracking service
  Future<void> stopTracking() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
    }
  }

  /// Check if tracking service is currently running
  Future<bool> isTrackingRunning() async {
    return await FlutterBackgroundService().isRunning();
  }
}

/// Top-level background entry point callback. Executed in background isolate.
@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async {
  // Ensure Flutter engine is bound
  DartPluginRegistrant.ensureInitialized();

  // Setup stop and state handlers
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Track location periodically
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final chassis = prefs.getString(OdooService.keyActiveBikeChassis);
    final bikeName = prefs.getString(OdooService.keyActiveBikeName) ?? 'Motorbike';

    // If no active bike is set, do nothing and wait
    if (chassis == null) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: "EXPRESS LEASE Rental LLC",
          content: "Tracking active, but no motorbike is selected.",
        );
      }
      return;
    }

    try {
      // 1. Get GPS coordinates
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _notifyUI(service, success: false, msg: "GPS is disabled on device.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _notifyUI(service, success: false, msg: "Location permissions denied.");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      // 2. Post coordinates to Odoo server
      bool isSuccess = await OdooService.updateLocationStatic(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      // 3. Update persistent notification message
      if (service is AndroidServiceInstance) {
        final now = DateTime.now();
        final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
        
        if (isSuccess) {
          service.setForegroundNotificationInfo(
            title: "Tracking: $bikeName",
            content: "Last location update synced successfully at $timeStr",
          );
        } else {
          service.setForegroundNotificationInfo(
            title: "Tracking: $bikeName (Offline)",
            content: "Failed to sync location to Odoo. Last retry at $timeStr",
          );
        }
      }

      // 4. Send update to UI
      _notifyUI(
        service,
        success: isSuccess,
        lat: position.latitude,
        lng: position.longitude,
      );
    } catch (e) {
      developer.log("Background location tracking error: $e");
      _notifyUI(service, success: false, msg: "Error: ${e.toString()}");
    }
  });

  return true;
}

/// Helper to communicate service results to foreground UI.
void _notifyUI(
  ServiceInstance service, {
  required bool success,
  double? lat,
  double? lng,
  String? msg,
}) {
  service.invoke(
    'update',
    {
      'latitude': lat,
      'longitude': lng,
      'success': success,
      'message': msg,
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}
