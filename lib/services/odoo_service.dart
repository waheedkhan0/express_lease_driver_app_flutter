import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OdooService {
  static const String keyServerUrl = 'odoo_server_url';
  static const String keyDbName = 'odoo_db_name';
  static const String keyUsername = 'odoo_username';
  static const String keyPassword = 'odoo_password';
  static const String keySessionCookie = 'odoo_session_cookie';
  static const String keyDriverName = 'odoo_driver_name';
  static const String keyActiveBikeChassis = 'odoo_active_bike_chassis';
  static const String keyActiveBikeName = 'odoo_active_bike_name';
  static const String keyLastSyncTime = 'odoo_last_sync_time';

  // Singleton instance
  static final OdooService _instance = OdooService._internal();
  factory OdooService() => _instance;
  OdooService._internal();

  /// Logs in the user and stores credentials & session cookie.
  Future<Map<String, dynamic>> login({
    required String serverUrl,
    required String dbName,
    required String username,
    required String password,
  }) async {
    // Standardize URL
    String formattedUrl = serverUrl.trim();
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }
    if (formattedUrl.endsWith('/')) {
      formattedUrl = formattedUrl.substring(0, formattedUrl.length - 1);
    }

    try {
      final loginUrl = Uri.parse('$formattedUrl/web/session/authenticate');
      final response = await http.post(
        loginUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'db': dbName,
            'login': username,
            'password': password,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Server returned status code ${response.statusCode}',
        };
      }

      final body = jsonDecode(response.body);
      if (body['error'] != null) {
        final err = body['error']['data'] ?? body['error'];
        return {
          'success': false,
          'message': err['message'] ?? 'Authentication failed',
        };
      }

      final result = body['result'];
      if (result == null || result['uid'] == null) {
        return {
          'success': false,
          'message': 'Invalid response from Odoo server.',
        };
      }

      // Extract cookie
      String? rawCookie = response.headers['set-cookie'];
      String sessionCookie = '';
      if (rawCookie != null) {
        int index = rawCookie.indexOf('session_id=');
        if (index != -1) {
          int endIndex = rawCookie.indexOf(';', index);
          sessionCookie = endIndex != -1
              ? rawCookie.substring(index, endIndex)
              : rawCookie.substring(index);
        }
      }

      if (sessionCookie.isEmpty) {
        // Fallback: check if we already have it in headers or elsewhere
        return {
          'success': false,
          'message': 'Failed to obtain session cookie from server.',
        };
      }

      // Save credentials in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyServerUrl, formattedUrl);
      await prefs.setString(keyDbName, dbName);
      await prefs.setString(keyUsername, username);
      await prefs.setString(keyPassword, password);
      await prefs.setString(keySessionCookie, sessionCookie);
      await prefs.setString(keyDriverName, result['name'] ?? username);

      return {
        'success': true,
        'driverName': result['name'] ?? username,
        'sessionCookie': sessionCookie,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: ${e.toString()}',
      };
    }
  }

  /// Fetches assigned motorbikes for the logged-in driver.
  Future<Map<String, dynamic>> fetchMyBikes() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString(keyServerUrl);
    final sessionCookie = prefs.getString(keySessionCookie);

    if (serverUrl == null || sessionCookie == null) {
      return {'success': false, 'message': 'Not authenticated.'};
    }

    try {
      final url = Uri.parse('$serverUrl/api/express_lease/my_bikes');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Cookie': sessionCookie,
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Server error: Status ${response.statusCode}',
        };
      }

      final body = jsonDecode(response.body);
      if (body['error'] != null) {
        return {
          'success': false,
          'message': body['error']['message'] ?? 'Failed to fetch motorbikes.',
        };
      }

      final result = body['result'];
      if (result == null) {
        return {
          'success': false,
          'message': 'Null response returned.',
        };
      }

      if (result['status'] == 'error') {
        return {
          'success': false,
          'message': result['message'] ?? 'An error occurred.',
        };
      }

      final bikes = result['bikes'] as List<dynamic>? ?? [];
      final driverName = result['driver_name'] ?? '';

      if (driverName.isNotEmpty) {
        await prefs.setString(keyDriverName, driverName);
      }

      return {
        'success': true,
        'driverName': driverName,
        'bikes': bikes,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to load bikes: ${e.toString()}',
      };
    }
  }

  /// Sends the current location to Odoo. Can be called from foreground or background.
  static Future<bool> updateLocationStatic({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString(keyServerUrl);
      final sessionCookie = prefs.getString(keySessionCookie);
      final chassis = prefs.getString(keyActiveBikeChassis);

      if (serverUrl == null || sessionCookie == null || chassis == null) {
        return false;
      }

      final url = Uri.parse('$serverUrl/api/express_lease/update_location');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Cookie': sessionCookie,
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'chassis_number': chassis,
            'latitude': latitude,
            'longitude': longitude,
          },
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final result = body['result'];
        if (result != null && result['status'] == 'success') {
          await prefs.setString(keyLastSyncTime, DateTime.now().toIso8601String());
          return true;
        }
      }
      return false;
    } catch (e) {
      // Log to system console in background service
      developer.log('OdooService.updateLocationStatic background error: $e');
      return false;
    }
  }

  /// Check if the user is authenticated.
  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(keySessionCookie) && prefs.getString(keySessionCookie) != null;
  }

  /// Selects the active bike for tracking.
  Future<void> setActiveBike(Map<String, dynamic> bike) async {
    final prefs = await SharedPreferences.getInstance();
    final chassis = bike['chassis_number'] ?? '';
    final name = "${bike['brand']} ${bike['model_name']} - ${bike['registration_number'] ?? chassis}";
    await prefs.setString(keyActiveBikeChassis, chassis);
    await prefs.setString(keyActiveBikeName, name);
    await prefs.setString('active_bike_json', jsonEncode(bike));
  }

  /// Log out and clear saved session.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Attempt standard Odoo session destruction (best effort)
    final serverUrl = prefs.getString(keyServerUrl);
    final sessionCookie = prefs.getString(keySessionCookie);
    if (serverUrl != null && sessionCookie != null) {
      try {
        final url = Uri.parse('$serverUrl/web/session/destroy');
        await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Cookie': sessionCookie,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {},
          }),
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    // Clear preferences related to auth and session
    await prefs.remove(keySessionCookie);
    await prefs.remove(keyDriverName);
    await prefs.remove(keyActiveBikeChassis);
    await prefs.remove(keyActiveBikeName);
    await prefs.remove('active_bike_json');
    await prefs.remove(keyLastSyncTime);
  }
}
