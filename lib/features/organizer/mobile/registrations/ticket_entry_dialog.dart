import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/registration_service.dart';
import '../../../../core/ticket_code.dart';
import '../../../../shared/widgets/error_alert.dart';
import '../org_tab_ui.dart' show kOnGold;

// ─────────────────────────────────────────────────────────────────────────────
// "Type Ticket ID" — the scanner's fallback for a ticket whose QR won't scan.
// The organizer types the 4-digit code printed under the student's QR code;
// the box finds that ticket in the organizer's events and hands back its QR
// value, so the same confirm screen opens as after a scan.
// ─────────────────────────────────────────────────────────────────────────────

/// Finds the organizer's tickets with a Ticket ID (tests pass their own).
typedef TicketLookup = Future<List<TicketMatch>> Function(String code);

/// Shows the box. Resolves to the ticket's QR value — what a scan would have
/// read — or null when the organizer closes it.
Future<String?> showTicketEntryDialog(BuildContext context, {TicketLookup? lookup}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => TicketEntryDialog(
      lookup: lookup ?? RegistrationService.findByTicketCode,
    ),
  );
}

const _kSurface = Color(0xFF1C1814);
const _kErrorText = Color(0xFFFF8A80);

class TicketEntryDialog extends StatefulWidget {
  final TicketLookup lookup;
  const TicketEntryDialog({required this.lookup, super.key});

  @override
  State<TicketEntryDialog> createState() => _TicketEntryDialogState();
}

class _TicketEntryDialogState extends State<TicketEntryDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String _code = '';
  // Set when the code is on tickets in several of the organizer's events.
  List<TicketMatch>? _choices;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static String _qrValueOf(TicketMatch m) =>
      m.registration['qr_code'] as String? ?? m.registration['id'] as String;

  Future<void> _lookUp() async {
    if (_busy) return;
    final input = parseTicketInput(_ctrl.text);
    switch (input.kind) {
      case TicketInputKind.invalid:
        setState(() => _error = _ctrl.text.trim().isEmpty
            ? 'Type the Ticket ID first.'
            : 'A Ticket ID is 4 digits, like 4821.');
        return;
      case TicketInputKind.qrValue:
        Navigator.pop(context, input.value);
        return;
      case TicketInputKind.ticketCode:
        break;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final matches = await widget.lookup(input.value);
      if (!mounted) return;
      final now = DateTime.now();
      final choices =
          ticketChoices(matches, (m) => checkInIsOpen(m.event, now: now));
      if (choices.length == 1) {
        Navigator.pop(context, _qrValueOf(choices.single));
        return;
      }
      setState(() {
        _busy = false;
        _code = input.value;
        if (choices.isEmpty) {
          _error = 'No ticket with ID ${input.value} in your events.';
        } else {
          _choices = choices;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorAlert(context, e, title: 'Couldn’t look up the ticket');
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    return Dialog(
      backgroundColor: _kSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: choices == null ? _buildEntry() : _buildChoices(choices),
        ),
      ),
    );
  }

  // ── Typing the code ───────────────────────────────────────────────────────

  Widget _buildEntry() {
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DialogTitle(
          icon: Icons.keyboard_rounded,
          title: 'Type Ticket ID',
          subtitle: 'Shown under the student’s QR code',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _ctrl,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.search,
          textAlign: TextAlign.center,
          cursorColor: kGold,
          // A centred cursor would cut through the "0000" hint; the gold
          // border already shows the box is ready.
          showCursor: _ctrl.text.isNotEmpty,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _lookUp(),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 8,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: '0000',
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
              color: Colors.white.withValues(alpha: 0.16),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            // 8 more on the left balances the letter spacing after the last
            // digit, so the code sits in the middle.
            contentPadding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: error != null ? _kErrorText : kGold,
                width: 1.5,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.topCenter,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 16, color: _kErrorText),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            height: 1.35,
                            color: _kErrorText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _OutlineButton(
                label: 'Cancel',
                onPressed: _busy ? null : () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _busy ? null : _lookUp,
                style: FilledButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: kOnGold,
                  disabledBackgroundColor: kGold.withValues(alpha: 0.55),
                  disabledForegroundColor: kOnGold,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: kOnGold,
                        ),
                      )
                    : const Text(
                        'Look Up',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Same code in several events ───────────────────────────────────────────

  Widget _buildChoices(List<TicketMatch> choices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DialogTitle(
          icon: Icons.confirmation_num_rounded,
          title: 'Ticket ID $_code',
          subtitle: '${choices.length} of your events have a ticket with '
              'this ID. Pick the student’s event.',
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: choices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ChoiceTile(
              match: choices[i],
              onTap: () => Navigator.pop(context, _qrValueOf(choices[i])),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _OutlineButton(
          label: 'Back',
          onPressed: () => setState(() => _choices = null),
        ),
      ],
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _DialogTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _DialogTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: kGold, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _OutlineButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        foregroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final TicketMatch match;
  final VoidCallback onTap;
  const _ChoiceTile({required this.match, required this.onTap});

  static String _when(DateTime d) {
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${mo[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  @override
  Widget build(BuildContext context) {
    final event = match.event;
    final title = (event['title'] as String?)?.trim().isNotEmpty == true
        ? event['title'] as String
        : match.registration['event_title'] as String? ?? 'Event';
    final start = eventWindow(event)?.start;
    final student = match.registration['student_name'] as String? ?? '';
    final details = [if (start != null) _when(start), if (student.isNotEmpty) student];

    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
