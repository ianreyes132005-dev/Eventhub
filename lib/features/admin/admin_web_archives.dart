import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/event_archive_service.dart';
import '../../shared/utils/csv_download.dart';
import '../organizer/web/web_shared.dart';
import '../organizer/web/attendance_record.dart';
import '../organizer/web/attendance_export_dialog.dart';
import 'admin_shared.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Archives tab — finished events and their attendance records.
//
// All (default) · Ready to archive (approved events with registrations,
// cancelled or with check-in closed) · Archived (moved out of students' and
// organizers' everyday lists; attendance frozen, check-in photos deleted) ·
// No registrations (never approved, or nobody registered — nothing to keep,
// so they're deleted instead of archived). Filtered by school year, with a
// school-year summary export and "Archive all ready". Every action goes
// through a SweetAlert2 confirmation and ends with a SweetAlert2 result.
// Rules are enforced by supabase/migrations/202610180010_event_archives.sql
// and 202610230003_archive_records.sql.
// ─────────────────────────────────────────────────────────────────────────────

typedef _Summary = ({int registered, int present, int rejected});

const _kReadyColor    = Color(0xFFF59E0B);
const _kArchivedColor = Color(0xFF6366F1);
const _kEmptyColor    = Color(0xFF6B7280);
// SweetAlert2 buttons — darker shades of the action colours so white text
// passes WCAG AA.
const _kArchiveBtn = Color(0xFFC2410C);
const _kRestoreBtn = Color(0xFF4F46E5);
const _kOkBtn      = Color(0xFFC2410C);

// Table geometry — the header and every row share these so columns line up.
const _kBarW   = 3.0;                  // left accent bar (archived rows)
const _kPadH   = 20.0;
const _kCheckW = 32.0;
const _kGap    = 12.0;
const _kActW   = 4 * 32.0 + 3 * 6.0;   // four action slots
const _kFlexEvent = 4, _kFlexDate = 2, _kFlexOrg = 3, _kFlexAtt = 3, _kFlexStatus = 2;

// Same type colours and icons as the organizer's event form.
(IconData, Color) _typeVisual(String? type) => switch ((type ?? '').toLowerCase()) {
  'concert'  => (Icons.music_note_rounded, const Color(0xFF7C3AED)),
  'sports'   => (Icons.sports_rounded,     const Color(0xFF2563EB)),
  'workshop' => (Icons.build_rounded,      const Color(0xFFEA580C)),
  'seminar'  => (Icons.school_rounded,     const Color(0xFF0D9488)),
  _          => (Icons.event_rounded,      const Color(0xFF6B7280)),
};

class AdminArchivesPage extends StatefulWidget {
  const AdminArchivesPage({super.key, this.debugEvents, this.debugSummary,
      this.debugRecordLoader});

  /// Widget tests and previews only: show these rows instead of loading from
  /// Supabase (no network, no realtime).
  @visibleForTesting
  final List<Map<String, dynamic>>? debugEvents;
  @visibleForTesting
  final Map<String, ({int registered, int present, int rejected})>? debugSummary;
  /// Widget tests and previews only: builds the "View attendance" record
  /// instead of loading it from Supabase.
  @visibleForTesting
  final Future<AttendanceRecord> Function(Map<String, dynamic> event)? debugRecordLoader;

  @override
  State<AdminArchivesPage> createState() => _AdminArchivesPageState();
}

