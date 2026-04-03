import 'core/constants/api_keys.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// Import your features (Ensure these paths match your project structure)
import 'features/auth/rider_login_screen.dart';
import 'features/home/rider_dashboard.dart';

// --- Configuration ---
const String supabaseUrl = 'https://xxvicmprwtbxinuluyqx.supabase.co';
const String supabaseAnonKey = 'sb_publishable_RGFSfrrMcY-uqQrFxNCNaw_Z6D6Jmo2';
const String oneSignalAppId = '98573413-e76f-4636-9442-40cce7f1e70e';

// Safe Global Access to Supabase
SupabaseClient get supabase => Supabase.instance.client;

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    // 2. Initialize OneSignal
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(ApiKeys.oneSignalAppId);

    // Request notification permission (Required for Android 13+)
    OneSignal.Notifications.requestPermission(true);

    // 3. Manual Notification Permission Check (Safety backup)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // 4. Check login status via SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final String? riderId = prefs.getString('rider_id');

    // 5. Sync Rider ID with OneSignal for targeted push notifications
    if (riderId != null) {
      OneSignal.login(riderId);
    }

    // 6. Launch App
    runApp(EzeeWashRiderApp(isLoggedIn: riderId != null));

  } catch (e) {
    debugPrint("Fatal Initialization Error: $e");
    // If something fails, we still try to run the app to show an error or login
    runApp(const EzeeWashRiderApp(isLoggedIn: false));
  }
}

class EzeeWashRiderApp extends StatelessWidget {
  final bool isLoggedIn;

  const EzeeWashRiderApp({
    super.key,
    required this.isLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzeeWash Rider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Primary Blue Color for the App
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          primary: const Color(0xFF3B82F6),
        ),
        textTheme: GoogleFonts.alexandriaTextTheme(),
        useMaterial3: true,
      ),
      // Router Logic: Choose starting screen based on login status
      home: isLoggedIn ? const RiderDashboard() : const RiderLoginScreen(),
    );
  }
}