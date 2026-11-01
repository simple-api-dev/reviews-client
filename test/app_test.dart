import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reviews_client/app.dart';
import 'package:reviews_client/app_state.dart';
import 'package:reviews_client/config.dart';
import 'package:reviews_client/reviews_api.dart';
import 'package:reviews_client/screens/ui.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const subjects = {
  'data': [
    {'subject': 'blue-bike', 'count': 2, 'average': 4.5},
  ],
  'total': 1,
  'page': 1,
  'per_page': 25,
};

/// What register and login answer.
Map<String, Object> session(String token, String name) => {
      'token': token,
      'expires_at': '2026-11-30T10:15:00Z',
      'user': {'id': 1, 'name': name, 'email': 'test-user@example.com', 'admin': false, 'enabled': true, 'created_at': '2026-10-31T10:15:00Z', 'updated_at': '2026-10-31T10:15:00Z'},
    };

const reviews = {
  'summary': {
    'count': 1,
    'average': 5.0,
    'distribution': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 1},
  },
  'data': [
    {'id': 7, 'subject': 'blue-bike', 'author': 'Ann', 'rating': 5, 'title': 'Loved it', 'body': 'Smooth ride', 'helpful_counter': 0, 'unhelpful_counter': 0, 'comment_count': 0},
  ],
  'total': 1,
  'page': 1,
  'per_page': 25,
};

/// Links the app asked to open.
final opened = <String>[];

