import 'core/constants/api_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// Import your features
import 'features/auth/rider_login_screen.dart';
import 'features/home/rider_dashboard.dart';

const String supabaseUrl = 'https://xxvicmprwtbxinuluyqx.supabase.co';
const String supabaseAnonKey = 'sb_publishable_RGFSfrrMcY-uqQrFxNCNaw_Z6D6Jmo2';

SupabaseClient get supabase => Supabase.instance.client;

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(ApiKeys.oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    final prefs = await SharedPreferences.getInstance();
    final String? riderId = prefs.getString('rider_id');

    if (riderId != null) {
      OneSignal.login(riderId);
    }

    runApp(EzeeWashRiderApp(isLoggedIn: riderId != null));

  } catch (e) {
    debugPrint("Fatal Initialization Error: $e");
    runApp(const EzeeWashRiderApp(isLoggedIn: false));
  }
}

class EzeeWashRiderApp extends StatelessWidget {
  final bool isLoggedIn;

  const EzeeWashRiderApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzeeWash Rider',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system, // Allows root to follow system
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6), primary: const Color(0xFF3B82F6)),
        textTheme: GoogleFonts.alexandriaTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6), brightness: Brightness.dark, primary: const Color(0xFF3B82F6)),
        textTheme: GoogleFonts.alexandriaTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const RiderDashboard() : const RiderLoginScreen(),
    );
  }
}