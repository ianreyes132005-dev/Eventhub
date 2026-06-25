import 'dart:math';

/// Generates a RFC-4122 v4 UUID (no external package needed).
String genUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int n) => n.toRadixString(16).padLeft(2, '0');
  return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}-'
      '${h(b[4])}${h(b[5])}-${h(b[6])}${h(b[7])}-'
      '${h(b[8])}${h(b[9])}-'
      '${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
}

String fmtDate(String? iso) {
  if (iso == null) return '—';
  try {
    final d = DateTime.parse(iso).toLocal();
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) { return '—'; }
}

String fmtTime(String? t) {
  if (t == null || t.isEmpty) return '';
  try {
    final parts  = t.split(':');
    final h      = int.parse(parts[0]);
    final m      = parts[1].padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h > 12 ? h - 12 : h == 0 ? 12 : h;
    return '$h12:$m $period';
  } catch (_) { return t; }
}

String timeAgo(String? iso) {
  if (iso == null) return '';
  try {
    final d    = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    if (diff.inDays    < 30) return '${diff.inDays}d ago';
    return fmtDate(iso);
  } catch (_) { return ''; }
}

String todayLabel() {
  final n = DateTime.now();
  const days   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  return '${days[n.weekday - 1]}, ${months[n.month - 1]} ${n.day}';
}

// Backward-compat aliases — callers in web pages and admin still use web_ prefix.
String webFmtDate(String? iso)  => fmtDate(iso);
String webFmtTime(String? t)    => fmtTime(t);
String webTimeAgo(String? iso)  => timeAgo(iso);
String webTodayLabel()          => todayLabel();
String webUuid()                => genUuid();
