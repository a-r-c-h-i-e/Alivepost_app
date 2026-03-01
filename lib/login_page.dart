import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'main.dart';
import 'dart:ui';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _mobileController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  static const Color _primaryColor = Color(0xFF10B981); // Health app green
  static const Color _bgColor = Color(0xFFFDFBF7); // Soft beige

  Future<void> _login() async {
    final mobileNumber = _mobileController.text.trim();
    if (mobileNumber.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your mobile number';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('https://api.alivepost.com/api/prescriptions/patient/$mobileNumber');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('mobileNumber', mobileNumber);
        await prefs.setString('user_data', response.body);

        if (mounted) {
           Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Login failed. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please check your connection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Animated Background Blobs
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryColor.withValues(alpha: 0.1),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scaleXY(end: 1.2, duration: 4.seconds, curve: Curves.easeInOutSine)
             .move(duration: 5.seconds, curve: Curves.easeInOutSine),
          ),
          Positioned(
            bottom: -50,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryColor.withValues(alpha: 0.08),
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .scaleXY(end: 1.15, duration: 6.seconds, curve: Curves.easeInOutSine)
             .move(duration: 4.seconds, curve: Curves.easeInOutSine),
          ),
          
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 80),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Floating Hero SVG
                        Center(
                          child: SvgPicture.asset(
                            'assets/login.svg',
                            height: 220,
                          ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                           .moveY(begin: -8, end: 8, duration: 2.seconds, curve: Curves.easeInOut)
                           .scaleXY(begin: 1.0, end: 1.02, duration: 2.5.seconds, curve: Curves.easeInOut),
                        ).animate().fadeIn(duration: 800.ms).scale(curve: Curves.easeOutBack, duration: 800.ms),
                        
                        const SizedBox(height: 48),
                        
                        // Texts
                        Text(
                          'Welcome Back',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: const Color(0xFF1E293B), // Slate 800
                          ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 200.ms, duration: 600.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
                        
                        const SizedBox(height: 12),
                        
                        Text(
                          'Enter your mobile number to access your health records',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF64748B), // Slate 500
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
                        
                        const SizedBox(height: 40),
                        
                        // Glassmorphic Input Form
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 20,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _mobileController,
                                    keyboardType: TextInputType.phone,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                    decoration: InputDecoration(
                                      labelText: 'Mobile Number',
                                      labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                                      hintText: 'e.g. +1 234 567 8900',
                                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                                      prefixIcon: Container(
                                        padding: const EdgeInsets.all(12),
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: _primaryColor.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.phone_android_rounded, color: _primaryColor, size: 20),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(color: _primaryColor, width: 2),
                                      ),
                                      errorText: _errorMessage,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  
                                  // Login Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryColor,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ).copyWith(
                                        overlayColor: WidgetStateProperty.resolveWith((states) {
                                          if (states.contains(WidgetState.pressed)) {
                                            return Colors.white.withValues(alpha: 0.1); // Add ripple effect
                                          }
                                          return null;
                                        })
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Text(
                                              'Continue',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                    ),
                                  ).animate(target: _isLoading ? 0 : 1).shimmer(duration: 2.seconds, delay: 2.seconds, color: Colors.white24),
                                ],
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: 500.ms, duration: 600.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad),
                        
                        const SizedBox(height: 32),
                        
                        // Footer terms
                        Text(
                          'By proceeding, you agree to our Terms & Conditions',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8), // Slate 400
                          ),
                          textAlign: TextAlign.center,
                        ).animate().fadeIn(delay: 700.ms, duration: 600.ms),
                      ],
                    ),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}
