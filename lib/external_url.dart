import 'package:flutter/services.dart';

import 'log.dart';

/// `MainActivity.openExternalUrl`. Native only accepts the hosts it knows
/// (WhatsApp, GitHub, Google Maps directions, Waze), so a new destination
/// needs a matching change in `MainActivity.isAllowedExternalUrl`.
abstract final class ExternalUrl {
  static const MethodChannel _channel = MethodChannel(
    'com.ratehelper.app/system',
  );

  /// True when Android found an app to open the link.
  static Future<bool> open(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openExternalUrl', {
            'url': url,
          }) ??
          false;
    } on Exception catch (e, s) {
      loge('external link failed', name: 'links', error: e, stack: s);
      return false;
    }
  }
}
