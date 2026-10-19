import 'dart:typed_data';

// No-op on non-web platforms. Admins only use the web build,
// so CSV download is silently skipped on Android/iOS.
void downloadCsv(String content, String name) {}

/// Web only — file downloads aren't supported on Android/iOS.
void downloadFile(Uint8List bytes, String fileName, String mimeType) =>
    throw UnsupportedError('File downloads are only available on the web.');
