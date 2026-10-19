import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../shared/utils/event_labels.dart';
import 'web_shared.dart';

// The date / time / status labels are shared with the app's event cards.
export '../../../shared/utils/event_labels.dart';

// Cells of the organizer web Events table (events_page.dart), kept apart from
// the page so they can be reused and rendered on their own.

/// What a row's Status cell says: one state — the same one the app's event
/// card shows (organizerEventStatus). Details live in the hover text.
class EventStatusView {
  final String  label;
  final Color   color;
  /// What the status means for this event (reason, deadline, pending
  /// changes), shown on hover.
  final String? tip;
  const EventStatusView(this.label, this.color, {this.tip});
}

/// A tinted pill with a dot.
class EventStatusPill extends StatelessWidget {
  final String label;
  final Color  color;
  const EventStatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          // Shrinks with an ellipsis in a narrow column instead of overflowing.
          Flexible(
            child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                  fontWeight: FontWeight.w600, height: 1.2,
                  color: readableStatusColor(color, dark))),
          ),
        ],
      ),
    );
  }
}

/// Just the pill — no second line under it; the explanation is on hover.
class EventStatusCell extends StatelessWidget {
  final EventStatusView view;
  const EventStatusCell({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    // Keeps the pill its own width inside the fixed-width column.
    final pill = Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: EventStatusPill(label: view.label, color: view.color),
    );
    return view.tip == null
        ? pill
        : Tooltip(message: view.tip!,
            waitDuration: const Duration(milliseconds: 300), child: pill);
  }
}

/// Registered count over a short, fixed-width meter — it never runs into the
/// next column. Capacity is every active student; the exact share is on hover.
class EventRegistrationsCell extends StatelessWidget {
  final int  registered;
  /// Active students; null until the count is known.
  final int? capacity;
  const EventRegistrationsCell({super.key, required this.registered, required this.capacity});

  @override
  Widget build(BuildContext context) {
    final t    = WebTk(Theme.of(context).brightness == Brightness.dark);
    final fill = capacityFill(registered, capacity);
    return Tooltip(
      message: capacity != null
          ? '$registered of $capacity students registered (${(fill * 100).round()}%)'
          : '$registered registered',
      waitDuration: const Duration(milliseconds: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$registered',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.text)),
              TextSpan(text: capacity != null ? ' / $capacity' : ' registered',
                style: TextStyle(fontSize: 12, color: t.sub)),
            ]),
            style: const TextStyle(fontFamily: 'Poppins',
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          if (capacity != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: 96,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fill,
                  minHeight: 4,
                  backgroundColor: t.divider,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Date without the year (a range for multi-day events) over the time slot;
/// the full date, year included, is on hover.
class EventDateCell extends StatelessWidget {
  final Map<String, dynamic> event;
  const EventDateCell({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final t     = WebTk(Theme.of(context).brightness == Brightness.dark);
    final start = DateTime.tryParse(event['event_date'] as String? ?? '');
    final end   = DateTime.tryParse(event['end_date'] as String? ?? '');
    final date  = start == null ? '—' : dateRangeLabel(start, end);
    final time  = timeRangeLabel(event['start_time'] as String?, event['end_time'] as String?);
    final cell  = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(date,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
              fontWeight: FontWeight.w500, color: t.text)),
        if (time.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(time,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
        ],
      ],
    );
    return start == null
        ? cell
        : Tooltip(message: dateRangeLabel(start, end, withYear: true),
            waitDuration: const Duration(milliseconds: 300), child: cell);
  }
}
