// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadCsv(String content, String name) {
  try {
    final blob = html.Blob([content], 'text/csv;charset=utf-8');
    final url  = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download',
          '${name}_${DateTime.now().millisecondsSinceEpoch}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}