class _AdminArchivesPageState extends State<AdminArchivesPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _rows = [];      // every event loaded
  List<Map<String, dynamic>> _events = [];    // the finished ones
  List<Map<String, dynamic>> _filtered = [];
  Map<String, ArchiveGroup> _groups = {};
  Map<String, _Summary> _summary = {};
  int    _photosLeft = 0;           // check-in photos still stored for archived events
  String _tab = 'all';              // all | ready | archived | empty
  String _search = '';
  int?   _schoolYear;               // the year it starts; null = every school year
  int    _page = 0;
  String _sortField = 'event_date';
  bool   _sortAsc = false;          // newest first
  final Set<String> _selected = {};
  final _searchCtrl = TextEditingController();
  RealtimeChannel? _channel;
  Timer? _debounce, _clock;

  bool get _preview => widget.debugEvents != null;

  @override
  void initState() {
    super.initState();
    // An event becomes ready to archive when its check-in closes.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(_regroup);
    });
    if (_preview) {
      _setData(widget.debugEvents!, widget.debugSummary ?? const {});
      return;
    }
    _load();
    _channel = SupabaseService.client.channel('admin-archives')
      ..on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'events'),
          (_, [_]) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 600),
                () { if (mounted) _load(silent: true); });
          })
      ..subscribe();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _clock?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_preview) return;
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final rows = await SupabaseService.client.from('events')
          .select('event_id, title, description, event_type, location, event_date, end_date, '
              'start_time, end_time, event_status, cancel_reason, approval_status, '
              'organizer_id, event_image_url, max_participants, archived_at, '
              'organizers(full_name, organization)')
          .order('event_date', ascending: false);
      final summary = await EventArchiveService.attendanceSummary();
      if (!mounted) return;
      setState(() => _setData(
          [for (final e in rows as List) e as Map<String, dynamic>], summary));
      unawaited(_loadPhotosLeft());
    } catch (e) {
      final msg = e.toString();
      final notInstalled =
          msg.contains('archived_at') || msg.contains('event_attendance_summary');
      // The technical fix stays in the debug log; admins see plain words.
      debugPrint(notInstalled
          ? 'Archives need supabase/migrations/202610180010_event_archives.sql: $e'
          : 'Archives failed to load: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = notInstalled
              ? FriendlyErrors.notSetUp
              : friendlyError(e, fallback: 'The archives couldn’t be loaded. Please try again.');
        });
      }
    }
  }

  // Photos archived before archiving deleted them, or a deletion that didn't
  // finish — offered for removal at the top of the tab.
  Future<void> _loadPhotosLeft() async {
    try {
      final n = await EventArchiveService.archivedSelfieCount();
      if (mounted && n != _photosLeft) setState(() => _photosLeft = n);
    } catch (e) {
      debugPrint('Archives: counting stored photos failed: $e');
    }
  }

  void _setData(List<Map<String, dynamic>> rows, Map<String, _Summary> summary) {
    _rows = rows;
    _summary = summary;
    _loading = false;
    _regroup();
  }

  /// Which events are finished and how each is handled, as of now.
  void _regroup() {
    final now = DateTime.now();
    _groups = {
      for (final e in _rows)
        e['event_id'] as String: ?archiveGroupOf(e, registrations: _regs(e), now: now),
    };
    _events = [for (final e in _rows) if (_groups.containsKey(e['event_id'])) e];
    _selected.removeWhere((id) => !_groups.containsKey(id));
    _recompute();
  }

  // Every registration row, declined ones included.
  int _regs(Map<String, dynamic> e) => _summary[e['event_id']]?.registered ?? 0;
  ArchiveGroup _groupOf(Map<String, dynamic> e) => _groups[e['event_id']]!;
  List<Map<String, dynamic>> _inGroup(Iterable<Map<String, dynamic>> events, ArchiveGroup g) =>
      [for (final e in events) if (_groups[e['event_id']] == g) e];

  // ── Filter & sort ───────────────────────────────────────────────────────────

  static String _lower(Object? s) => (s as String? ?? '').toLowerCase();
  static String _orgName(Map<String, dynamic> e) =>
      (e['organizers'] as Map<String, dynamic>?)?['full_name'] as String? ?? '';
  // Ready (ended, then cancelled), then nothing to keep, then archived.
  int _statusRank(Map<String, dynamic> e) => switch (_groupOf(e)) {
    ArchiveGroup.ready    => eventIsCancelled(e) ? 1 : 0,
    ArchiveGroup.empty    => 2,
    ArchiveGroup.archived => 3,
  };

  // The summary's `registered` is every registration; declined ones don't
  // count toward attendance (countsAsRegistered).
  double _rate(Map<String, dynamic> e) {
    final s = _summary[e['event_id']];
    final counted = s == null ? 0 : s.registered - s.rejected;
    if (s == null || counted <= 0 || eventIsCancelled(e)) return -1;
    return s.present / counted;
  }

  void _recompute() {
    final q = _search.trim().toLowerCase();
    final want = switch (_tab) {
      'ready'    => ArchiveGroup.ready,
      'archived' => ArchiveGroup.archived,
      'empty'    => ArchiveGroup.empty,
      _          => null,
    };
    final list = _events.where((e) {
      if (want != null && _groupOf(e) != want) return false;
      if (_schoolYear != null && eventSchoolYear(e) != _schoolYear) return false;
      if (q.isEmpty) return true;
      return '${e['title'] ?? ''} ${e['location'] ?? ''} ${e['event_type'] ?? ''} ${_orgName(e)}'
          .toLowerCase().contains(q);
    }).toList();

    int compare(Map<String, dynamic> a, Map<String, dynamic> b) => switch (_sortField) {
      'title'      => _lower(a['title']).compareTo(_lower(b['title'])),
      'organizer'  => _orgName(a).toLowerCase().compareTo(_orgName(b).toLowerCase()),
      'attendance' => _rate(a).compareTo(_rate(b)),
      'status'     => _statusRank(a).compareTo(_statusRank(b)),
      _            => (a['event_date'] as String? ?? '').compareTo(b['event_date'] as String? ?? ''),
    };
    list.sort((a, b) {
      final c = compare(a, b);
      if (c != 0) return _sortAsc ? c : -c;
      // Ties: newest event first.
      return (b['event_date'] as String? ?? '').compareTo(a['event_date'] as String? ?? '');
    });
    _filtered = list;
  }

  void _applyFilter({bool resetPage = false}) {
    if (resetPage) _page = 0;
    setState(_recompute);
  }

  void _setTab(String tab) {
    _tab = tab;
    _selected.clear();
    _applyFilter(resetPage: true);
  }

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc = field == 'title' || field == 'organizer';   // A→Z first
    }
    _applyFilter(resetPage: true);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _search = '';
    _schoolYear = null;
    _applyFilter(resetPage: true);
  }

  void _togglePage(List<Map<String, dynamic>> rows) => setState(() {
    final ids = [for (final e in rows) e['event_id'] as String];
    ids.every(_selected.contains) ? _selected.removeAll(ids) : _selected.addAll(ids);
  });

  String get _yearTitle =>
      _schoolYear == null ? 'All school years' : schoolYearLabel(_schoolYear!);

  // ── Actions (SweetAlert2 before and after each one) ─────────────────────────

  static String _quoted(Map<String, dynamic> e) {
    final title = (e['title'] as String? ?? '').trim();
    return '“${title.isEmpty ? 'Untitled event' : title}”';
  }

  Future<void> _setArchived(List<Map<String, dynamic>> events, {required bool archive}) async {
    if (events.isEmpty) return;
    final ids  = [for (final e in events) e['event_id'] as String];
    final one  = events.length == 1;
    final what = one ? _quoted(events.first) : '${events.length} events';
    final it   = one ? 'it' : 'them';
    final organizers = one ? 'The organizer was' : 'Their organizers were';
    var photosLeft = 0;

    final r = await Swal.fire(context,
      icon: SwalIcon.question,
      title: archive
          ? (one ? 'Archive this event?' : 'Archive ${events.length} events?')
          : (one ? 'Restore this event?' : 'Restore ${events.length} events?'),
      text: archive
          ? '$what will be hidden from students’ Events tab and organizers’ event lists. '
            'The attendance stays saved and read-only, and the check-in photos are deleted. '
            'You can restore $it later, but not the photos.'
          : '$what will show again in students’ Events tab and organizers’ event lists. '
            'Check-in photos deleted when $it ${one ? 'was' : 'were'} archived don’t come back.',
      showCancelButton: true,
      confirmButtonText: archive ? 'Yes, archive $it' : 'Yes, restore $it',
      confirmButtonColor: archive ? _kArchiveBtn : _kRestoreBtn,
      preConfirm: (_) async {
        try {
          if (archive) {
            photosLeft = await EventArchiveService.archive(ids);
          } else {
            await EventArchiveService.restore(ids);
          }
          return null;
        } catch (e) {
          return friendlyError(e);
        }
      },
    );
    if (!r.isConfirmed) return;
    if (!mounted) return;
    setState(() => _selected.removeAll(ids));
    unawaited(_load(silent: true));
    if (photosLeft > 0) {
      await Swal.fire(context,
        icon: SwalIcon.warning,
        title: 'Archived, but some photos are left',
        text: '$what ${one ? 'has' : 'have'} been moved to Archives, but some check-in photos '
            'couldn’t be deleted. Use “Remove photos” at the top of Archives to try again.',
        confirmButtonColor: _kOkBtn,
      );
      return;
    }
    await Swal.fire(context,
      icon: SwalIcon.success,
      title: archive ? 'Archived!' : 'Restored!',
      text: archive
          ? '$what ${one ? 'has' : 'have'} been moved to Archives and the check-in photos were '
            'deleted. $organizers notified.'
          : '$what ${one ? 'is' : 'are'} back in the active lists. $organizers notified.',
      confirmButtonColor: _kOkBtn,
      timer: const Duration(seconds: 3),
      timerProgressBar: true,
    );
  }

  /// Permanently deletes an archived event (its attendance goes with it).
  Future<void> _delete(Map<String, dynamic> e) async {
    final title = (e['title'] as String? ?? '').trim();
    final n = _regs(e);
    final r = await Swal.fire(context,
      icon: SwalIcon.warning,
      title: 'Delete permanently?',
      text: n == 0
          ? 'This deletes ${_quoted(e)} and its banner. It has no registrations. '
            'The organizer is notified. You won’t be able to revert this!'
          : 'This deletes ${_quoted(e)} with its $n registration${n == 1 ? '' : 's'} and '
            'attendance records, and the organizer is notified. You won’t be able to revert this!',
      input: true,
      inputLabel: 'Type the event title to confirm',
      inputPlaceholder: title,
      inputValidator: (v) => v.trim().toLowerCase() == title.toLowerCase()
          ? null
          : 'The title you typed doesn’t match the event title.',
      showCancelButton: true,
      confirmButtonText: 'Yes, delete it!',
      confirmButtonColor: kSwalDenyColor,
      allowOutsideClick: false,
      footer: WebBtn(
        label: 'Export the attendance first',
        icon: Icons.download_rounded,
        small: true,
        outlined: true,
        onTap: () => _export(e),
      ),
      preConfirm: (v) async {
        try {
          await EventArchiveService.deletePermanently(e, (v ?? '').trim());
          return null;
        } catch (err) {
          return friendlyError(err);
        }
      },
    );
    if (!r.isConfirmed) return;
    if (!mounted) return;
    unawaited(_load(silent: true));
    await Swal.fire(context,
      icon: SwalIcon.success,
      title: 'Deleted!',
      text: '${_quoted(e)} and its records have been permanently deleted. '
          'The organizer was notified, and the deletion is recorded in the Logs.',
      confirmButtonColor: _kOkBtn,
      timer: const Duration(seconds: 4),
      timerProgressBar: true,
    );
  }

  /// Deletes finished events with nothing to keep (never approved, or nobody
  /// registered). Their organizers are notified.
  Future<void> _deleteUnused(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    final ids  = [for (final e in events) e['event_id'] as String];
    final one  = events.length == 1;
    final what = one ? _quoted(events.first) : '${events.length} events';
    final failures = <String>[];

    final r = await Swal.fire(context,
      icon: SwalIcon.warning,
      title: one ? 'Delete this event?' : 'Delete ${events.length} events?',
      text: '$what ${one ? 'has' : 'have'} no registrations, so there’s no attendance to keep. '
          '${one ? 'It is' : 'They are'} deleted with ${one ? 'its banner' : 'their banners'}, '
          'and ${one ? 'the organizer is' : 'their organizers are'} notified. '
          'You won’t be able to revert this!',
      showCancelButton: true,
      confirmButtonText: one ? 'Yes, delete it' : 'Yes, delete them',
      confirmButtonColor: kSwalDenyColor,
      preConfirm: (_) async {
        failures.clear();
        for (final e in events) {
          try {
            await EventArchiveService.deleteUnused(e);
          } catch (err) {
            failures.add('${_quoted(e)}: ${friendlyError(err)}');
          }
        }
        // Stay open only when nothing could be deleted.
        return failures.length == events.length ? failures.first : null;
      },
    );
    if (!r.isConfirmed) return;
    if (!mounted) return;
    setState(() => _selected.removeAll(ids));
    unawaited(_load(silent: true));
    if (failures.isNotEmpty) {
      await Swal.fire(context,
        icon: SwalIcon.warning,
        title: 'Some events weren’t deleted',
        text: '${events.length - failures.length} of ${events.length} events were deleted. '
            '${failures.first}',
        confirmButtonColor: _kOkBtn,
      );
      return;
    }
    await Swal.fire(context,
      icon: SwalIcon.success,
      title: 'Deleted!',
      text: '$what ${one ? 'has' : 'have'} been deleted. ${one ? 'The organizer was' : 'Their organizers were'} '
          'notified, and the deletion is recorded in the Logs.',
      confirmButtonColor: _kOkBtn,
      timer: const Duration(seconds: 3),
      timerProgressBar: true,
    );
  }

  Future<void> _removePhotos() async {
    final n = _photosLeft;
    var removed = 0, failed = 0;
    final r = await Swal.fire(context,
      icon: SwalIcon.question,
      title: 'Delete the remaining photos?',
      text: '$n check-in photo${n == 1 ? '' : 's'} from archived events will be deleted. '
          'The attendance stays exactly as it is.',
      showCancelButton: true,
      confirmButtonText: 'Yes, delete ${n == 1 ? 'it' : 'them'}',
      confirmButtonColor: _kArchiveBtn,
      preConfirm: (_) async {
        final res = await EventArchiveService.purgeSelfies();
        removed = res.removed;
        failed = res.failed;
        return failed > 0 && removed == 0
            ? 'The photos couldn’t be deleted. Please try again.'
            : null;
      },
    );
    if (!r.isConfirmed) return;
    if (!mounted) return;
    unawaited(_loadPhotosLeft());
    await Swal.fire(context,
      icon: failed > 0 ? SwalIcon.warning : SwalIcon.success,
      title: failed > 0 ? 'Some photos are left' : 'Deleted!',
      text: failed > 0
          ? '$removed photo${removed == 1 ? '' : 's'} deleted; some couldn’t be. Please try again.'
          : '$removed check-in photo${removed == 1 ? ' was' : 's were'} deleted.',
      confirmButtonColor: _kOkBtn,
      timer: failed > 0 ? null : const Duration(seconds: 3),
      timerProgressBar: failed == 0,
    );
  }

  void _export(Map<String, dynamic> e) => showAttendanceExportDialog(context, e,
      profileLoader: EventArchiveService.adminProfiles,
      onDownloaded: _downloaded,
      onDownloadFailed: _downloadFailed);

  void _downloaded(String name) => Swal.fire(context,
      icon: SwalIcon.success,
      title: 'Downloaded!',
      text: '$name was saved. Check your browser’s downloads.',
      confirmButtonColor: _kOkBtn,
      timer: const Duration(seconds: 3),
      timerProgressBar: true);

  void _downloadFailed(String msg) => Swal.fire(context,
      icon: SwalIcon.error,
      title: 'Download failed',
      text: msg,
      confirmButtonColor: _kOkBtn);

  /// One Excel file: every approved event listed (the current tab, school
  /// year and search), with its organizer, registered, present and rate.
  void _exportSummary() {
    final rows = [
      for (final e in _filtered)
        if (eventIsApproved(e)) _summaryRow(e),
    ];
    if (rows.isEmpty) {
      Swal.fire(context,
          icon: SwalIcon.info,
          title: 'Nothing to export',
          text: 'No approved events are listed. Change the school year or filters and try again.',
          confirmButtonColor: _kOkBtn);
      return;
    }
    final title = _yearTitle;
    final name = 'Attendance summary - ${title.replaceAll('–', '-')}.xlsx';
    try {
      downloadFile(
          buildAttendanceSummaryXlsx(title: title, rows: rows, generatedAt: DateTime.now()),
          name, kXlsxMime);
      _downloaded(name);
    } catch (e) {
      debugPrint('Summary export failed: $e');
      _downloadFailed(friendlyError(e, fallback: 'The summary couldn’t be created. Please try again.'));
    }
  }

  AttendanceSummaryRow _summaryRow(Map<String, dynamic> e) {
    final s = _summary[e['event_id']];
    return AttendanceSummaryRow(
      date: webFmtDate(e['event_date'] as String?),
      sortKey: '${e['event_date'] ?? ''} ${e['start_time'] ?? ''}',
      title: (e['title'] as String? ?? '').trim().ifEmpty('Untitled event'),
      type: (e['event_type'] as String? ?? '').trim(),
      venue: (e['location'] as String? ?? '').trim(),
      organizer: _orgName(e).trim(),
      cancelled: eventIsCancelled(e),
      archived: eventIsArchived(e),
      registrations: s?.registered ?? 0,
      present: s?.present ?? 0,
      rejected: s?.rejected ?? 0,
    );
  }

  void _viewAttendance(Map<String, dynamic> e) => showDialog<void>(
        context: context,
        builder: (_) => _AttendanceDialog(event: e, onExport: () => _export(e),
            loader: widget.debugRecordLoader),
      );

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kAdminAccent));
    }
    if (_error) return AdminErrorState(message: _errorMsg, onRetry: _load);

    final readyCount    = _inGroup(_events, ArchiveGroup.ready).length;
    final archivedCount = _inGroup(_events, ArchiveGroup.archived).length;
    final emptyCount    = _inGroup(_events, ArchiveGroup.empty).length;
    final tabTotal = switch (_tab) {
      'ready'    => readyCount,
      'archived' => archivedCount,
      'empty'    => emptyCount,
      _          => _events.length,
    };
    final noun = switch (_tab) {
      'ready'    => 'events ready to archive',
      'archived' => 'archived events',
      'empty'    => 'events without registrations',
      _          => 'finished events',
    };
    final years = {for (final e in _events) eventSchoolYear(e)}.whereType<int>().toList()
      ..sort((a, b) => b.compareTo(a));
    final hasFilter = _search.isNotEmpty || _schoolYear != null;
    // "Archive all ready" takes what's listed: search and school year apply.
    final readyInView = _tab == 'all' || _tab == 'ready'
        ? _inGroup(_filtered, ArchiveGroup.ready)
        : const <Map<String, dynamic>>[];

    final pageCount = _filtered.isEmpty
        ? 1 : (_filtered.length + kAdminPageSize - 1) ~/ kAdminPageSize;
    final page     = _page.clamp(0, pageCount - 1);
    final pageRows = _filtered.skip(page * kAdminPageSize).take(kAdminPageSize).toList();
    final selectedRows = _events.where((e) => _selected.contains(e['event_id'])).toList();
    final onPage = pageRows.where((e) => _selected.contains(e['event_id'])).length;
    final bool? pageSelection = onPage == 0 ? false : onPage == pageRows.length ? true : null;

    Widget divider() => Container(width: 1, height: 22, color: t.border,
        margin: const EdgeInsets.symmetric(horizontal: 6));

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Page header ─────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
          color: t.card,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Archives', style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                  fontWeight: FontWeight.w800, color: t.text)),
            ])),
            const SizedBox(width: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_tab != 'empty')
                Tooltip(
                  message: 'Excel: every approved event listed below, with its attendance',
                  child: WebBtn(label: 'Export summary', icon: Icons.table_chart_rounded,
                      outlined: true, color: kGold, onTap: _exportSummary),
                ),
              if (readyInView.isNotEmpty)
                WebBtn(label: 'Archive all ready (${readyInView.length})',
                    icon: Icons.archive_outlined,
                    onTap: () => _setArchived(readyInView, archive: true)),
            ]),
          ]),
        ),

        // ── Filter bar ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 10, kWebPad, 10),
          decoration: BoxDecoration(color: t.inputBg,
              border: Border(bottom: BorderSide(color: t.border))),
          child: Row(children: [
            Expanded(child: Wrap(
              spacing: 6, runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                WebSearchField(controller: _searchCtrl,
                    hint: 'Search title, organizer, or venue…', width: 220,
                    onChanged: (v) { _search = v; _applyFilter(resetPage: true); }),
                divider(),
                WebFilterMenu<String>(
                  icon: Icons.filter_list_rounded,
                  label: 'Status',
                  menuWidth: 260,
                  selected: _tab,
                  options: [
                    WebFilterOption(
                      value: 'all',
                      label: 'All',
                      count: _events.length,
                    ),
                    WebFilterOption(
                      value: 'ready',
                      label: 'Ready to archive',
                      count: readyCount,
                      color: _kReadyColor,
                    ),
                    WebFilterOption(
                      value: 'archived',
                      label: 'Archived',
                      count: archivedCount,
                      color: _kArchivedColor,
                    ),
                    WebFilterOption(
                      value: 'empty',
                      label: 'No registrations',
                      count: emptyCount,
                      color: _kEmptyColor,
                    ),
                  ],
                  onSelect: _setTab,
                ),
                divider(),
                _SchoolYearMenu(years: years, selected: _schoolYear,
                    onSelect: (y) { _schoolYear = y; _applyFilter(resetPage: true); }),
              ],
            )),
            if (hasFilter)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: Icon(Icons.close_rounded, size: 14, color: t.muted),
                label: Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
              ),
          ]),
        ),

        // ── Photos left from before archiving deleted them ──────────────────
        if (_photosLeft > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(kWebPad, kWebPad, kWebPad, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                color: _kReadyColor.withValues(alpha: t.dark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kReadyColor.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.photo_library_outlined, size: 20, color: _kArchiveBtn),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  '$_photosLeft check-in photo${_photosLeft == 1 ? ' is' : 's are'} still stored '
                  'for archived events. Archived events keep the attendance only.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text, height: 1.4))),
                const SizedBox(width: 12),
                WebBtn(label: 'Remove photos', icon: Icons.delete_sweep_outlined,
                    small: true, outlined: true, color: _kArchiveBtn, onTap: _removePhotos),
              ]),
            ),
          ),

        // ── Body ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(kWebPad),
          child: _filtered.isEmpty
              ? WebEmptyState(
                  icon: switch (_tab) {
                    'archived' => Icons.inventory_2_outlined,
                    'empty'    => Icons.event_busy_outlined,
                    _          => Icons.task_alt_rounded,
                  },
                  title: hasFilter
                      ? 'No $noun match your filters'
                      : switch (_tab) {
                          'ready'    => 'Nothing to archive',
                          'archived' => 'No archived events yet',
                          'empty'    => 'No events without registrations',
                          _          => 'No finished events yet',
                        },
                  subtitle: hasFilter
                      ? 'Try a different search or school year.'
                      : switch (_tab) {
                          'ready'    => 'Approved events with registrations appear here once they’re '
                                        'cancelled or their check-in closes (2 hours after the end).',
                          'archived' => 'Events you archive appear here with their attendance records.',
                          'empty'    => 'Finished events that were never approved, or that nobody '
                                        'registered for, appear here so you can delete them.',
                          _          => 'Cancelled events, and ended events once check-in closes '
                                        '(2 hours after the end), appear here.',
                        },
                  action: hasFilter
                      ? TextButton(onPressed: _clearFilters,
                          child: const Text('Clear all filters', style: TextStyle(
                              fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                              color: kAdminAccent)))
                      : null,
                )
              : WebCard(
                  padding: EdgeInsets.zero,
                  // Clip so the header's tint follows the card's rounded corners.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Column(children: [
                      if (selectedRows.isNotEmpty) _buildBulkBar(t, selectedRows),
                      _TableHeader(
                        selection: pageSelection,
                        onToggleAll: () => _togglePage(pageRows),
                        sortField: _sortField,
                        sortAsc: _sortAsc,
                        onSort: _setSort,
                      ),
                      for (var i = 0; i < pageRows.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: t.border),
                        _buildRow(pageRows[i]),
                      ],
                      AdminPaginationBar(
                        page: page, total: _filtered.length,
                        unfiltered: hasFilter ? tabTotal : null,
                        noun: noun,
                        onPage: (p) => setState(() => _page = p),
                      ),
                    ]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildRow(Map<String, dynamic> e) {
    final id = e['event_id'] as String;
    final group = _groupOf(e);
    return _ArchiveRow(
      event: e,
      group: group,
      summary: _summary[id],
      selected: _selected.contains(id),
      onSelect: (v) => setState(() => v ? _selected.add(id) : _selected.remove(id)),
      // Nothing to view or export without registrations.
      onView:   group == ArchiveGroup.empty ? null : () => _viewAttendance(e),
      onExport: group == ArchiveGroup.empty ? null : () => _export(e),
      onArchive: switch (group) {
        ArchiveGroup.ready    => () => _setArchived([e], archive: true),
        ArchiveGroup.archived => () => _setArchived([e], archive: false),
        ArchiveGroup.empty    => null,
      },
      onDelete: switch (group) {
        ArchiveGroup.archived => () => _delete(e),
        ArchiveGroup.empty    => () => _deleteUnused([e]),
        ArchiveGroup.ready    => null,
      },
    );
  }

  // Selection bar — on All, a selection can mix ready, archived and empty
  // events; each kind gets its own button.
  Widget _buildBulkBar(WebTk t, List<Map<String, dynamic>> rows) {
    final toArchive = _inGroup(rows, ArchiveGroup.ready);
    final toRestore = _inGroup(rows, ArchiveGroup.archived);
    final toDelete  = _inGroup(rows, ArchiveGroup.empty);
    final kinds = [toArchive, toRestore, toDelete].where((l) => l.isNotEmpty).length;
    final mixed = kinds > 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(_kBarW + _kPadH, 10, _kPadH, 10),
      decoration: BoxDecoration(
        color: kAdminAccent.withValues(alpha: t.dark ? 0.10 : 0.06),
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, size: 18, color: kAdminAccent),
        const SizedBox(width: 8),
        Text('${rows.length} selected', style: TextStyle(fontFamily: 'Poppins',
            fontSize: 12.5, fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(width: 16),
        Wrap(spacing: 8, children: [
          if (toArchive.isNotEmpty)
            WebBtn(
              label: mixed ? 'Archive ${toArchive.length}' : 'Archive selected',
              icon: Icons.archive_outlined, small: true, outlined: true,
              color: _kArchiveBtn,
              onTap: () => _setArchived(toArchive, archive: true),
            ),
          if (toRestore.isNotEmpty)
            WebBtn(
              label: mixed ? 'Restore ${toRestore.length}' : 'Restore selected',
              icon: Icons.unarchive_outlined, small: true, outlined: true,
              color: _kRestoreBtn,
              onTap: () => _setArchived(toRestore, archive: false),
            ),
          if (toDelete.isNotEmpty)
            WebBtn(
              label: mixed ? 'Delete ${toDelete.length}' : 'Delete selected',
              icon: Icons.delete_outline_rounded, small: true, outlined: true,
              color: kAdminErrorRed,
              onTap: () => _deleteUnused(toDelete),
            ),
        ]),
        const Spacer(),
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: Text('Clear selection', style: TextStyle(fontFamily: 'Poppins',
              fontSize: 12, color: t.sub)),
        ),
      ]),
    );
  }
}

