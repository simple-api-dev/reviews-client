# reviews-client

A small Flutter **web** app that shows how to use the free
[SimpleApi Reviews API](https://reviews.simpleapi.dev/docs) (rate and review
anything, vote reviews helpful, comment on them). It is a teaching sample: no
backend, no state-management package, and the only dependency besides Flutter
is [`http`](https://pub.dev/packages/http).

**Live demo:** https://simple-api-dev.github.io/reviews-client/

## Keys

This is a **reference implementation**: the live demo opens straight on the
reviews, with no sign-in or key prompt, because a demo key is compiled into it
at build time.

**Use your own key.** In the app open **Settings -> Use your own key** and paste
a key; it is checked with one call and kept only in your browser's
localStorage, where it overrides the demo key. Get a free key at
https://keys.simpleapi.dev/?product=reviews (product URL
`https://reviews.simpleapi.dev`). Keys are sent only to `reviews.simpleapi.dev`,
as the `apikey` query parameter. Reading needs just the key; writing (reviews,
comments, votes) also needs a logged-in user, whom you can register inside the
app. Users belong to your key, so every developer has their own set of users.

**Set the demo key for your deployment.** The key is read with
`String.fromEnvironment('SIMPLEAPI_KEY')` and nothing is ever committed:

1. In your repository go to **Settings -> Secrets and variables -> Actions ->
   Variables** and add a repository **variable** named `SIMPLEAPI_KEY`.
2. Push to `main` (or run the workflow). It builds with
   `--dart-define=SIMPLEAPI_KEY=...`.

Anything passed with `--dart-define` ends up in the compiled JavaScript, so
anyone can read it from the deployed site. Use a free key made for a public
demo. If the variable is empty, the app shows "This demo has no key
configured" with a link to get one.

## Screens and the API calls they use

| Screen | What it does | Calls |
| --- | --- | --- |
| **Subjects** (`subjects_screen.dart`) | The landing screen. Browse things that have reviews, with count and average; search by name prefix; start a review for a new subject. | `GET /api/subjects` |
| **Settings** (`settings_screen.dart`) | Use your own key instead of the demo key (or go back to it). | `GET /api/subjects` (a one-item request used to check the key) |
| **Log in / Register** (`auth_screen.dart`) | Get a token. Opened automatically when you try to write or vote. | `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/logout` |
| **Delete my account** (`delete_account_dialog.dart`) | Shown in the Subjects bar when logged in. Asks for your password; the checkbox "Also delete my reviews and comments" adds `purge=true`. | `DELETE /api/users/me` (password in the JSON body), `DELETE /api/users/me?purge=true` |
| **Reviews** (`reviews_screen.dart`) | One subject: average, 1-5 star breakdown, sortable reviews, helpful / not helpful votes (click again to take a vote back), write a review. | `GET /api/reviews?subject=`, `POST /api/reviews`, `POST /api/reviews/{id}/helpful`, `POST /api/reviews/{id}/unhelpful`, `DELETE /api/reviews/{id}/vote` |
| **Review** (`review_screen.dart`) | A review with its comments; add a comment. | `GET /api/reviews/{id}/comments`, `POST /api/reviews/{id}/comments` |

Every call lives in [`lib/reviews_api.dart`](lib/reviews_api.dart), one method
per endpoint with a comment naming it. The rest of the app never touches HTTP.
The login token is held in memory only, so reloading the page logs you out
while your own key, if you saved one, stays.

The API also has endpoints this sample does not use (editing and deleting your
own reviews and comments, `GET /api/users/me`, password reset, listing a
user's reviews); see the [full docs](https://reviews.simpleapi.dev/docs).

## Good to know

- Errors come back as `{"message": "..."}`; the app shows that text.
- A bad or missing key answers `401`. So does a wrong email or password on login
  (`"Invalid email or password."`), which is not an expired session; an expired or
  replaced token answers `401 "Invalid auth token. Log in again."`.
- Register: `409` if the email is taken, `422` for invalid input, `400` for a
  malformed JSON body. A new user answers `201` (the API used to answer `200`;
  the sample accepts both).
- `DELETE /api/users/me` needs your password in the JSON body (`403` if wrong,
  `422` if missing). Without `purge=true` your reviews and comments stay,
  attributed to your deleted user id; with it they are deleted and the vote
  counters are recounted.
- Running locally with a key: `flutter run -d chrome --dart-define=SIMPLEAPI_KEY=<your key>`, or just paste it under Settings.
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
lib/config.dart           the build-time key (SIMPLEAPI_KEY)
lib/screens/              the screens
test/                     unit tests for the client, widget tests for the app
```

## Deploy (GitHub Pages)

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) runs on every push
to `main`: it installs Flutter, runs `flutter analyze` and `flutter test`,
builds with `flutter build web --release --base-href /reviews-client/` and
publishes through the official `upload-pages-artifact` and `deploy-pages`
actions. In your fork or copy, add the `SIMPLEAPI_KEY` variable (see Keys) and set **Settings -> Pages -> Source** to
**GitHub Actions**. If you rename the repository, change `--base-href` to
match.
