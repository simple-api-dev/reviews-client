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
    final (api, _) = apiWith((_) => json({'message': 'Unauthorized.  Invalid apikey detected [x].'}, 401));
    await expectLater(
      api.listSubjects(),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 401)
          .having((e) => e.message, 'message', contains('Invalid apikey'))),
    );
  });

  test('an error without a JSON body still gets a readable message', () async {
    final (api, _) = apiWith((_) => http.Response('oops', 500));
    await expectLater(api.listSubjects(), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('500'))));
  });
}