// ─── School-year filter ───────────────────────────────────────────────────────

class _SchoolYearMenu extends StatelessWidget {
  final List<int> years;            // the years each school year starts in
  final int? selected;
  final ValueChanged<int?> onSelect;
  const _SchoolYearMenu({required this.years, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final active = selected != null;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? kAdminAccent : t.border, width: active ? 1.5 : 1),
      ),
      child: DropdownButtonHideUnderline(child: DropdownButton<int?>(
        value: selected,
        dropdownColor: t.card,
        icon: Icon(Icons.expand_more_rounded, size: 18, color: t.muted),
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
            fontWeight: FontWeight.w600, color: active ? kAdminAccent : t.text),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('All school years')),
          for (final y in years)
            DropdownMenuItem<int?>(value: y, child: Text(schoolYearLabel(y))),
        ],
        onChanged: onSelect,
      )),
    );
  }
}

// ─── Table ────────────────────────────────────────────────────────────────────

/// Compact checkbox used in the header and rows (same as the Students table).
class _Check extends StatelessWidget {
  final bool? value;            // null = some selected (header only)
  final ValueChanged<bool?> onChanged;
  const _Check({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Checkbox(
      value: value,
      tristate: value == null,
      onChanged: onChanged,
      activeColor: kAdminAccent,
      side: BorderSide(color: t.muted.withValues(alpha: 0.6), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _TableHeader extends StatelessWidget {
  final bool? selection;
  final VoidCallback onToggleAll;
  final String sortField;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  const _TableHeader({required this.selection, required this.onToggleAll,
      required this.sortField, required this.sortAsc, required this.onSort});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    Widget col(String label, String field, int flex) => Expanded(
      flex: flex,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AdminSortColBtn(
          label: label, field: field,
          active: sortField == field,
          asc: sortAsc && sortField == field,
          onSort: onSort,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(_kBarW + _kPadH, 9, _kPadH, 9),
      decoration: BoxDecoration(color: t.bg, border: Border(bottom: BorderSide(color: t.border))),
      child: Row(children: [
        SizedBox(
          width: _kCheckW,
          child: Tooltip(
            message: selection == true ? 'Unselect this page' : 'Select this page',
            child: _Check(value: selection, onChanged: (_) => onToggleAll()),
          ),
        ),
        const SizedBox(width: _kGap),
        col('EVENT', 'title', _kFlexEvent),
        col('DATE', 'event_date', _kFlexDate),
        col('ORGANIZER', 'organizer', _kFlexOrg),
        col('ATTENDANCE', 'attendance', _kFlexAtt),
        col('STATUS', 'status', _kFlexStatus),
        SizedBox(
          width: _kActW,
          child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700,
              letterSpacing: 0.8, color: t.sub)),
        ),
      ]),
    );
  }
}

class _ArchiveRow extends StatefulWidget {
  final Map<String, dynamic> event;
  final ArchiveGroup group;
  final _Summary? summary;
  final bool selected;
  final ValueChanged<bool> onSelect;
  // Null = not offered for this event (its slot stays empty).
  final VoidCallback? onView, onExport, onArchive, onDelete;
  const _ArchiveRow({
    required this.event, required this.group, required this.summary,
    required this.selected, required this.onSelect, required this.onView,
    required this.onExport, required this.onArchive, required this.onDelete,
  });

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final e = widget.event;
    final archived  = widget.group == ArchiveGroup.archived;
    final cancelled = eventIsCancelled(e);
    // Never approved (a pending event that reached its start counts as rejected).
    final neverLive = !eventIsApproved(e);
    final org       = e['organizers'] as Map<String, dynamic>?;
    final orgName   = (org?['full_name'] as String? ?? '').trim();
    final orgSub    = (org?['organization'] as String? ?? '').trim();
    final title     = (e['title'] as String? ?? '').trim();
    final type      = (e['event_type'] as String? ?? '').trim();
    final venue     = (e['location'] as String? ?? '').trim();
    final start     = webFmtTime(e['start_time'] as String?);
    final archivedOn = DateTime.tryParse(e['archived_at'] as String? ?? '')?.toLocal();
    final (typeIcon, typeColor) = _typeVisual(type);

    TextStyle st(double size, Color c, [FontWeight w = FontWeight.w400]) =>
        TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: w, color: c);
    Widget slot(Widget? w) => w ?? const SizedBox(width: 32);

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: widget.selected
            ? kAdminAccent.withValues(alpha: t.dark ? 0.08 : 0.05)
            : _h ? kAdminAccent.withValues(alpha: t.dark ? 0.04 : 0.025) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: _kBarW,
                color: archived ? _kArchivedColor.withValues(alpha: 0.55) : Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kPadH, vertical: 12),
                child: Row(children: [
                  SizedBox(width: _kCheckW,
                      child: _Check(value: widget.selected,
                          onChanged: (v) => widget.onSelect(v ?? false))),
                  const SizedBox(width: _kGap),

                  // Event
                  Expanded(flex: _kFlexEvent, child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: typeColor.withValues(alpha: 0.18)),
                        ),
                        child: Icon(typeIcon, size: 18, color: typeColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title.isEmpty ? 'Untitled event' : title,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: st(13, t.text, FontWeight.w600)),
                          if (type.isNotEmpty || venue.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text([if (type.isNotEmpty) type, if (venue.isNotEmpty) venue].join(' · '),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: st(11, t.muted)),
                          ],
                        ],
                      )),
                    ]),
                  )),

                  // Date
                  Expanded(flex: _kFlexDate, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(webFmtDate(e['event_date'] as String?),
                          style: st(12, t.text, FontWeight.w500)),
                      if (start.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(start, style: st(11, t.muted)),
                      ],
                    ],
                  )),

                  // Organizer
                  Expanded(flex: _kFlexOrg, child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(orgName.isEmpty ? '—' : orgName, maxLines: 1,
                            overflow: TextOverflow.ellipsis, style: st(12, t.text, FontWeight.w500)),
                        if (orgSub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(orgSub, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: st(11, t.muted)),
                        ],
                      ],
                    ),
                  )),

                  // Attendance
                  Expanded(flex: _kFlexAtt, child: Padding(
                    padding: const EdgeInsets.only(right: 28),
                    child: _AttendanceCell(summary: widget.summary, cancelled: cancelled),
                  )),

                  // Status
                  Expanded(flex: _kFlexStatus, child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      neverLive
                          ? Tooltip(
                              message: 'Never approved, so it never went live',
                              child: WebStatusBadge(label: 'Rejected',
                                  color: approvalStatusColor('rejected')),
                            )
                          : WebStatusBadge(
                              label: cancelled ? 'Cancelled' : 'Ended',
                              color: cancelled ? const Color(0xFFEF4444) : const Color(0xFF6B7280)),
                      if (archived)
                        Tooltip(
                          message: archivedOn == null ? 'Archived'
                              : 'Archived ${webFmtDate(archivedOn.toIso8601String())}',
                          child: const WebStatusBadge(label: 'Archived', color: _kArchivedColor),
                        ),
                    ]),
                  )),

                  // Actions — four fixed slots so the icons line up row to row.
                  SizedBox(width: _kActW, child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      slot(widget.onView == null ? null : AdminActBtn(
                          icon: Icons.groups_rounded, color: const Color(0xFF3B82F6),
                          tip: 'View attendance', onTap: widget.onView!)),
                      const SizedBox(width: 6),
                      slot(widget.onExport == null ? null : AdminActBtn(
                          icon: Icons.download_rounded, color: kGold,
                          tip: 'Export attendance (Excel or PDF)', onTap: widget.onExport!)),
                      const SizedBox(width: 6),
                      slot(widget.onArchive == null ? null : AdminActBtn(
                          icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                          color: archived ? _kArchivedColor : kAdminAccent,
                          tip: archived ? 'Restore to active lists' : 'Archive',
                          onTap: widget.onArchive!)),
                      const SizedBox(width: 6),
                      slot(widget.onDelete == null ? null : AdminActBtn(
                          icon: archived ? Icons.delete_forever_rounded : Icons.delete_outline_rounded,
                          color: kAdminErrorRed,
                          tip: archived ? 'Delete permanently' : 'Delete — nothing to keep',
                          onTap: widget.onDelete!)),
                    ],
                  )),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "42 / 64 present · 66%" with a bar coloured by how well attended it was.
