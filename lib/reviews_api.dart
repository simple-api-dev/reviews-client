/// The whole Reviews API client. Every network call in the app is in this file.
///
/// Docs: https://reviews.simpleapi.dev/docs
///
/// Two rules apply to every request:
///  * the API key goes in the `apikey` query string (an `APIKEY` header also works);
///  * calls that write data also send `Authorization: Bearer <token>`, where
///    the token comes from [ReviewsApi.register] / [ReviewsApi.login].
///
/// Every list answers `{data, total, page, per_page}`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thrown for any non-2xx answer. [message] is the API's own `message` when it
/// sent one, e.g. "Invalid email or password.". [statusCode] is 0 when the API
/// could not be reached at all.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.sessionEnded = false});

  final int statusCode;
  final String message;

  /// True for a 401 on a call that carried a Bearer token: the token is dead
  /// (it expired, the user logged out everywhere, or was deleted).
  final bool sessionEnded;

  /// True for a 401 about the apikey itself.
  bool get keyRejected => statusCode == 401 && !sessionEnded && message.toLowerCase().contains('apikey');

  @override
  String toString() => message;
}

/// The API host. Keys are sent only here.
const apiHost = 'reviews.simpleapi.dev';

class ReviewsApi {
  ReviewsApi({
    required this.apiKey,
    this.token,
    http.Client? client,
    this.host = apiHost,
    this.onSessionExpired,
  }) : _http = client ?? http.Client();

  final String apiKey;
  final String host;

  /// Set after [login] / [register]; sent as the Bearer token.
  String? token;

  /// Called after the API rejected our Bearer token (401): a token lasts 30
  /// days and a user can have 20 sessions, so it can end while the app is open.
  /// The token is dropped first, so the next write asks for a login again.
  final void Function()? onSessionExpired;

  final http.Client _http;

  // ---------------------------------------------------------------- reading

