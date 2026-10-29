import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'key_store.dart';
import 'reviews_api.dart';

/// The app's only shared state: the saved key and who is logged in.
/// Screens listen to it with [ListenableBuilder].
class AppState extends ChangeNotifier {
  AppState({required this.store, this._client}) {
    final saved = store.read();
    if (saved != null && saved.isNotEmpty) _api = ReviewsApi(apiKey: saved, client: _client);
  }

  final KeyStore store;
  final http.Client? _client;

  ReviewsApi? _api;
  String? userName;

  bool get hasKey => _api != null;
  bool get loggedIn => _api?.token != null;

  /// The client for the saved key. Only call when [hasKey] is true.
  ReviewsApi get api => _api!;

  /// Checks [key] with one real call (GET /api/subjects), then remembers it.
  /// Throws [ApiException] if the API rejects it.
  Future<void> checkAndSaveKey(String key) async {
    final candidate = ReviewsApi(apiKey: key, client: _client);
    await candidate.listSubjects(perPage: 1);
    store.write(key);
    _api = candidate;
    userName = null;
    notifyListeners();
  }

  void forgetKey() {
    store.clear();
    _api = null;
    userName = null;
    notifyListeners();
  }

  void loggedInAs(String name) {
    userName = name;
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