class _AttendanceCell extends StatelessWidget {
  final _Summary? summary;
  final bool cancelled;
  const _AttendanceCell({required this.summary, required this.cancelled});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    // `registered` in the summary is every registration; declined ones are
    // left out of the count and the rate (countsAsRegistered).
    final all = summary?.registered ?? 0;
    final reg = all - (summary?.rejected ?? 0);
    final present = summary?.present ?? 0;
    TextStyle st(double size, Color c, [FontWeight w = FontWeight.w400]) =>
        TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: w, color: c);

    if (all == 0) return Text('No registrations', style: st(12, t.muted));
    if (reg <= 0) return Text('All registrations rejected', style: st(12, t.muted));
    if (cancelled) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Text('$reg registered', style: st(12, t.text, FontWeight.w500)),
            const SizedBox(height: 2),
            Text('Cancelled — no check-in', style: st(11, t.muted)),
          ]);
    }
    final rate = present / reg;
    // Bar colour + a darker shade for the percentage text (WCAG AA).
    final (bar, text) = rate >= 0.75
        ? (const Color(0xFF10B981), const Color(0xFF047857))
        : rate >= 0.5
            ? (const Color(0xFFF59E0B), const Color(0xFFB45309))
            : (const Color(0xFFEF4444), const Color(0xFFDC2626));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text.rich(TextSpan(children: [
              TextSpan(text: '$present', style: st(13, t.text, FontWeight.w700)),
              TextSpan(text: ' / $reg present', style: st(11.5, t.muted)),
            ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('${(rate * 100).round()}%', style: st(12, t.dark ? bar : text, FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate, minHeight: 5,
              backgroundColor: t.divider,
              color: bar,
            ),
          ),
        ]);
  }
}

