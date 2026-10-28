import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../shared/utils/event_labels.dart';
import '../org_tab_ui.dart';

// The look of the organizer app's Registrations tab: the registration card,
// the select and bulk-action bars, and the details sheet — made from the same
// pieces as the Events tab (org_tab_ui.dart), so the two tabs match. Purely
// visual: organizer_registrations.dart keeps the data, filters and actions and
// hands them in.

/// Selection (checkbox, selected card, bulk bar) and the event filter's
/// accent — the same purple as the web Registrations page.
const Color kRegSelectColor = Color(0xFF8B5CF6);

const Color _kGreen = Color(0xFF16A34A);

String registrationStatusLabel(String s) {
  const map = {
    'pending': 'Pending',
    'qr_scanned': 'QR Scanned',
    'photo_required': 'Awaiting Selfie',
    'photo_submitted': 'Photo Submitted',
    'checked_in': 'Checked In',
    'rejected': 'Rejected',
  };
  return map[s] ?? s;
}

Color registrationStatusColor(String s) {
  switch (s) {
    case 'pending':
      return const Color(0xFFE87A00);
    case 'qr_scanned':
      return const Color(0xFF2979C8);
    case 'photo_required':
      return const Color(0xFF9333EA);
    case 'photo_submitted':
      return const Color(0xFF0891B2);
    case 'checked_in':
      return const Color(0xFF16A34A);
    case 'rejected':
      return const Color(0xFFDC2626);
    default:
      return kMuted;
  }
}

String registrationInitials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return parts.isNotEmpty && parts[0].isNotEmpty
      ? parts[0][0].toUpperCase()
      : '?';
}

/// "Oct 19, 2026" from an ISO timestamp (the text itself if it isn't one).
String registrationDateLabel(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return iso;
  }
}

Color _danger(AppTk t) => t.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

// ── Registration card ───────────────────────────────────────────────────────

/// One registration: the student and their status, the event, the selfie
/// once it's in, and the next step for that status.
class OrgRegistrationCard extends StatelessWidget {
  final Map<String, dynamic> registration;
  final String? selfieUrl;
  final bool selected;

  /// A bulk update is running — selection is locked.
  final bool busy;

  /// This card's selfie request is on its way.
  final bool sending;

  /// The admin archived this event: the attendance is a frozen record, so
  /// the card has no actions (and the check-in photo was deleted).
  final bool archived;

  /// The event's check-in has closed: the attendance is final (only the
  /// admin can correct it), so the card has no actions either.
  final bool attendanceFinal;

  final VoidCallback onToggleSelect;
  final VoidCallback onRequestSelfie;
  final VoidCallback onCheckIn;
  final VoidCallback onReject;
  final VoidCallback onDetails;
  final VoidCallback onDelete;
  final AppTk t;

