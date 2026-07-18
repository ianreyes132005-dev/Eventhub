// No-op on non-web platforms. Admins only use the web build,
// so CSV download is silently skipped on Android/iOS.
void downloadCsv(String content, String name) {}
