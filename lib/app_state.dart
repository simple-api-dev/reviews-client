import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'key_store.dart';
import 'reviews_api.dart';

/// The app's only shared state: which key is in use and who is logged in.
/// Screens listen to it with [ListenableBuilder].
///
/// The key comes from the build ([buildKey]) unless the visitor saved their
/// own in this browser's localStorage, which then takes over.
class AppState extends ChangeNotifier {
  AppState({required this.store, this.buildKey = configuredKey, this._client}) {
    final own = store.read();
    _useKey(
      own != null && own.isNotEmpty ? own : buildKey,
      own: own != null && own.isNotEmpty,
    );
  }

  final KeyStore store;
  final String buildKey;
  final http.Client? _client;

  ReviewsApi? _api;
  bool _usingOwnKey = false;
  String? userName;

  /// Bumped whenever the key changes so screens can reload their data.
  int keyVersion = 0;

  bool get hasKey => _api != null;
  bool get hasBuildKey => buildKey.isNotEmpty;
  bool get usingOwnKey => _usingOwnKey;
  bool get loggedIn => _api?.token != null;

  /// The client for the current key. Only call when [hasKey] is true.
  ReviewsApi get api => _api!;

  void _useKey(String key, {required bool own}) {
    _api = key.isEmpty ? null : ReviewsApi(apiKey: key, client: _client, onSessionExpired: _sessionExpired);
    _usingOwnKey = own;
    userName = null;
    keyVersion++;
  }

  /// The API rejected our token (e.g. the user logged in elsewhere): the api
  /// object already dropped it, so just update what the screens show.
  void _sessionExpired() {
    userName = null;
    notifyListeners();
  }

  /// Checks [key] with one real call (GET /api/subjects), then remembers it in
  /// localStorage and uses it instead of the build key.
  /// Throws [ApiException] if the API rejects it.
  Future<void> useOwnKey(String key) async {
    await ReviewsApi(apiKey: key, client: _client).listSubjects(perPage: 1);
    store.write(key);
    _useKey(key, own: true);
    notifyListeners();
  }

  /// Forgets the saved key and goes back to the build key (if there is one).
  void useBuildKey() {
    store.clear();
    _useKey(buildKey, own: false);
    notifyListeners();
  }

  void loggedInAs(String name) {
    userName = name;
    notifyListeners();
  }

  /// DELETE /api/users/me. Throws [ApiException] (403 wrong password, 422
  /// missing password) and leaves the user logged in; on success the user is
  /// logged out.
  Future<void> deleteAccount({required String password, bool purge = false}) async {
    await api.deleteAccount(password: password, purge: purge);
    userName = null;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      api.token = null; // token already invalid: just drop it
    }
    userName = null;
    notifyListeners();
  }
}
