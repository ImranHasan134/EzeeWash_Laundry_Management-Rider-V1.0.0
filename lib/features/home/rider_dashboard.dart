// lib/features/home/rider_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart';
import '../auth/rider_login_screen.dart';
import '../orders/screens/rider_order_details_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});
  @override State<RiderDashboard> createState() => _RiderDashboardState();
}

class _RiderDashboardState extends State<RiderDashboard> with WidgetsBindingObserver {
  int _currentIndex = 0;
  String _riderId = '';
  Map<String, dynamic>? _riderProfile;

  bool _isOnline = false;
  bool _loading = true;

  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _historyOrders = [];

  RealtimeChannel? _channel;
  StreamSubscription<Position>? _positionStream;

  // ─── NEW: TRIP ANALYTICS VARIABLES ───
  int _todayTrips = 0;
  int _thisMonthTrips = 0;
  int _allTimeTrips = 0;
  int _pickupOnlyCount = 0;
  int _deliveryOnlyCount = 0;
  int _roundTripCount = 0;

  final Color _primaryBlue = const Color(0xFF3B82F6);
  final Color _bgColor = const Color(0xFFF8FAFC);
  final Color _textColor = const Color(0xFF1E293B);
  final Color _subtextColor = const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDashboard();

    OneSignal.Notifications.addClickListener((event) {
      if (mounted) {
        _fetchRiderProfile();
        _fetchOrders();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.unsubscribe();
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted && _riderId.isNotEmpty) {
        _fetchRiderProfile();
        _fetchOrders();
      }
    }
  }

  Future<void> _initDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    _riderId = prefs.getString('rider_id') ?? '';

    if (_riderId.isEmpty) {
      _logout();
      return;
    }

    await Future.wait([
      _fetchRiderProfile(),
      _fetchOrders(),
    ]);

    _setupRealtime();

