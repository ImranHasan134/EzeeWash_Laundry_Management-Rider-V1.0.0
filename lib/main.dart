// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/auth/rider_login_screen.dart';
import 'features/home/rider_dashboard.dart';

// TODO: Replace with your credentials
const String supabaseUrl = 'https://xxvicmprwtbxinuluyqx.supabase.co';
const String supabaseAnonKey = 'sb_publishable_RGFSfrrMcY-uqQrFxNCNaw_Z6D6Jmo2';

final supabase = Supabase.instance.client;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Check if a rider ID is already saved on the device
  final prefs = await SharedPreferences.getInstance();
  final riderId = prefs.getString('rider_id');

  runApp(EzeeWashRiderApp(initialRoute: riderId != null ? 'home' : 'login'));
}

class EzeeWashRiderApp extends StatelessWidget {
  final String initialRoute;
  const EzeeWashRiderApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzeeWash Rider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        textTheme: GoogleFonts.alexandriaTextTheme(),
        useMaterial3: true,
      ),
      home: initialRoute == 'home' ? const RiderDashboard() : const RiderLoginScreen(),
    );
  }
}