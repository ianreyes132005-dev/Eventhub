import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';
import '../../../shared/utils/csv_download.dart';
import 'attendance_record.dart';
import 'web_shared.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "Export attendance record" dialog — opened from an ended event's row in the
// Events table or from its details dialog. Loads the registrations, shows the
// totals, and downloads the record as Excel or PDF. Stays open after a
// download so the organizer can grab the other format too.
// ─────────────────────────────────────────────────────────────────────────────

/// [onDownloaded] / [onDownloadFailed] replace the dialog's own inline note
/// (the admin Archives tab shows a SweetAlert2 popup instead).
Future<void> showAttendanceExportDialog(BuildContext context, Map<String, dynamic> event,
        {RegistrantProfileLoader? profileLoader,
        void Function(String fileName)? onDownloaded,
        void Function(String message)? onDownloadFailed}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AttendanceExportDialog(event: event, profileLoader: profileLoader,
          onDownloaded: onDownloaded, onDownloadFailed: onDownloadFailed),
    );

enum _Format { excel, pdf }

class _AttendanceExportDialog extends StatefulWidget {
  final Map<String, dynamic> event;
  final RegistrantProfileLoader? profileLoader;
  final void Function(String fileName)? onDownloaded;
  final void Function(String message)? onDownloadFailed;
  const _AttendanceExportDialog({required this.event, this.profileLoader,
      this.onDownloaded, this.onDownloadFailed});

  @override
  State<_AttendanceExportDialog> createState() => _AttendanceExportDialogState();
}

