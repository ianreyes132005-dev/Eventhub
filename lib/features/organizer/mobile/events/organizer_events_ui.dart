import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../shared/utils/event_labels.dart';
import '../org_tab_ui.dart';

export '../org_tab_ui.dart';

// The look of the organizer app's Events tab: its header and the event cards.
// The search field, filter chips, buttons and messages are shared with the
// Registrations tab (org_tab_ui.dart). Purely visual: organizer_events.dart
// keeps the data, filters, rules and actions and hands them in.

const Color _kGreen = Color(0xFF16A34A);
const Color _kBlue  = Color(0xFF2563EB);

// ── Header ──────────────────────────────────────────────────────────────────

/// "My Events" with New event on the right.
class OrgEventsHeader extends StatelessWidget {
  final VoidCallback onCreate;
  final AppTk t;
  const OrgEventsHeader({
    super.key,
    required this.onCreate,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return OrgTabHeader(
      title: 'My Events',
      t: t,
      action: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: kGold.withValues(alpha: t.dark ? 0.12 : 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Tooltip(
          message: 'Create a new event',
          child: OrgPrimaryButton(
            label: 'New event',
            icon: Icons.add_rounded,
            onPressed: onCreate,
          ),
        ),
      ),
    );
  }
}

// ── Event card ──────────────────────────────────────────────────────────────

/// One event: banner (status, start date, delete), title, schedule and venue,
/// registration numbers, then Edit / Details.
class OrganizerEventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final int registered;
  /// Every active student; null until the count loads.
  final int? capacity;
  final int checkedIn;
  final bool canEdit;
  final bool canDelete;
  final bool deleting;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final AppTk t;

  const OrganizerEventCard({
    super.key,
    required this.event,
    required this.registered,
    required this.capacity,
    required this.checkedIn,
    required this.canEdit,
    required this.canDelete,
    required this.deleting,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final eventId  = event['event_id'] as String? ?? '';
    final title    = event['title'] as String? ?? '—';
    final location = event['location'] as String? ?? '—';
    final type     = event['event_type'] as String?;
    final start    = DateTime.tryParse(event['event_date'] as String? ?? '');
    // Same compact labels as the web Events table: "Oct 25–27", "1:00–4:00 PM".
    final date = start == null
        ? '—'
        : dateRangeLabel(start, DateTime.tryParse(event['end_date'] as String? ?? ''));
    final time = timeRangeLabel(
        event['start_time'] as String?, event['end_time'] as String?);
    final shortId = eventId.length > 8
        ? '…${eventId.substring(eventId.length - 8)}'
        : eventId;
    final attendancePct =
        registered > 0 ? ((checkedIn / registered) * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 3)),
          ],
        ),
        child: Material(
          color: t.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(title, start),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: type != null && type.isNotEmpty
                                ? _TypeTag(label: type, t: t)
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          shortId,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: t.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MetaLine(
                      icon: Icons.schedule_rounded,
                      text: time.isEmpty ? date : '$date  ·  $time',
                      t: t,
                    ),
                    const SizedBox(height: 6),
                    _MetaLine(icon: Icons.place_outlined, text: location, t: t),
                    const SizedBox(height: 14),
                    _StatsPanel(
                      registered: registered,
                      capacity: capacity,
                      checkedIn: checkedIn,
                      attendancePct: attendancePct,
                      t: t,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (canEdit) ...[
                          Expanded(
                            child: OrgPrimaryButton(
                              label: 'Edit',
                              icon: Icons.edit_outlined,
                              onPressed: onEdit,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: OrgSecondaryButton(
                            label: 'Details',
                            icon: Icons.info_outline_rounded,
                            onPressed: onOpen,
                            t: t,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(String title, DateTime? start) {
    final imageUrl = event['event_image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final status   = organizerEventStatus(event);
    final danger   = t.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

    return SizedBox(
      height: 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasImage
              ? Image.network(imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholder())
              : _placeholder(),
          // Tap anywhere on the banner for the details (ripple included).
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                button: true,
                label: 'Open $title',
                child: InkWell(onTap: onOpen),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: IgnorePointer(
              child: _StatusChip(label: status.label, color: status.color, t: t),
            ),
          ),
          if (start != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: IgnorePointer(child: _DateTile(date: start, t: t)),
            ),
          if (canDelete)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Delete event',
                onPressed: deleting ? null : onDelete,
                style: IconButton.styleFrom(
                  backgroundColor: t.card.withValues(alpha: 0.94),
                  disabledBackgroundColor: t.card.withValues(alpha: 0.94),
                  foregroundColor: danger,
                  minimumSize: const Size(40, 40),
                  maximumSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                ),
                icon: deleting
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2, color: danger),
                      )
                    : Icon(Icons.delete_outline_rounded, color: danger, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kGold.withValues(alpha: t.dark ? 0.20 : 0.22),
              kGold.withValues(alpha: t.dark ? 0.06 : 0.07),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Center(
          child: Icon(Icons.event_rounded,
              size: 44, color: kGold.withValues(alpha: 0.45)),
        ),
      );
}

// The event's one status, nothing under it: the same words, colours and dot
// as the web Events table's pill (organizerEventStatus), on a solid card so
// it reads over any banner image.
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final AppTk t;
  const _StatusChip({required this.label, required this.color, required this.t});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: readableStatusColor(color, t.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Calendar-style start date on the banner: "OCT" over "25".
class _DateTile extends StatelessWidget {
  final DateTime date;
  final AppTk t;
  const _DateTile({required this.date, required this.t});

  @override
  Widget build(BuildContext context) {
    final month = monthDayLabel(date).split(' ').first.toUpperCase();
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            month,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: goldText(t),
              height: 1.2,
            ),
          ),
          Text(
            '${date.day}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: t.text,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String label;
  final AppTk t;
  const _TypeTag({required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: t.dark ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: goldText(t),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final AppTk t;
  const _MetaLine({required this.icon, required this.text, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: t.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: t.sub,
            ),
          ),
        ),
      ],
    );
  }
}

/// Registered (of all students) · Checked in · Attendance, in one panel.
class _StatsPanel extends StatelessWidget {
  final int registered;
  final int? capacity;
  final int checkedIn;
  final int attendancePct;
  final AppTk t;
  const _StatsPanel({
    required this.registered,
    required this.capacity,
    required this.checkedIn,
    required this.attendancePct,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    Widget divider() => Container(width: 1, height: 34, color: t.divider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.dark ? const Color(0xFF1E1912) : const Color(0xFFFAF7F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          _stat('$registered', 'Registered', t.text,
              suffix: capacity != null ? ' / $capacity' : null),
          divider(),
          _stat('$checkedIn', 'Checked in', readableStatusColor(_kGreen, t.dark),
              leftPad: true),
          divider(),
          _stat('$attendancePct%', 'Attendance', readableStatusColor(_kBlue, t.dark),
              leftPad: true),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color,
      {String? suffix, bool leftPad = false}) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(left: leftPad ? 12 : 0, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  if (suffix != null)
                    TextSpan(
                      text: suffix,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.muted,
                      ),
                    ),
                ]),
                style: const TextStyle(fontFamily: 'Poppins', height: 1.2),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty / error message ───────────────────────────────────────────────────

class OrgEventsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  /// Red tint for errors; gold otherwise.
  final bool isError;
  final AppTk t;
  const OrgEventsMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.t,
    this.action,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = isError
        ? (t.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
        : goldText(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: tint),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: t.muted,
              height: 1.55,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 22),
            action!,
          ],
        ],
      ),
    );
  }
}
