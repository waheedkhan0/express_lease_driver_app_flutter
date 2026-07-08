import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/odoo_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _odoo = OdooService();
  final _location = LocationService();
  
  String _driverName = 'Driver';
  List<dynamic> _myBikes = [];
  Map<String, dynamic>? _selectedBike;
  
  bool _isLoadingBikes = false;
  bool _isTrackingActive = false;
  
  // Real-time tracking data from background service
  double? _liveLatitude;
  double? _liveLongitude;
  String? _lastSyncTime;
  bool _lastSyncSuccess = false;
  String _statusMessage = 'Service idle. Click Start Tracking to begin.';

  StreamSubscription? _backgroundSubscription;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadLocalInfo();
    _fetchBikesFromOdoo();
    _checkServiceStatus();
    _setupBackgroundListener();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _backgroundSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _driverName = prefs.getString(OdooService.keyDriverName) ?? 'Driver';
      final bikeJson = prefs.getString('active_bike_json');
      if (bikeJson != null) {
        try {
          _selectedBike = Map<String, dynamic>.from(jsonDecode(bikeJson));
        } catch (_) {
          _loadSelectedBikeFallback(prefs);
        }
      } else {
        _loadSelectedBikeFallback(prefs);
      }
    });
  }

  void _loadSelectedBikeFallback(SharedPreferences prefs) {
    final activeChassis = prefs.getString(OdooService.keyActiveBikeChassis);
    final activeName = prefs.getString(OdooService.keyActiveBikeName);
    if (activeChassis != null && activeName != null) {
      _selectedBike = {
        'chassis_number': activeChassis,
        'registration_number': activeName.split(' - ').last,
        'name': activeName.split(' - ').first,
        'brand': activeName.split(' - ').first.split(' ').first,
        'model_name': activeName.split(' - ').first.split(' ').skip(1).join(' '),
      };
    }
  }

  Future<void> _checkServiceStatus() async {
    bool running = await _location.isTrackingRunning();
    setState(() {
      _isTrackingActive = running;
      if (running) {
        _pulseController.repeat(reverse: true);
        _statusMessage = 'Tracking motorbike location...';
      } else {
        _pulseController.stop();
        _statusMessage = 'Service idle. Click Start Tracking to begin.';
      }
    });
  }

  void _setupBackgroundListener() {
    _backgroundSubscription = FlutterBackgroundService().on('update').listen((event) {
      if (event != null) {
        setState(() {
          _liveLatitude = event['latitude'];
          _liveLongitude = event['longitude'];
          _lastSyncSuccess = event['success'] ?? false;
          _statusMessage = event['message'] ?? 
              (_lastSyncSuccess 
                  ? 'Location successfully synchronized with Odoo' 
                  : 'Failed to sync location to Odoo (offline)');
          
          if (event['timestamp'] != null) {
            final parsed = DateTime.tryParse(event['timestamp']);
            if (parsed != null) {
              _lastSyncTime = "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}:${parsed.second.toString().padLeft(2, '0')}";
            }
          }
        });
      }
    });
  }

  Future<void> _fetchBikesFromOdoo() async {
    setState(() {
      _isLoadingBikes = true;
    });

    final res = await _odoo.fetchMyBikes();
    
    setState(() {
      _isLoadingBikes = false;
    });

    if (res['success'] == true) {
      setState(() {
        _myBikes = res['bikes'] ?? [];
        _driverName = res['driverName'] ?? _driverName;
        
        // If there are bikes and none selected yet, auto-select the first one
        if (_myBikes.isNotEmpty && _selectedBike == null) {
          _selectBike(_myBikes.first);
        }
      });
    }
  }

  void _selectBike(Map<String, dynamic> bike) async {
    setState(() {
      _selectedBike = bike;
    });
    
    final bikeDisplayName = "${bike['brand']} ${bike['model_name']} - ${bike['registration_number'] ?? bike['chassis_number']}";
    await _odoo.setActiveBike(bike);

    // If tracking is active, restart service to pick up the new bike chassis
    if (_isTrackingActive) {
      await _location.stopTracking();
      await _location.startTracking();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched tracking to: $bikeDisplayName'),
          backgroundColor: const Color(0xFF0EA5E9),
        ),
      );
    }
  }

  Future<void> _toggleTracking() async {
    if (_selectedBike == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a motorbike first.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    if (_isTrackingActive) {
      // Stop tracking
      await _location.stopTracking();
      setState(() {
        _isTrackingActive = false;
        _pulseController.stop();
        _liveLatitude = null;
        _liveLongitude = null;
        _statusMessage = 'Location tracking stopped.';
      });
    } else {
      // Start tracking - request location permissions first
      bool hasPermission = await _location.requestPermissions(context);
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are required to start tracking.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      bool started = await _location.startTracking();
      if (started) {
        setState(() {
          _isTrackingActive = true;
          _pulseController.repeat(reverse: true);
          _statusMessage = 'Tracking active, fetching coordinates...';
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    // 1. Confirm logout
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Log Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to log out? This will stop any active location tracking.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('LOG OUT', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // 2. Stop tracking service
    await _location.stopTracking();

    // 3. Clear session
    await _odoo.logout();

    // 4. Navigate to Login
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        elevation: 0,
        title: const Text(
          'EXPRESS LEASE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF38BDF8)),
            onPressed: _isLoadingBikes ? null : _fetchBikesFromOdoo,
            tooltip: 'Sync Motorbikes',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFF87171)),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF334155)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000), // 20% opacity black
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0x260EA5E9), // 15% opacity sky
                      child: const Icon(Icons.person, size: 32, color: Color(0xFF38BDF8)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WELCOME BACK,',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            _driverName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Motorbike Selection Dropdown Card
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.motorcycle, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ACTIVE MOTORBIKE',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _isLoadingBikes
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      dropdownColor: const Color(0xFF1E293B),
                                      hint: const Text(
                                        'Select assigned bike',
                                        style: TextStyle(color: Color(0xFF64748B)),
                                      ),
                                      value: _selectedBike != null &&
                                              _myBikes.any((b) =>
                                                  b['chassis_number'] ==
                                                  _selectedBike!['chassis_number'])
                                          ? _selectedBike!['chassis_number']
                                          : null,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      isExpanded: true,
                                      items: _myBikes.map<DropdownMenuItem<String>>((dynamic bike) {
                                        final brand = _safeOdooString(bike['brand']);
                                        final model = _safeOdooString(bike['model_name']);
                                        final reg = _safeOdooString(bike['registration_number'], fallback: 'No Plate');
                                        final disp = "$brand $model ($reg)";
                                        return DropdownMenuItem<String>(
                                          value: _safeOdooString(bike['chassis_number']),
                                          child: Text(
                                            disp,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (String? newChassis) {
                                        if (newChassis != null) {
                                          final chosenBike = _myBikes.firstWhere(
                                            (b) => b['chassis_number'] == newChassis,
                                          );
                                          _selectBike(Map<String, dynamic>.from(chosenBike));
                                        }
                                      },
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Vehicle Details Card if a bike is selected
              if (_selectedBike != null) ...[
                Card(
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'VEHICLE DETAILS',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            if (_selectedBike!['state'] != null && _selectedBike!['state'] != false)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _selectedBike!['state'] == 'available'
                                      ? const Color(0x2610B981)
                                      : _selectedBike!['state'] == 'leased'
                                          ? const Color(0x260EA5E9)
                                          : const Color(0x26F59E0B),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedBike!['state'] == 'available'
                                        ? const Color(0xFF10B981)
                                        : _selectedBike!['state'] == 'leased'
                                            ? const Color(0xFF0EA5E9)
                                            : const Color(0xFFF59E0B),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  _selectedBike!['state'].toString().toUpperCase(),
                                  style: TextStyle(
                                    color: _selectedBike!['state'] == 'available'
                                        ? const Color(0xFF34D399)
                                        : _selectedBike!['state'] == 'leased'
                                            ? const Color(0xFF38BDF8)
                                            : const Color(0xFFFBBF24),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Divider(color: Color(0x1FFFFFFF), height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDetailRow(
                                label: 'BRAND / MODEL',
                                value: "${_safeOdooString(_selectedBike!['brand'])} ${_safeOdooString(_selectedBike!['model_name'])}".trim().toUpperCase(),
                                icon: Icons.motorcycle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDetailRow(
                                label: 'REGISTRATION NO',
                                value: _safeOdooString(_selectedBike!['registration_number'], fallback: 'N/A'),
                                icon: Icons.badge,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildDetailRow(
                                label: 'CHASSIS NUMBER',
                                value: _safeOdooString(_selectedBike!['chassis_number'], fallback: 'N/A'),
                                icon: Icons.fingerprint,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Visual pulsing radar & Live Tracker Panel
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isTrackingActive 
                        ? const Color(0x4D38BDF8) // 30% opacity sky
                        : const Color(0x0DFFFFFF), // 5% opacity white
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    // Radar ring pulse (micro-animation)
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0F172A),
                            boxShadow: _isTrackingActive
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF38BDF8).withValues(alpha: 0.1 * (1 - _pulseController.value)),
                                      blurRadius: 20 + 30 * _pulseController.value,
                                      spreadRadius: 10 + 20 * _pulseController.value,
                                    ),
                                    const BoxShadow(
                                      color: Color(0x2638BDF8), // 15% opacity sky
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _isTrackingActive ? Icons.radar : Icons.location_off,
                            size: 64,
                            color: _isTrackingActive 
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF64748B),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    // Tracking status pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isTrackingActive
                            ? const Color(0x2610B981) // 15% opacity Emerald
                            : const Color(0x2664748B), // 15% opacity Slate
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isTrackingActive
                              ? const Color(0x6610B981) // 40% opacity Emerald
                              : const Color(0x4D64748B), // 30% opacity Slate
                        ),
                      ),
                      child: Text(
                        _isTrackingActive ? 'LIVE TRACKING ACTIVE' : 'TRACKING PAUSED',
                        style: TextStyle(
                          color: _isTrackingActive 
                              ? const Color(0xFF34D399) // Emerald 400
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Digital Dashboard Coordinates
                    Row(
                      children: [
                        Expanded(
                          child: _buildDashboardMetric(
                            label: 'LATITUDE',
                            value: _liveLatitude != null 
                                ? _liveLatitude!.toStringAsFixed(6) 
                                : '--.------',
                            icon: Icons.explore,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDashboardMetric(
                            label: 'LONGITUDE',
                            value: _liveLongitude != null 
                                ? _liveLongitude!.toStringAsFixed(6) 
                                : '--.------',
                            icon: Icons.explore,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDashboardMetric(
                            label: 'LAST SYNC TIME',
                            value: _lastSyncTime ?? '--:--:--',
                            icon: Icons.sync,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDashboardMetric(
                            label: 'SYNC STATUS',
                            value: _lastSyncTime == null 
                                ? 'No updates yet' 
                                : (_lastSyncSuccess ? 'SUCCESS' : 'OFFLINE'),
                            valueColor: _lastSyncTime == null
                                ? const Color(0xFF94A3B8)
                                : (_lastSyncSuccess ? const Color(0xFF34D399) : const Color(0xFFF87171)),
                            icon: Icons.cloud_done,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Tracking Action Button
              ElevatedButton(
                onPressed: _toggleTracking,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: _isTrackingActive
                      ? const Color(0xFFEF4444) // Red 500
                      : const Color(0xFF0EA5E9), // Sky 500
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 6,
                  shadowColor: _isTrackingActive 
                      ? const Color(0x4DEF4444) // 30% opacity red
                      : const Color(0x4D0EA5E9), // 30% opacity sky
                ),
                child: Text(
                  _isTrackingActive ? 'STOP LOCATION TRACKING' : 'START LOCATION TRACKING',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Network Status Logs
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  String _safeOdooString(dynamic value, {String fallback = ''}) {
    if (value == null || value == false) return fallback;
    return value.toString();
  }

  Widget _buildDashboardMetric({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Slate 950/900
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x08FFFFFF)), // 3% opacity white
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.white,
              fontFamily: 'Courier', // monospaced style for values
            ),
          ),
        ],
      ),
    );
  }
}
