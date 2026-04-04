import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../main.dart';
import '../auth/rider_login_screen.dart';
import '../orders/screens/rider_order_details_screen.dart';

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

  final Set<String> _pendingPaymentOrders = {};

  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _cashChannel;

  // STRICT LOGIC: Replaced Stream with a 10-second Timer
  Timer? _locationTimer;

  int _todayTrips = 0; int _thisMonthTrips = 0; int _allTimeTrips = 0;
  int _pickupOnlyCount = 0; int _deliveryOnlyCount = 0; int _roundTripCount = 0;

  final Color _primaryBlue = const Color(0xFF3B82F6);
  final Color _bgColor = const Color(0xFFF8FAFC);
  final Color _textColor = const Color(0xFF1E293B);
  final Color _subtextColor = const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OneSignal.Notifications.requestPermission(true);
    _initDashboard();

    OneSignal.Notifications.addClickListener((event) {
      if (mounted) { _fetchRiderProfile(); _fetchOrders(); }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ordersChannel?.unsubscribe();
    _cashChannel?.unsubscribe();
    _stopLocationTracking(); // Kills the 10-second timer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _riderId.isNotEmpty) {
      _fetchRiderProfile(); _fetchOrders();
    }
  }

  Future<void> _initDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    _riderId = prefs.getString('rider_id') ?? '';

    if (_riderId.isEmpty) { _logout(); return; }

    OneSignal.login(_riderId);

    await Future.wait<void>([_fetchRiderProfile(), _fetchOrders()]);
    _setupRealtime();
  }

  void _calculateTripStats() {
    _todayTrips = 0; _thisMonthTrips = 0; _allTimeTrips = 0;
    _pickupOnlyCount = 0; _deliveryOnlyCount = 0; _roundTripCount = 0;

    final now = DateTime.now();
    final allMyOrders = [..._activeOrders, ..._historyOrders];

    for (var order in allMyOrders) {
      bool didPickup = order['pickup_rider_id'] == _riderId;
      bool didDelivery = order['delivery_rider_id'] == _riderId;
      String status = order['status'] ?? '';

      bool pickupCompleted = didPickup && !['pending', 'confirmed', 'assign_pickup', 'picked_up', 'dropped'].contains(status);
      bool deliveryCompleted = didDelivery && status == 'delivered';

      int points = 0;
      if (pickupCompleted && deliveryCompleted) { _roundTripCount++; points = 2; }
      else if (pickupCompleted) { _pickupOnlyCount++; points = 1; }
      else if (deliveryCompleted) { _deliveryOnlyCount++; points = 1; }

      _allTimeTrips += points;

      if (order['updated_at'] != null) {
        DateTime updatedAt = DateTime.parse(order['updated_at']).toLocal();
        if (updatedAt.year == now.year && updatedAt.month == now.month && updatedAt.day == now.day) _todayTrips += points;
        if (updatedAt.year == now.year && updatedAt.month == now.month) _thisMonthTrips += points;
      }
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    return permission != LocationPermission.deniedForever;
  }

  // --- EXACT FIX: 10-Second Time-Based Tracking ---
  void _startLocationTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      // 1. Instantly push first location when accessing
      Position initialPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _pushLocationToDB(initialPosition);
    } catch (e) {
      debugPrint("Error fetching initial GPS: $e");
    }

    // 2. Start the 10-second loop
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {

      // ONLY push if Rider is online AND actively working on an order
      if (_isOnline && _activeOrders.isNotEmpty) {
        try {
          Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          await _pushLocationToDB(position);
        } catch (e) {
          debugPrint("Timer GPS Error: $e");
        }
      }
    });
  }

  Future<void> _pushLocationToDB(Position position) async {
    try {
      // Update riders table for Realtime WebSockets
      await supabase.from('riders').update({
        'current_lat': position.latitude,
        'current_lng': position.longitude,
        'last_location_update': DateTime.now().toIso8601String(),
      }).eq('id', _riderId);

    } catch (e) {
      debugPrint("Error pushing to DB: $e");
    }
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _fetchRiderProfile() async {
    try {
      final data = await supabase.from('riders').select().eq('id', _riderId).single();
      if (mounted) {
        setState(() {
          _riderProfile = data;
          _isOnline = data['is_online'] ?? false;
        });

        // Use _locationTimer instead of _positionStream
        if ((data['is_active'] ?? false) && _locationTimer == null) {
          _startLocationTracking();
        } else if (!(data['is_active'] ?? false)) {
          _stopLocationTracking();
        }
      }
    } catch (e) {
      debugPrint("Error fetching rider profile: $e");
    }
  }

  Future<void> _openGoogleMaps(Map<String, dynamic> order) async {
    final lat = order['latitude'] ?? order['pickup_lat'];
    final lng = order['longitude'] ?? order['pickup_lng'];
    final address = order['pickup_address'] ?? '';

    Uri url;

    if (lat != null && lng != null && lat.toString() != 'null' && lng.toString() != 'null') {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    }
    else if (address.toString().trim().isNotEmpty) {
      final encodedAddress = Uri.encodeComponent(address);
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    }
    else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No location or address provided for this order.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch maps: $e');
    }
  }

  Future<void> _fetchOrders() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('orders')
          .select('*, profiles(full_name, phone)')
          .or('pickup_rider_id.eq.$_riderId,delivery_rider_id.eq.$_riderId')
          .order('updated_at', ascending: false);

      final allOrders = List<Map<String, dynamic>>.from(data);

      if (mounted) {
        setState(() {
          _activeOrders = allOrders.where((o) {
            bool isMyPickup = o['pickup_rider_id'] == _riderId && ['assign_pickup', 'picked_up', 'dropped'].contains(o['status']);
            bool isMyDelivery = o['delivery_rider_id'] == _riderId && o['status'] == 'out_for_delivery';
            return isMyPickup || isMyDelivery;
          }).toList();

          _historyOrders = allOrders.where((o) {
            bool finishedPickup = o['pickup_rider_id'] == _riderId && !['pending', 'confirmed', 'assign_pickup', 'picked_up', 'dropped'].contains(o['status']);
            bool finishedDelivery = o['delivery_rider_id'] == _riderId && o['status'] == 'delivered';
            return finishedPickup || finishedDelivery;
          }).toList();

          _calculateTripStats();
          _loading = false;
        });
      }
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  void _setupRealtime() {
    _cashChannel = supabase.channel('rider_profile_sync').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'riders', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: _riderId),
      callback: (payload) { _fetchRiderProfile(); },
    ).subscribe();

    _ordersChannel = supabase.channel('rider_orders_sync').onPostgresChanges(
      event: PostgresChangeEvent.all, schema: 'public', table: 'orders',
      callback: (payload) { _fetchOrders(); },
    ).subscribe();
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    setState(() => _isOnline = value);
    try { await supabase.from('riders').update({'is_online': value}).eq('id', _riderId); }
    catch (e) { setState(() => _isOnline = !value); }
  }

  Future<void> _updateOrderStatus(Map<String, dynamic> order, String newStatus, double progress) async {
    try {
      final now = DateTime.now();

      await supabase.from('orders').update({
        'status': newStatus,
        'progress': progress,
        'updated_at': now.toIso8601String()
      }).eq('id', order['id']);

      if (newStatus == 'delivered') {
        final orderPrice = (order['total_price'] as num?)?.toDouble() ?? 0.0;
        final currentDue = (_riderProfile?['cash_in_hand'] as num?)?.toDouble() ?? 0.0;

        await supabase.from('riders').update({
          'cash_in_hand': currentDue + orderPrice
        }).eq('id', _riderId);

        await _fetchRiderProfile();
      }

      await _fetchOrders();
    } catch (e) {
      debugPrint("Error updating status: $e");
    }
  }

  Future<void> _logout() async {
    _stopLocationTracking();
    if (_riderId.isNotEmpty) await supabase.from('riders').update({'is_online': false}).eq('id', _riderId);
    final prefs = await SharedPreferences.getInstance(); await prefs.clear();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RiderLoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (_riderProfile == null && _loading) return Scaffold(backgroundColor: _bgColor, body: Center(child: CircularProgressIndicator(color: _primaryBlue)));
    final pages = [_buildActiveTasksTab(), _buildHistoryTab(), _buildProfileTab()];
    final fullName = _riderProfile?['full_name'] ?? 'Rider';

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_currentIndex == 0 ? 'Hello, ${fullName.split(' ').first} 👋' : _currentIndex == 1 ? 'Delivery History' : 'My Profile', style: GoogleFonts.alexandria(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
          if (_currentIndex == 0) Text('Here are your active assignments', style: GoogleFonts.alexandria(fontSize: 12, color: _subtextColor)),
        ]),
        actions: [IconButton(icon: Icon(Icons.refresh_rounded, color: _primaryBlue), onPressed: () { _fetchRiderProfile(); _fetchOrders(); })],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, -5))]),
        child: SafeArea(child: Padding(
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
        )),
      ),
    );
  }

  Widget _buildActiveTasksTab() {
    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10), padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _isOnline ? Colors.green.withOpacity(0.3) : Colors.grey.shade200), boxShadow: [BoxShadow(color: (_isOnline ? Colors.green : Colors.black).withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (_isOnline ? Colors.green : Colors.grey).withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.power_settings_new_rounded, color: _isOnline ? Colors.green : Colors.grey.shade500)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current Status', style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w500)),
              Text(_isOnline ? 'Online & Ready' : 'You are Offline', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: _isOnline ? Colors.green.shade700 : _textColor)),
            ]),
          ]),
          Switch.adaptive(value: _isOnline, activeColor: Colors.green, onChanged: _toggleOnlineStatus),
        ]),
      ),
      Expanded(
        child: _loading ? Center(child: CircularProgressIndicator(color: _primaryBlue))
            : _activeOrders.isEmpty ? _buildEmptyState('No active tasks', 'Go online to receive tasks.', Icons.task_alt_rounded)
            : RefreshIndicator(onRefresh: _fetchOrders, color: _primaryBlue, child: ListView.separated(padding: const EdgeInsets.fromLTRB(20, 10, 20, 24), itemCount: _activeOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 16), itemBuilder: (_, i) => _buildActiveOrderCard(_activeOrders[i]))),
      )
    ]);
  }

  Widget _buildActiveOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? '';
    final isDelivery = status == 'out_for_delivery';
    final themeColor = isDelivery ? _primaryBlue : const Color(0xFF8B5CF6);
    final profile = order['profiles'] as Map?;

    Widget actionButton;
    if (status == 'assign_pickup') {
      actionButton = ElevatedButton(onPressed: () => _updateOrderStatus(order, 'picked_up', 0.4), style: ElevatedButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text('Picked Up', style: GoogleFonts.alexandria(color: Colors.white, fontWeight: FontWeight.bold)));
    } else if (status == 'picked_up') {
      actionButton = ElevatedButton(onPressed: () => _updateOrderStatus(order, 'dropped', 0.5), style: ElevatedButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text('Drop Order', style: GoogleFonts.alexandria(color: Colors.white, fontWeight: FontWeight.bold)));
    } else if (status == 'dropped') {
      actionButton = ElevatedButton(onPressed: null, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade400, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text('Processing Drop Off...', style: GoogleFonts.alexandria(color: Colors.white, fontWeight: FontWeight.bold)));
    } else if (isDelivery) {
      if (_pendingPaymentOrders.contains(order['id'])) {
        actionButton = ElevatedButton(onPressed: () { _pendingPaymentOrders.remove(order['id']); _updateOrderStatus(order, 'delivered', 1.0); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text('Payment Collected', style: GoogleFonts.alexandria(color: Colors.white, fontWeight: FontWeight.bold)));
      } else {
        actionButton = ElevatedButton(onPressed: () { setState(() => _pendingPaymentOrders.add(order['id'])); }, style: ElevatedButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: Text('Mark Delivered', style: GoogleFonts.alexandria(color: Colors.white, fontWeight: FontWeight.bold)));
      }
    } else {
      actionButton = const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RiderOrderDetailsScreen(order: order))),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: themeColor.withOpacity(0.15)), boxShadow: [BoxShadow(color: themeColor.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), decoration: BoxDecoration(color: themeColor.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: ShapeDecoration(shape: const StadiumBorder(), color: themeColor.withOpacity(0.15)), child: Text(isDelivery ? 'DELIVERY TASK' : 'PICKUP TASK', style: GoogleFonts.alexandria(fontSize: 10, fontWeight: FontWeight.bold, color: themeColor))), Text('#${order['order_number']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold, fontSize: 14, color: _subtextColor))])),
          Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.person_rounded, size: 18, color: Colors.grey)), const SizedBox(width: 12), Text(profile?['full_name'] ?? 'Guest Customer', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.w700, color: _textColor))]), const SizedBox(height: 16),
            Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.location_on_rounded, size: 18, color: Colors.grey)), const SizedBox(width: 12), Expanded(child: Text(order['pickup_address'] ?? 'No address', style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor))), IconButton(onPressed: () => _openGoogleMaps(order), icon: Icon(Icons.navigation_rounded, color: themeColor))]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Cash to Collect', style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor)), Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade600))]), const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 54, child: actionButton),
          ]))
        ]),
      ),
    );
  }

  Widget _buildProfileTab() {
    final name = _riderProfile?['full_name'] ?? 'Rider';
    final cash = (_riderProfile?['cash_in_hand'] as num?)?.toDouble() ?? 0.0;
    final avatar = _riderProfile?['avatar_url'] as String?;
    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)]), child: Column(children: [
        CircleAvatar(radius: 46, backgroundColor: _primaryBlue.withOpacity(0.1), backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null, child: avatar == null ? Text(name[0].toUpperCase(), style: GoogleFonts.alexandria(fontSize: 32, fontWeight: FontWeight.bold, color: _primaryBlue)) : null),
        const SizedBox(height: 16), Text(name, style: GoogleFonts.alexandria(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor)), Text(_riderProfile?['phone'] ?? '', style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor))
      ])),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: _buildGradientStat('Today\'s Trips', '$_todayTrips', [const Color(0xFF3B82F6), const Color(0xFF2563EB)], Icons.today_rounded)),
        const SizedBox(width: 16),
        Expanded(child: _buildGradientStat('Cash in Hand', '৳${cash.toStringAsFixed(0)}', [const Color(0xFF10B981), const Color(0xFF059669)], Icons.account_balance_wallet_rounded)),
      ]),
      const SizedBox(height: 24),
      Text('Trip Analytics', style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor)),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildSmallStat('This Month', '$_thisMonthTrips', Icons.calendar_month, Colors.purple), _buildSmallStat('All-Time', '$_allTimeTrips', Icons.all_inclusive, Colors.teal)]),
        const Divider(height: 32),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildSmallStat('Round Trips', '$_roundTripCount', Icons.sync_alt, Colors.orange), _buildSmallStat('Pickup', '$_pickupOnlyCount', Icons.move_to_inbox, Colors.blueGrey), _buildSmallStat('Delivery', '$_deliveryOnlyCount', Icons.outbox, Colors.indigo)]),
      ])),
      const SizedBox(height: 48),
      SizedBox(width: double.infinity, height: 56, child: OutlinedButton(onPressed: _logout, style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade200), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text('Sign Out', style: GoogleFonts.alexandria(color: Colors.redAccent, fontWeight: FontWeight.bold))))
    ]));
  }

  Widget _buildGradientStat(String t, String v, List<Color> colors, IconData i) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(i, color: Colors.white, size: 20), const SizedBox(height: 16), Text(v, style: GoogleFonts.alexandria(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)), Text(t, style: GoogleFonts.alexandria(fontSize: 12, color: Colors.white70))
    ]));
  }

  Widget _buildSmallStat(String t, String v, IconData i, Color c) {
    return Column(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, color: c, size: 20)), const SizedBox(height: 8), Text(v, style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold)), Text(t, style: GoogleFonts.alexandria(fontSize: 11, color: _subtextColor))]);
  }

  Widget _buildEmptyState(String t, String s, IconData i) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 48, color: Colors.grey.shade300), const SizedBox(height: 24), Text(t, style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold)), Text(s, style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor))]));

  Widget _buildHistoryTab() => _historyOrders.isEmpty ? _buildEmptyState('No history yet', 'Completed deliveries show here.', Icons.receipt_long) : ListView.separated(padding: const EdgeInsets.all(20), itemCount: _historyOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, i) => _buildHistoryOrderCard(_historyOrders[i]));

  Widget _buildHistoryOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    bool picked = order['pickup_rider_id'] == _riderId;
    bool deliv = order['delivery_rider_id'] == _riderId;
    String label = status == 'delivered' ? (picked && deliv ? 'ROUND TRIP' : picked ? 'PICKUP ONLY' : 'DELIVERY ONLY') : status.toUpperCase();
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('#${order['order_number']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold)), Text(label, style: GoogleFonts.alexandria(fontSize: 10, fontWeight: FontWeight.bold, color: _primaryBlue))]), Text('৳${order['total_price']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold))]));
  }
}