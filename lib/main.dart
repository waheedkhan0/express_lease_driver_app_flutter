import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const SplashScreen(),
    );
  }
}
