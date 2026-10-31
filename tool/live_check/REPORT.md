# Live check report: Reviews API and this sample app

Run on 2026-10-31 against https://reviews.simpleapi.dev with the shared demo key
(read from `SIMPLEAPI_KEY`, never stored). Harness: [`live_check.py`](live_check.py),
see the [README](README.md).

**This shows what was tried, not that the API or the app is bug free.** The API
source is private, so behaviour is judged only from the live Swagger
(`/docs-api.json`) and real responses. One run, one key, one region, no load.

Summary: 132 checks in the functional run (about 140 paced requests, one per second),
129 PASS, 3 FAIL, plus a burst probe (the table's last row and the section below). The 3 FAILs are API/doc mismatches, not
app problems. Clean-up worked: both test users were deleted and no `livecheck-*`
review or subject remained. "PASS" means the API did what the docs say, or, where
the docs are silent, what is conventional (stated in the Expected column).

## Every API call the app makes (`lib/reviews_api.dart`)

| App method | Request | Checked |
| --- | --- | --- |
| `listSubjects` | `GET /api/subjects` (`q`, `sort`, `page`, `per_page`) | yes |
| `listReviews` | `GET /api/reviews` (`subject`, `sort`, `page`, `per_page`) | yes |
| `listComments` | `GET /api/reviews/{id}/comments` | yes |
| `register` | `POST /api/users/register` | yes (not the 202 admin path) |
| `login` | `POST /api/users/login` | yes |
| `logout` | `POST /api/users/logout` | yes |
| `createReview` | `POST /api/reviews` | yes |
| `addComment` | `POST /api/reviews/{id}/comments` | yes |
| `vote` | `POST /api/reviews/{id}/helpful` and `/unhelpful` | yes |
| `removeVote` | `DELETE /api/reviews/{id}/vote` | yes |

The harness also covers calls the app does not make (edit/delete review, edit/delete
comment, `GET /reviews/{id}`, `GET /users/{id}/reviews`, `GET /users/me`,
`DELETE /users/{id}`) because the task asked for them.

## The four things the earlier manual run suspected

| Suspicion | What I saw | Does the live Swagger promise otherwise? |
| --- | --- | --- |
| After a new login the register token stops working (single session per user) | **Confirmed.** Every login (also with an upper-cased email) returns a new token and the previous one answers `401 "Invalid auth token. Log in again."`. Logging out kills the token too. | **Silent.** Login says only "Returns a new bearer token"; nothing says earlier tokens die. Not a contradiction, but an undocumented rule that bites anyone with two tabs/devices. The app had a real bug because of it (fixed, below). |
| Wrong password gives `404 "Login Failed (<email>)"`, not 401 | **Confirmed.** An unknown email gives the same 404, so it does not leak which emails exist. The message echoes the email. | **No, it matches.** `POST /users/login` documents `404: Login failed`. Unconventional (401 is the usual), but promised. |
| Duplicate register gives `400 "User registration failed, email already registered to this developer account."` | **Confirmed**, also for a different letter case of the same email. | **Doc gap.** Register documents only `200` and `202`. `400` is not listed; elsewhere the API uses `409` for "already exists" (duplicate review) and `422` for validation. I'd expect `409` or `422`. |
| Register returns `200`, not `201` | **Confirmed**: `200` with `{name,email,enabled,token,admin,id}`. | **No, it matches.** Documented as `200: User created`. |

## Rate limit

* Every response carries `X-RateLimit-Limit: 20` and `X-RateLimit-Remaining`. No `Retry-After` was ever seen because **no 429 was provoked**.
* The paced functional part ran about 140 requests at one per second (around 60 per minute, including roughly 20 login/register calls) with zero 429s.
* Burst probes after clean-up: 80 unpaced sequential GETs (about 2 per second, 43 s) and 40 GETs from 8 threads in 9 s: zero 429s.
* `Remaining` is not a steady countdown. It jumps between 0 and 20 from one call to the next (it read `0` once and the next call was still `200`), which looks like several server instances each keeping their own counter. So the header is not a reliable meter, and the effective limit is **not** "20 per short window per key".
* The earlier manual run's `429 Throttle Limit Exceeded` after about 25 quick calls therefore **could not be reproduced**, and its exact body and headers were not captured. The app tests use `{"message":"Throttle Limit Exceeded"}` as reported by that run, plus a body-less 429 with `Retry-After`. The limit may depend on endpoint, time of day or total load; I did not push harder against a shared API.
* The harness still paces at 1/s by default and backs off on 429 using `Retry-After` (else 5, 10, 20 s), so it is safe to rerun.

## All checks

Expected = what the Swagger says, or the conventional answer where it is silent.
Actual = HTTP status (0 = no response). Notes show the API's own message.

| Check | Expected | Actual | Result | Note |
| --- | --- | --- | --- | --- |
| GET /subjects without apikey | 4xx (docs: apikey required; no code listed) | 401 | PASS | Unauthorized.  Please provide a valid apikey. Register for a free apikey at https://keys.simpleapi.dev using product URL https://reviews.simpleapi.dev. |
| GET /subjects with a wrong apikey | 401 (docs silent; app expects 'Unauthorized...') | 401 | PASS | Unauthorized.  Invalid apikey detected [00000000-0000-0000-0000-000000000000]. Register for a free apikey at https://keys.simpleapi.dev using product URL https: |
| GET /subjects with a malformed apikey | 4xx | 401 | PASS | Unauthorized.  Invalid apikey detected [not-a-uuid]. Register for a free apikey at https://keys.simpleapi.dev using product URL https://reviews.simpleapi.dev. |
| GET /subjects with the demo key | 200 {subjects:[...]} | 200 | PASS |  |
| apikey as a header only (docs: query param) | 401 | 401 | PASS | header must not work |
| register u1 | 200 + token (docs: 200 'User created') | 200 | PASS | app also copes with 202 |
| register u2 | 200 + token | 200 | PASS |  |
| register duplicate email | 409 or 422 (docs list neither) | 400 | FAIL | User registration failed, email already registered to this developer account. |
| register duplicate email, different case | 409/422 (same mailbox) | 400 | PASS | User registration failed, email already registered to this developer account. |
| register bad email | 422 (docs: format email) | 422 | PASS | The email must be a valid email address. |
| register short password (3 chars) | 422 (docs give no minimum) | 422 | PASS | The password must be at least 8 characters. |
| register missing name+password | 422 | 422 | PASS | The name field is required.  The password field is required. |
| login right password | 200 + token | 200 | PASS |  |
| session: register token still valid after a later login? | docs silent ('Returns a new bearer token') | 401 | PASS | OLD token rejected -> single active session |
| session: newest token works | 200 | 200 | PASS |  |
| session: 2nd login invalidates the previous login token? | docs silent | 401 | PASS | yes |
| login with upper-cased email | 200 (emails are case-insensitive) | 200 | PASS |  |
| login with mixed-case local part | 200 | 200 | PASS |  |
| login wrong password | 404 (docs: 404 'Login failed') | 404 | PASS | Login Failed (simpleapi-sample-apps+fd856d4006@agentmail.to) |
| login unknown email | 404 (same as wrong password, no user enumeration) | 404 | PASS | Login Failed (nobody+bdb9d19fd2@agentmail.to) |
| login missing password | 422 | 422 | PASS | The password field is required. |
| login malformed JSON | 4xx | 422 | PASS | The email field is required.  The password field is required. |
| GET /users/me without a token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| GET /users/me with a garbage token | 401 | 401 | PASS | Invalid auth token. Log in again. |
| POST /reviews without a token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| POST /reviews with a garbage token | 401 | 401 | PASS | Invalid auth token. Log in again. |
| POST /reviews valid (u1) | 200 + review | 200 | PASS |  |
| POST /reviews response has every field of the Swagger Review schema | id,subject,user_id,author,rating,title,body,tags,meta,helpful_counter,unhelpful_counter,spam,bad,comment_count,reviewed_at | 200 | FAIL | missing: comment_count \| fields: {"id": "int", "subject": "str", "user_id": "int", "tags": "list", "rating": "int", "title": "str", "body": "str", "bad": "bool |
| POST /reviews duplicate subject (same user) | 409 (docs) | 409 | PASS | You already reviewed "livecheck-21747031" (review 8). Use PUT /reviews/8 to change it. |
| POST /reviews same subject, different case | informational: 409 if subjects are case-insensitive, 200 if distinct | 409 | PASS | You already reviewed "LIVECHECK-21747031" (review 8). Use PUT /reviews/8 to change it. |
| POST /reviews rating 0 | 422 (docs: 422 validation error) | 422 | PASS | The rating must be between 1 and 5. |
| POST /reviews rating 6 | 422 (docs: 422 validation error) | 422 | PASS | The rating must be between 1 and 5. |
| POST /reviews rating -1 | 422 (docs: 422 validation error) | 422 | PASS | The rating must be between 1 and 5. |
| POST /reviews rating 3.5 | 422 (docs: 422 validation error) | 422 | PASS | The rating must be an integer. |
| POST /reviews rating "abc" | 422 (docs: 422 validation error) | 422 | PASS | The rating must be an integer. |
| POST /reviews missing rating | 422 (docs: 422 validation error) | 422 | PASS | The rating field is required. |
| POST /reviews missing subject | 422 (docs: 422 validation error) | 422 | PASS | The subject field is required. |
| POST /reviews empty subject | 422 (docs: 422 validation error) | 422 | PASS | The subject field is required. |
| POST /reviews rating "5" (numeric string) | informational (lenient coercion is fine) | 200 | PASS |  |
| POST /reviews same subject, different user | 200 | 200 | PASS |  |
| POST /reviews 300-char subject | 422 or 200 (docs give no limit) | 422 | PASS | The subject may not be greater than 255 characters. |
| POST /reviews unicode + HTML in text | 200 and echoed unchanged | 200 | PASS | title echoed as: <script>alert(1)</script> |
| GET /reviews?subject= (list + summary) | 200 {summary,total,reviews} | 200 | PASS | keys: page,per_page,reviews,summary,total |
| GET /reviews list items have every field the app reads | author+body+comment_count+helpful_counter+id+rating+reviewed_at+subject+title+unhelpful_counter | 200 | PASS | missing:  |
| summary count/average/distribution correct (2 reviews: 4 and 2) | count 2, average 3.0, distribution 2->1, 4->1 | 200 | PASS | {"count": 2, "average": 3, "distribution": {"1": 0, "2": 1, "3": 0, "4": 1, "5": 0}} |
| total field matches | total 2 | 200 | PASS | total=2 |
| GET /reviews rating=4 filter | only the 4-star review | 200 | PASS |  |
| GET /reviews sort=newest | 200 | 200 | PASS | ratings=[2, 4] |
| GET /reviews sort=oldest | 200 | 200 | PASS | ratings=[4, 2] |
| GET /reviews sort=rating_desc | 200, order [4, 2] | 200 | PASS | ratings=[4, 2] |
| GET /reviews sort=rating_asc | 200, order [2, 4] | 200 | PASS | ratings=[2, 4] |
| GET /reviews sort=helpful | 200 | 200 | PASS | ratings=[2, 4] |
| GET /reviews sort=bogus | 200 (default) or 422 | 200 | PASS | silently defaults |
| GET /reviews per_page=1&page=2 | 1 review, total still 2 | 200 | PASS | total=2 |
| GET /reviews per_page=500 (docs: max 50) | 200 clamped, or 422 | 200 | PASS | 2 returned |
| GET /reviews page=0 | 200 or 422 | 200 | PASS |  |
| GET /reviews unknown subject | 200, empty list | 200 | PASS | summary={"count": 0, "average": null, "distribution": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0}} |
| GET /reviews tags=livecheck | the tagged review only | 200 | PASS | total=1 |
| GET /reviews/{id} | 200 review (+ comments) | 200 | PASS | keys: author,bad,body,comments,helpful_counter,id,meta,rating,reviewed_at,spam,subject,tags,title,unhelpful_counter,user_id |
| GET /reviews/{missing} | 404 | 404 | PASS | Review 999999999 not found. |
| GET /reviews/abc | 404 or 422 | 404 | PASS | Review abc not found. |
| GET /subjects?q=<prefix> | contains our subject | 200 | PASS | 1 match(es) |
| GET /subjects?q=<middle of name> (docs: prefix only) | does not match | 200 | PASS |  |
| GET /subjects?q=<UPPERCASE prefix> | informational (case sensitivity) | 200 | PASS | case-INsensitive |
| GET /subjects sort=most_reviewed | 200, correctly ordered | 200 | PASS | 3 items |
| GET /subjects sort=best | 200, correctly ordered | 200 | PASS | 3 items |
| GET /subjects sort=worst | 200, correctly ordered | 200 | PASS | 3 items |
| GET /subjects sort=name | 200, correctly ordered | 200 | PASS | 3 items |
| GET /subjects per_page=2 | <= 2 items | 200 | PASS |  |
| subject count/average | count 2, average 3 | 200 | PASS | [{"subject": "livecheck-21747031", "count": 2, "average": 3}] |
| GET /users/{id}/reviews | 200, only u1's reviews | 200 | PASS | 3 review(s) |
| GET /users/{missing}/reviews | 200 empty or 404 | 200 | PASS | empty list |
| PUT /reviews/{id} own | 200, updated | 200 | PASS |  |
| PUT /reviews/{id} someone else's | 403 (docs: 'Not your review') | 403 | PASS | Only the review's author or an admin can change this review. |
| PUT /reviews/{id} without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| PUT /reviews/{id} rating 9 | 422 | 422 | PASS | The rating must be between 1 and 5. |
| PUT /reviews/{id} tries to change subject | subject unchanged (docs: cannot be changed) | 200 | PASS | subject now livecheck-21747031 |
| PUT /reviews/{id} non-admin sets spam flag | ignored or 403 (docs: admin only) | 403 | PASS | spam=None |
| PUT /reviews/{missing} | 404 | 404 | PASS | Review 999999999 not found. |
| POST comment without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| POST comment (u2 on u1's review) | 200 + comment | 200 | PASS | keys: author,body,commented_at,id,meta,review_id,user_id |
| POST comment empty body | 422 | 422 | PASS | The body field is required. |
| POST comment whitespace-only body | 422 | 422 | PASS | The body field is required. |
| POST comment missing body | 422 | 422 | PASS | The body field is required. |
| POST comment on missing review | 404 (docs) | 404 | PASS | Review 999999999 not found. |
| GET comments of missing review | 404 (docs) | 404 | PASS | Review 999999999 not found. |
| GET comments (list) | 200, JSON array, oldest first (app reads a bare array) | 200 | PASS | array |
| comment_count in GET /reviews list reflects the comment | 1 | 200 | PASS | comment_count=1 |
| GET /reviews/{id} has comment_count (Swagger Review schema) and its comments | comment_count=1 and comments:[1] | 200 | FAIL | comment_count=None, comments=1 |
| PUT comment own | 200, updated | 200 | PASS |  |
| PUT comment someone else's (u1 edits u2's) | 403 (docs: 'Not your comment') | 403 | PASS | Only the comment's author or an admin can change this comment. |
| PUT comment without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| PUT comment empty body | 422 | 422 | PASS | The body field is required. |
| PUT comment via the wrong review id | 404 | 404 | PASS | Comment 4 not found. |
| PUT missing comment | 404 (docs) | 404 | PASS | Comment 999999999 not found. |
| DELETE comment someone else's (review author u1 deletes u2's) | 403 (docs: author or admin only) | 403 | PASS | Only the comment's author or an admin can delete this comment. |
| DELETE comment without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| DELETE comment own | 200 | 200 | PASS | Comment 4 deleted. |
| DELETE comment again | 404 (docs) | 404 | PASS | Comment 4 not found. |
| POST comment (to test cascade on review delete) | 200 | 200 | PASS |  |
| vote helpful without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| vote helpful (u2 on u1's review) | 200 counters helpful=1 | 200 | PASS | keys: helpful_counter,unhelpful_counter,your_vote |
| vote helpful again (repeat) | 200, still helpful=1 (one vote per user) | 200 | PASS | counters 1/0 |
| switch helpful -> unhelpful | 200, helpful=0 unhelpful=1 | 200 | PASS | counters 0/1 |
| vote on own review | 4xx (docs: cannot vote on your own review) | 403 | PASS | You cannot vote on your own review. |
| remove vote | 200, counters 0/0 | 200 | PASS |  |
| remove vote when none exists | 200 (idempotent) or 404 | 200 | PASS | idempotent |
| remove vote without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| vote on missing review | 404 | 404 | PASS | Review 999999999 not found. |
| remove vote on missing review | 404 | 404 | PASS | Review 999999999 not found. |
| DELETE /reviews/{id} someone else's | 403 (docs) | 403 | PASS | Only the review's author or an admin can delete this review. |
| DELETE /reviews/{id} without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| DELETE /reviews/{id} own (has comment+vote) | 200 | 200 | PASS | Review 8 deleted. |
| deleted review is gone | 404 | 404 | PASS | Review 8 not found. |
| comments of a deleted review are gone | 404 (docs: comments go with it) | 404 | PASS | Review 8 not found. |
| DELETE /reviews/{id} again | 404 | 404 | PASS | Review 8 not found. |
| logout without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| logout u1 | 200 | 200 | PASS | true |
| reuse token after logout (POST /reviews) | 401 (docs: 'the token no longer works') | 401 | PASS | Invalid auth token. Log in again. |
| reuse token after logout (GET /users/me) | 401 | 401 | PASS | Invalid auth token. Log in again. |
| logout twice with the same token | 401 | 401 | PASS | Invalid auth token. Log in again. |
| login again after logout | 200 | 200 | PASS |  |
| read-only call still works with a dead token (key only) | 200 | 200 | PASS |  |
| DELETE /users/{other} as non-admin | 403 (docs: 'Not allowed') | 403 | PASS | Not authorized to delete user (13) |
| GET /users as non-admin | 403 (docs) | 403 | PASS | List all users failed.  Only admins can list all users. |
| clean-up: delete user u1 | 200 | 200 | PASS | User deleted (12) |
| clean-up: deleted u1 can no longer log in | 404 | 404 | PASS | Login Failed (simpleapi-sample-apps+fd856d4006@agentmail.to) |
| clean-up: delete user u2 | 200 | 200 | PASS | User deleted (13) |
| clean-up: deleted u2 can no longer log in | 404 | 404 | PASS | Login Failed (simpleapi-sample-apps+8345dd0b97@agentmail.to) |
| clean-up: no reviews left on test subject | total 0 | 200 | PASS | total=0 |
| clean-up: test subjects gone from /subjects | none | 200 | PASS | left: [] |
| burst: unpaced GETs | informational: a 429 within N calls | 200 | PASS | no 429 in 80 requests (43s) |
| burst: unpaced GETs (8 threads) | informational: a 429 within N calls | 200 | PASS | no 429 in 40 requests from 8 thread(s) (9s) |

## App bugs (fixed)

1. **A revoked token was kept, so every write failed until the visitor found "Log out"**
   (commit "Drop a revoked token on 401…"). Because the API allows one session per
   user, logging in again elsewhere makes the app's token invalid. The app still held
   it, `ensureLoggedIn` still said "logged in", and every vote, comment or review
   showed "Invalid auth token. Log in again." without ever opening the login screen.
   Now a 401 on a request that carried a token drops the token and refreshes the UI,
   so the next write opens login. A 401 about the apikey keeps the token. Regression
   tests: three API-level cases and one widget test (verified to fail without the fix).
2. **"Try again" did not redraw in debug and test builds** (commit "Fix 'Try again'…").
   `_reload()` in `subjects_screen.dart` and `review_screen.dart` handed `setState` a
   callback that returned the new Future, which Flutter asserts on before marking the
   widget dirty. Release builds strip the assert, so the live site was not affected;
   found by the new 429 widget test.

Checked and fine: the app reads only `{"message": ...}` from errors, which is the
shape of every real error seen (401, 403, 404, 409 with an extra `review_id`, 422,
and the undocumented 400); it copes with the bare JSON `true` that logout returns,
`"meta": null`, extra fields, and a missing `comment_count` on a created review.
Static `apikey` in the query string works and the header-only form is rejected (401).

## API bugs or doc mismatches (not fixed, API source is private)

1. **`comment_count` is missing from `POST /api/reviews` and `GET /api/reviews/{id}`**,
   although the `Review` schema lists it. The single-review GET returns a `comments`
   array instead. `GET /api/reviews` (what the app reads) has it and it counts correctly.
2. **Duplicate register answers `400`**, which register does not document (`200`/`202`
   only); `409`/`422` would match the rest of the API.
3. **Single active session per user is undocumented** (see above); a second login
   silently logs the first client out.
4. **Rate limit is unclear.** Header says 20, `Remaining` is non-monotonic, and about 260
   requests (140 paced, 80 unpaced sequential, 40 concurrent) never produced the 429 seen earlier. Swagger
   documents `429` only for `/users/forgot`.
5. **Most error statuses are undocumented** in the Swagger (401 on every protected
   call, 403 on vote-own-review, 422 on bad login input, the 400 above). The real
   answers were consistent and sensible; only the docs lag.
6. Small things, probably intended: `sort=bogus` and `page=0` silently succeed; a
   malformed JSON body answers `422` ("email field required") rather than `400`; a
   bad-apikey 401 echoes whatever key text was sent; the duplicate-review 409 is
   case-insensitive on the subject (`X` vs `x` collide) while the `subjects` prefix
   filter is also case-insensitive (consistent, but undocumented); text is stored and
   returned as sent (`<script>` in a title came back unchanged), so non-Flutter clients
   must escape it (Flutter `Text` is safe).

## Leftovers and honest caveats

* **One test user could not be deleted:** user id 9, email
  `simpleapi-sample-apps+probebc5be193@agentmail.to`. My very first manual probe (before
  the harness existed) logged in a second time, which invalidated its only token, and I
  had not kept the random password. It has no reviews, comments or votes. A non-admin
  cannot delete other users and the reset-by-email route needs that mailbox, so the key
  owner (admin) can delete it. The harness itself keeps credentials in memory and
  always cleans up through a fresh login; the final run left nothing behind.
* The task's email template contained a full-width `＠` (U+FF20); I used an ASCII `@`.
* Python (stdlib only) was used for the harness; Flutter 3.47.8 (the CI version) was
  installed only to run `flutter analyze` and `flutter test` (41 tests pass, analyze clean).

## Not tested and why

* `POST /api/users/forgot`, `/reset`, `/register/confirm`: need a real inbox; forgot is capped at 20/day per key; the app does not use them.
* Registering the key owner's own email (the 202 admin path) and every admin-only
  behaviour (admin editing or deleting others' content, setting `spam`/`bad`, listing
  users successfully, filtering by `spam`/`bad`): no admin access. Only the non-admin
  refusals were checked.
* The 429 response itself (could not be provoked, see above); `per_page` clamping at 50
  (a 2-item subject cannot show it); the 512-byte `meta` limit; very large bodies.
* Races (two simultaneous reviews by one user), cross-key isolation ("users belong to
  your key"), and the custom `auth-url` mode where register/login answer 409.
* The deployed Pages site in a real browser (CORS, rendering): the API answers
  `Access-Control-Allow-Origin: *`, but I did not drive the UI. Widget tests use fake HTTP.
* Load or long-run behaviour, and anything outside the paths the sample uses.
