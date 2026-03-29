// lib/features/home/rider_dashboard.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../auth/rider_login_screen.dart';

class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});
  @override State<RiderDashboard> createState() => _RiderDashboardState();
}

class _RiderDashboardState extends State<RiderDashboard> {
  int _currentIndex = 0;
  String _riderId = '';
  Map<String, dynamic>? _riderProfile;

  bool _isOnline = false;
  bool _loading = true;

  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _historyOrders = [];

  RealtimeChannel? _channel;

  // Theme Colors for easy reference
  final Color _primaryBlue = const Color(0xFF3B82F6);
  final Color _bgColor = const Color(0xFFF8FAFC);
  final Color _textColor = const Color(0xFF1E293B);
  final Color _subtextColor = const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
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
          _activeOrders = allOrders.where((o) {
            return o['rider_id'] == _riderId && (o['status'] == 'picked_up' || o['status'] == 'out_for_delivery');
          }).toList();

          _historyOrders = allOrders.where((o) {
            bool isActive = o['rider_id'] == _riderId && (o['status'] == 'picked_up' || o['status'] == 'out_for_delivery');
            return !isActive;
          }).toList();

          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setupRealtime() {
    _channel = supabase.channel('public:orders:rider_$_riderId')
        .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (payload) {
          _fetchOrders();
        }
    ).subscribe();
  }

  Future<void> _toggleOnlineStatus(bool value) async {
    setState(() => _isOnline = value);
    try {
      await supabase.from('riders').update({'is_online': value}).eq('id', _riderId);
    } catch (e) {
      setState(() => _isOnline = !value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update status')));
    }
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus, double progress) async {
    try {
      await supabase.from('orders').update({'status': newStatus, 'progress': progress}).eq('id', orderId);

      if (newStatus == 'delivered' && _riderProfile != null) {
        final currentTrips = _riderProfile!['total_trips'] as int? ?? 0;
        await supabase.from('riders').update({'total_trips': currentTrips + 1}).eq('id', _riderId);
        _fetchRiderProfile();
      }

      _fetchOrders();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _logout() async {
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

    final pages = [
      _buildActiveTasksTab(),
      _buildHistoryTab(),
      _buildProfileTab(),
    ];

    // Get first name for greeting
    final fullName = _riderProfile?['full_name'] ?? 'Rider';
    final firstName = fullName.split(' ').first;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_currentIndex == 0 ? 'Hello, $firstName 👋' : _currentIndex == 1 ? 'Delivery History' : 'My Profile',
              style: GoogleFonts.alexandria(fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
          if (_currentIndex == 0)
            Text('Here are your active assignments', style: GoogleFonts.alexandria(fontSize: 12, color: _subtextColor)),
        ]),
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              backgroundColor: Colors.white,
              elevation: 0,
              selectedItemColor: _primaryBlue,
              unselectedItemColor: Colors.grey.shade400,
              selectedLabelStyle: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w700),
              unselectedLabelStyle: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w500),
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

  // ─── TAB 1: ACTIVE TASKS ───────────────────────────────────────────────────
  Widget _buildActiveTasksTab() {
    return Column(children: [
      // Polished Toggle Card
      Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isOnline ? Colors.green.withOpacity(0.3) : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: (_isOnline ? Colors.green : Colors.black).withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: (_isOnline ? Colors.green : Colors.grey).withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.power_settings_new_rounded, color: _isOnline ? Colors.green : Colors.grey.shade500),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Current Status', style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(_isOnline ? 'Online & Ready' : 'You are Offline',
                  style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: _isOnline ? Colors.green.shade700 : _textColor)),
            ]),
          ]),
          Switch.adaptive(value: _isOnline, activeColor: Colors.green, onChanged: _toggleOnlineStatus),
        ]),
      ),

      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: _primaryBlue))
            : _activeOrders.isEmpty
            ? _buildEmptyState('No active tasks', _isOnline ? 'Searching for nearby orders...' : 'Go online to receive tasks.', Icons.task_alt_rounded)
            : RefreshIndicator(
          onRefresh: _fetchOrders,
          color: _primaryBlue,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _activeOrders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (_, i) => _buildActiveOrderCard(_activeOrders[i]),
          ),
        ),
      )
    ]);
  }

  // ─── TAB 2: HISTORY ────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    return _loading
        ? Center(child: CircularProgressIndicator(color: _primaryBlue))
        : _historyOrders.isEmpty
        ? _buildEmptyState('No history yet', 'Your completed deliveries will appear here.', Icons.receipt_long_rounded)
        : RefreshIndicator(
      onRefresh: _fetchOrders,
      color: _primaryBlue,
      child: ListView.separated(
        padding: const EdgeInsets.all(20), physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _historyOrders.length, separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildHistoryOrderCard(_historyOrders[i]),
      ),
    );
  }

  // ─── TAB 3: PROFILE ────────────────────────────────────────────────────────
  Widget _buildProfileTab() {
    final name = _riderProfile?['full_name'] ?? 'Rider';
    final phone = _riderProfile?['phone'] ?? '—';
    final vehiclePlate = _riderProfile?['vehicle_plate'] ?? '—';
    final trips = _riderProfile?['total_trips']?.toString() ?? '0';
    final rating = (_riderProfile?['rating'] as num?)?.toDouble().toStringAsFixed(1) ?? '5.0';
    final avatar = _riderProfile?['avatar_url'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        // Profile Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _primaryBlue.withOpacity(0.2), width: 4),
              ),
              child: CircleAvatar(
                radius: 46, backgroundColor: _primaryBlue.withOpacity(0.1),
                backgroundImage: (avatar != null && avatar.isNotEmpty) ? NetworkImage(avatar) : null,
                child: (avatar == null || avatar.isEmpty) ? Text(name[0].toUpperCase(), style: GoogleFonts.alexandria(fontSize: 32, fontWeight: FontWeight.bold, color: _primaryBlue)) : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: GoogleFonts.alexandria(fontSize: 22, fontWeight: FontWeight.bold, color: _textColor)),
            const SizedBox(height: 4),
            Text(phone, style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
              child: Text('Plate: $vehiclePlate', style: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w600, color: _textColor)),
            )
          ]),
        ),
        const SizedBox(height: 24),

        // Stats Row
        Row(children: [
          Expanded(child: _buildStatCard('Total Trips', trips, Icons.local_shipping_rounded, _primaryBlue)),
          const SizedBox(width: 16),
          Expanded(child: _buildStatCard('Rating', rating, Icons.star_rounded, Colors.orange.shade500)),
        ]),
        const SizedBox(height: 48),

        // Logout Button
        SizedBox(
          width: double.infinity, height: 56,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            label: Text('Sign Out', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: BorderSide(color: Colors.red.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
            ),
          ),
        )
      ]),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 16),
        Text(value, style: GoogleFonts.alexandria(fontSize: 24, fontWeight: FontWeight.bold, color: _textColor)),
        const SizedBox(height: 4),
        Text(title, style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ─── HELPER COMPONENTS ─────────────────────────────────────────────────────

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)]),
          child: Icon(icon, size: 48, color: Colors.grey.shade300),
        ),
        const SizedBox(height: 24),
        Text(title, style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor)),
        const SizedBox(height: 8),
        Text(subtitle, style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor)),
      ]),
    );
  }

  // Polished Active Order Card
  Widget _buildActiveOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    final isPickup = status == 'picked_up';
    final isDelivery = status == 'out_for_delivery';
    final profile = order['profiles'] as Map?;

    final themeColor = isPickup ? const Color(0xFF8B5CF6) : _primaryBlue; // Purple for pickup, Blue for delivery
    final actionText = isPickup ? 'Mark as Dropped' : 'Mark as Delivered';
    final badgeText = isPickup ? 'PICKUP TASK' : 'DELIVERY TASK';

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: themeColor.withOpacity(0.15)),
          boxShadow: [BoxShadow(color: themeColor.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Card Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(color: themeColor.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: ShapeDecoration(shape: const StadiumBorder(), color: themeColor.withOpacity(0.15)),
              child: Text(badgeText, style: GoogleFonts.alexandria(fontSize: 10, fontWeight: FontWeight.bold, color: themeColor)),
            ),
            Text('#${order['order_number']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold, fontSize: 14, color: _subtextColor)),
          ]),
        ),

        // Card Body
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.person_rounded, size: 18, color: Colors.grey)),
              const SizedBox(width: 12),
              Text(profile?['full_name'] ?? 'Guest Customer', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.w700, color: _textColor)),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle), child: const Icon(Icons.location_on_rounded, size: 18, color: Colors.grey)),
              const SizedBox(width: 12),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(order['pickup_address'] ?? 'No address provided', style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor, height: 1.4)),
              )),
            ]),
            const SizedBox(height: 16),

            // Dotted Divider
            Row(children: List.generate(40, (index) => Expanded(child: Container(color: index % 2 == 0 ? Colors.transparent : Colors.grey.shade300, height: 1)))),

            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Cash to Collect', style: GoogleFonts.alexandria(fontSize: 13, color: _subtextColor, fontWeight: FontWeight.w500)),
              Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.alexandria(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade600)),
            ]),
            const SizedBox(height: 20),

            // Action Button
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (isPickup) _updateOrderStatus(order['id'], 'in_process', 0.6);
                  else if (isDelivery) _updateOrderStatus(order['id'], 'delivered', 1.0);
                },
                icon: Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                label: Text(actionText, style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // Polished History Card
  Widget _buildHistoryOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? '';
    final profile = order['profiles'] as Map?;

    String historyLabel = 'COMPLETED';
    Color historyColor = Colors.green;

    if (status == 'cancelled') {
      historyLabel = 'CANCELLED';
      historyColor = Colors.red;
    } else {
      bool pickedByMe = order['pickup_rider_id'] == _riderId;
      bool deliveredByMe = order['delivery_rider_id'] == _riderId && status == 'delivered';

      if (pickedByMe && deliveredByMe) {
        historyLabel = 'PICKUP & DELIVERY';
        historyColor = Colors.green;
      } else if (deliveredByMe) {
        historyLabel = 'DELIVERED';
        historyColor = _primaryBlue;
      } else if (pickedByMe) {
        historyLabel = 'PICKED UP';
        historyColor = const Color(0xFF8B5CF6);
      } else if (status == 'delivered') {
        historyLabel = 'DELIVERED';
        historyColor = Colors.green;
      } else {
        historyLabel = status.replaceAll('_', ' ').toUpperCase();
        historyColor = Colors.grey.shade500;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('#${order['order_number']}', style: GoogleFonts.alexandria(fontWeight: FontWeight.bold, fontSize: 15, color: _textColor)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(shape: const StadiumBorder(), color: historyColor.withOpacity(0.1)),
            child: Text(historyLabel, style: GoogleFonts.alexandria(fontSize: 10, fontWeight: FontWeight.bold, color: historyColor)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(Icons.person_rounded, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(profile?['full_name'] ?? 'Guest', style: GoogleFonts.alexandria(fontSize: 14, fontWeight: FontWeight.w600, color: _subtextColor)),
          ]),
          Text('৳${((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: _textColor)),
        ]),
      ]),
    );
  }
}