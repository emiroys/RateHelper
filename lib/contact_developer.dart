import 'external_url.dart';
import 'l10n.dart';

/// "Contact developer" row. The WhatsApp target is a compile-time define so
/// the number never lands in this public repo:
/// `--dart-define-from-file=dart_defines.json` (see dart_defines.example.json).
abstract final class ContactDeveloper {
  /// Digits with country code (`48123456789`) or a full `https://wa.me/…`
  /// link such as a QR contact link. Empty in CI and public clones.
  static const String whatsApp = String.fromEnvironment('CONTACT_WHATSAPP');

  static const String issuesUrl =
      'https://github.com/emiroys/ratehelper/issues';

  static bool get hasWhatsApp => whatsAppUrl(whatsApp) != null;

  /// Null when [raw] is empty or not a usable WhatsApp target.
  static String? whatsAppUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('https://wa.me/')) return value;
    if (!RegExp(r'^\d{6,15}$').hasMatch(value)) return null;
    final text = Uri.encodeComponent(S.contactDeveloperPrefill);
    return 'https://wa.me/$value?text=$text';
  }

  /// WhatsApp when configured, otherwise the GitHub issues page.
  static String get targetUrl => whatsAppUrl(whatsApp) ?? issuesUrl;

  static String get subtitle =>
      hasWhatsApp ? S.contactDeveloperWhatsApp : S.contactDeveloperGitHub;

  /// True when Android found an app to open the link.
  static Future<bool> open([String? url]) => ExternalUrl.open(url ?? targetUrl);
}
