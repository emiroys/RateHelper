import 'dart:io';

import 'package:flutter/foundation.dart';

/// The only place this app constructs an [HttpClient] for GitHub.
///
/// [requests] records every URL passed to a GET before a socket is opened.
/// Tests replace [newClient] and read [requests] to prove a quiet startup
/// stayed offline.
class GithubHttp {
  static HttpClient Function() newClient = HttpClient.new;

  static final List<Uri> requests = <Uri>[];

  static void note(Uri uri) => requests.add(uri);

  static HttpClient open() => newClient();

  @visibleForTesting
  static void reset() {
    requests.clear();
    newClient = HttpClient.new;
  }
}
