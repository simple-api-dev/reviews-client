# reviews-client

A small Flutter **web** app that shows how to use the free
[SimpleApi Reviews API](https://reviews.simpleapi.dev/docs) (rate and review
anything, vote reviews helpful, comment on them). It is a teaching sample: no
backend, no state-management package, and the only dependency besides Flutter
is [`http`](https://pub.dev/packages/http).

**Live demo:** https://simple-api-dev.github.io/reviews-client/

## Get a free key

1. Go to https://keys.simpleapi.dev and request a key for the product URL
   `https://reviews.simpleapi.dev`.
2. Open the app and paste the key on the first screen.

The key is kept **only in your browser's localStorage** and is sent only to
`reviews.simpleapi.dev`, as the `apikey` query parameter. It is never hardcoded
or committed. Reading is allowed with just the key; writing (reviews, comments,
votes) also needs a logged-in user, whom you can register inside the app.
Users belong to your key, so every developer has their own set of users.

## Screens and the API calls they use

| Screen | What it does | Calls |
| --- | --- | --- |
| **Key** (`key_screen.dart`) | Paste and validate your key; "Change key" forgets it. | `GET /api/subjects` (a one-item request used to check the key) |
| **Subjects** (`subjects_screen.dart`) | Browse things that have reviews, with count and average; search by name prefix; start a review for a new subject. | `GET /api/subjects` |
| **Log in / Register** (`auth_screen.dart`) | Get a token. Opened automatically when you try to write or vote. | `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/logout` |
| **Reviews** (`reviews_screen.dart`) | One subject: average, 1-5 star breakdown, sortable reviews, helpful / not helpful votes (click again to take a vote back), write a review. | `GET /api/reviews?subject=`, `POST /api/reviews`, `POST /api/reviews/{id}/helpful`, `POST /api/reviews/{id}/unhelpful`, `DELETE /api/reviews/{id}/vote` |
| **Review** (`review_screen.dart`) | A review with its comments; add a comment. | `GET /api/reviews/{id}/comments`, `POST /api/reviews/{id}/comments` |

Every call lives in [`lib/reviews_api.dart`](lib/reviews_api.dart), one method
per endpoint with a comment naming it. The rest of the app never touches HTTP.
The login token is held in memory only, so reloading the page logs you out
while the key stays saved.

The API also has endpoints this sample does not use (editing and deleting your
own reviews and comments, `GET /api/users/me`, password reset, listing a
user's reviews); see the [full docs](https://reviews.simpleapi.dev/docs).

## Good to know

- Errors come back as `{"message": "..."}`; the app shows that text.
- A bad or missing key answers `401`.
- Registering with the email address your key belongs to answers `202` and
  emails a confirmation code instead of returning a token
  (`POST /api/users/register/confirm`). The sample shows the message but does
  not implement the confirmation step; use a different address to try it out.
- You get one review per user per subject; a second one answers `409`.
- The API is rate limited, so a burst of clicks may be answered with an error.

## Run locally

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable; CI uses 3.47.8).

```bash
flutter pub get
flutter run -d chrome
```

Run the tests (all HTTP is mocked, nothing calls the real API):

```bash
flutter test
```

## Project layout

```
lib/reviews_api.dart      the whole API client
lib/models.dart           response classes
lib/app_state.dart        saved key + logged-in user (a ChangeNotifier)
lib/key_store*.dart       localStorage wrapper (+ in-memory one for tests)
lib/screens/              the five screens
test/                     unit tests for the client, widget tests for the app
```

## Deploy (GitHub Pages)

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) runs on every push
to `main`: it installs Flutter, runs `flutter analyze` and `flutter test`,
builds with `flutter build web --release --base-href /reviews-client/` and
publishes through the official `upload-pages-artifact` and `deploy-pages`
actions. In your fork or copy, set **Settings -> Pages -> Source** to
**GitHub Actions**. If you rename the repository, change `--base-href` to
match.
