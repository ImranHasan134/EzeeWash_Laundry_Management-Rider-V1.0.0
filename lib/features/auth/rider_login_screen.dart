// lib/features/auth/rider_login_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      // Look for the rider in the database
      final data = await supabase
          .from('riders')
          .select()
          .eq('phone', phone)
          .eq('is_active', true) // Make sure you haven't fired them!
          .maybeSingle();

      if (data == null) {
        setState(() {
          _error = 'Number not found or account is inactive. Contact Admin.';
          _loading = false;
        });
        return;
      }

      // Success! Save their ID so they don't have to log in again
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rider_id', data['id']);
      await prefs.setString('rider_name', data['full_name']);

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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.two_wheeler, size: 48, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(height: 24),
            Text('Rider App', style: GoogleFonts.pacifico(fontSize: 28, color: const Color(0xFF3B82F6))),
            const SizedBox(height: 8),
            Text('Enter your registered phone number to log in', style: GoogleFonts.alexandria(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 32),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                child: Text(_error!, style: GoogleFonts.alexandria(color: Colors.red.shade700, fontSize: 13), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
            ],

            // Phone Input
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '+8801XXXXXXXXX',
                  hintStyle: GoogleFonts.alexandria(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                  prefixIcon: Icon(Icons.phone_android, color: Colors.grey.shade400),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Login Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _loading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: const Color(0xFF3B82F6).withOpacity(0.5),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('Login to Dashboard', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            )
          ]),
        ),
      ),
    );
  }
}