// ─── Attendance viewer ────────────────────────────────────────────────────────

class _AttendanceDialog extends StatefulWidget {
  final Map<String, dynamic> event;
  final VoidCallback onExport;
  final Future<AttendanceRecord> Function(Map<String, dynamic> event)? loader;
  const _AttendanceDialog({required this.event, required this.onExport, this.loader});
  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  AttendanceRecord? _rec;
  String? _error;
  String  _query = '';
  AttendanceMark? _mark;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _error = null; _rec = null; });
    try {
      final rec = widget.loader != null
          ? await widget.loader!(widget.event)
          : await loadAttendanceRecord(widget.event,
              profileLoader: EventArchiveService.adminProfiles);
      if (mounted) setState(() => _rec = rec);
    } catch (e) {
      debugPrint('Attendance record failed to load: $e');
      if (mounted) {
        setState(() => _error = friendlyError(e,
            fallback: 'Couldn’t load the attendance record. Please try again.'));
      }
    }
  }

  String _clock(DateTime? d) {
    if (d == null) return '—';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final t   = WebTk(Theme.of(context).brightness == Brightness.dark);
    final rec = _rec;
    final org = (widget.event['organizers'] as Map<String, dynamic>?)?['full_name'] as String?;
    return Dialog(
      backgroundColor: t.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
            child: AdminDialogHeader(
              icon: Icons.groups_rounded, iconColor: const Color(0xFF3B82F6),
              title: widget.event['title'] as String? ?? 'Attendance',
              subtitle: [
                webFmtDate(widget.event['event_date'] as String?),
                ?org,
              ].join(' · '),
            ),
          ),
          Flexible(child: _error != null
              ? Padding(padding: const EdgeInsets.all(24), child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                    AdminFormErrorBanner(_error!),
                    const SizedBox(height: 12),
                    WebBtn(label: 'Try again', icon: Icons.refresh_rounded, small: true, onTap: _load),
                  ]))
              : rec == null
                  ? const Padding(padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: kAdminAccent)))
                  : _buildBody(t, rec)),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
            child: Row(children: [
              Text('Sorted by grade, section and last name',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close', style: TextStyle(fontFamily: 'Poppins', color: t.sub)),
              ),
              const SizedBox(width: 8),
              WebBtn(label: 'Export', icon: Icons.download_rounded, onTap: widget.onExport),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody(WebTk t, AttendanceRecord rec) {
    final q = _query.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final rows = rec.rows.where((r) {
      if (_mark != null && r.mark != _mark) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          (qDigits.isNotEmpty && r.lrn.replaceAll(RegExp(r'\D'), '').contains(qDigits));
    }).toList();

    Widget stat(String v, String l, Color c) => Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: t.dark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
            fontWeight: FontWeight.w800, color: t.text)),
        Text(l, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
      ]),
    ));

    Widget chip(String label, AttendanceMark? m, int n, Color c) => WebFilterChip(
        label: label, count: n, selected: _mark == m, selectedColor: c,
        onTap: () => setState(() => _mark = m));

    final headStyle = TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
        fontWeight: FontWeight.w700, letterSpacing: 0.8, color: t.sub);
    // Header labels stay on one line, whatever the width.
    Widget head(String s) => Text(s, maxLines: 1, softWrap: false,
        overflow: TextOverflow.ellipsis, style: headStyle);

    // One column layout for the header and every row, so they always line
    // up. Short, predictable columns get fixed widths that fit their labels
    // ("ATTENDANCE", "CHECKED IN"); Name and Section share the rest.
    Widget cols(List<Widget> c) => Row(children: [
      SizedBox(width: 36, child: c[0]),
      Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 12), child: c[1])),
      SizedBox(width: 140, child: c[2]),
      SizedBox(width: 76, child: c[3]),
      Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 12), child: c[4])),
      SizedBox(width: 100, child: c[5]),
      SizedBox(width: 112, child: c[6]),
    ]);
    final number = {for (var i = 0; i < rec.rows.length; i++) rec.rows[i]: i + 1};

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      // min: the window hugs short lists instead of leaving a tall empty gap;
      // long lists still scroll inside the Flexible below.
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          stat('${rec.registered}', 'Registered', kAdminAccent),
          const SizedBox(width: 8),
          stat('${rec.present}', 'Present', const Color(0xFF10B981)),
          const SizedBox(width: 8),
          stat('${rec.count(AttendanceMark.absent)}', 'Absent', kAdminErrorRed),
          const SizedBox(width: 8),
          stat('${(rec.rate * 100).round()}%', 'Attendance rate', const Color(0xFF3B82F6)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 6, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 220, height: 36, child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
            decoration: webInputDeco('Search name or LRN…', icon: Icons.search_rounded,
                dark: t.dark).copyWith(isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
          )),
          const SizedBox(width: 4),
          chip('All', null, rec.rows.length, kAdminAccent),
          chip('Present', AttendanceMark.present, rec.present, const Color(0xFF10B981)),
          chip('Absent', AttendanceMark.absent, rec.count(AttendanceMark.absent), kAdminErrorRed),
          if (rec.count(AttendanceMark.rejected) > 0)
            chip('Rejected', AttendanceMark.rejected,
                rec.count(AttendanceMark.rejected), const Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 12),
        // Column header — same style as the Archives table.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: cols([head('#'), head('NAME'), head('LRN'), head('GRADE'),
              head('SECTION'), head('CHECKED IN'), head('ATTENDANCE')]),
        ),
        Flexible(child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(rec.rows.isEmpty
                        ? 'No students registered for this event.'
                        : 'No students match your search.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted)))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: t.divider),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final c = switch (r.mark) {
                    AttendanceMark.present  => const Color(0xFF10B981),
                    AttendanceMark.rejected => const Color(0xFFF59E0B),
                    AttendanceMark.absent   => kAdminErrorRed,
                  };
                  TextStyle s([Color? col]) => TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, color: col ?? t.sub);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: cols([
                      Text('${number[r]}', style: s(t.muted)),
                      Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: s(t.text).copyWith(fontWeight: FontWeight.w600)),
                      Text(r.lrn.isEmpty ? '—' : r.lrn, maxLines: 1,
                          overflow: TextOverflow.ellipsis, style: s()),
                      Text([
                        if (r.grade != null) '${r.grade}',
                        if (r.strand != null) r.strand!,
                      ].join(' ').ifEmpty('—'), maxLines: 1,
                          overflow: TextOverflow.ellipsis, style: s()),
                      Text(r.section ?? '—', maxLines: 1,
                          overflow: TextOverflow.ellipsis, style: s()),
                      Text(r.mark == AttendanceMark.present ? _clock(r.checkedInAt) : '—',
                          maxLines: 1, style: s()),
                      Align(alignment: Alignment.centerLeft,
                          child: WebStatusBadge(label: attendanceMarkLabel(r.mark), color: c)),
                    ]),
                  );
                },
              )),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
