// lib/features/orders/screens/rider_order_details_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class RiderOrderDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const RiderOrderDetailsScreen({super.key, required this.order});

  // Theme Colors
  final Color _primaryBlue = const Color(0xFF3B82F6);
  final Color _bgColor = const Color(0xFFF8FAFC);
  final Color _textColor = const Color(0xFF1E293B);
  final Color _subtextColor = const Color(0xFF64748B);

  Future<void> _callCustomer(String? phone) async {
    if (phone == null || phone.isEmpty || phone == 'No phone number') return;
    final Uri url = Uri.parse('tel:$phone');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch phone dialer');
    }
  }

  Future<void> _openGoogleMaps(String? lat, String? lng, String? address) async {
    Uri url;
    if (lat != null && lng != null && lat != 'null' && lng != 'null') {
      // Official Google Maps Intent for Coordinates
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      // Official Google Maps Intent for Address Search
      final encodedAddress = Uri.encodeComponent(address ?? '');
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    }

    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open Maps');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = order['profiles'] as Map?;
    final status = order['status'] as String? ?? '';
    final isPickup = status == 'picked_up';
    final themeColor = isPickup ? const Color(0xFF8B5CF6) : _primaryBlue;

    // 1. Check if it's a manual order
    final isAdminOrder = order['is_manual'] == true;

    // 2. Name Logic: Use manual entry first, then profile, then fallback
    final rawName = order['manual_customer_name'] ?? profile?['full_name'] ?? 'Guest Customer';
    final customerName = isAdminOrder ? '$rawName (Admin Order)' : rawName;

    // 3. Phone Logic: Use manual phone column to match the Admin App's insert
    final customerPhone = order['manual_customer_phone'] ?? profile?['phone'] ?? 'No phone number';

    final address = order['pickup_address'] ?? 'No address provided';
    final lat = order['latitude']?.toString() ?? order['pickup_lat']?.toString();
    final lng = order['longitude']?.toString() ?? order['pickup_lng']?.toString();
    final totalPrice = ((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
    final specialInstructions = order['special_instructions'] ?? 'None';

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: _textColor),
        title: Text('Order #${order['order_number'] ?? '000'}',
            style: GoogleFonts.alexandria(color: _textColor, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- CUSTOMER INFO CARD ---
            Text('Customer Details', style: GoogleFonts.alexandria(fontSize: 14, fontWeight: FontWeight.bold, color: _subtextColor)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: themeColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(Icons.person, color: themeColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customerName, style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.bold, color: _textColor)),
                        const SizedBox(height: 4),
                        Text(customerPhone, style: GoogleFonts.alexandria(fontSize: 14, color: _subtextColor)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _callCustomer(customerPhone),
                    icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.green),
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.green.withOpacity(0.1),
                        padding: const EdgeInsets.all(12)
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 24),

            // --- LOCATION CARD ---
            Text('Location', style: GoogleFonts.alexandria(fontSize: 14, fontWeight: FontWeight.bold, color: _subtextColor)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded, size: 16, color: Colors.grey.shade400),
                            const SizedBox(width: 8),
                            Text('Pickup / Delivery Address', style: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w600, color: _subtextColor)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(address, style: GoogleFonts.alexandria(fontSize: 15, color: _textColor, height: 1.4)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => _openGoogleMaps(lat, lng, address),
                    icon: Icon(Icons.navigation_rounded, color: themeColor),
                    style: IconButton.styleFrom(backgroundColor: themeColor.withOpacity(0.1)),
                  )
                ],
              ),
            ),

            const SizedBox(height: 24),

            // --- ORDER SUMMARY CARD ---
            Text('Order Summary', style: GoogleFonts.alexandria(fontSize: 14, fontWeight: FontWeight.bold, color: _subtextColor)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cash to Collect', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor)),
                      Text('৳$totalPrice', style: GoogleFonts.alexandria(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade600)),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFF1F5F9))),
                  Text('Special Instructions:', style: GoogleFonts.alexandria(fontSize: 12, fontWeight: FontWeight.w600, color: _subtextColor)),
                  const SizedBox(height: 8),
                  Text(specialInstructions, style: GoogleFonts.alexandria(fontSize: 14, color: _textColor, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            const SizedBox(height: 100), // Space to ensure content isn't hidden by slider
          ],
        ),
      ),
    );
  }
}