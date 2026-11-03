import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/registration_service.dart';
import '../../../../core/services/supabase_service.dart';

Future<void> showEventStudentDetails(
  BuildContext context, {
  required Map<String, dynamic> registration,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EventStudentDetailsSheet(registration: registration),
  );
}

class EventStudentDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> registration;

  const EventStudentDetailsSheet({super.key, required this.registration});

  @override
  State<EventStudentDetailsSheet> createState() =>
      _EventStudentDetailsSheetState();
}

class _EventStudentDetailsSheetState extends State<EventStudentDetailsSheet> {
  Map<String, dynamic>? _profile;
  String? _profileError;
  String? _selfieUrl;
  String? _selfieError;
  bool _profileLoading = true;
  bool _selfieLoading = true;

  Map<String, dynamic> get _registration => widget.registration;
  String get _status => _registration['status'] as String? ?? 'pending';
  String get _name => _registration['student_name'] as String? ?? '—';
  String get _lrn =>
      formatLrn(_registration['student_school_id'] as String? ?? '');

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSelfie();
  }

  Future<void> _loadProfile() async {
    final userId = _registration['student_user_id'] as String?;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _profileLoading = false;
        _profileError = 'Student profile is unavailable.';
      });
      return;
    }

    try {
      final row = await SupabaseService.client
          .from('event_registrant_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _profile = row == null ? null : Map<String, dynamic>.from(row);
        _profileLoading = false;
        if (row == null) _profileError = 'Student profile is unavailable.';
      });
    } catch (error) {
      debugPrint('Event student profile load failed: $error');
      if (mounted) {
        setState(() {
          _profileLoading = false;
          _profileError = 'Could not load student profile.';
        });
      }
    }
  }

  Future<void> _loadSelfie() async {
    final path = _registration['selfie_url'] as String?;
    if (path == null || path.isEmpty) {
      setState(() => _selfieLoading = false);
      return;
    }
    try {
      final url = await RegistrationService.getSelfieSignedUrl(path);
      if (mounted) {
        setState(() {
          _selfieUrl = url;
          _selfieLoading = false;
        });
      }
    } catch (error) {
      debugPrint('Event student selfie link failed: $error');
      if (mounted) {
        setState(() {
          _selfieLoading = false;
          _selfieError = 'Could not load check-in selfie.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.94,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: t.border),
        ),
        child: Column(
          children: [
            _header(t),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  _profileSection(t),
                  const SizedBox(height: 28),
                  _sectionLabel('THIS EVENT', t),
                  const SizedBox(height: 10),
                  _eventProgress(t),
                  if (_showIdentity) ...[
                    const SizedBox(height: 28),
                    _sectionLabel('IDENTITY CHECK', t),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _photoTile(
                            label: 'Profile photo',
                            sub: _profile == null ? null : 'On file · tap to enlarge',
                            url: _profile?['profile_image_url'] as String?,
                            loading: _profileLoading,
                            error: _profileError,
                            emptyText: 'No profile photo',
                            t: t,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _photoTile(
                            label: 'Check-in selfie',
                            sub: _selfieUrl == null ? null : 'Submitted · tap to enlarge',
                            url: _selfieUrl,
                            loading: _selfieLoading,
                            error: _selfieError,
                            emptyText: _status == 'photo_required'
                                ? 'Waiting for selfie'
                                : 'No selfie',
                            t: t,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _footer(t, bottomInset),
          ],
        ),
      ),
    );
  }

  Widget _header(AppTk t) => Container(
        height: 64,
        padding: const EdgeInsets.only(left: 20, right: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(
          children: [
            Text(
              'Student details',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_rounded, color: t.muted),
            ),
          ],
        ),
      );

  Widget _profileSection(AppTk t) {
    final grade = int.tryParse('${_profile?['year_level'] ?? ''}');
    String? strand;
    if (grade == 11 || grade == 12) {
      strand = _profile?['strand'] as String?;
    }
    final section = (_profile?['section'] as String?)?.trim();
    final image = _profile?['profile_image_url'] as String?;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(t, image),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _lrn.isEmpty ? '—' : _lrn,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: t.sub,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (_lrn.isNotEmpty)
                    IconButton(
                      tooltip: 'Copy LRN',
                      visualDensity: VisualDensity.compact,
                      iconSize: 15,
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _lrn.replaceAll(RegExp(r'\D'), '')),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('LRN copied')),
                        );
                      },
                      icon: Icon(Icons.copy_rounded, color: t.muted),
                    ),
                ],
              ),
              if (_profileLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.sub,
                    ),
                  ),
                )
              else if (_profileError != null)
                Text(
                  _profileError!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: t.muted,
                  ),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (grade != null) _chip('Grade $grade', t),
                    if (strand != null) _chip(strand, t, highlighted: true),
                    if (section != null && section.isNotEmpty)
                      _chip(section, t),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatar(AppTk t, String? url) {
    final color = _statusColor(_status);
    final initials = _name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return ClipOval(
      child: SizedBox(
        width: 68,
        height: 68,
        child: url == null || url.isEmpty
            ? ColoredBox(
                color: color.withValues(alpha: 0.12),
                child: Center(
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              )
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) {
                return ColoredBox(
                  color: color.withValues(alpha: 0.12),
                  child: Icon(Icons.person_rounded, color: color),
                );
              }),
      ),
    );
  }

  Widget _chip(String label, AppTk t, {bool highlighted = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: highlighted ? kGold.withValues(alpha: 0.12) : t.inputBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlighted ? kGold.withValues(alpha: 0.35) : t.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: highlighted ? const Color(0xFFB8861C) : t.sub,
          ),
        ),
      );

  Widget _sectionLabel(String label, AppTk t) => Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: t.muted,
        ),
      );

  Widget _eventProgress(AppTk t) {
    const steps = [
      ('pending', 'Registered'),
      ('qr_scanned', 'QR scanned'),
      ('photo_required', 'Selfie requested'),
      ('photo_submitted', 'Selfie submitted'),
      ('checked_in', 'Checked in'),
    ];
    final rejected = _status == 'rejected';
    final current = rejected
        ? 3
        : steps.indexWhere((step) => step.$1 == _status)
            .clamp(0, steps.length - 1);
    final completed = _status == 'checked_in';
    final items = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      if (rejected && i == steps.length - 1) break;
      final (key, label) = steps[i];
      final done = i < current || (i == current && (completed || rejected));
      final active = i == current && !done;
      items.add(_progressRow(
        label: label,
        time: key == 'pending'
            ? _dateTime(_registration['registered_at'] as String?)
            : key == 'checked_in'
                ? _dateTime(_registration['checked_in_at'] as String?)
                : null,
        color: done ? const Color(0xFF16A34A) : active ? kGold : t.muted,
        done: done,
        isLast: !rejected && i == steps.length - 1,
        t: t,
      ));
    }
    if (rejected) {
      items.add(_progressRow(
        label: 'Rejected',
        color: const Color(0xFFDC2626),
        done: true,
        rejected: true,
        isLast: true,
        t: t,
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 8),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _registration['event_title'] as String? ?? 'This event',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(t),
            ],
          ),
          const SizedBox(height: 16),
          ...items,
          if (_status == 'rejected')
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 8),
                child: Text(
                  (_registration['rejection_reason'] as String?)?.trim() ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressRow({
    required String label,
    required Color color,
    required bool done,
    required bool isLast,
    required AppTk t,
    String? time,
    bool rejected = false,
  }) =>
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? color : Colors.transparent,
                      border: Border.all(color: color, width: 1.5),
                    ),
                    child: Icon(
                      rejected
                          ? Icons.close_rounded
                          : done
                              ? Icons.check_rounded
                              : Icons.circle,
                      size: 12,
                      color: done ? Colors.white : color,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        color: done
                            ? const Color(0xFF16A34A).withValues(alpha: 0.5)
                            : t.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 5 : 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                          color: done ? (rejected ? color : t.text) : t.muted,
                        ),
                      ),
                    ),
                    if (time != null)
                      Text(
                        time,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: t.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _statusBadge(AppTk t) {
    final color = _statusColor(_status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(_status),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  bool get _showIdentity =>
      const {'photo_required', 'photo_submitted', 'checked_in', 'rejected'}
          .contains(_status) ||
      (_registration['selfie_url'] as String?)?.isNotEmpty == true;

  Widget _photoTile({
    required String label,
    required String emptyText,
    required AppTk t,
    required bool loading,
    required String? error,
    required String? url,
    String? sub,
  }) {
    final borderColor = t.border;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: t.inputBg,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: url == null ? null : () => _showImage(url, label),
            child: Container(
              height: 174,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoContent(
                url: url,
                loading: loading,
                error: error,
                emptyText: emptyText,
                t: t,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        Text(
          sub ?? (error ?? emptyText),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10.5,
            color: t.muted,
          ),
        ),
      ],
    );
  }

  Widget _photoContent({
    required String? url,
    required bool loading,
    required String? error,
    required String emptyText,
    required AppTk t,
  }) {
    if (loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: t.sub),
      );
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => Center(
          child: Icon(Icons.broken_image_outlined, color: t.muted, size: 32),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              error == null
                  ? Icons.person_outline_rounded
                  : Icons.warning_amber_rounded,
              color: t.muted,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              error ?? emptyText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImage(String url, String label) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Close $label',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(AppTk t, double bottomInset) {
    final checkedAt = _dateTime(_registration['checked_in_at'] as String?);
    final text = _status == 'checked_in'
        ? 'Checked in${checkedAt == null ? '' : ' $checkedAt'}'
        : _status == 'rejected'
            ? 'Check-in rejected'
            : _status == 'photo_submitted'
                ? 'Selfie submitted · waiting for review'
                : _status == 'photo_required'
                    ? 'Waiting for the student to submit a selfie'
                    : _status == 'qr_scanned'
                        ? 'QR scanned · selfie verification pending'
                        : 'Registered · check-in has not started';
    final color = _statusColor(_status);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottomInset),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(
            _status == 'checked_in'
                ? Icons.verified_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: t.sub,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'pending' => 'Registered',
        'qr_scanned' => 'QR Scanned',
        'photo_required' => 'Awaiting Selfie',
        'photo_submitted' => 'Photo Submitted',
        'checked_in' => 'Checked In',
        'rejected' => 'Rejected',
        _ => status,
      };

  Color _statusColor(String status) => switch (status) {
        'checked_in' => const Color(0xFF16A34A),
        'photo_submitted' => const Color(0xFF2563EB),
        'photo_required' => const Color(0xFF9333EA),
        'qr_scanned' => const Color(0xFFE87A00),
        'rejected' => const Color(0xFFDC2626),
        _ => kMuted,
      };

  String? _dateTime(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '${months[date.month - 1]} ${date.day}, $hour:$minute $period';
  }
}
