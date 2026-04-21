// lib/features/orders/rider_order_details_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RiderOrderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isDarkMode;

  const RiderOrderDetailsScreen({super.key, required this.order, required this.isDarkMode});

  @override
  State<RiderOrderDetailsScreen> createState() => _RiderOrderDetailsScreenState();
}

class _RiderOrderDetailsScreenState extends State<RiderOrderDetailsScreen> {
  late Map<String, dynamic> currentOrder;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    currentOrder = widget.order;
  }

  Future<void> _callCustomer(String? phone) async {
    HapticFeedback.lightImpact();
    if (phone == null || phone.isEmpty || phone == 'No phone number') return;
    final Uri url = Uri.parse('tel:$phone');
    try { await launchUrl(url, mode: LaunchMode.externalApplication); }
    catch (e) { debugPrint('Could not launch phone dialer'); }
  }

  Future<void> _openGoogleMaps(String? lat, String? lng, String? address) async {
    HapticFeedback.lightImpact();
    Uri url;
    if (lat != null && lng != null && lat != 'null' && lng != 'null') {
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else if (address != null && address.trim().isNotEmpty) {
      final encodedAddress = Uri.encodeComponent(address);
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No location or address provided for this order.'), backgroundColor: Colors.red));
      return;
    }

    try { await launchUrl(url, mode: LaunchMode.externalApplication); }
    catch (e) { debugPrint('Could not open Maps'); }
  }

  void _copyToClipboard(String text, String label) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied to clipboard', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  Future<void> _processOrderStatus(String newStatus, double progress) async {
    setState(() => isProcessing = true);
    HapticFeedback.heavyImpact();
    try {
      final now = DateTime.now();
      Map<String, dynamic> updateData = {'status': newStatus, 'progress': progress, 'updated_at': now.toIso8601String()};

      final pm = currentOrder['payment_method']?.toString().toLowerCase() ?? '';
      bool isCOD = pm.contains('cash') || pm.contains('cod');

      if (newStatus == 'delivered' && isCOD) {
        updateData['payment_status'] = 'paid';
      }

      await Supabase.instance.client.from('orders').update(updateData).eq('id', currentOrder['id']);

      // --- RESTORED LOGIC: Update Rider's Cash In Hand ---
      if (newStatus == 'delivered') {
        final riderId = currentOrder['delivery_rider_id'];
        if (riderId != null) {
          final riderData = await Supabase.instance.client.from('riders').select('cash_in_hand').eq('id', riderId).maybeSingle();
          if (riderData != null) {
            final currentCash = (riderData['cash_in_hand'] as num?)?.toDouble() ?? 0.0;
            final orderPrice = (currentOrder['total_price'] as num?)?.toDouble() ?? 0.0;

            await Supabase.instance.client.from('riders').update({
              'cash_in_hand': currentCash + orderPrice
            }).eq('id', riderId);
          }
        }
      }
      // ---------------------------------------------------

      setState(() {
        currentOrder['status'] = newStatus;
        currentOrder['progress'] = progress;
        isProcessing = false;
      });

      if (mounted && newStatus == 'delivered') Navigator.pop(context);

    } catch (e) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update order')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final borderColor = isDark ? const Color(0xFF334155).withOpacity(0.5) : const Color(0xFFE2E8F0);
    final iconBgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    final status = currentOrder['status'] as String? ?? '';
    final isDelivery = status == 'out_for_delivery';
    final themeColor = isDelivery ? const Color(0xFF3B82F6) : const Color(0xFF8B5CF6);

    final profile = currentOrder['profiles'] as Map?;
    final isAdminOrder = currentOrder['is_manual'] == true;
    final rawName = currentOrder['manual_customer_name'] ?? profile?['full_name'] ?? 'Guest Customer';
    final customerName = isAdminOrder ? '$rawName (Admin Order)' : rawName;
    final customerPhone = currentOrder['manual_customer_phone'] ?? profile?['phone'] ?? 'No phone number';

    String address = isDelivery ? (currentOrder['delivery_address'] ?? currentOrder['pickup_address'] ?? '') : (currentOrder['pickup_address'] ?? '');
    if (address.trim().isEmpty) address = 'No address provided';

    final lat = isDelivery ? (currentOrder['delivery_lat']?.toString() ?? currentOrder['latitude']?.toString()) : (currentOrder['pickup_lat']?.toString() ?? currentOrder['latitude']?.toString());
    final lng = isDelivery ? (currentOrder['delivery_lng']?.toString() ?? currentOrder['longitude']?.toString()) : (currentOrder['pickup_lng']?.toString() ?? currentOrder['longitude']?.toString());

    final totalPrice = ((currentOrder['total_price'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
    final specialInstructions = currentOrder['special_instructions'] ?? 'None';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Order #${currentOrder['order_number'] ?? '000'}', style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.bold, fontSize: 20)),
      ),
      body: Hero(
        tag: 'order_card_${currentOrder['id']}',
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text('Customer Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: subtextColor)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: themeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.person_rounded, color: themeColor)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customerName, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(customerPhone, style: GoogleFonts.inter(fontSize: 14, color: subtextColor, fontWeight: FontWeight.w500)),
                                const SizedBox(width: 8),
                                GestureDetector(onTap: ()=> _copyToClipboard(customerPhone, "Phone Number"), child: Icon(Icons.copy_rounded, size: 14, color: subtextColor.withOpacity(0.7)))
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => _callCustomer(customerPhone), icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.green), style: IconButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.15), padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                Text('Location', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: subtextColor)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(isDelivery ? 'Delivery Address' : 'Pickup Address', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: subtextColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Text(address, style: GoogleFonts.inter(fontSize: 16, color: textColor, height: 1.5, fontWeight: FontWeight.w500))),
                          const SizedBox(width: 12),
                          GestureDetector(onTap: ()=> _copyToClipboard(address, "Address"), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.copy_rounded, size: 16, color: subtextColor)))
                        ],
                      ),
                      const SizedBox(height: 24),

                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: InkWell(
                            onTap: () => _openGoogleMaps(lat, lng, address),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(color: themeColor.withOpacity(0.1), border: Border.all(color: themeColor.withOpacity(0.2)), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.navigation_rounded, color: themeColor, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Navigate with Maps', style: GoogleFonts.inter(color: themeColor, fontWeight: FontWeight.bold, fontSize: 15))
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                Text('Order Summary', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: subtextColor)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.03), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Cash to Collect', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                          Text('৳$totalPrice', style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.green.shade600)),
                        ],
                      ),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: borderColor)),
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: isDark ? Colors.amber.shade400 : Colors.orange),
                          const SizedBox(width: 8),
                          Text('Special Instructions', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: subtextColor)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(16)),
                        child: Text(specialInstructions, style: GoogleFonts.inter(fontSize: 15, color: textColor, fontStyle: FontStyle.italic, height: 1.4)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                if (status == 'assign_pickup')
                  _buildSlider('Slide to Pick Up', themeColor, () => _processOrderStatus('picked_up', 0.4))
                else if (status == 'picked_up')
                  _buildSlider('Slide to Drop Off', themeColor, () => _processOrderStatus('dropped', 0.5))
                else if (status == 'dropped')
                    Center(child: Text('Order is being processed at hub...', style: GoogleFonts.inter(color: subtextColor, fontWeight: FontWeight.bold)))
                  else if (isDelivery)
                      _buildSlider('Slide to Deliver (Collect ৳$totalPrice)', Colors.green.shade600, () => _processOrderStatus('delivered', 1.0))
                    else if (status == 'delivered')
                        Center(child: Text('Order Completed!', style: GoogleFonts.outfit(color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold))),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(String text, Color color, Future<void> Function() onSubmit) {
    if (isProcessing) {
      return Center(child: CircularProgressIndicator(color: color));
    }
    return SlideAction(
      onSubmit: onSubmit,
      borderRadius: 24,
      elevation: 0,
      innerColor: Colors.white,
      outerColor: color,
      sliderButtonIcon: Icon(Icons.arrow_forward_ios_rounded, color: color),
      text: text,
      textStyle: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      sliderRotate: false,
    );
  }
}