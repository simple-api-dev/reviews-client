# SimpleAPI Reviews API: Flutter web sample

A small Flutter web app that shows how to call the free [SimpleAPI Reviews API](https://reviews.simpleapi.dev/docs) from a browser, with no backend of your own.

**[Live demo](https://simple-api-dev.github.io/reviews-client/)** | **[API docs](https://reviews.simpleapi.dev/docs)** | **[Get a free key](https://keys.simpleapi.dev/?product=reviews)**

![The sample app](docs/screenshot.png)

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable; CI uses 3.47.8) and a free key from [keys.simpleapi.dev](https://keys.simpleapi.dev/?product=reviews).

```bash
git clone https://github.com/simple-api-dev/reviews-client
cd reviews-client
flutter pub get
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=YOUR_KEY
```

On the live demo, press **Try the demo account** on the login screen to log in as the shared demo user in one click. Run the tests with `flutter test`. All HTTP is mocked, so nothing calls the real API.

## How it calls the API

Every call is one method in [`lib/reviews_api.dart`](lib/reviews_api.dart). The key goes in the `apikey` query string. Writes also send the user's bearer token. Every list answers `{data, total, page, per_page}`, with `summary` beside it on the review lists:

```dart
final uri = Uri.https('reviews.simpleapi.dev', '/api/reviews', {'subject': 'pizza-palace', 'apikey': apiKey});
final response = await http.get(uri, headers: {'Accept': 'application/json'});
final reviews = jsonDecode(response.body)['data'];
```

The rest of the app never touches HTTP. The login token is held in memory only, so reloading the page logs you out.

## Screens and API calls

| Screen | What it does | Calls |
| --- | --- | --- |
| **Subjects** (`subjects_screen.dart`) | The landing screen, with a back arrow to simpleapi.dev. Browse things that have reviews, with count and average; search by name prefix; start a review for a new subject. | `GET /api/subjects` |
| **Log in / Register** (`auth_screen.dart`) | Get a token, or press **Try the demo account** to log in as the shared demo user. Opened automatically when you try to write or vote. | `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/logout` |
| **Delete my account** (`delete_account_dialog.dart`) | Shown in the Subjects bar when logged in, but not to the shared demo account: the API answers `403` `The demo account cannot be changed.` for it. Asks for your password; the checkbox "Also delete my reviews and comments" adds `purge=true`. | `DELETE /api/users/me` (password in the JSON body), `DELETE /api/users/me?purge=true` |
| **Reviews** (`reviews_screen.dart`) | One subject: average, 1-5 star breakdown, sortable reviews, helpful / not helpful votes (click again to take a vote back), write a review. | `GET /api/reviews?subject=`, `POST /api/reviews`, `POST /api/reviews/{id}/helpful`, `POST /api/reviews/{id}/unhelpful`, `DELETE /api/reviews/{id}/vote` |
| **Review** (`review_screen.dart`) | A review with its comments; add a comment. | `GET /api/reviews/{id}/comments`, `POST /api/reviews/{id}/comments` |

The API also has calls this sample does not use (editing and deleting your own reviews and comments, `GET` and `PUT /api/users/me`, password reset, listing a user's reviews); see the [full docs](https://reviews.simpleapi.dev/docs).

## Use your own key

The live demo is built with a shared demo key. The app has no screen for entering a key: it uses only the key compiled in at build time. To run it with your own, pass it to Flutter:

```bash
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=YOUR_KEY
```

Get a free key at [keys.simpleapi.dev](https://keys.simpleapi.dev/?product=reviews).

## Good to know

- Errors come back as `{"message": "..."}`, on every status. The app turns the common ones into the same short sentences in all the SimpleAPI samples (see `describeError` in `lib/screens/ui.dart`) and shows the API's own message for 401 on login, 403, 409 and 422.
- A bad or missing key answers `401`. So does a wrong email or password on login (`"Invalid email or password."`), which is not an expired session. A token that is no longer valid also answers `401`, on any route it is sent to: the app drops it and asks the user to log in again. Login and register never send the bearer token, and neither does reading, which needs only the key.
- Register and login answer `{"token": "...", "expires_at": "...", "user": {...}}`. A token lasts 30 days, and a user can have 20 sessions, so logging in on a second device leaves the first one logged in. Logging out ends this session only.
- Register: `201`, `409` if the email is taken, `422` for invalid input, `400` for a malformed JSON body, `403` when the key already has 25 users.
- Registering with the email address your key belongs to answers `202` and emails a confirmation code instead of returning a token (`POST /api/users/register/confirm`). The sample shows the message but does not implement the confirmation step; use a different address to try it out.
- `DELETE /api/users/me` needs your password in the JSON body (`403` if wrong, `422` if missing). Without `purge=true` your reviews and comments stay, with `author` set to `null`. With it they are deleted and the vote counters are recounted.
- You get one review per user per subject; a second one answers `409`.
- Writing a review or a comment answers `201` with the new object. Taking back a vote answers `{"message": "..."}`, so the app works out the new counters itself.
- Timestamps are UTC, like `2026-11-01T03:47:06Z`.
- `author` is the writer's name, or `null` if there is none. The app shows `by <author>`, or `by Unknown`.
- A subject is any id or slug. The app shows a lowercase slug such as `pizza-palace` as `Pizza Palace`, and sends the stored text in every call.
- The API allows 60 requests a minute per IP address and answers `429` beyond that.
- The demo account is `demo@simpleapi.dev` with password `try-the-demo`. It is public by design and shared by every visitor, and the live demo resets every night, so do not use a real password or any private details. When the demo key has no room for more users, registering shows "The demo is full. It resets every night." Writing needs a logged-in user, whom you can register inside the app. Users belong to your key, so every developer has their own set of users.

## Project layout

```
lib/reviews_api.dart      the whole API client
lib/models.dart           response classes
lib/app_state.dart        the API client and logged-in user (a ChangeNotifier)
lib/open_url*.dart        opens a link in the same tab (the back arrow)
lib/config.dart           the build-time key (SIMPLEAPI_KEY) and the demo account
lib/screens/              the screens, and ui.dart with the shared widgets and error wording
test/                     unit tests for the client, widget tests for the app
```

## Deploy to GitHub Pages

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) runs on every push to `main`. It runs `flutter analyze` and `flutter test`, builds with `flutter build web --release --base-href /reviews-client/`, and publishes with the official Pages actions.

In your own copy:

1. Set **Settings, Pages, Source** to **GitHub Actions**.
2. Add a repository **variable** named `SIMPLEAPI_KEY` under **Settings, Secrets and variables, Actions, Variables**. The build passes it with `--dart-define=SIMPLEAPI_KEY=...`.
3. Push to `main`, or run the workflow.

Anything passed with `--dart-define` ends up in the compiled JavaScript, so anyone can read it from the deployed site. Use a free key made for a public demo. If you rename the repository, change `--base-href` to match.

## License

[MIT](LICENSE)
