// lib/features/auth/rider_login_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../../main.dart';
import '../home/rider_dashboard.dart';

class RiderLoginScreen extends StatefulWidget {
  const RiderLoginScreen({super.key});
  @override State<RiderLoginScreen> createState() => _RiderLoginScreenState();
}

class _RiderLoginScreenState extends State<RiderLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _handleLogin() async {
    final phone = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter both phone number and password');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final data = await supabase
          .from('riders')
          .select()
          .eq('phone', phone)
          .eq('password', password)
          .eq('is_active', true)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Invalid credentials or inactive account. Contact Admin.';
          _loading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rider_id', data['id'].toString());
      await prefs.setString('rider_name', data['full_name']);
      await prefs.setString('rider_password', password);

      OneSignal.login(data['id'].toString());

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RiderDashboard()));
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // High-contrast, premium dark/light backgrounds
    final bgGradient = isDark
        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)])
        : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)]);

    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final primaryBlue = const Color(0xFF3B82F6);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

              // Animated Logo Container
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 40, spreadRadius: 5)
                    ]
                ),
                child: const Icon(Icons.two_wheeler_rounded, size: 64, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(height: 32),
              Text('Rider Portal', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800, color: textColor, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text('Secure login for EzeeWash delivery partners', style: GoogleFonts.inter(color: subtextColor, fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
              const SizedBox(height: 48),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.withOpacity(0.3))),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Glassmorphic Login Card
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 10))]
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                          decoration: InputDecoration(
                            hintText: '+8801XXXXXXXXX',
                            hintStyle: GoogleFonts.inter(color: subtextColor.withOpacity(0.6), fontWeight: FontWeight.normal),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(left: 20, right: 12),
                              child: Icon(Icons.phone_android_rounded, color: subtextColor),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                          ),
                        ),
                        Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2)),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: GoogleFonts.inter(color: subtextColor.withOpacity(0.6), fontWeight: FontWeight.normal),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(left: 20, right: 12),
                              child: Icon(Icons.lock_outline_rounded, color: subtextColor),
                            ),
                            suffixIcon: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: subtextColor),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Premium Login Button
              Container(
                width: double.infinity,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Secure Login', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                      const SizedBox(width: 12),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)
                    ],
                  ),
                ),
              )
            ]),
          ),
        ),
      ),
    );
  }
}