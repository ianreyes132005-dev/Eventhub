import 'package:flutter/material.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/app_colors.dart';
import '../../../../shared/widgets/error_alert.dart';

class NewAnnouncementScreen extends StatefulWidget {
  const NewAnnouncementScreen({super.key});

  @override
  State<NewAnnouncementScreen> createState() => _NewAnnouncementScreenState();
}

class _NewAnnouncementScreenState extends State<NewAnnouncementScreen> {
  final _titleCtrl   = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _publishing   = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() => setState(() {}));
    _messageCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      _titleCtrl.text.trim().isNotEmpty &&
      _messageCtrl.text.trim().isNotEmpty;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (!_canPublish) { _snack('Title and message are required.', Colors.red); return; }
    setState(() => _publishing = true);
    try {
      await SupabaseService.createAnnouncement(
        title:   _titleCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
      );
      if (!mounted) return;
      _snack('Announcement published!', const Color(0xFF16A34A));
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _publishing = false);
        showErrorAlert(context, e, title: 'Couldn’t publish the announcement');
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(t),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: _buildComposeSurface(t),
              ),
            ),
            _buildBottomBar(context, t),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: t.text),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New Announcement',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: t.text, height: 1.1),
              ),
              Text(
                'Notify all students instantly',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Compose surface ───────────────────────────────────────────────────────

  Widget _buildComposeSurface(AppTk t) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title field ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('TITLE', t),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleCtrl,
                  maxLength: 100,
                  maxLines: 2,
                  minLines: 1,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 16,
                    fontWeight: FontWeight.w700, color: t.text,
                  ),
                  decoration: _fieldDecor(
                    hint: 'e.g. Pep Rally Reminder',
                    counterText: '${_titleCtrl.text.length}/100',
                    t: t,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 24, color: t.divider),
          ),

          // ── Message field ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('MESSAGE', t),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 9,
                  minLines: 5,
                  maxLength: 1000,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14,
                    color: t.text, height: 1.65,
                  ),
                  decoration: _fieldDecor(
                    hint: 'Write what students need to know…',
                    counterText: '${_messageCtrl.text.length}/1000',
                    t: t,
                  ),
                ),
              ],
            ),
          ),

          // ── Audience chip (read-only info) ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGold.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: kGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.groups_rounded, color: kGold, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Audience', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                        const SizedBox(height: 2),
                        Text('All Students', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: t.text)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Instant',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom action bar ─────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context, AppTk t) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
      decoration: BoxDecoration(
        color: t.card,
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: (_publishing || !_canPublish) ? null : _publish,
          icon: _publishing
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : const Icon(Icons.send_rounded, size: 20),
          label: Text(
            _publishing ? 'Publishing…' : 'Publish Announcement',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _canPublish ? kGold : kMuted,
            foregroundColor: Colors.white,
            elevation: _canPublish ? 3 : 0,
            shadowColor: kGold.withValues(alpha: 0.40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _fieldLabel(String text, AppTk t) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Poppins', fontSize: 10,
      fontWeight: FontWeight.w700, letterSpacing: 1.1, color: t.muted,
    ),
  );

  InputDecoration _fieldDecor({required String hint, required AppTk t, String counterText = ''}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.muted),
      counterText: counterText,
      counterStyle: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
      border:        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kGold, width: 2)),
      filled: true,
      fillColor: t.inputBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
