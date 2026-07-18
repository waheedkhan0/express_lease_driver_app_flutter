import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController(text: 'https://expresslease.quicksol.ca');
  final _dbController = TextEditingController(text: 'db2');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _serverController.dispose();
    _dbController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final odoo = OdooService();
    final result = await odoo.login(
      serverUrl: _serverController.text,
      dbName: _dbController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Authentication failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0F172A), // Slate 900
              Color(0xFF1E293B), // Slate 800
              Color(0xFF020617), // Slate 950
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Logo Area
                    Image.asset(
                      'assets/icon/express_lease_logo.png',
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'EXPRESS LEASE',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'MOTORCYCLES RENTAL LLC',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8), // Slate 400
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Driver Companion',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0x26EF4444), // Red 500 with 15% opacity
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x4DEF4444)), // Red 500 with 30% opacity
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Server URL Input
                    _buildTextField(
                      controller: _serverController,
                      label: 'Odoo Server URL',
                      hint: 'e.g. https://expresslease.ae or IP:PORT',
                      icon: Icons.dns,
                      keyboardType: TextInputType.url,
                      validator: (v) => v!.isEmpty ? 'Enter Odoo server URL' : null,
                    ),
                    const SizedBox(height: 16),

                    // Database Name Input
                    _buildTextField(
                      controller: _dbController,
                      label: 'Database Name',
                      hint: 'e.g. express_lease_db',
                      icon: Icons.storage,
                      validator: (v) => v!.isEmpty ? 'Enter database name' : null,
                    ),
                    const SizedBox(height: 16),

                    // Username Input
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Username / Email',
                      hint: 'e.g. driver1@expresslease.ae',
                      icon: Icons.person,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v!.isEmpty ? 'Enter username or email' : null,
                    ),
                    const SizedBox(height: 16),

                    // Password Input
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        hintText: 'Enter your password',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.lock, color: Color(0xFF38BDF8)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF64748B),
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 30),

                    // Submit Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF0EA5E9), // Sky 500
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                        shadowColor: const Color(0x660EA5E9), // Sky 500 with 40% opacity
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'AUTHENTICATE',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        prefixIcon: Icon(icon, color: const Color(0xFF38BDF8)),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}
