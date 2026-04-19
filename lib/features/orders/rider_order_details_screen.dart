// lib/features/orders/screens/rider_order_details_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class RiderOrderDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const RiderOrderDetailsScreen({super.key, required this.order});

  Future<void> _callCustomer(String? phone) async {
    if (phone == null || phone.isEmpty || phone == 'No phone number') return;
    final Uri url = Uri.parse('tel:$phone');
    try { await launchUrl(url, mode: LaunchMode.externalApplication); }
    catch (e) { debugPrint('Could not launch phone dialer'); }
  }

  Future<void> _openGoogleMaps(String? lat, String? lng, String? address) async {
    Uri url;
    if (lat != null && lng != null && lat != 'null' && lng != 'null') {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      final encodedAddress = Uri.encodeComponent(address ?? '');
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    }
    try { await launchUrl(url, mode: LaunchMode.externalApplication); }
    catch (e) { debugPrint('Could not open Maps'); }
  }

  @override
  Widget build(BuildContext context) {
    // ─── DYNAMIC THEME COLORS ───
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final iconBgColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final primaryBlue = const Color(0xFF3B82F6);

    final profile = order['profiles'] as Map?;
    final status = order['status'] as String? ?? '';
    final isPickup = status == 'picked_up';
    final themeColor = isPickup ? const Color(0xFF8B5CF6) : primaryBlue;

    final isAdminOrder = order['is_manual'] == true;
    final rawName = order['manual_customer_name'] ?? profile?['full_name'] ?? 'Guest Customer';
    final customerName = isAdminOrder ? '$rawName (Admin Order)' : rawName;
    final customerPhone = order['manual_customer_phone'] ?? profile?['phone'] ?? 'No phone number';

    final address = order['pickup_address'] ?? 'No address provided';
    final lat = order['latitude']?.toString() ?? order['pickup_lat']?.toString();
    final lng = order['longitude']?.toString() ?? order['pickup_lng']?.toString();
    final totalPrice = ((order['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
    final specialInstructions = order['special_instructions'] ?? 'None';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Order #${order['order_number'] ?? '000'}',
            style: GoogleFonts.alexandria(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- CUSTOMER INFO CARD ---
            Text('Customer Details', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: subtextColor)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: themeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                    child: Icon(Icons.person_rounded, color: themeColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customerName, style: GoogleFonts.alexandria(fontSize: 17, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(height: 6),
                        Text(customerPhone, style: GoogleFonts.alexandria(fontSize: 14, color: subtextColor, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _callCustomer(customerPhone),
                    icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.green),
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.green.withOpacity(0.15),
                        padding: const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 32),

            // --- LOCATION CARD ---
            Text('Location', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: subtextColor)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                            const SizedBox(width: 8),
                            Text('Pickup / Delivery Address', style: GoogleFonts.alexandria(fontSize: 13, fontWeight: FontWeight.w600, color: subtextColor)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(address, style: GoogleFonts.alexandria(fontSize: 16, color: textColor, height: 1.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => _openGoogleMaps(lat, lng, address),
                    icon: Icon(Icons.navigation_rounded, color: themeColor),
                    style: IconButton.styleFrom(
                        backgroundColor: themeColor.withOpacity(0.15),
                        padding: const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 32),

            // --- ORDER SUMMARY CARD ---
            Text('Order Summary', style: GoogleFonts.alexandria(fontSize: 15, fontWeight: FontWeight.bold, color: subtextColor)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cash to Collect', style: GoogleFonts.alexandria(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                      Text('৳$totalPrice', style: GoogleFonts.alexandria(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green.shade600)),
                    ],
                  ),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: borderColor)),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: isDark ? Colors.amber.shade400 : Colors.orange),
                      const SizedBox(width: 8),
                      Text('Special Instructions', style: GoogleFonts.alexandria(fontSize: 13, fontWeight: FontWeight.w600, color: subtextColor)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(16)),
                    child: Text(specialInstructions, style: GoogleFonts.alexandria(fontSize: 15, color: textColor, fontStyle: FontStyle.italic, height: 1.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}