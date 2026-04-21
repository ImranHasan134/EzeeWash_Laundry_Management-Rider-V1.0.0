// lib/features/home/rider_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../main.dart';
import '../auth/rider_login_screen.dart';
import '../orders/rider_order_details_screen.dart';

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
  bool _isDarkMode = false;

  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _historyOrders = [];

  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _cashChannel;
  Timer? _locationTimer;

  int _todayTrips = 0; int _thisMonthTrips = 0; int _allTimeTrips = 0;
  int _pickupOnlyCount = 0; int _deliveryOnlyCount = 0; int _roundTripCount = 0;

  // --- PREMIUM HIGH CONTRAST COLORS ---
  Color get _primaryBlue => const Color(0xFF3B82F6);
  Color get _bgColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get _subtextColor => _isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  Color get _borderColor => _isDarkMode ? const Color(0xFF334155).withOpacity(0.5) : const Color(0xFFE2E8F0);
  Color get _bottomNavBg => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  Color get _unselectedIconColor => _isDarkMode ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  Color get _iconBgColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OneSignal.Notifications.requestPermission(true);
    _initTheme();
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
    _stopLocationTracking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _riderId.isNotEmpty) {
      _fetchRiderProfile(); _fetchOrders();
    }
  }

  Future<void> _initTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('is_dark_mode')) {
      setState(() => _isDarkMode = prefs.getBool('is_dark_mode')!);
    } else {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      setState(() => _isDarkMode = brightness == Brightness.dark);
    }
  }

  Future<void> _toggleTheme() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isDarkMode = !_isDarkMode);
    await prefs.setBool('is_dark_mode', _isDarkMode);
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

  void _startLocationTracking() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      Position initialPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _pushLocationToDB(initialPosition);
    } catch (e) {
      debugPrint("Error fetching initial GPS: $e");
    }

    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
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

      final prefs = await SharedPreferences.getInstance();
      final localPassword = prefs.getString('rider_password');

      if (data['password'] != null && localPassword != null && data['password'] != localPassword) {
        _stopLocationTracking();
        await supabase.from('riders').update({'is_online': false}).eq('id', _riderId);
        await prefs.clear();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed, contact admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red, duration: Duration(seconds: 5)));
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RiderLoginScreen()), (_) => false);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _riderProfile = data;
          _isOnline = data['is_online'] ?? false;
        });

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
    HapticFeedback.mediumImpact();
    final isDelivery = order['status'] == 'out_for_delivery';

    final lat = isDelivery ? (order['delivery_lat'] ?? order['latitude']) : (order['pickup_lat'] ?? order['latitude']);
    final lng = isDelivery ? (order['delivery_lng'] ?? order['longitude']) : (order['pickup_lng'] ?? order['longitude']);

    String address = isDelivery ? (order['delivery_address'] ?? order['pickup_address'] ?? '') : (order['pickup_address'] ?? '');

    Uri url;
    if (lat != null && lng != null && lat.toString() != 'null' && lng.toString() != 'null') {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else if (address.toString().trim().isNotEmpty) {
      final encodedAddress = Uri.encodeComponent(address);
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No location or address provided for this order.'), backgroundColor: Colors.red));
      }
      return;
    }

    try { await launchUrl(url, mode: LaunchMode.externalApplication); }
    catch (e) { debugPrint('Could not launch maps: $e'); }
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

      final ratingsRes = await supabase.from('rider_ratings').select('order_id, stars').eq('rider_id', _riderId);
      final ratingsList = List<Map<String, dynamic>>.from(ratingsRes);
      final allOrders = List<Map<String, dynamic>>.from(data);

      List<Map<String, dynamic>> mergedOrders = [];
      for (var o in allOrders) {
        var ratingData = ratingsList.where((r) => r['order_id'] == o['id']).toList();
        double stars = 0.0;
        if (ratingData.isNotEmpty) {
          stars = ratingData.map((e) => (e['stars'] as num).toDouble()).reduce((a, b) => a + b) / ratingData.length;
        }
        mergedOrders.add({...o, 'stars': stars});
      }

      if (mounted) {
        setState(() {
          _activeOrders = mergedOrders.where((o) {
            bool isMyPickup = o['pickup_rider_id'] == _riderId && ['assign_pickup', 'picked_up', 'dropped'].contains(o['status']);
            bool isMyDelivery = o['delivery_rider_id'] == _riderId && o['status'] == 'out_for_delivery';
            return isMyPickup || isMyDelivery;
          }).toList();

          _historyOrders = mergedOrders.where((o) {
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
    HapticFeedback.lightImpact();
    if (_riderProfile?['is_active'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are marked inactive please contact to the authority', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.red));
      }
      return;
    }

    setState(() => _isOnline = value);
    try {
      await supabase.from('riders').update({'is_online': value}).eq('id', _riderId);
    } catch (e) {
      setState(() => _isOnline = !value);
    }
  }

  Future<void> _logout() async {
    HapticFeedback.heavyImpact();
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
        backgroundColor: _bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_currentIndex == 0 ? 'Hello, ${fullName.split(' ').first} 👋' : _currentIndex == 1 ? 'Delivery History' : 'My Profile', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: _textColor, letterSpacing: -0.5)),
          if (_currentIndex == 0) Text('Here are your active assignments', style: GoogleFonts.inter(fontSize: 14, color: _subtextColor, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh_rounded, color: _primaryBlue),
              style: IconButton.styleFrom(backgroundColor: _primaryBlue.withOpacity(0.1)),
              onPressed: () { HapticFeedback.lightImpact(); _fetchRiderProfile(); _fetchOrders(); }
          ),
          const SizedBox(width: 8)
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutQuart,
        switchOutCurve: Curves.easeInQuart,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.0, 0.05), end: Offset.zero).animate(animation), child: child));
        },
        child: Container(key: ValueKey<int>(_currentIndex), child: pages[_currentIndex]),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _bottomNavBg,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.3 : 0.05), blurRadius: 30, offset: const Offset(0, -10))],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: SafeArea(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Theme(
              data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
              child: BottomNavigationBar(
                currentIndex: _currentIndex, onTap: (i) { HapticFeedback.selectionClick(); setState(() => _currentIndex = i); },
                backgroundColor: _bottomNavBg, elevation: 0, selectedItemColor: _primaryBlue, unselectedItemColor: _unselectedIconColor,
                selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold), unselectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6), child: Icon(Icons.two_wheeler_rounded, size: 24)), label: 'Tasks'),
                  BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6), child: Icon(Icons.receipt_long_rounded, size: 24)), label: 'History'),
                  BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(bottom: 6), child: Icon(Icons.person_outline_rounded, size: 24)), label: 'Profile'),
                ],
              ),
            ),
          )),
        ),
      ),
    );
  }

  Widget _buildThemeToggle() {
    return GestureDetector(
      onTap: _toggleTheme,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: ShapeDecoration(color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white, shape: const StadiumBorder(), shadows: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 18, color: _isDarkMode ? Colors.amber.shade400 : Colors.orange.shade500),
          const SizedBox(width: 8),
          Text(_isDarkMode ? 'Dark' : 'Light', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: _textColor)),
        ]),
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => Container(
          height: 200,
          decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderColor)),
          child: Column(children: [
            Container(height: 50, decoration: BoxDecoration(color: _iconBgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)))),
            Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 20, width: 150, color: _iconBgColor), const SizedBox(height: 16),
              Container(height: 16, width: double.infinity, color: _iconBgColor), const SizedBox(height: 8),
              Container(height: 16, width: 200, color: _iconBgColor),
            ]))
          ]),
        )
    );
  }

  Widget _buildActiveTasksTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('App Theme', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: _subtextColor)),
          _buildThemeToggle(),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10), padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: _isOnline ? Colors.green.withOpacity(0.3) : _borderColor), boxShadow: [BoxShadow(color: (_isOnline ? Colors.green : Colors.black).withOpacity(_isDarkMode ? 0.2 : 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: (_isOnline ? Colors.green : Colors.grey).withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.power_settings_new_rounded, color: _isOnline ? Colors.green : Colors.grey.shade500)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current Status', style: GoogleFonts.inter(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w600)),
              Text(_isOnline ? 'Online & Ready' : 'You are Offline', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: _isOnline ? Colors.green.shade600 : _textColor)),
            ]),
          ]),
          Switch.adaptive(value: _isOnline, activeColor: Colors.green, onChanged: _toggleOnlineStatus),
        ]),
      ),
      Expanded(
        child: _loading
            ? _buildSkeletonLoader()
            : _activeOrders.isEmpty
            ? _buildEmptyState('You\'re all caught up!', 'Wait for new assignments or go online.', Icons.coffee_rounded)
            : RefreshIndicator(onRefresh: _fetchOrders, color: _primaryBlue, child: ListView.separated(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), itemCount: _activeOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 16), itemBuilder: (_, i) => _buildActiveOrderCard(_activeOrders[i]))),
      )
    ]);
  }

  Widget _buildActiveOrderCard(Map<String, dynamic> order) {
    final status = order['status'] ?? '';
    final isDelivery = status == 'out_for_delivery';
    final themeColor = isDelivery ? _primaryBlue : const Color(0xFF8B5CF6);
    final profile = order['profiles'] as Map?;

    String address = isDelivery ? (order['delivery_address'] ?? order['pickup_address'] ?? '') : (order['pickup_address'] ?? '');
    if (address.trim().isEmpty) address = 'No address provided';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(context, MaterialPageRoute(builder: (context) => RiderOrderDetailsScreen(order: order, isDarkMode: _isDarkMode)));
      },
      child: Hero(
        tag: 'order_card_${order['id']}',
        child: Container(
          decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Column(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18), decoration: BoxDecoration(color: themeColor.withOpacity(0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: ShapeDecoration(shape: const StadiumBorder(), color: themeColor.withOpacity(0.15)), child: Text(isDelivery ? 'DELIVERY TASK' : 'PICKUP TASK', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: themeColor))), Text('#${order['order_number']}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: _textColor))])),
            Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _iconBgColor, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.person_rounded, size: 20, color: _isDarkMode ? Colors.grey.shade400 : Colors.grey)), const SizedBox(width: 14), Text(order['manual_customer_name'] ?? profile?['full_name'] ?? 'Guest Customer', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _textColor))]), const SizedBox(height: 16),
              Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _iconBgColor, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.location_on_rounded, size: 20, color: _isDarkMode ? Colors.grey.shade400 : Colors.grey)), const SizedBox(width: 14), Expanded(child: Text(address, style: GoogleFonts.inter(fontSize: 14, color: _subtextColor, height: 1.4))), IconButton(onPressed: () => _openGoogleMaps(order), icon: Icon(Icons.navigation_rounded, color: themeColor), style: IconButton.styleFrom(backgroundColor: themeColor.withOpacity(0.1))) ]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Divider(color: _borderColor, height: 1)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Cash to Collect', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _subtextColor)), Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade600))]),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Tap card to process order', style: GoogleFonts.inter(fontSize: 13, color: themeColor, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: themeColor)
                ],
              )
            ]))
          ]),
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final name = _riderProfile?['full_name'] ?? 'Rider';
    final cash = (_riderProfile?['cash_in_hand'] as num?)?.toDouble() ?? 0.0;
    final avatar = _riderProfile?['avatar_url'] as String?;
    final rating = (_riderProfile?['rating'] as num?)?.toDouble() ?? 5.0;

    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(32), border: Border.all(color: _borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.03), blurRadius: 24, offset: const Offset(0, 10))]), child: Column(children: [
        Container(decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: _primaryBlue.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))]), child: CircleAvatar(radius: 50, backgroundColor: _primaryBlue.withOpacity(0.1), backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null, child: avatar == null ? Text(name[0].toUpperCase(), style: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.bold, color: _primaryBlue)) : null)),
        const SizedBox(height: 20),
        Text(name, style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: _textColor, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(_riderProfile?['phone'] ?? '', style: GoogleFonts.inter(fontSize: 15, color: _subtextColor)),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.withOpacity(0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star_rounded, color: Colors.amber, size: 20), const SizedBox(width: 8), Text('${rating.toStringAsFixed(1)} Rating', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber))])),
      ])),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: _buildGradientStat('Today\'s Trips', '$_todayTrips', [const Color(0xFF3B82F6), const Color(0xFF2563EB)], Icons.today_rounded)),
        const SizedBox(width: 16),
        Expanded(child: _buildGradientStat('Cash in Hand', '৳${cash.toStringAsFixed(0)}', [const Color(0xFF10B981), const Color(0xFF059669)], Icons.account_balance_wallet_rounded)),
      ]),
      const SizedBox(height: 32),
      Text('Trip Analytics', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderColor)), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildSmallStat('This Month', '$_thisMonthTrips', Icons.calendar_month, Colors.purple), _buildSmallStat('All-Time', '$_allTimeTrips', Icons.all_inclusive, Colors.teal)]),
        Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: _borderColor)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_buildSmallStat('Round Trips', '$_roundTripCount', Icons.sync_alt, Colors.orange), _buildSmallStat('Pickup', '$_pickupOnlyCount', Icons.move_to_inbox, Colors.blueGrey), _buildSmallStat('Delivery', '$_deliveryOnlyCount', Icons.outbox, Colors.indigo)]),
      ])),
      const SizedBox(height: 48),
      SizedBox(width: double.infinity, height: 60, child: OutlinedButton(onPressed: _logout, style: OutlinedButton.styleFrom(side: BorderSide(color: _isDarkMode ? Colors.red.shade800 : Colors.red.shade200, width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text('Sign Out', style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold))))
    ]));
  }

  Widget _buildGradientStat(String t, String v, List<Color> colors, IconData i) {
    return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: colors.last.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Icon(i, color: Colors.white, size: 20)), const SizedBox(height: 16), Text(v, style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)), const SizedBox(height: 4), Text(t, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9)))
    ]));
  }

  Widget _buildSmallStat(String t, String v, IconData i, Color c) {
    return Column(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: c, size: 22)), const SizedBox(height: 12), Text(v, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor)), const SizedBox(height: 2), Text(t, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _subtextColor))]);
  }

  Widget _buildEmptyState(String t, String s, IconData i) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: _iconBgColor, shape: BoxShape.circle), child: Icon(i, size: 48, color: _isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400)), const SizedBox(height: 24), Text(t, style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor)), const SizedBox(height: 8), Text(s, style: GoogleFonts.inter(fontSize: 15, color: _subtextColor))]));

  Widget _buildHistoryTab() => _historyOrders.isEmpty ? _buildEmptyState('No history yet', 'Completed deliveries show here.', Icons.receipt_long) : ListView.separated(padding: const EdgeInsets.all(24), itemCount: _historyOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 16), itemBuilder: (_, i) => _buildHistoryOrderCard(_historyOrders[i]));

  Widget _buildHistoryOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    bool picked = order['pickup_rider_id'] == _riderId;
    bool deliv = order['delivery_rider_id'] == _riderId;
    String label = status == 'delivered' ? (picked && deliv ? 'ROUND TRIP' : picked ? 'PICKUP ONLY' : 'DELIVERY ONLY') : status.toUpperCase();
    double stars = order['stars'] ?? 0.0;

    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: _borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(_isDarkMode ? 0.2 : 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${order['order_number']}', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: _textColor)),
                    const SizedBox(height: 8),
                    Row(
                        children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: ShapeDecoration(shape: const StadiumBorder(), color: _primaryBlue.withOpacity(0.1)), child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: _primaryBlue))),
                          if (status == 'delivered') ...[
                            const SizedBox(width: 10),
                            if (stars > 0) Row(children: [const Icon(Icons.star_rounded, color: Colors.amber, size: 14), const SizedBox(width: 4), Text(stars.toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber))])
                            else Text('No Rating', style: GoogleFonts.inter(fontSize: 11, color: _subtextColor, fontWeight: FontWeight.w500)),
                          ]
                        ]
                    )
                  ]
              ),
              Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor))
            ]
        )
    );
  }
}