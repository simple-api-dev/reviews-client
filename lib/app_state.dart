import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'reviews_api.dart';

/// The app's only shared state: the API client and who is logged in.
/// Screens listen to it with [ListenableBuilder].
///
/// The app uses only the key built in with --dart-define (see config.dart).
class AppState extends ChangeNotifier {
  AppState({String apiKey = configuredKey, http.Client? client}) {
    api = ReviewsApi(
      apiKey: apiKey,
      client: client,
      onSessionExpired: _sessionExpired,
    );
  }

  late final ReviewsApi api;
  String? userName;

  /// True for the shared demo account. Every visitor uses it, so the app does
  /// not offer to delete it.
  bool isDemoUser = false;

  bool get loggedIn => api.token != null;

  /// The API rejected our token (e.g. the user logged in elsewhere): the api
  /// object already dropped it, so just update what the screens show.
  void _sessionExpired() {
    userName = null;
    isDemoUser = false;
    notifyListeners();
  }

  void loggedInAs(String name, {required String email}) {
    userName = name;
    isDemoUser = email.trim().toLowerCase() == demoEmail;
    notifyListeners();
  }

  /// DELETE /api/users/me. Throws [ApiException] (403 wrong password, 422
  /// missing password) and leaves the user logged in; on success the user is
  /// logged out.
  Future<void> deleteAccount({
    required String password,
    bool purge = false,
  }) async {
    await api.deleteAccount(password: password, purge: purge);
    userName = null;
    isDemoUser = false;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      api.token = null; // token already invalid: just drop it
    }
    userName = null;
    isDemoUser = false;
    notifyListeners();
  }
}
