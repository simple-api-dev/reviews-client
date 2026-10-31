import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reviews_client/app.dart';
import 'package:reviews_client/app_state.dart';
import 'package:reviews_client/key_store.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const subjects = {
  'subjects': [
    {'subject': 'blue-bike', 'count': 2, 'average': 4.5},
  ],
};

const reviews = {
  'summary': {
    'count': 1,
    'average': 5.0,
    'distribution': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 1},
  },
  'total': 1,
  'reviews': [
    {'id': 7, 'subject': 'blue-bike', 'author': 'Ann', 'rating': 5, 'title': 'Loved it', 'body': 'Smooth ride', 'helpful_counter': 0, 'unhelpful_counter': 0, 'comment_count': 0},
  ],
};

/// Links the app asked to open.
final opened = <String>[];

/// Pumps the whole app against a fake server and records the requests.
/// [buildKey] stands in for the key passed with --dart-define at build time.
Future<List<http.Request>> pumpApp(
  WidgetTester tester, {
  KeyStore? store,
  String buildKey = '',
  required http.Response Function(http.Request) server,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  opened.clear();
  final seen = <http.Request>[];
  final client = MockClient((r) async {
    seen.add(r);
    return server(r);
  });
  final state = AppState(store: store ?? MemoryKeyStore(), buildKey: buildKey, client: client);
  await tester.pumpWidget(ReviewsApp(state: state, openUrl: opened.add));
  await tester.pumpAndSettle();
  return seen;
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens straight on subjects using the build-time key', (tester) async {
    final seen = await pumpApp(tester, buildKey: 'build-key', server: (_) => json(subjects));

    expect(find.text('blue-bike'), findsOneWidget);
    expect(find.text('2 reviews'), findsOneWidget);
    expect(find.text('This demo has no key configured'), findsNothing);
    expect(seen.single.url.queryParameters['apikey'], 'build-key');
  });

  testWidgets('without any key it explains so, links to get one, and calls nothing', (tester) async {
    final seen = await pumpApp(tester, server: (_) => json(subjects));

    expect(find.text('This demo has no key configured'), findsOneWidget);
    expect(seen, isEmpty);

    await tester.tap(find.text('Get a free key'));
    expect(opened, ['https://keys.simpleapi.dev/?product=reviews']);
  });

  testWidgets('a key saved in this browser overrides the build key', (tester) async {
    final seen = await pumpApp(
      tester,
      store: MemoryKeyStore('own-key'),
      buildKey: 'build-key',
      server: (_) => json(subjects),
    );
    expect(seen.single.url.queryParameters['apikey'], 'own-key');
  });

  testWidgets('"Use your own key" validates it, saves it and reloads with it', (tester) async {
    final store = MemoryKeyStore();
    final seen = await pumpApp(tester, store: store, buildKey: 'build-key', server: (_) => json(subjects));

    await openSettings(tester);
    await tester.enterText(find.byType(TextField), '  pasted-key ');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(seen.map((r) => r.url.queryParameters['apikey']), ['build-key', 'pasted-key', 'pasted-key']);
    expect(store.read(), 'pasted-key');
    expect(find.text('blue-bike'), findsOneWidget);
  });

  testWidgets('a rejected own key is not saved and the API message is shown', (tester) async {
    final store = MemoryKeyStore();
    await pumpApp(
      tester,
      store: store,
      buildKey: 'build-key',
      server: (r) => r.url.queryParameters['apikey'] == 'nope'
          ? json({'message': 'Unauthorized.  Invalid apikey detected [nope].'}, 401)
          : json(subjects),
    );
    await openSettings(tester);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(store.read(), isNull);
    expect(find.textContaining('Invalid apikey'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('"Go back to the demo key" forgets the saved key', (tester) async {
    final store = MemoryKeyStore('own-key');
    final seen = await pumpApp(tester, store: store, buildKey: 'build-key', server: (_) => json(subjects));

    await openSettings(tester);
    await tester.tap(find.text('Go back to the demo key'));
    await tester.pumpAndSettle();

    expect(store.read(), isNull);
    expect(seen.last.url.queryParameters['apikey'], 'build-key');
    expect(find.text('blue-bike'), findsOneWidget);
  });

  testWidgets('an API error is shown with a retry button', (tester) async {
    await pumpApp(
      tester,
      store: MemoryKeyStore('bad'),
      server: (_) => json({'message': 'Unauthorized.  Invalid apikey detected [bad].'}, 401),
    );
    expect(find.textContaining('Invalid apikey'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('opens a subject and shows the summary and its reviews', (tester) async {
    final seen = await pumpApp(
      tester,
      store: MemoryKeyStore('k'),
      server: (r) => r.url.path == '/api/reviews' ? json(reviews) : json(subjects),
    );

    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();

    expect(find.text('Loved it'), findsOneWidget);
    expect(find.text('5.0'), findsOneWidget);
    expect(seen.last.url.queryParameters['subject'], 'blue-bike');
  });

  testWidgets('voting while logged out opens login, then votes after logging in', (tester) async {
    final seen = await pumpApp(
      tester,
      store: MemoryKeyStore('k'),
      server: (r) {
        switch (r.url.path) {
          case '/api/reviews':
            return json(reviews);
          case '/api/users/login':
            return json({'id': 1, 'name': 'Jane', 'token': 'tok'});
          case '/api/reviews/7/helpful':
            return json({'helpful_counter': 1, 'unhelpful_counter': 0, 'your_vote': 'helpful'});
          default:
            return json(subjects);
        }
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsWidgets); // the login screen opened

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    // After logging in, the vote you attempted goes through.
    expect(find.text('Helpful 1'), findsOneWidget);
    final vote = seen.last;
    expect(vote.url.path, '/api/reviews/7/helpful');
    expect(vote.headers['Authorization'], 'Bearer tok');
  });

  testWidgets('posting a review sends rating, title and body', (tester) async {
    final seen = await pumpApp(
      tester,
      store: MemoryKeyStore('k'),
      server: (r) {
        if (r.url.path == '/api/users/login') return json({'name': 'Jane', 'token': 'tok'});
        if (r.method == 'POST' && r.url.path == '/api/reviews') return json({'id': 8, 'subject': 'blue-bike', 'rating': 4});
        if (r.url.path == '/api/reviews') return json(reviews);
        return json(subjects);
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();

    // Writing needs a user: the login screen opens first, then the form.
    await tester.tap(find.text('Write a review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Great');
    await tester.enterText(find.widgetWithText(TextField, 'Review'), 'Would ride again');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    final post = seen.firstWhere((r) => r.method == 'POST' && r.url.path == '/api/reviews');
    expect(jsonDecode(post.body), {'subject': 'blue-bike', 'rating': 5, 'title': 'Great', 'body': 'Would ride again'});
    expect(post.headers['Authorization'], 'Bearer tok');
  });
}
