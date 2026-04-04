// lib/features/auth/rider_login_screen.dart
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
  bool _loading = false;
  String? _error;

  Future<void> _handleLogin() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Please enter your phone number');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final data = await supabase
          .from('riders')
          .select()
          .eq('phone', phone)
          .eq('is_active', true)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Number not found or account is inactive. Contact Admin.';
          _loading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rider_id', data['id'].toString());
      await prefs.setString('rider_name', data['full_name']);

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
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Modern Floating Icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.15), blurRadius: 30, spreadRadius: 10)
                  ]
              ),
              child: const Icon(Icons.two_wheeler_rounded, size: 56, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(height: 32),
            Text('Rider Portal', style: GoogleFonts.alexandria(fontSize: 28, fontWeight: FontWeight.w800, color: textColor)),
            const SizedBox(height: 8),
            Text('Sign in to view your deliveries', style: GoogleFonts.alexandria(color: subtextColor, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 40),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_error!, style: GoogleFonts.alexandria(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Input Field
            Container(
              decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.04), blurRadius: 20, offset: const Offset(0, 8))]
              ),
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                decoration: InputDecoration(
                  hintText: '+8801XXXXXXXXX',
                  hintStyle: GoogleFonts.alexandria(color: subtextColor.withOpacity(0.5), fontWeight: FontWeight.normal),
                  prefixIcon: Icon(Icons.phone_android_rounded, color: subtextColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Modern Gradient Button
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: ElevatedButton(
                onPressed: _loading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : Text('Login to Dashboard', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            )
          ]),
        ),
      ),
    );
  }
}