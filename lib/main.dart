import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/location_service.dart';
import 'services/odoo_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background location tracking service
  await LocationService.initializeService();
  
  // Check if driver is already authenticated
  final odoo = OdooService();
  final isAuth = await odoo.isAuthenticated();

  runApp(MyApp(isAuth: isAuth));
}

class MyApp extends StatelessWidget {
  final bool isAuth;
  const MyApp({super.key, required this.isAuth});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Express Lease Driver App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        primaryColor: const Color(0xFF0EA5E9), // Sky 500
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0EA5E9),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Inter', // Sleek modern typography style
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF020617),
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: isAuth ? const HomeScreen() : const LoginScreen(),
    );
  }
}