  const OrgRegistrationCard({
    super.key,
    required this.registration,
    required this.selfieUrl,
    required this.selected,
    required this.busy,
    required this.sending,
    this.archived = false,
    this.attendanceFinal = false,
    required this.onToggleSelect,
    required this.onRequestSelfie,
    required this.onCheckIn,
    required this.onReject,
    required this.onDetails,
    required this.onDelete,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final r = registration;
    final name = r['student_name'] as String? ?? '—';
    final sid = r['student_school_id'] as String? ?? '—';
    final event = r['event_title'] as String? ?? '—';
    final registeredAt = r['registered_at'] as String? ?? '';
    final checkedInAt = r['checked_in_at'] as String?;
    final status = r['status'] as String? ?? 'pending';
    final color = registrationStatusColor(status);
    // Archived or final: a record, not a to-do.
    final locked = archived || attendanceFinal;
    final note = (r['attendance_note'] as String?)?.trim() ?? '';

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
            side: selected
                ? const BorderSide(color: kRegSelectColor, width: 1.5)
                : BorderSide(color: t.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(initials: registrationInitials(name), color: color, t: t),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatLrn(sid),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: t.muted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RegistrationStatusChip(
                      label: registrationStatusLabel(status),
                      color: color,
                      t: t,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _MetaLine(icon: Icons.event_rounded, text: event, t: t),
                const SizedBox(height: 6),
                _MetaLine(
                  icon: Icons.schedule_rounded,
                  text: 'Registered ${registrationDateLabel(registeredAt)}',
                  t: t,
                ),
                if (status == 'checked_in') ...[
                  const SizedBox(height: 6),
                  _MetaLine(
                    icon: Icons.check_circle_rounded,
                    text: checkedInAt == null
                        ? 'Checked in'
                        : 'Checked in ${registrationDateLabel(checkedInAt)}',
                    color: readableStatusColor(_kGreen, t.dark),
                    t: t,
                  ),
                ],
                if (status == 'checked_in' && note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _MetaLine(
                    icon: Icons.edit_note_rounded,
                    text: r['corrected_at'] != null
                        ? 'Corrected by the admin: $note'
                        : 'Checked in by hand: $note',
                    t: t,
                  ),
                ],
                if (archived) ...[
                  const SizedBox(height: 6),
                  _MetaLine(
                    icon: Icons.inventory_2_outlined,
                    text: 'Archived · read-only attendance record',
                    color: readableStatusColor(kArchivedColor, t.dark),
                    t: t,
                  ),
                ] else if (attendanceFinal) ...[
                  const SizedBox(height: 6),
                  _MetaLine(
                    icon: Icons.lock_clock_rounded,
                    text: 'Check-in closed · attendance is final',
                    t: t,
                  ),
                ],
                if (status == 'photo_submitted' && !locked) ...[
                  const SizedBox(height: 14),
                  _SelfiePreview(
                    url: selfieUrl,
                    path: r['selfie_url'] as String?,
                    // Selecting is about the selfie, so the checkbox sits with it.
                    select: _SelectToggle(
                      selected: selected,
                      enabled: !busy,
                      onToggle: onToggleSelect,
                      t: t,
                    ),
                    t: t,
                  ),
                ],
                if (status == 'photo_required' && !locked) ...[
                  const SizedBox(height: 12),
                  _WaitingStrip(t: t),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: locked
                          ? OrgSecondaryButton(
                              label: 'View Details',
                              icon: Icons.info_outline_rounded,
                              onPressed: onDetails,
                              t: t,
                            )
                          : _nextStep(status),
                    ),
                    // Checked-in registrations are the attendance record.
                    if (!locked && registrationDeletable(r)) ...[
                      const SizedBox(width: 10),
                      _MoreButton(onDelete: onDelete, t: t),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // The next step for this status, in the Events tab's buttons.
  Widget _nextStep(String status) {
    switch (status) {
      case 'pending':
        return _DisabledAction(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Scan QR Code First',
          tooltip: "Scan the student's QR code before requesting a selfie.",
          color: t.muted,
          t: t,
        );
      case 'qr_scanned':
        return OrgPrimaryButton(
          label: 'Request Selfie',
          icon: Icons.add_a_photo_rounded,
          onPressed: onRequestSelfie,
        );
      case 'photo_required':
        return _DisabledAction(
          icon: Icons.photo_camera_outlined,
          busy: sending,
          label: sending ? 'Sending Request' : 'Awaiting Selfie',
          tooltip: sending
              ? 'Sending selfie request to student'
              : 'Awaiting selfie from student',
          color: readableStatusColor(registrationStatusColor(status), t.dark),
          t: t,
        );
      case 'photo_submitted':
        return Row(
          children: [
            Expanded(
              child: OrgPrimaryButton(
                label: 'Check In Student',
                icon: Icons.how_to_reg_rounded,
                onPressed: onCheckIn,
              ),
            ),
            const SizedBox(width: 10),
            _RejectButton(onTap: onReject, tooltip: 'Reject', t: t),
          ],
        );
      case 'checked_in':
      default:
        return OrgSecondaryButton(
          label: 'View Details',
          icon: Icons.info_outline_rounded,
          onPressed: onDetails,
          t: t,
        );
    }
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final AppTk t;
  final double size;
  const _Avatar({
    required this.initials,
    required this.color,
    required this.t,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: t.dark ? 0.18 : 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: size * 0.33,
          fontWeight: FontWeight.w800,
          color: readableStatusColor(color, t.dark),
        ),
      ),
    );
  }
}

/// A registration's status: the same dot-and-label pill as the Events tab's
/// status chip, tinted because it sits on the card.
class RegistrationStatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final AppTk t;
  const RegistrationStatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: t.dark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(20),
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

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final AppTk t;
  const _MetaLine({required this.icon, required this.text, required this.t, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? t.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: color == null ? FontWeight.w500 : FontWeight.w600,
              color: color ?? t.sub,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelfiePreview extends StatefulWidget {
  final String? url;
  final String? path;
  /// The bulk-selection checkbox, at the end of the "Student selfie" row.
  final Widget? select;
  final AppTk t;
  const _SelfiePreview({required this.url, required this.path, required this.t, this.select});

  @override
  State<_SelfiePreview> createState() => _SelfiePreviewState();
}

class _SelfiePreviewState extends State<_SelfiePreview> {
  // Links are renewed before they expire (SelfieLinks): the photo stays on
  // screen while the new link loads instead of flashing the spinner.
  bool _shown = false;

  String? get url => widget.url;
  String? get path => widget.path;
  Widget? get select => widget.select;
  AppTk get t => widget.t;

  @override
  void didUpdateWidget(_SelfiePreview old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _shown = false;   // a different student
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: select == null ? 0 : 40),
          child: Row(
            children: [
              Icon(Icons.photo_camera_rounded, size: 16, color: goldText(t)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Student selfie',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              ?select,
            ],
          ),
        ),
        SizedBox(height: select == null ? 8 : 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: url != null
              ? Image.network(
                  url!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: (_, child, frame, sync) {
                    if (frame != null || sync) _shown = true;
                    return _shown ? child : _spinner(160);
                  },
                  errorBuilder: (_, _, _) => _broken(),
                )
              : (path != null ? _spinner(110) : _broken()),
        ),
      ],
    );
  }

  Widget _spinner(double height) => Container(
        height: height,
        color: t.inputBg,
        child: const Center(
          child: CircularProgressIndicator(color: kGold, strokeWidth: 3),
        ),
      );

  Widget _broken() => Container(
        height: 110,
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kGold.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: kGold.withValues(alpha: 0.4),
            size: 36,
          ),
        ),
      );
}

/// "Select" — adds this selfie to the bulk Approve / Reject.
class _SelectToggle extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;
  final AppTk t;
  const _SelectToggle({
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final ink = readableStatusColor(kRegSelectColor, t.dark);
    return InkWell(
      onTap: enabled ? onToggle : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: selected,
                onChanged: enabled ? (_) => onToggle() : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: kRegSelectColor,
                side: BorderSide(color: t.muted, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              selected ? 'Selected' : 'Select',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? ink : t.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingStrip extends StatelessWidget {
  final AppTk t;
  const _WaitingStrip({required this.t});

  @override
  Widget build(BuildContext context) {
    final purple = registrationStatusColor('photo_required');
    final ink = readableStatusColor(purple, t.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: purple.withValues(alpha: t.dark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Waiting for student selfie…',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A step that isn't the organizer's to take yet — same size as the buttons.
class _DisabledAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final bool busy;
  final AppTk t;
  const _DisabledAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.t,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: null,
        icon: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: color,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Square outlined Reject, beside a gold Check In.
class _RejectButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String tooltip;
  final AppTk t;
  const _RejectButton({required this.onTap, required this.tooltip, required this.t});

  @override
  Widget build(BuildContext context) {
    final danger = _danger(t);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: 46,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: danger,
            side: BorderSide(color: danger.withValues(alpha: 0.45), width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Icon(Icons.block_rounded, size: 19),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  final VoidCallback onDelete;
  final AppTk t;
  const _MoreButton({required this.onDelete, required this.t});

  @override
  Widget build(BuildContext context) {
    final danger = _danger(t);
    return PopupMenuButton<String>(
      tooltip: 'More',
      color: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: danger),
              const SizedBox(width: 8),
              Text(
                'Delete',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: danger),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: orgOutlineColor(t), width: 1.4),
        ),
        child: Icon(Icons.more_vert_rounded, color: t.sub, size: 20),
      ),
    );
  }
}

// ── Count + select, bulk actions ─────────────────────────────────────────────

/// "12 registrations found" and, when selfies are waiting, Select ready.
class OrgRegistrationsToolbar extends StatelessWidget {
  final int count;
  final bool canSelect;
  final bool allSelected;
  final bool busy;
  final VoidCallback onToggleSelectAll;
  final AppTk t;
  const OrgRegistrationsToolbar({
    super.key,
    required this.count,
    required this.canSelect,
    required this.allSelected,
    required this.busy,
    required this.onToggleSelectAll,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final ink = readableStatusColor(kRegSelectColor, t.dark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count registration${count == 1 ? '' : 's'} found',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.sub,
                ),
              ),
            ),
            if (canSelect)
              OutlinedButton.icon(
                onPressed: busy ? null : onToggleSelectAll,
                icon: Icon(
                  allSelected ? Icons.check_box_rounded : Icons.select_all_rounded,
                  size: 16,
                ),
                label: Text(allSelected ? 'Clear ready' : 'Select ready'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  backgroundColor: kRegSelectColor.withValues(alpha: t.dark ? 0.10 : 0.06),
                  side: BorderSide(color: kRegSelectColor.withValues(alpha: 0.40), width: 1.2),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What to do with the selected selfies — approve them all, or reject them.
class OrgBulkActionBar extends StatelessWidget {
  final int selectedCount;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final AppTk t;
  const OrgBulkActionBar({
    super.key,
    required this.selectedCount,
    required this.busy,
    required this.onClear,
    required this.onApprove,
    required this.onReject,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final ink = readableStatusColor(kRegSelectColor, t.dark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
        decoration: BoxDecoration(
          color: kRegSelectColor.withValues(alpha: t.dark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kRegSelectColor.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded, size: 18, color: ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$selectedCount selected',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onClear,
                  style: TextButton.styleFrom(foregroundColor: t.sub),
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OrgPrimaryButton(
                      label: 'Approve & Check In',
                      icon: Icons.check_circle_rounded,
                      onPressed: busy ? null : onApprove,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _RejectButton(
                    onTap: busy ? null : onReject,
                    tooltip: 'Reject selected',
                    t: t,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Details sheet ───────────────────────────────────────────────────────────

/// A registration in full: the student, status, event, timeline and selfie.
class OrgRegistrationDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> registration;
  final String? selfieUrl;
  const OrgRegistrationDetailsSheet({
    super.key,
    required this.registration,
    this.selfieUrl,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    final r = registration;
    final name = r['student_name'] as String? ?? '—';
    final sid = r['student_school_id'] as String? ?? '—';
    final event = r['event_title'] as String? ?? '—';
    final status = r['status'] as String? ?? 'pending';
    final regDate = r['registered_at'] as String? ?? '';
    final checkedInAt = r['checked_in_at'] as String?;
    final color = registrationStatusColor(status);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPad + 20),
              child: Column(
                children: [
                  _Avatar(
                    initials: registrationInitials(name),
                    color: color,
                    size: 72,
                    t: t,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatLrn(sid),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: t.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 12),
                  RegistrationStatusChip(
                    label: registrationStatusLabel(status),
                    color: color,
                    t: t,
                  ),
                  const SizedBox(height: 22),
                  _InfoCard(
                    t: t,
                    children: [
                      _InfoRow(
                        icon: Icons.event_rounded,
                        label: 'Event',
                        value: event,
                        color: goldText(t),
                        multiLine: true,
                        t: t,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    t: t,
                    children: [
                      _InfoRow(
                        icon: Icons.schedule_rounded,
                        label: 'Registered',
                        value: registrationDateLabel(regDate),
                        color: t.sub,
                        t: t,
                      ),
                      if (checkedInAt != null) ...[
                        Divider(height: 1, thickness: 1, color: t.divider),
                        _InfoRow(
                          icon: Icons.check_circle_rounded,
                          label: 'Checked In',
                          value: registrationDateLabel(checkedInAt),
                          color: readableStatusColor(_kGreen, t.dark),
                          t: t,
                        ),
                      ],
                    ],
                  ),
                  if (selfieUrl != null) ...[
                    const SizedBox(height: 12),
                    _InfoCard(
                      t: t,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: _SelfiePreview(url: selfieUrl, path: null, t: t),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: OrgSecondaryButton(
                      label: 'Close',
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                      t: t,
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
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final AppTk t;
  const _InfoCard({required this.children, required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.dark ? const Color(0xFF1E1912) : const Color(0xFFFAF7F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool multiLine;
  final AppTk t;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.t,
    this.multiLine = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: multiLine ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
