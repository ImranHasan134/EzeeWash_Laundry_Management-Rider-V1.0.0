import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  final _supabase = Supabase.instance.client;

  void startTracking() async {
    // 1. Check Permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 2. Define how often to update (Battery vs Accuracy)
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Updates only when rider moves 10 meters
    );

    // 3. Start the continuous stream
    Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
        _updateLocationInSupabase(position);
      },
      onError: (e) => print("Location Stream Error: $e"),
    );
  }

  Future<void> _updateLocationInSupabase(Position pos) async {
    final riderId = _supabase.auth.currentUser?.id;
    if (riderId == null) return;

    try {
      await _supabase.from('riders').update({
        'current_lat': pos.latitude,
        'current_lng': pos.longitude,
        'last_location_update': DateTime.now().toIso8601String(),
      }).eq('id', riderId);

      print("Location Pushed: ${pos.latitude}, ${pos.longitude}");
    } catch (e) {
      print("Error pushing location: $e");
    }
  }
}