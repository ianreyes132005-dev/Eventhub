import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/app_colors.dart';

String _fullDate(String? iso) {
  if (iso == null) return 'â€”';
  try {
    final d  = DateTime.parse(iso).toLocal();
    const mo = ['January','February','March','April','May','June',
                'July','August','September','October','November','December'];
    final h  = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m  = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${mo[d.month - 1]} ${d.day}, ${d.year}  Â·  $h:$m $ap';
  } catch (_) { return iso; }
}

class AnnouncementViewScreen extends StatelessWidget {
  final String  id;
  final String  title;
  final String  message;
  final String? createdAt;

  const AnnouncementViewScreen({
    super.key,
    required this.id,
    required this.title,
    required this.message,
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: kBackground,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverToBoxAdapter(child: _buildHeroBanner()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildMessageCard(),
                    const SizedBox(height: 12),
                    _buildMetaCard(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kText),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Announcement',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: kText),
            ),
          ),
          // Copy button
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Message copied', style: TextStyle(fontFamily: 'Poppins')),
                  backgroundColor: kGold,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: const Icon(Icons.copy_rounded, size: 18, color: kText),
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Hero banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildHeroBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFC49230), Color(0xFFD6A742), Color(0xFFEAB866)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: kGold.withValues(alpha: 0.38), blurRadius: 22, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Decorative circles
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 26),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text('Sent', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 19,
                fontWeight: FontWeight.w800, color: Colors.white, height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, size: 13, color: Colors.white70),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _fullDate(createdAt),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Message card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildMessageCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: kGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.message_outlined, color: kGold, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'MESSAGE',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: kMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: kText, height: 1.75),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Meta card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildMetaCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: kGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.info_outline_rounded, color: kGold, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'DETAILS',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: kMuted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _metaRow(Icons.calendar_today_rounded, 'Published',  _fullDate(createdAt)),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),
          _metaRow(Icons.groups_rounded,          'Audience',   'All Students'),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 12),
          _metaRow(Icons.tag_rounded,             'Ref ID',     '#$id'),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: kGold.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: kGold, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted)),
              const SizedBox(height: 3),
              Text(value,  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
            ],
          ),
        ),
      ],
    );
  }
}