  /// GET /api/subjects - subjects that have reviews, with count and average.
  /// [sort]: most_reviewed (default), best, worst or name. [q]: name prefix.
  Future<List<Subject>> listSubjects({String? q, String? sort, int page = 1, int perPage = 25}) async {
    final json = await _send('GET', '/api/subjects', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      'sort': ?sort,
      'page': '$page',
      'per_page': '$perPage',
    }, authenticated: false);
    return [for (final s in (json['data'] as List? ?? const [])) Subject.fromJson(s as Map<String, dynamic>)];
  }

  /// GET /api/reviews?subject=... - reviews plus the average rating and the
  /// 1-5 star breakdown. [sort]: newest (default), oldest, rating_desc,
  /// rating_asc or helpful.
  Future<ReviewPage> listReviews({String? subject, String? sort, int page = 1, int perPage = 25}) async {
    final json = await _send('GET', '/api/reviews', query: {
      'subject': ?subject,
      'sort': ?sort,
      'page': '$page',
      'per_page': '$perPage',
    }, authenticated: false);
    return ReviewPage.fromJson(json);
  }

  /// GET /api/reviews/{id}/comments - comments on one review, oldest first.
  Future<List<Comment>> listComments(int reviewId, {int page = 1, int perPage = 100}) async {
    final json = await _send('GET', '/api/reviews/$reviewId/comments', query: {
      'page': '$page',
      'per_page': '$perPage',
    }, authenticated: false);
    return [for (final c in (json['data'] as List? ?? const [])) Comment.fromJson(c as Map<String, dynamic>)];
  }

  // ------------------------------------------------------------------ users

  /// POST /api/users/register - create a user that belongs to this key.
  /// Answers 201 with `{token, expires_at, user}`, or 202 (no token) when the email is the one the
  /// key belongs to and a confirmation code was emailed instead. Errors: 403
  /// the key already has its 25 users, 409 the email is taken, 422 invalid input.
  Future<AuthResult> register({required String name, required String email, required String password}) async {
    final json = await _send('POST', '/api/users/register', body: {'name': name, 'email': email, 'password': password}, authenticated: false);
    return _authResult(json);
  }

  /// POST /api/users/login - answers `{token, expires_at, user}`. A wrong email or
  /// password is a 401 "Invalid email or password." - not an expired session,
  /// so it never touches the token the app may be holding.
  Future<AuthResult> login({required String email, required String password}) async {
    final json = await _send('POST', '/api/users/login', body: {'email': email, 'password': password}, authenticated: false);
    return _authResult(json);
  }

  /// DELETE /api/users/me - delete your own account. The current [password]
  /// goes in the JSON body (403 if wrong, 422 if missing). With [purge] the
  /// API also deletes your reviews, your comments, every comment on your
  /// reviews and all your votes (`?purge=true`); without it they stay,
  /// shown under your name. Either way all your sessions end.
  Future<void> deleteAccount({required String password, bool purge = false}) async {
    await _send('DELETE', '/api/users/me', query: {if (purge) 'purge': 'true'}, body: {'password': password});
    token = null;
  }

  /// POST /api/users/logout - ends this session. Your other sessions keep
  /// working; `?all=true` would end them too.
  Future<void> logout() async {
    await _send('POST', '/api/users/logout');
    token = null;
  }

  AuthResult _authResult(Map<String, dynamic> json) {
    final result = AuthResult.fromJson(json);
    if (result.token != null) token = result.token;
    return result;
  }

  // ---------------------------------------------------------------- writing
  // Everything below needs a logged-in user (Bearer token).

  /// POST /api/reviews - write a review. One review per user per subject
  /// (a second one answers 409). [rating] is 1-5.
  Future<Review> createReview({
    required String subject,
    required int rating,
    String? title,
    String? body,
  }) async {
    final json = await _send('POST', '/api/reviews', body: {
      'subject': subject,
      'rating': rating,
      if (title != null && title.isNotEmpty) 'title': title,
      if (body != null && body.isNotEmpty) 'body': body,
    });
    return Review.fromJson(json);
  }

  /// POST /api/reviews/{id}/comments - comment on a review.
  Future<Comment> addComment(int reviewId, String body) async {
    final json = await _send('POST', '/api/reviews/$reviewId/comments', body: {'body': body});
    return Comment.fromJson(json);
  }

  /// POST /api/reviews/{id}/helpful or /unhelpful - vote on a review.
  Future<VoteResult> vote(int reviewId, {required bool helpful}) async {
    final json = await _send('POST', '/api/reviews/$reviewId/${helpful ? 'helpful' : 'unhelpful'}');
    return VoteResult.fromJson(json);
  }

  /// DELETE /api/reviews/{id}/vote - take back your vote. Answers a message,
  /// not the counters.
  Future<void> removeVote(int reviewId) async {
    await _send('DELETE', '/api/reviews/$reviewId/vote');
  }

  // ---------------------------------------------------------------- plumbing

  /// Sends one request and returns the decoded JSON object. Login, register
  /// and reading pass `authenticated: false`: they need only the key. A 401
  /// from login is about the credentials, not about a session, and a token
  /// that has ended must not get in the way of reading.
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.https(host, path, {...query, 'apikey': apiKey});
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers.addAll({if (authenticated && token != null) 'Authorization': 'Bearer $token'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw ApiException(0, 'Could not reach $host. Check your connection and try again.');
    }

    Object? decoded;
    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _errorMessage(response.statusCode, decoded);
      // 401 with a token sent = the session is over ("Invalid auth token. Log
      // in again."). A 401 about the apikey is a different problem: keep the token.
      final sessionEnded = response.statusCode == 401 && request.headers.containsKey('Authorization') && !message.toLowerCase().contains('apikey');
      if (sessionEnded) {
        token = null;
        onSessionExpired?.call();
      }
      throw ApiException(response.statusCode, message, sessionEnded: sessionEnded);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  /// Errors arrive as `{"message": "..."}`; validation errors may add more
  /// detail, so fall back to showing whatever came back.
  String _errorMessage(int status, Object? decoded) {
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
      if (decoded['errors'] != null) return '${decoded['errors']}';
    }
    return 'Something went wrong. Please try again.';
  }
}