/// Pumps the whole app against a fake server and records the requests.
/// [buildKey] stands in for the key passed with --dart-define at build time.
Future<List<http.Request>> pumpApp(
  WidgetTester tester, {
  String buildKey = 'demo-key',
  Size size = const Size(1000, 1600),
  required http.Response Function(http.Request) server,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  opened.clear();
  final seen = <http.Request>[];
  final client = MockClient((r) async {
    seen.add(r);
    return server(r);
  });
  final state = AppState(apiKey: buildKey, client: client);
  await tester.pumpWidget(ReviewsApp(state: state, openUrl: opened.add));
  await tester.pumpAndSettle();
  return seen;
}

void main() {
  testWidgets('opens straight on subjects using the build-time key', (tester) async {
    final seen = await pumpApp(tester, buildKey: 'build-key', server: (_) => json(subjects));

    expect(find.text('blue-bike'), findsOneWidget);
    expect(find.text('2 reviews'), findsOneWidget);
        expect(seen.single.url.queryParameters['apikey'], 'build-key');
  });

  testWidgets('an API error is shown with a retry button', (tester) async {
    await pumpApp(
      tester,
      server: (_) => json({'message': 'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=reviews'}, 401),
    );
    expect(find.text('The API key was not accepted.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('opens a subject and shows the summary and its reviews', (tester) async {
    final seen = await pumpApp(
      tester,
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
      server: (r) {
        switch (r.url.path) {
          case '/api/reviews':
            return json(reviews);
          case '/api/users/login':
            return json(session('tok', 'Jane'));
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

  testWidgets('clicking your vote again takes it back and the counter drops', (tester) async {
    final seen = await pumpApp(
      tester,
      server: (r) {
        switch (r.url.path) {
          case '/api/reviews':
            return json(reviews);
          case '/api/users/login':
            return json(session('tok', 'Jane'));
          case '/api/reviews/7/helpful':
            return json({'helpful_counter': 1, 'unhelpful_counter': 0, 'your_vote': 'helpful'});
          case '/api/reviews/7/vote':
            return json({'message': 'Vote removed.'});
          default:
            return json(subjects);
        }
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Helpful 1'), findsOneWidget);

    await tester.tap(find.text('Helpful 1'));
    await tester.pumpAndSettle();

    expect(find.text('Helpful 0'), findsOneWidget);
    expect(seen.last.method, 'DELETE');
    expect(seen.last.url.path, '/api/reviews/7/vote');
  });

  testWidgets('posting a review sends rating, title and body', (tester) async {
    final seen = await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/login') return json(session('tok', 'Jane'));
        if (r.method == 'POST' && r.url.path == '/api/reviews') return json({'id': 8, 'subject': 'blue-bike', 'rating': 4}, 201);
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

  testWidgets('a vote rejected because the session ended asks for a login the next time', (tester) async {
    var logins = 0;
    await pumpApp(
      tester,
      server: (r) {
        switch (r.url.path) {
          case '/api/reviews':
            return json(reviews);
          case '/api/users/login':
            logins++;
            return json(session('tok-$logins', 'Jane'));
          case '/api/reviews/7/helpful':
            // Real answer once that session has ended.
            return r.headers['Authorization'] == 'Bearer tok-1'
                ? json({'message': 'Invalid or expired auth token. Log in again.'}, 401)
                : json({'helpful_counter': 1, 'unhelpful_counter': 0, 'your_vote': 'helpful'});
          default:
            return json(subjects);
        }
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();

    Future<void> logIn() async {
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    await logIn(); // token 1, which the fake server now rejects

    expect(find.text('Your session has ended. Please log in again.'), findsOneWidget);
    expect(find.text('Helpful 0'), findsOneWidget);

    // Before the fix the app still thought it was logged in and failed again.
    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    await logIn(); // token 2 works
    expect(find.text('Helpful 1'), findsOneWidget);
  });

  testWidgets('posting a second review of a subject shows the 409 message inside the dialog', (tester) async {
    await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/login') return json(session('tok', 'Jane'));
        if (r.method == 'POST' && r.url.path == '/api/reviews') {
          return json({'message': 'You already reviewed "blue-bike" (review 8). Use PUT /reviews/8 to change it.', 'review_id': 8}, 409);
        }
        if (r.url.path == '/api/reviews') return json(reviews);
        return json(subjects);
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(find.textContaining('You already reviewed "blue-bike"'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget); // the dialog stays open
  });

  testWidgets('a wrong password (401 from the real API) is shown on the login screen', (tester) async {
    await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/login') return json({'message': 'Invalid email or password.'}, 401);
        if (r.url.path == '/api/reviews') return json(reviews);
        return json(subjects);
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget); // still on the login screen
  });

  testWidgets('a 429 while loading subjects is shown with a retry that works afterwards', (tester) async {
    var throttled = true;
    await pumpApp(
      tester,
      server: (r) {
        if (throttled) return json({'message': 'Rate limit exceeded: 60 requests per minute.  Please try again in 12 seconds.'}, 429);
        return json(subjects);
      },
    );
    expect(find.text('Too many requests. Wait a few seconds and try again.'), findsOneWidget);
    throttled = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('blue-bike'), findsOneWidget);
  });

  testWidgets('voting on your own review (403) shows the API message and keeps the login', (tester) async {
    final seen = await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/login') return json(session('tok', 'Jane'));
        if (r.url.path == '/api/reviews/7/helpful') return json({'message': 'You cannot vote on your own review.'}, 403);
        if (r.url.path == '/api/reviews') return json(reviews);
        return json(subjects);
      },
    );
    await tester.tap(find.text('blue-bike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'test-user');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(find.text('You cannot vote on your own review.'), findsOneWidget);
    // A 403 is not a lost session: the next tap goes straight to the API again.
    seen.clear();
    await tester.tap(find.text('Helpful 0'));
    await tester.pumpAndSettle();
    expect(seen.single.url.path, '/api/reviews/7/helpful');
    expect(find.widgetWithText(FilledButton, 'Log in'), findsNothing);
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.account_circle));
    await tester.pumpAndSettle();
  }

  Future<List<http.Request>> pumpLoggedIn(WidgetTester tester, http.Response? Function(http.Request) extra) async {
    final seen = await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/login') return json(session('tok', 'Jane'));
        return extra(r) ?? json(subjects);
      },
    );
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'jane@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
    return seen;
  }

  group('The shared demo user cannot delete the account', () {
    Future<void> pumpLoggedOut(WidgetTester tester) async {
      await pumpApp(
        tester,
        server: (r) {
          if (r.url.path == '/api/users/login') return json(session('tok', 'Demo User'));
          return json(subjects);
        },
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
    }

    testWidgets('after the Try the demo account button', (tester) async {
      await pumpLoggedOut(tester);
      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();
      await openMenu(tester);

      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Delete my account'), findsNothing);
    });

    testWidgets('after typing the demo email by hand', (tester) async {
      await pumpLoggedOut(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), ' Demo@SimpleAPI.dev ');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'try-the-demo');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      await openMenu(tester);

      expect(find.text('Delete my account'), findsNothing);
    });
  });

  testWidgets('Delete my account: a wrong password (403) is shown and the user stays logged in', (tester) async {
    final seen = await pumpLoggedIn(tester, (r) {
      if (r.method == 'DELETE') return json({'message': 'Wrong password.'}, 403);
      return null;
    });
    await openMenu(tester);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong password.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete account'), findsOneWidget); // dialog still open
    final del = seen.firstWhere((r) => r.method == 'DELETE');
    expect(del.url.path, '/api/users/me');
    expect(del.url.queryParameters.containsKey('purge'), isFalse);
    expect(jsonDecode(del.body), {'password': 'wrong'});

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(find.text('Log out'), findsOneWidget); // still logged in
  });

  testWidgets('Delete my account with "also delete my reviews and comments" sends purge=true and logs out', (tester) async {
    final seen = await pumpLoggedIn(tester, (r) {
      if (r.method == 'DELETE') return json({'message': 'Account deleted.'});
      return null;
    });
    await openMenu(tester);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.text('Also delete my reviews and comments'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();

    final del = seen.firstWhere((r) => r.method == 'DELETE');
    expect(del.url.queryParameters['purge'], 'true');
    expect(del.headers['Authorization'], 'Bearer tok');
    expect(find.text('Your account was deleted.'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget); // logged out
    expect(find.byIcon(Icons.account_circle), findsNothing);
  });

  group('wording shared by the SimpleAPI samples', () {
    String say(int status, String message, {bool sessionEnded = false}) => describeError(ApiException(status, message, sessionEnded: sessionEnded));

    test('describeError', () {
      expect(say(0, 'Could not reach reviews.simpleapi.dev. Check your connection and try again.'), 'Could not reach reviews.simpleapi.dev. Check your connection and try again.');
      expect(say(401, 'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=reviews'), 'The API key was not accepted.');
      expect(say(401, 'Invalid or expired auth token. Log in again.', sessionEnded: true), 'Your session has ended. Please log in again.');
      expect(say(401, 'Invalid email or password.'), 'Invalid email or password.');
      expect(say(403, 'Wrong password.'), 'Wrong password.');
      expect(say(409, 'User registration failed, email already registered to this key.'), 'User registration failed, email already registered to this key.');
      expect(say(422, 'The email format is invalid.'), 'The email format is invalid.');
      expect(say(404, 'Review 9 not found.'), 'Not found. It may already have been deleted.');
      expect(say(429, 'Rate limit exceeded: 60 requests per minute.  Please try again in 5 seconds.'), 'Too many requests. Wait a few seconds and try again.');
      expect(say(503, 'Key service unavailable. Please try again shortly.'), 'The service is busy. Please try again shortly.');
      expect(describeError(StateError('boom')), 'Something went wrong. Please try again.');
    });

    testWidgets('the login screen shows the demo notice and the demo button, on login and on register', (tester) async {
      await pumpApp(tester, server: (_) => json(subjects));
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(find.text('This is a shared demo. Data resets every night. Do not use a real password or any private details.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try the demo account'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsNothing);
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(find.text('This is a shared demo. Data resets every night. Do not use a real password or any private details.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try the demo account'), findsOneWidget);
    });

    testWidgets('"Try the demo account" logs in as the demo user in one click, without the bearer token', (tester) async {
      final seen = await pumpApp(tester, server: (r) {
        if (r.url.path == '/api/users/login') return json(session('tok', 'Demo'));
        return json(subjects);
      });
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try the demo account'));
      await tester.pumpAndSettle();

      final login = seen.singleWhere((r) => r.url.path == '/api/users/login');
      expect(jsonDecode(login.body), {'email': 'demo@simpleapi.dev', 'password': 'try-the-demo'});
      expect(login.headers.containsKey('Authorization'), isFalse);
      expect(find.byIcon(Icons.account_circle), findsOneWidget); // back on Subjects, logged in
      expect(find.text('Log in'), findsNothing);
    });

    testWidgets('voting while logged out opens a login screen that offers the demo account', (tester) async {
      await pumpApp(tester, server: (r) => json(r.url.path == '/api/reviews' ? reviews : subjects));
      await tester.tap(find.text('blue-bike'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.thumb_up_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('Try the demo account'), findsOneWidget);
    });

    testWidgets('back arrow: tooltip, and it opens the SimpleAPI home page', (tester) async {
      await pumpApp(tester, server: (_) => json(subjects));
      expect(find.byTooltip('Back to SimpleAPI'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to SimpleAPI'));
      expect(opened, ['https://simpleapi.dev']);
    });

    testWidgets('inner screens keep the normal back arrow, not the home one', (tester) async {
      await pumpApp(tester, server: (r) => json(r.url.path == '/api/reviews' ? reviews : subjects));
      await tester.tap(find.text('blue-bike'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to SimpleAPI'), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });

    http.Response fullServer(http.Request r) => r.url.path == '/api/users/register'
        ? json({'message': 'Maximum number of user accounts (25) per key has been reached.'}, 403)
        : json(subjects);

    Future<void> register(WidgetTester tester) async {
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ann');
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'longenough');
      await tester.tap(find.widgetWithText(FilledButton, 'Register'));
      await tester.pumpAndSettle();
    }

    testWidgets('a full demo (403 on register) gets the demo-full message', (tester) async {
      await pumpApp(tester, server: fullServer);
      await register(tester);
      expect(find.text('The demo is full. It resets every night.'), findsOneWidget);
    });

    testWidgets('constants: the public demo account', (tester) async {
      expect(demoEmail, 'demo@simpleapi.dev');
      expect(demoPassword, 'try-the-demo');
    });

    testWidgets('a network failure reads the same everywhere', (tester) async {
      await pumpApp(tester, server: (_) => throw http.ClientException('socket detail'));
      expect(find.text('Could not reach reviews.simpleapi.dev. Check your connection and try again.'), findsOneWidget);
      expect(find.textContaining('socket detail'), findsNothing);
    });

    testWidgets('an empty subject list is padded, not flush against the edge', (tester) async {
      await pumpApp(tester, server: (_) => json({'data': [], 'total': 0, 'page': 1, 'per_page': 25}));
      final padding = find.ancestor(of: find.textContaining('No subjects yet'), matching: find.byType(Padding));
      expect(padding, findsWidgets);
    });
  });
}