    if (_isOnline) {
      _startLocationTracking();
    }
  }

  // ─── THE NEW TRIP CALCULATION LOGIC ────────────────────────────────────────

  void _calculateTripStats() {
    _todayTrips = 0; _thisMonthTrips = 0; _allTimeTrips = 0;
    _pickupOnlyCount = 0; _deliveryOnlyCount = 0; _roundTripCount = 0;

    final now = DateTime.now();
    final allMyOrders = [..._activeOrders, ..._historyOrders];

    for (var order in allMyOrders) {
      // 1. Identify what role the rider played
      bool didPickup = order['pickup_rider_id'] == _riderId || order['rider_id'] == _riderId;
      bool didDelivery = order['delivery_rider_id'] == _riderId || order['rider_id'] == _riderId;

      String status = order['status'] ?? '';

      // 2. Check if the task was actually completed
      // Pickup is done when status is past 'picked_up'
      bool pickupCompleted = didPickup && ['in_process', 'ready', 'out_for_delivery', 'delivered'].contains(status);
      // Delivery is done when status is 'delivered'
      bool deliveryCompleted = didDelivery && status == 'delivered';

      int pointsEarnedForThisOrder = 0;

      // 3. Determine the point value and categorize
      if (pickupCompleted && deliveryCompleted) {
        _roundTripCount++;
        pointsEarnedForThisOrder = 2; // Round Trip = 2 Points
      } else if (pickupCompleted && !didDelivery) {
        _pickupOnlyCount++;
        pointsEarnedForThisOrder = 1; // Pickup Only = 1 Point
      } else if (!didPickup && deliveryCompleted) {
        _deliveryOnlyCount++;
        pointsEarnedForThisOrder = 1; // Delivery Only = 1 Point
      } else if (pickupCompleted && didDelivery && !deliveryCompleted) {
        // Edge case: They did the pickup, and are assigned the delivery, but haven't delivered yet.
        pointsEarnedForThisOrder = 1; // Give them the 1 point for the pickup now
      }

      _allTimeTrips += pointsEarnedForThisOrder;

      // 4. Date Filtering for Salary calculation
      if (order['updated_at'] != null) {
        DateTime updatedAt = DateTime.parse(order['updated_at']).toLocal();

        // Today's Points (For Daily Salary)
        if (updatedAt.year == now.year && updatedAt.month == now.month && updatedAt.day == now.day) {
          _todayTrips += pointsEarnedForThisOrder;
        }

        // This Month's Points
        if (updatedAt.year == now.year && updatedAt.month == now.month) {
          _thisMonthTrips += pointsEarnedForThisOrder;
        }
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.')));
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied.')));
      return false;
    }
    return true;
  }

  void _startLocationTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      setState(() => _isOnline = false);
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position position) {
      _updateLiveLocationInDb(position);
    });
  }

  void _stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  Future<void> _updateLiveLocationInDb(Position position) async {
    if (_activeOrders.isEmpty) return;

    try {
      for (var order in _activeOrders) {
        final existing = await supabase.from('rider_locations').select('id').eq('order_id', order['id']).maybeSingle();

        if (existing != null) {
          await supabase.from('rider_locations').update({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', existing['id']);
        } else {
          await supabase.from('rider_locations').insert({
            'rider_id': _riderId,
            'order_id': order['id'],
            'latitude': position.latitude,
            'longitude': position.longitude,
          });
        }
      }
    } catch (e) {
      debugPrint('Error pushing live location: $e');
    }
  }

  Future<void> _openGoogleMaps(Map<String, dynamic> order) async {
    final lat = order['latitude'] ?? order['pickup_lat'];
    final lng = order['longitude'] ?? order['pickup_lng'];
    final address = order['pickup_address'] ?? '';

    Uri url;
    if (lat != null && lng != null) {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      final encodedAddress = Uri.encodeComponent(address);
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    }

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Maps.')));
    }
  }

  Future<void> _fetchRiderProfile() async {
    try {
      final data = await supabase.from('riders').select().eq('id', _riderId).single();
      if (mounted) {
        setState(() {
          _riderProfile = data;
          _isOnline = data['is_online'] ?? false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  Future<void> _fetchOrders() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('orders')
          .select('*, profiles(full_name, phone)')
          .or('rider_id.eq.$_riderId,pickup_rider_id.eq.$_riderId,delivery_rider_id.eq.$_riderId')
          .order('updated_at', ascending: false);

      final allOrders = List<Map<String, dynamic>>.from(data);

      if (mounted) {
        setState(() {
          // STRICT ACTIVE LOGIC
          _activeOrders = allOrders.where((o) {
            bool isMyPickup = (o['pickup_rider_id'] == _riderId || o['rider_id'] == _riderId) && o['status'] == 'picked_up';
            bool isMyDelivery = (o['delivery_rider_id'] == _riderId || o['rider_id'] == _riderId) && o['status'] == 'out_for_delivery';
            return isMyPickup || isMyDelivery;
          }).toList();

          // HISTORY LOGIC (Involved, but not currently active for me)
          _historyOrders = allOrders.where((o) {
            bool involved = o['pickup_rider_id'] == _riderId || o['delivery_rider_id'] == _riderId || o['rider_id'] == _riderId;
            bool isActive = (o['pickup_rider_id'] == _riderId || o['rider_id'] == _riderId) && o['status'] == 'picked_up' ||
                (o['delivery_rider_id'] == _riderId || o['rider_id'] == _riderId) && o['status'] == 'out_for_delivery';
            return involved && !isActive;
          }).toList();

          _calculateTripStats();
          _loading = false;
        });

        if (_isOnline && _activeOrders.isNotEmpty) {
          Geolocator.getCurrentPosition().then((pos) => _updateLiveLocationInDb(pos));
        }
      }
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setupRealtime() {
    _channel = supabase.channel('public:orders')
        .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (payload) {
          if (payload.newRecord != null) {
            final newRecord = payload.newRecord!;

            final rId = newRecord['rider_id']?.toString() ?? '';
            final pId = newRecord['pickup_rider_id']?.toString() ?? '';
            final dId = newRecord['delivery_rider_id']?.toString() ?? '';
            final status = newRecord['status']?.toString().toLowerCase() ?? '';

            // STRICT REALTIME NOTIFICATION LOGIC
            bool isMyPickup = (pId == _riderId || rId == _riderId) && status == 'picked_up';
            bool isMyDelivery = (dId == _riderId || rId == _riderId) && status == 'out_for_delivery';

            if (isMyPickup || isMyDelivery) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🏍️ Task Updated: ${newRecord['order_number']?.toString() ?? 'Update'}'),
                    backgroundColor: Colors.green.shade700,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          }
          _fetchOrders();
        }
    ).subscribe();
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    if (value) {
      try {
        final response = await supabase.from('riders').select('is_active').eq('id', _riderId).single();
        final bool isActive = response['is_active'] ?? false;

        if (!isActive) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Your account is inactive. Please contact the Admin.', style: GoogleFonts.alexandria(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
          }
          setState(() => _isOnline = false);
          return;
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not verify account status.')));
        return;
      }

      bool hasPerm = await _handleLocationPermission();
      if (!hasPerm) return;
    }

    setState(() => _isOnline = value);

    try {
      await supabase.from('riders').update({'is_online': value}).eq('id', _riderId);
      if (value) { _startLocationTracking(); } else { _stopLocationTracking(); }
    } catch (e) {
      setState(() => _isOnline = !value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update status')));
    }
  }

  Future<void> _updateOrderStatus(Map<String, dynamic> order, String newStatus, double progress) async {
    try {
      final orderId = order['id'];
      final now = DateTime.now();

      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      int hour = now.hour;
      final amPm = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      final timeStr = "${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $amPm";

      Map<String, dynamic> updates = {
        'status': newStatus,
        'progress': progress,
        'updated_at': now.toIso8601String(),
      };

      if (newStatus == 'in_process') {
        updates['pickup_date'] = dateStr;
        updates['pickup_time'] = timeStr;
      } else if (newStatus == 'delivered') {
        updates['delivery_date'] = dateStr;
        updates['delivery_time'] = timeStr;
      }

      await supabase.from('orders').update(updates).eq('id', orderId);

      if (newStatus == 'delivered' && _riderProfile != null) {
        final currentCash = (_riderProfile!['cash_in_hand'] as num?)?.toDouble() ?? 0.0;
        final orderPrice = (order['total_price'] as num?)?.toDouble() ?? 0.0;

        await supabase.from('riders').update({
          'cash_in_hand': currentCash + orderPrice,
        }).eq('id', _riderId);

        _fetchRiderProfile();
      }

      _fetchOrders();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _logout() async {
    _stopLocationTracking();
    if (_riderId.isNotEmpty) {
      await supabase.from('riders').update({'is_online': false}).eq('id', _riderId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RiderLoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_riderProfile == null && _loading) {
      return Scaffold(backgroundColor: _bgColor, body: Center(child: CircularProgressIndicator(color: _primaryBlue)));
    }

    final pages = [_buildActiveTasksTab(), _buildHistoryTab(), _buildProfileTab()];
    final fullName = _riderProfile?['full_name'] ?? 'Rider';
    final firstName = fullName.split(' ').first;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_currentIndex == 0 ? 'Hello, $firstName 👋' : _currentIndex == 1 ? 'Delivery History' : 'My Profile',
              style: GoogleFonts.alexandria(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
          if (_currentIndex == 0) Text('Here are your active assignments', style: GoogleFonts.alexandria(fontSize: 12, color: _subtextColor)),
        ]),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: _primaryBlue),
              tooltip: 'Refresh Data',
              onPressed: () { _fetchRiderProfile(); _fetchOrders(); },
            ),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, -5))]),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: BottomNavigationBar(
              currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
              backgroundColor: Colors.white, elevation: 0, selectedItemColor: _primaryBlue, unselectedItemColor: Colors.grey.shade400,
              selectedLabelStyle: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w700), unselectedLabelStyle: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w500),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.two_wheeler_rounded, size: 24)), label: 'Tasks'),
                BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.receipt_long_rounded, size: 24)), label: 'History'),
                BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.person_outline_rounded, size: 24)), label: 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTasksTab() {
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10), padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isOnline ? Colors.green.withOpacity(0.3) : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: (_isOnline ? Colors.green : Colors.black).withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (_isOnline ? Colors.green : Colors.grey).withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.power_settings_new_rounded, color: _isOnline ? Colors.green : Colors.grey.shade500)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current Status', style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w500)), const SizedBox(height: 4),
              Text(_isOnline ? 'Online & Ready' : 'You are Offline', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: _isOnline ? Colors.green.shade700 : _textColor)),
            ]),
          ]),
          Switch.adaptive(value: _isOnline, activeColor: Colors.green, onChanged: _toggleOnlineStatus),
        ]),
      ),
      Expanded(
        child: _loading ? Center(child: CircularProgressIndicator(color: _primaryBlue))
            : _activeOrders.isEmpty ? _buildEmptyState('No active tasks', _isOnline ? 'Searching for nearby orders...' : 'Go online to receive tasks.', Icons.task_alt_rounded)
            : RefreshIndicator(
          onRefresh: _fetchOrders, color: _primaryBlue,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24), physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _activeOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (_, i) => _buildActiveOrderCard(_activeOrders[i]),
          ),
        ),
      )
    ]);
  }

  Widget _buildHistoryTab() {
    return _loading ? Center(child: CircularProgressIndicator(color: _primaryBlue))
        : _historyOrders.isEmpty ? _buildEmptyState('No history yet', 'Your completed deliveries will appear here.', Icons.receipt_long_rounded)
        : RefreshIndicator(
      onRefresh: _fetchOrders, color: _primaryBlue,
      child: ListView.separated(
        padding: const EdgeInsets.all(20), physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _historyOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildHistoryOrderCard(_historyOrders[i]),
      ),
    );
  }

  Widget _buildProfileTab() {
    final name = _riderProfile?['full_name'] ?? 'Rider';
    final phone = _riderProfile?['phone'] ?? '—';
    final vehiclePlate = _riderProfile?['vehicle_plate'] ?? '—';
    final rating = (_riderProfile?['rating'] as num?)?.toDouble().toStringAsFixed(1) ?? '5.0';
    final cashInHand = (_riderProfile?['cash_in_hand'] as num?)?.toDouble() ?? 0.0;
    final avatar = _riderProfile?['avatar_url'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // 1. Profile Header
        Container(
          width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _primaryBlue.withOpacity(0.2), width: 4)), child: CircleAvatar(radius: 46, backgroundColor: _primaryBlue.withOpacity(0.1), backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null, child: (avatar == null || avatar.isEmpty) ? Text(name[0].toUpperCase(), style: GoogleFonts.alexandria(fontSize: 32, fontWeight: FontWeight.bold, color: _primaryBlue)) : null)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name, style: GoogleFonts.alexandria(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor)),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.star_rounded, color: Colors.orange, size: 14), const SizedBox(width: 4), Text(rating, style: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange))]))
            ]),
            const SizedBox(height: 4), Text(phone, style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor)), const SizedBox(height: 12),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)), child: Text('Plate: $vehiclePlate', style: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w600, color: _textColor)))
          ]),
        ),

        const SizedBox(height: 24),

        // 2. Salary & Trips Highlight
        Row(
          children: [
            // Today's Trips (Salary Basis)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: _primaryBlue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.today_rounded, color: Colors.white, size: 20)),
                    const SizedBox(height: 16),
                    Text(_todayTrips.toString(), style: GoogleFonts.alexandria(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Today\'s Trips', style: GoogleFonts.alexandria(fontSize: 12, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Cash in Hand
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 20)),
                    const SizedBox(height: 16),
                    Text('৳${cashInHand.toStringAsFixed(0)}', style: GoogleFonts.alexandria(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Cash in Hand', style: GoogleFonts.alexandria(fontSize: 12, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
        Text('Trip Analytics', style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor)),
        const SizedBox(height: 16),

        // 3. Analytics Grid
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSmallStat('This Month', '$_thisMonthTrips', Icons.calendar_month_rounded, Colors.purple),
                  _buildSmallStat('All-Time', '$_allTimeTrips', Icons.all_inclusive_rounded, Colors.teal),
                ],
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSmallStat('Round Trips', '$_roundTripCount', Icons.sync_alt_rounded, Colors.orange),
                  _buildSmallStat('Pickup Only', '$_pickupOnlyCount', Icons.move_to_inbox_rounded, Colors.blueGrey),
                  _buildSmallStat('Delivery Only', '$_deliveryOnlyCount', Icons.outbox_rounded, Colors.indigo),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        SizedBox(width: double.infinity, height: 56, child: OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout_rounded, color: Colors.redAccent), label: Text('Sign Out', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)), style: OutlinedButton.styleFrom(backgroundColor: Colors.white, side: BorderSide(color: Colors.red.shade200), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))))
      ]),
    );
  }

  Widget _buildSmallStat(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor)),
        const SizedBox(height: 2),
        Text(title, style: GoogleFonts.alexandria(fontSize: 11, color: _subtextColor, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)]), child: Icon(icon, size: 48, color: Colors.grey.shade300)), const SizedBox(height: 24), Text(title, style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor)), const SizedBox(height: 8), Text(subtitle, style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor))]));
  }

  Widget _buildActiveOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    // STRICT CARD UI LOGIC
    final isPickup = status == 'picked_up';
    final isDelivery = status == 'out_for_delivery';

    final profile = order['profiles'] as Map?;
    final themeColor = isPickup ? const Color(0xFF8B5CF6) : _primaryBlue;
    final actionText = isPickup ? 'Mark as Dropped' : 'Mark as Delivered';
    final badgeText = isPickup ? 'PICKUP TASK' : 'DELIVERY TASK';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => RiderOrderDetailsScreen(order: order)));
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: themeColor.withOpacity(0.15)), boxShadow: [BoxShadow(color: themeColor.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), decoration: BoxDecoration(color: themeColor.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: ShapeDecoration(shape: const StadiumBorder(), color: themeColor.withOpacity(0.15)), child: Text(badgeText, style: GoogleFonts.alexandria(fontSize: 10, fontWeight: FontWeight.bold, color: themeColor))), Text('#${order['order_number']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold, fontSize: 14, color: _subtextColor))])),
          Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.person_rounded, size: 18, color: Colors.grey)), const SizedBox(width: 12), Text(profile?['full_name'] ?? 'Guest Customer', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.w700, color: _textColor))]), const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.location_on_rounded, size: 18, color: Colors.grey)),
              const SizedBox(width: 12),
              Expanded(child: Text(order['pickup_address'] ?? 'No address provided', style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor, height: 1.4))),
              IconButton(onPressed: () => _openGoogleMaps(order), icon: Icon(Icons.navigation_rounded, color: themeColor), tooltip: 'Navigate in Maps', style: IconButton.styleFrom(backgroundColor: themeColor.withOpacity(0.1)))
            ]),
            const SizedBox(height: 16),
            Row(children: List.generate(40, (index) => Expanded(child: Container(color: index % 2 == 0 ? Colors.transparent : Colors.grey.shade300, height: 1)))), const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Cash to Collect', style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w500)), Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade600))]), const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 54, child: ElevatedButton.icon(onPressed: () { if (isPickup) _updateOrderStatus(order, 'in_process', 0.6); else if (isDelivery) _updateOrderStatus(order, 'delivered', 1.0); }, icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22), label: Text(actionText, style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0)))
          ]))
        ]),
      ),
    );
  }

  Widget _buildHistoryOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    final profile = order['profiles'] as Map?;
    String historyLabel = 'COMPLETED'; Color historyColor = Colors.green;

    if (status == 'cancelled') { historyLabel = 'CANCELLED'; historyColor = Colors.red; } else {
      bool pickedByMe = order['pickup_rider_id'] == _riderId || order['rider_id'] == _riderId;
      bool deliveredByMe = order['delivery_rider_id'] == _riderId || order['rider_id'] == _riderId;

      if (pickedByMe && deliveredByMe && status == 'delivered') { historyLabel = 'ROUND TRIP'; historyColor = Colors.green; }
      else if (deliveredByMe && status == 'delivered') { historyLabel = 'DELIVERY ONLY'; historyColor = _primaryBlue; }
      else if (pickedByMe) { historyLabel = 'PICKUP ONLY'; historyColor = const Color(0xFF8B5CF6); }
      else { historyLabel = status.replaceAll('_', ' ').toUpperCase(); historyColor = Colors.grey.shade500; }
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => RiderOrderDetailsScreen(order: order)));
      },
      child: Container(
        padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('#${order['order_number']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold, fontSize: 15, color: _textColor)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: ShapeDecoration(shape: const StadiumBorder(), color: historyColor.withOpacity(0.1)), child: Text(historyLabel, style: GoogleFonts.alexandria(fontSize: 10, fontWeight: FontWeight.bold, color: historyColor)))]), const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Icon(Icons.person_rounded, size: 16, color: Colors.grey.shade400), const SizedBox(width: 8), Text(profile?['full_name'] ?? 'Guest', style: GoogleFonts.alexandria(fontSize: 14, fontWeight: FontWeight.w600, color: _subtextColor))]), Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: _textColor))])
        ]),
      ),
    );
  }
}