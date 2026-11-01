import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reviews_client/reviews_api.dart';

// A made-up value: the tests never touch the real API or a real key.
const fakeKey = 'test-key';

/// Builds an API whose HTTP client answers with [handler] and records requests.
(ReviewsApi, List<http.Request>) apiWith(http.Response Function(http.Request) handler, {String? token}) {
  final seen = <http.Request>[];
  final client = MockClient((request) async {
    seen.add(request);
    return handler(request);
  });
  return (ReviewsApi(apiKey: fakeKey, token: token, client: client), seen);
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('sends the key as the apikey query parameter, not as a header', () async {
    final (api, seen) = apiWith((_) => json({'subjects': []}));
    await api.listSubjects(q: 'bi');

    final r = seen.single;
    expect(r.method, 'GET');
    expect(r.url.host, 'reviews.simpleapi.dev');
    expect(r.url.path, '/api/subjects');
    expect(r.url.queryParameters['apikey'], fakeKey);
    expect(r.url.queryParameters['q'], 'bi');
    expect(r.headers.containsKey('Authorization'), isFalse);
    expect(r.headers.values.any((v) => v.contains(fakeKey)), isFalse);
  });

  test('parses subjects', () async {
    final (api, _) = apiWith((_) => json({
          'subjects': [
            {'subject': 'blue-bike', 'count': 3, 'average': 4.5},
          ],
        }));
    final subjects = await api.listSubjects();
    expect(subjects.single.name, 'blue-bike');
    expect(subjects.single.count, 3);
    expect(subjects.single.average, 4.5);
  });

  test('parses reviews with summary and star breakdown', () async {
    final (api, seen) = apiWith((_) => json({
          'summary': {
            'count': 2,
            'average': 4.0,
            'distribution': {'1': 0, '2': 0, '3': 0, '4': 2, '5': 0},
          },
          'total': 2,
          'reviews': [
            {'id': 7, 'subject': 'blue-bike', 'author': 'Ann', 'rating': 4, 'title': 'Nice', 'body': 'Good', 'helpful_counter': 2, 'unhelpful_counter': 1, 'comment_count': 3},
          ],
        }));
    final page = await api.listReviews(subject: 'blue-bike', sort: 'helpful');

    expect(seen.single.url.queryParameters['subject'], 'blue-bike');
    expect(seen.single.url.queryParameters['sort'], 'helpful');
    expect(page.summary.average, 4.0);
    expect(page.summary.distribution[4], 2);
    expect(page.reviews.single.id, 7);
    expect(page.reviews.single.helpful, 2);
    expect(page.reviews.single.commentCount, 3);
  });

  test('parses a comments array', () async {
    final (api, seen) = apiWith((_) => json([
          {'id': 1, 'review_id': 7, 'author': 'Bob', 'body': 'Thanks'},
        ]));
    final comments = await api.listComments(7);
    expect(seen.single.url.path, '/api/reviews/7/comments');
    expect(comments.single.body, 'Thanks');
  });

  test('login stores the token and later calls send it as a Bearer header', () async {
    final (api, seen) = apiWith((r) {
      if (r.url.path == '/api/users/login') return json({'id': 1, 'name': 'Jane', 'token': 'tok-1'});
      return json({'id': 9, 'subject': 'x', 'rating': 5});
    });
    final result = await api.login(email: 'test-user', password: 'pw');
    expect(result.token, 'tok-1');
    expect(result.name, 'Jane');
    expect(jsonDecode(seen.first.body), {'email': 'test-user', 'password': 'pw'});
    expect(seen.first.headers['Authorization'], isNull);

    await api.createReview(subject: 'x', rating: 5, title: 'T', body: 'B');
    final post = seen.last;
    expect(post.method, 'POST');
    expect(post.url.path, '/api/reviews');
    expect(post.url.queryParameters['apikey'], fakeKey);
    expect(post.headers['Authorization'], 'Bearer tok-1');
    expect(jsonDecode(post.body), {'subject': 'x', 'rating': 5, 'title': 'T', 'body': 'B'});
  });

  test('register answering 202 gives no token and keeps the message', () async {
    final (api, _) = apiWith((_) => json({'message': 'A code was emailed.', 'confirmation_required': true}, 202));
    final result = await api.register(name: 'Jane', email: 'test-user', password: 'pw');
    expect(result.token, isNull);
    expect(result.message, 'A code was emailed.');
    expect(api.token, isNull);
  });

  test('vote, change of mind and comment hit the right endpoints', () async {
    final (api, seen) = apiWith((r) {
      if (r.url.path.endsWith('/comments')) return json({'id': 1, 'body': 'hi', 'author': 'Jane'});
      return json({'helpful_counter': 1, 'unhelpful_counter': 0, 'your_vote': 'helpful'});
    }, token: 'tok');

    final v = await api.vote(5, helpful: true);
    expect(v.helpful, 1);
    expect(v.yourVote, 'helpful');
    await api.vote(5, helpful: false);
    await api.removeVote(5);
    await api.addComment(5, 'hi');

    expect([for (final r in seen) '${r.method} ${r.url.path}'], [
      'POST /api/reviews/5/helpful',
      'POST /api/reviews/5/unhelpful',
      'DELETE /api/reviews/5/vote',
      'POST /api/reviews/5/comments',
    ]);
    expect(jsonDecode(seen.last.body), {'body': 'hi'});
  });

  test('logout clears the token', () async {
    final (api, seen) = apiWith((_) => json({}), token: 'tok');
    await api.logout();
    expect(seen.single.url.path, '/api/users/logout');
    expect(api.token, isNull);
  });

  test('non-2xx answers become an ApiException carrying the API message', () async {
    final (api, _) = apiWith((_) => json({'message': 'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=reviews'}, 401));
    await expectLater(
      api.listSubjects(),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 401)
          .having((e) => e.message, 'message', contains('valid apikey'))),
    );
  });

  test('an error without a JSON body still gets a readable message', () async {
    final (api, _) = apiWith((_) => http.Response('oops', 500));
    await expectLater(api.listSubjects(), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('500'))));
  });

  group('a 401 on a request that carried a token', () {
    test('drops the dead token and tells the app, keeping the API message', () async {
      var expired = 0;
      final client = MockClient((_) async => json({'message': 'Invalid auth token. Log in again.'}, 401));
      final api = ReviewsApi(apiKey: fakeKey, token: 'old', client: client, onSessionExpired: () => expired++);

      await expectLater(
        api.createReview(subject: 'x', rating: 5),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401).having((e) => e.message, 'message', 'Invalid auth token. Log in again.')),
      );
      expect(api.token, isNull);
      expect(expired, 1);
    });

    test('a bad apikey is a different 401: the token is kept', () async {
      var expired = 0;
      final client = MockClient((_) async => json({'message': 'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=reviews'}, 401));
      final api = ReviewsApi(apiKey: fakeKey, token: 'good', client: client, onSessionExpired: () => expired++);

      await expectLater(api.listSubjects(), throwsA(isA<ApiException>()));
      expect(api.token, 'good');
      expect(expired, 0);
    });

    test('a 401 with no token sent (login first) does not call it a lost session', () async {
      var expired = 0;
      final client = MockClient((_) async => json({'message': 'Unauthorized. Log in and send the header "Authorization: Bearer <token>".'}, 401));
      final api = ReviewsApi(apiKey: fakeKey, client: client, onSessionExpired: () => expired++);

      await expectLater(api.addComment(1, 'hi'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
      expect(expired, 0);
    });
  });

  // Status codes and bodies as the API answers them. Every error is {"message": "..."}.
  group('real error answers', () {
    Future<ApiException> fails(int status, Object? body, Future<void> Function(ReviewsApi) call, {String? token}) async {
      final (api, _) = apiWith((_) => body is String ? http.Response(body, status) : json(body!, status), token: token);
      try {
        await call(api);
      } on ApiException catch (e) {
        expect(e.statusCode, status);
        return e;
      }
      fail('expected an ApiException');
    }

    test('403 voting on your own review', () async {
      final e = await fails(403, {'message': 'You cannot vote on your own review.'}, (a) => a.vote(7, helpful: true), token: 't');
      expect(e.message, 'You cannot vote on your own review.');
    });

    test('403 editing someone else\'s comment is shown as sent', () async {
      final e = await fails(403, {'message': "Only the comment's author or an admin can change this comment."}, (a) => a.addComment(7, 'x'), token: 't');
      expect(e.message, contains('author or an admin'));
    });

    test('401 wrong email or password on login', () async {
      final e = await fails(401, {'message': 'Invalid email or password.'}, (a) => a.login(email: 'jane@example.com', password: 'nope'));
      expect(e.statusCode, 401);
      expect(e.message, 'Invalid email or password.');
    });

    test('a failed login is not an expired session: the token is kept and not sent', () async {
      var expired = 0;
      final seen = <http.Request>[];
      final api = ReviewsApi(
        apiKey: fakeKey,
        token: 'still-good',
        client: MockClient((r) async {
          seen.add(r);
          return json({'message': 'Invalid email or password.'}, 401);
        }),
        onSessionExpired: () => expired++,
      );
      await expectLater(api.login(email: 'a@b.co', password: 'nope'), throwsA(isA<ApiException>()));
      expect(expired, 0);
      expect(api.token, 'still-good');
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('404 comments of a missing review', () async {
      final e = await fails(404, {'message': 'Review 999999999 not found.'}, (a) => a.listComments(999999999));
      expect(e.message, 'Review 999999999 not found.');
    });

    test('409 second review of a subject keeps the message (extra review_id is ignored)', () async {
      final e = await fails(
        409,
        {'message': 'You already reviewed "blue-bike" (review 8). Use PUT /reviews/8 to change it.', 'review_id': 8},
        (a) => a.createReview(subject: 'blue-bike', rating: 4),
        token: 't',
      );
      expect(e.message, startsWith('You already reviewed "blue-bike"'));
    });

    test('422 rating out of range', () async {
      final e = await fails(422, {'message': 'The rating must be between 1 and 5.'}, (a) => a.createReview(subject: 'x', rating: 6), token: 't');
      expect(e.message, 'The rating must be between 1 and 5.');
    });

    test('422 several missing fields arrive as one message', () async {
      final e = await fails(
        422,
        {'message': 'The name field is required.  The password field is required.'},
        (a) => a.register(name: '', email: 'a@b.co', password: ''),
      );
      expect(e.message, contains('password field is required'));
    });

    test('422 short password', () async {
      final e = await fails(422, {'message': 'The password must be at least 8 characters.'}, (a) => a.register(name: 'J', email: 'a@b.co', password: 'abc'));
      expect(e.message, 'The password must be at least 8 characters.');
    });

    test('409 duplicate register', () async {
      final e = await fails(
        409,
        {'message': 'User registration failed, email already registered to this developer account.'},
        (a) => a.register(name: 'J', email: 'a@b.co', password: 'longenough'),
      );
      expect(e.statusCode, 409);
      expect(e.message, contains('already registered'));
    });

    test('400 malformed JSON body', () async {
      final e = await fails(
        400,
        {'message': 'The request body is not valid JSON: Syntax error'},
        (a) => a.login(email: 'a@b.co', password: 'longenough'),
      );
      expect(e.statusCode, 400);
      expect(e.message, startsWith('The request body is not valid JSON'));
    });

    test('422 register with an email that has no dotted domain', () async {
      final e = await fails(422, {'message': 'The email format is invalid.'}, (a) => a.register(name: 'J', email: 'a@b', password: 'longenough'));
      expect(e.statusCode, 422);
    });

    test('429 throttling, with or without a JSON body, is readable and does not drop the login', () async {
      // A body-less 429 is covered too.
      final e = await fails(429, {'message': 'Rate limit exceeded: 60 requests per minute.  Please try again in 30 seconds.'}, (a) => a.listSubjects(), token: 'keep-me');
      expect(e.message, 'Rate limit exceeded: 60 requests per minute.  Please try again in 30 seconds.');
      final (api, _) = apiWith((_) => http.Response('', 429, headers: {'retry-after': '30'}), token: 'keep-me');
      await expectLater(api.listSubjects(), throwsA(isA<ApiException>().having((x) => x.message, 'message', contains('429'))));
      expect(api.token, 'keep-me');
    });
  });

  test('logout copes with the bare JSON `true` the API answers with', () async {
    final (api, _) = apiWith((_) => http.Response('true', 200, headers: {'content-type': 'application/json'}), token: 'tok');
    await api.logout();
    expect(api.token, isNull);
  });

  test('register answers with: user fields plus token', () async {
    final (api, _) = apiWith((_) => json({'name': 'Jane', 'email': 'jane@example.com', 'enabled': true, 'token': 'tok', 'admin': false, 'id': 9}));
    final result = await api.register(name: 'Jane', email: 'jane@example.com', password: 'longenough');
    expect(result.token, 'tok');
    expect(result.name, 'Jane');
    expect(api.token, 'tok');
  });

  test('real review and vote bodies: null meta, extra fields and your_vote are tolerated', () async {
    final (api, _) = apiWith((r) {
      if (r.url.path.endsWith('/helpful')) return json({'helpful_counter': 1, 'unhelpful_counter': 0, 'your_vote': 'helpful'});
      // POST /api/reviews has no comment_count and "meta": null.
      return json({
        'id': 4, 'subject': 'blue-bike', 'user_id': 10, 'tags': ['livecheck'], 'rating': 4, 'title': 'T', 'body': 'B',
        'bad': false, 'spam': false, 'helpful_counter': 0, 'unhelpful_counter': 0, 'author': 'Live One', 'meta': null,
        'reviewed_at': '2026-10-31T10:00:00.000000Z',
      });
    }, token: 't');
    final review = await api.createReview(subject: 'blue-bike', rating: 4, title: 'T', body: 'B');
    expect(review.id, 4);
    expect(review.commentCount, 0);
    expect((await api.vote(4, helpful: true)).yourVote, 'helpful');
  });

  group('register', () {
    test('201 with a token logs the new user in', () async {
      final (api, seen) = apiWith((_) => json({'id': 3, 'name': 'Jane', 'email': 'j@x.co', 'admin': false, 'token': 'tok-201'}, 201));
      final result = await api.register(name: 'Jane', email: 'j@x.co', password: 'longenough');
      expect(result.token, 'tok-201');
      expect(api.token, 'tok-201');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/api/users/register');
    });

    test('202 (the key owner\'s email) returns the message and no token', () async {
      final (api, _) = apiWith((_) => json({'message': 'We sent a 6 digit code.', 'confirmation_required': true}, 202));
      final result = await api.register(name: 'Dev', email: 'dev@x.co', password: 'longenough');
      expect(result.token, isNull);
      expect(result.message, 'We sent a 6 digit code.');
      expect(api.token, isNull);
    });
  });

  test('comment_count is read from a single-review response', () async {
    final (api, _) = apiWith(
      (_) => json({'id': 9, 'subject': 's', 'author': 'Ann', 'rating': 4, 'helpful_counter': 0, 'unhelpful_counter': 0, 'comment_count': 3}),
      token: 'tok',
    );
    final review = await api.createReview(subject: 's', rating: 4);
    expect(review.commentCount, 3);
  });

  group('deleteAccount (DELETE /api/users/me)', () {
    test('sends the password in the JSON body, no purge by default, then forgets the token', () async {
      final (api, seen) = apiWith((_) => json({'message': 'Account deleted.'}), token: 'tok');
      await api.deleteAccount(password: 'secret-pw');

      final r = seen.single;
      expect(r.method, 'DELETE');
      expect(r.url.path, '/api/users/me');
      expect(r.url.queryParameters.containsKey('purge'), isFalse);
      expect(r.url.queryParameters['apikey'], fakeKey);
      expect(r.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(r.body), {'password': 'secret-pw'});
      expect(r.url.toString().contains('secret-pw'), isFalse); // never in the URL
      expect(api.token, isNull);
    });

    test('purge adds ?purge=true', () async {
      final (api, seen) = apiWith(
        (_) => json({'message': 'Account deleted.', 'purged': {'reviews': 1, 'comments': 2, 'votes': 3}}),
        token: 'tok',
      );
      await api.deleteAccount(password: 'secret-pw', purge: true);
      expect(seen.single.url.queryParameters['purge'], 'true');
      expect(jsonDecode(seen.single.body), {'password': 'secret-pw'});
    });

    test('403 wrong password keeps the login', () async {
      var expired = 0;
      final api = ReviewsApi(
        apiKey: fakeKey,
        token: 'tok',
        client: MockClient((_) async => json({'message': 'Wrong password.'}, 403)),
        onSessionExpired: () => expired++,
      );
      final e = await api.deleteAccount(password: 'nope').then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);
      expect(e?.statusCode, 403);
      expect(e?.message, 'Wrong password.');
      expect(api.token, 'tok');
      expect(expired, 0);
    });

    test('422 missing password', () async {
      final (api, _) = apiWith((_) => json({'message': 'The password field is required.'}, 422), token: 'tok');
      await expectLater(api.deleteAccount(password: ''), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)));
      expect(api.token, 'tok');
    });

    test('401 (token no longer valid) ends the session', () async {
      var expired = 0;
      final api = ReviewsApi(
        apiKey: fakeKey,
        token: 'old',
        client: MockClient((_) async => json({'message': 'Invalid auth token. Log in again.'}, 401)),
        onSessionExpired: () => expired++,
      );
      await expectLater(api.deleteAccount(password: 'pw'), throwsA(isA<ApiException>()));
      expect(expired, 1);
      expect(api.token, isNull);
    });
  });

  group('errors the user sees', () {
    test('a network failure names the host and never leaks the exception', () async {
      final api = ReviewsApi(apiKey: fakeKey, client: MockClient((_) async => throw http.ClientException('XMLHttpRequest error. secret detail')));
      await expectLater(
        api.listSubjects(),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 0)
            .having((e) => e.message, 'message', 'Could not reach reviews.simpleapi.dev. Check your connection and try again.')),
      );
    });

    test('a 401 with a token is a session that ended, not a rejected key', () async {
      final api = ReviewsApi(apiKey: fakeKey, token: 'old', client: MockClient((_) async => json({'message': 'Invalid auth token. Log in again.'}, 401)));
      await expectLater(api.addComment(1, 'x'), throwsA(isA<ApiException>().having((e) => e.sessionEnded, 'sessionEnded', true).having((e) => e.keyRejected, 'keyRejected', false)));
    });

    test('a 401 about the apikey is a rejected key, even while logged in', () async {
      final api = ReviewsApi(apiKey: fakeKey, token: 'good', client: MockClient((_) async => json({'message': 'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=reviews'}, 401)));
      await expectLater(api.addComment(1, 'x'), throwsA(isA<ApiException>().having((e) => e.keyRejected, 'keyRejected', true).having((e) => e.sessionEnded, 'sessionEnded', false)));
    });

    test('a wrong password on login is neither of those, and no Bearer token is sent', () async {
      final seen = <http.Request>[];
      final api = ReviewsApi(
        apiKey: fakeKey,
        token: 'stale',
        client: MockClient((r) async {
          seen.add(r);
          return json({'message': 'Invalid email or password.'}, 401);
        }),
      );
      await expectLater(
        api.login(email: 'a@b.co', password: 'nope-nope'),
        throwsA(isA<ApiException>().having((e) => e.sessionEnded, 'sessionEnded', false).having((e) => e.keyRejected, 'keyRejected', false)),
      );
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
      expect(api.token, 'stale');
    });

    test('register never sends the Bearer token either', () async {
      final seen = <http.Request>[];
      final api = ReviewsApi(apiKey: fakeKey, token: 'stale', client: MockClient((r) async {
        seen.add(r);
        return json({'message': 'x'}, 409);
      }));
      await expectLater(api.register(name: 'J', email: 'a@b.co', password: 'longenough'), throwsA(isA<ApiException>()));
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });
  });
}