class _AttendanceExportDialogState extends State<_AttendanceExportDialog> {
  AttendanceRecord? _record;
  String? _loadError;
  _Format _format = _Format.excel;
  bool _busy = false;
  String? _savedName;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loadError = null; _record = null; });
    try {
      final loader = widget.profileLoader;
      final rec = loader == null
          ? await loadAttendanceRecord(widget.event)
          : await loadAttendanceRecord(widget.event, profileLoader: loader);
      if (mounted) setState(() => _record = rec);
    } catch (e) {
      debugPrint('Attendance record load error: $e');
      if (mounted) {
        setState(() => _loadError =
            'Couldn’t load the registrations. Check your connection and try again.');
      }
    }
  }

  Future<void> _download() async {
    final rec = _record;
    if (rec == null || _busy) return;
    setState(() { _busy = true; _savedName = null; _saveError = null; });
    try {
      // Stamp the file with the moment it's made, not when the dialog opened.
      final fresh = AttendanceRecord(event: rec.event, organizerName: rec.organizerName,
          rows: rec.rows, generatedAt: DateTime.now());
      final String name;
      if (_format == _Format.excel) {
        name = '${fresh.fileBaseName}.xlsx';
        downloadFile(buildAttendanceXlsx(fresh), name, kXlsxMime);
      } else {
        name = '${fresh.fileBaseName}.pdf';
        downloadFile(await buildAttendancePdf(fresh), name, kPdfMime);
      }
      if (widget.onDownloaded != null) {
        widget.onDownloaded!(name);
      } else if (mounted) {
        setState(() => _savedName = name);
      }
    } catch (e) {
      debugPrint('Attendance export error: $e');
      const msg = 'The file couldn’t be created. Please try again.';
      if (widget.onDownloadFailed != null) {
        widget.onDownloadFailed!(msg);
      } else if (mounted) {
        setState(() => _saveError = msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: t.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildHeader(t),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: _loadError != null
                ? _buildLoadError(t)
                : _record == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: kGold)),
                      )
                    : _buildBody(t, _record!),
          )),
          _buildFooter(t),
        ]),
      ),
    );
  }

  Widget _buildHeader(WebTk t) => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
    decoration: BoxDecoration(
      color: t.inputBg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: Border(bottom: BorderSide(color: t.border)),
    ),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: kGoldLight, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.download_rounded, color: kGold, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Export attendance record',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
              fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(height: 2),
        Text(widget.event['title'] as String? ?? '—',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(Icons.close_rounded, size: 18, color: t.sub),
        style: IconButton.styleFrom(backgroundColor: t.divider,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    ]),
  );

  Widget _buildLoadError(WebTk t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(children: [
      const Icon(Icons.cloud_off_rounded, size: 34, color: Color(0xFFEF4444)),
      const SizedBox(height: 10),
      Text(_loadError!, textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub, height: 1.5)),
      const SizedBox(height: 12),
      WebBtn(label: 'Try again', icon: Icons.refresh_rounded, small: true, onTap: _load),
    ]),
  );

  Widget _buildBody(WebTk t, AttendanceRecord rec) {
    final closes = rec.checkInClosesAt;
    final rejected = rec.count(AttendanceMark.rejected);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _stat(t, '${rec.registered}', 'Registered', kGold),
        const SizedBox(width: 8),
        _stat(t, '${rec.present}', 'Present', const Color(0xFF16A34A)),
        const SizedBox(width: 8),
        _stat(t, '${rec.count(AttendanceMark.absent) + rejected}',
            rejected > 0 ? 'Absent / rejected' : 'Absent', const Color(0xFFEF4444)),
        const SizedBox(width: 8),
        _stat(t, '${(rec.rate * 100).round()}%', 'Attendance', const Color(0xFF3B82F6)),
      ]),
      if (closes != null) ...[
        const SizedBox(height: 12),
        _note(t, Icons.schedule_rounded, const Color(0xFFF59E0B),
            'Check-in is still open until ${webFmtTime('${closes.hour}:${closes.minute}')}. '
            'Students who check in after you export won’t be in this file — '
            'export again after that for the final record.'),
      ],
      if (rec.registered == 0) ...[
        const SizedBox(height: 12),
        _note(t, Icons.info_outline_rounded, t.muted,
            'No students registered for this event. The file will contain the event '
            'details only.'),
      ],
      const SizedBox(height: 18),
      Text('FORMAT', style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
          fontWeight: FontWeight.w700, letterSpacing: 0.8, color: t.muted)),
      const SizedBox(height: 8),
      Row(children: [
        _formatTile(t, _Format.excel, Icons.table_chart_rounded, const Color(0xFF16A34A),
            'Excel (.xlsx)', 'Every column, ready to sort and filter'),
        const SizedBox(width: 10),
        _formatTile(t, _Format.pdf, Icons.picture_as_pdf_rounded, const Color(0xFFDC2626),
            'PDF', 'Formatted for printing, with a sign-off line'),
      ]),
      const SizedBox(height: 12),
      Text('Students are listed by grade, section and last name.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted)),
      if (_savedName != null) ...[
        const SizedBox(height: 12),
        _note(t, Icons.check_circle_rounded, const Color(0xFF16A34A), 'Downloaded $_savedName'),
      ],
      if (_saveError != null) ...[
        const SizedBox(height: 12),
        _note(t, Icons.error_outline_rounded, const Color(0xFFEF4444), _saveError!),
      ],
      const SizedBox(height: 14),
    ]);
  }

  Widget _stat(WebTk t, String value, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: t.dark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
            fontWeight: FontWeight.w700, color: t.text)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.sub)),
      ]),
    ),
  );

  Widget _note(WebTk t, IconData icon, Color color, String text) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: t.dark ? 0.12 : 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontFamily: 'Poppins',
          fontSize: 11.5, color: t.text, height: 1.45))),
    ]),
  );

  Widget _formatTile(WebTk t, _Format f, IconData icon, Color color,
      String title, String caption) {
    final selected = _format == f;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: title,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() { _format = f; _savedName = null; _saveError = null; }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? kGold.withValues(alpha: t.dark ? 0.12 : 0.07) : t.inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? kGold : t.border, width: selected ? 1.6 : 1),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w700, color: t.text)),
                const SizedBox(height: 2),
                Text(caption, style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    color: t.sub, height: 1.35)),
              ])),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 18, color: selected ? kGold : t.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(WebTk t) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(foregroundColor: t.sub),
        child: const Text('Close', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      ),
      const SizedBox(width: 8),
      Opacity(
        opacity: _record == null || _busy ? 0.55 : 1,
        child: WebBtn(
          label: _busy
              ? 'Preparing…'
              : _format == _Format.excel ? 'Download Excel' : 'Download PDF',
          icon: _busy ? Icons.hourglass_top_rounded : Icons.download_rounded,
          onTap: _download,
        ),
      ),
    ]),
  );
}
