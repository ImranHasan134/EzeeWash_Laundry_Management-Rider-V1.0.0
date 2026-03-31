// lib/main.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'features/auth/rider_login_screen.dart';
import 'features/home/rider_dashboard.dart';

const String supabaseUrl = 'https://xxvicmprwtbxinuluyqx.supabase.co';
const String supabaseAnonKey = 'sb_publishable_RGFSfrrMcY-uqQrFxNCNaw_Z6D6Jmo2';
final supabase = Supabase.instance.client;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // 2. Initialize OneSignal
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("ccdfa117-940d-41fc-8a59-f2043aa3cee8");
  OneSignal.Notifications.requestPermission(true);

  // 3. Check login status
  final prefs = await SharedPreferences.getInstance();
  final riderId = prefs.getString('rider_id');

  // 4. IMPORTANT: If logged in, register this phone with OneSignal!
  if (riderId != null) {
    OneSignal.login(riderId); // Tells OneSignal: "This phone is rider #riderId"
  }

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