import 'dart:io';

class StrictSecurityHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => false;
    client.connectionTimeout = const Duration(seconds: 10);
    return client;
  }
}
