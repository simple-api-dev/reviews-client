# Live check report: Reviews API and this sample app

Re-run on 2026-10-31 against https://reviews.simpleapi.dev (the API after
`reviews-api-private` PR #1, which is deployed) with the shared demo key read from
`SIMPLEAPI_KEY` (never stored). Harness: [`live_check.py`](live_check.py), see the
[README](README.md). It replaces the first report, which was written against the
API before PR #1.

**This shows what was tried, not that the API or the app is bug free.** One run,
one key, one network path, no load. Behaviour is judged from real responses and the
PR #1 description.

Summary: **157 checks, 154 PASS, 3 FAIL** (175 HTTP requests in 176 s, about one per
second, zero 429s). The 3 FAILs are:

1. `register u1` expected `201`, live answers `200`: **Part 1 of the API PR, not deployed.**
2. `register a@b` expected `422`, live answers `200` and creates the user: **same PR, not deployed.**
3. `X-RateLimit-Remaining` still goes **up** inside one window: **a real problem, see "Rate limit".**

Clean-up worked: every user, review, comment and vote created by the run was deleted
(including the `a@b` user the live API wrongly accepted); no `livecheck-*` subject remained.
`POST /api/admin/purge` was **not** called.

## Earlier bugs: fixed live

| Earlier finding | Now (live) |
| --- | --- |
| `comment_count` missing from `POST /api/reviews` and `GET /api/reviews/{id}` | **Fixed.** Both have it; on the single review it is 1 next to the 1 comment. |
| Duplicate register answered `400` | **Fixed.** `409`, also for a different letter case. |
| Wrong password / unknown email answered `404 "Login Failed (<email>)"` | **Fixed.** `401 "Invalid email or password."`, the same text for both, no email echoed. |
| Malformed JSON answered `422` ("email field required") | **Fixed.** `400 "The request body is not valid JSON: Syntax error."` |
| A bad apikey's `401` echoed whatever key text was sent | **Fixed.** "Unauthorized.  Invalid apikey. Register for ..." |
| Single session per user was undocumented | Behaviour unchanged (a new login kills the old token, confirmed again); PR #1 documents it. |
| Most error statuses undocumented in Swagger | PR #1 documents them. **Not re-compared** against the live `/docs-api.json` in this run. |

`sort=bogus` and `page=0` still succeed silently (200, default); PR #1 documents that.

## Earlier bugs: still present live

* **Rate limit** (the earlier "20 / unreliable `Remaining`" finding), see below. Not fixed as seen from here.
* **Register answers `200` and accepts `a@b`.** Both are fixed in `reviews-api-private` PR #2 and will
  differ live until that is deployed. The harness expects `201` and `422`, so those two checks FAIL today and
  should pass after the deploy. The sample app accepts `200` and `201`.
* Test user id 9 from the first run (`...+probebc5be193@agentmail.to`) can still only be removed by the key owner;
  it cannot be checked or deleted without admin access.

## Delete flows (new live endpoint `DELETE /api/users/me`)

All PASS:

| Case | Result |
| --- | --- |
| No token | `401` |
| Missing password (no body) / empty password | `422 "The password field is required."` |
| Right password only in the URL (`?password=`) | `422` (the password is read from the body only) |
| Wrong password | `403 "Wrong password."`; account and token still work afterwards |
| Right password, no purge | `200 {"message":"Account deleted."}`; the token answers `401`; login answers `401`; a second delete answers `401` |
| No purge: what stays | The deleted user's helpful vote and comment stayed on the other user's review (`helpful_counter` 1, 1 comment, `comment_count` 1) |
| `purge=true` with a wrong password | `403`, nothing deleted (counters and comments unchanged) |
| `purge=true`, right password | `200` with `purged: {reviews:1, comments:2, votes:2}`: the user's review, their comment on another review, another user's comment on their review, their unhelpful vote on another review and another user's vote on their review |
| After the purge | The purged review answers `404`, its subject left `/subjects`, **`unhelpful_counter` on the other review was recounted from 1 to 0**, while the earlier (non-purge) vote and comment stayed (helpful 1, 1 comment) |

## Rate limit

PR #1 says the limit is 20 a minute per IP, enforced exactly, with `Remaining` only going down
within a minute and a new `X-RateLimit-Reset`.

* **Headers:** `X-RateLimit-Limit: 20` and `X-RateLimit-Reset` (a unix time on a minute boundary) are on every
  response, so the new limiter is deployed.
* **`Remaining` does not only go down.** In 4 one-minute windows (173 responses, grouped by `Reset`) it went
  **up 56 times inside a window**, for example `19, 18, 19, 19, 19, 18, 19 ...` within one minute. The same
  bounce as in the first report.
* **The limit was not enforced against this client.** About 60 requests a minute were sent for three minutes
  (the lowest `Remaining` seen was 8) and no 429 came. With one shared counter per IP the 21st request in a
  minute would have been refused.
* The likely cause is not the code but where it runs: several PHP workers or servers that do not share
  `storage/framework/throttle`, or this network's requests leaving from different IP addresses (each gets its
  own counter). **From outside I cannot tell which.** It needs a look at the server (is `THROTTLE_PATH` shared
  between all instances? what does the proxy send as the client IP?).
* Not provoked: the 429 body and `Retry-After`; the app tests keep using the message from PR #1.
* The harness checks this itself now: the last check, "X-RateLimit-Remaining only goes down within a window".

## Sample app (this repo)

Changes made for what is live (tests added for each):

* A failed login is `401 "Invalid email or password."`, shown on the login screen. `login` and `register` no
  longer send the Bearer token and a `401` from them is never treated as an expired session.
* Duplicate register `409`, malformed JSON `400`, invalid input `422`: shown with the API's own message.
* Register accepts `200` and `201` (and `202` without a token).
* `comment_count` is read from single-review responses.
* New **Delete my account** (Subjects bar, when logged in): password field and the checkbox
  "Also delete my reviews and comments" (`purge=true`). A wrong password (`403`) is shown in the dialog and
  keeps the login.
* `flutter analyze`: no issues. `flutter test`: 55 tests pass.

## All checks

Expected = what the API now promises (PR #1 and its Swagger), or the conventional answer where it is silent.
Actual = HTTP status (0 = no response).

| Check | Expected | Actual | Result | Note |
| --- | --- | --- | --- | --- |
| GET /subjects without apikey | 4xx (docs: apikey required; no code listed) | 401 | PASS | Unauthorized.  Please provide a valid apikey. Register for a free apikey at https://keys.simpleapi.dev using product URL https://reviews.simpleapi.dev |
| GET /subjects with a wrong apikey | 401 (docs silent; app expects 'Unauthorized...') | 401 | PASS | Unauthorized.  Invalid apikey. Register for a free apikey at https://keys.simpleapi.dev using product URL https://reviews.simpleapi.dev. |
| GET /subjects with a malformed apikey | 4xx | 401 | PASS | Unauthorized.  Invalid apikey. Register for a free apikey at https://keys.simpleapi.dev using product URL https://reviews.simpleapi.dev. |
| GET /subjects with the demo key | 200 {subjects:[...]} | 200 | PASS |  |
| apikey as a header only (docs: query param) | 401 | 401 | PASS | header must not work |
| register u1 (201 once reviews-api-private PR #2 is deployed) | 201 + token | 200 | FAIL | live answered 200 before the deploy |
| register u2 | 200 or 201 + token | 200 | PASS |  |
| register duplicate email | 409 | 409 | PASS | User registration failed, email already registered to this developer account. |
| register duplicate email, different case | 409 (same mailbox) | 409 | PASS | User registration failed, email already registered to this developer account. |
| register bad email | 422 (docs: format email) | 422 | PASS | The email must be a valid email address. |
| register email without a dotted domain (a@b) - PR #2, not deployed yet | 422 | 200 | FAIL | accepted: user created (fixed by reviews-api-private PR #2) |
| register short password (3 chars) | 422 (docs give no minimum) | 422 | PASS | The password must be at least 8 characters. |
| register missing name+password | 422 | 422 | PASS | The name field is required.  The password field is required. |
| login right password | 200 + token | 200 | PASS |  |
| session: register token still valid after a later login? | docs silent ('Returns a new bearer token') | 401 | PASS | OLD token rejected -> single active session |
| session: newest token works | 200 | 200 | PASS |  |
| session: 2nd login invalidates the previous login token? | docs silent | 401 | PASS | yes |
| login with upper-cased email | 200 (emails are case-insensitive) | 200 | PASS |  |
| login with mixed-case local part | 200 | 200 | PASS |  |
| login wrong password | 401 Invalid email or password. | 401 | PASS | Invalid email or password. |
| login unknown email | 401, same message as a wrong password | 401 | PASS | Invalid email or password. |
| login missing password | 422 | 422 | PASS | The password field is required. |
| login malformed JSON | 400 | 400 | PASS | The request body is not valid JSON: Syntax error. |
| GET /users/me without a token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| GET /users/me with a garbage token | 401 | 401 | PASS | Invalid auth token. Log in again. |
| POST /reviews without a token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| POST /reviews with a garbage token | 401 | 401 | PASS | Invalid auth token. Log in again. |
| POST /reviews valid (u1) | 200 + review | 200 | PASS |  |
| POST /reviews response has every field of the Swagger Review schema | id,subject,user_id,author,rating,title,body,tags,meta,helpful_counter,unhelpful_counter,spam,bad,comment_count,reviewed_at | 200 | PASS | missing:  / fields: {"id": "int", "subject": "str", "user_id": "int", "tags": "list", "rating": "int", "title": "str", "body": "str", "bad": "bool", " |
| POST /reviews duplicate subject (same user) | 409 (docs) | 409 | PASS | You already reviewed "livecheck-7367f949" (review 12). Use PUT /reviews/12 to change it. |
| POST /reviews same subject, different case | informational: 409 if subjects are case-insensitive, 200 if distinct | 409 | PASS | You already reviewed "LIVECHECK-7367F949" (review 12). Use PUT /reviews/12 to change it. |
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
| GET /reviews/{id} | 200 review (+ comments) | 200 | PASS | keys: author,bad,body,comment_count,comments,helpful_counter,id,meta,rating,reviewed_at,spam,subject,tags,title,unhelpful_counter,user_id |
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
| subject count/average | count 2, average 3 | 200 | PASS | [{"subject": "livecheck-7367f949", "count": 2, "average": 3}] |
| GET /users/{id}/reviews | 200, only u1's reviews | 200 | PASS | 3 review(s) |
| GET /users/{missing}/reviews | 200 empty or 404 | 200 | PASS | empty list |
| PUT /reviews/{id} own | 200, updated | 200 | PASS |  |
| PUT /reviews/{id} someone else's | 403 (docs: 'Not your review') | 403 | PASS | Only the review's author or an admin can change this review. |
| PUT /reviews/{id} without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| PUT /reviews/{id} rating 9 | 422 | 422 | PASS | The rating must be between 1 and 5. |
| PUT /reviews/{id} tries to change subject | subject unchanged (docs: cannot be changed) | 200 | PASS | subject now livecheck-7367f949 |
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
| GET /reviews/{id} has comment_count (Swagger Review schema) and its comments | comment_count=1 and comments:[1] | 200 | PASS | comment_count=1, comments=1 |
| PUT comment own | 200, updated | 200 | PASS |  |
| PUT comment someone else's (u1 edits u2's) | 403 (docs: 'Not your comment') | 403 | PASS | Only the comment's author or an admin can change this comment. |
| PUT comment without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| PUT comment empty body | 422 | 422 | PASS | The body field is required. |
| PUT comment via the wrong review id | 404 | 404 | PASS | Comment 6 not found. |
| PUT missing comment | 404 (docs) | 404 | PASS | Comment 999999999 not found. |
| DELETE comment someone else's (review author u1 deletes u2's) | 403 (docs: author or admin only) | 403 | PASS | Only the comment's author or an admin can delete this comment. |
| DELETE comment without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| DELETE comment own | 200 | 200 | PASS | Comment 6 deleted. |
| DELETE comment again | 404 (docs) | 404 | PASS | Comment 6 not found. |
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
| DELETE /reviews/{id} own (has comment+vote) | 200 | 200 | PASS | Review 12 deleted. |
| deleted review is gone | 404 | 404 | PASS | Review 12 not found. |
| comments of a deleted review are gone | 404 (docs: comments go with it) | 404 | PASS | Review 12 not found. |
| DELETE /reviews/{id} again | 404 | 404 | PASS | Review 12 not found. |
| logout without token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| logout u1 | 200 | 200 | PASS | true |
| reuse token after logout (POST /reviews) | 401 (docs: 'the token no longer works') | 401 | PASS | Invalid auth token. Log in again. |
| reuse token after logout (GET /users/me) | 401 | 401 | PASS | Invalid auth token. Log in again. |
| logout twice with the same token | 401 | 401 | PASS | Invalid auth token. Log in again. |
| login again after logout | 200 | 200 | PASS |  |
| read-only call still works with a dead token (key only) | 200 | 200 | PASS |  |
| DELETE /users/{other} as non-admin | 403 (docs: 'Not allowed') | 403 | PASS | Not authorized to delete user (18) |
| GET /users as non-admin | 403 (docs) | 403 | PASS | List all users failed.  Only admins can list all users. |
| delete flows: u3 votes helpful on u1's review | helpful=1 | 200 | PASS |  |
| DELETE /users/me without a token | 401 | 401 | PASS | Unauthorized. Log in and send the header "Authorization: Bearer <token>". |
| DELETE /users/me with a MISSING password (no body) | 422 | 422 | PASS | The password field is required. |
| DELETE /users/me with an EMPTY password | 422 | 422 | PASS | The password field is required. |
| DELETE /users/me with the right password only in the URL | 422 (body only) | 422 | PASS | The password field is required. |
| DELETE /users/me with a WRONG password | 403 | 403 | PASS | Wrong password. |
| account and token survive the refused deletes | 200 | 200 | PASS |  |
| DELETE /users/me with the RIGHT password (no purge) | 200 {message} | 200 | PASS | Account deleted. |
| deleted user's token answers 401 | 401 | 401 | PASS | Invalid auth token. Log in again. |
| deleted user can no longer log in | 401 | 401 | PASS | Invalid email or password. |
| DELETE /users/me twice | 401 | 401 | PASS | Invalid auth token. Log in again. |
| no purge: u3's vote and comment stay on u1's review | helpful=1, 1 comment, comment_count=1 | 200 | PASS | (1, 0, 1, 1) |
| delete flows: u4 writes a review | 200 | 200 | PASS |  |
| delete flows: u4 votes unhelpful on u1's review | unhelpful=1 | 200 | PASS |  |
| before purge: u1's review has helpful=1 (u3), unhelpful=1 (u4), 2 comments | (1, 1, 2, 2) | 200 | PASS | (1, 1, 2, 2) |
| purge=true with a WRONG password deletes nothing | 403 | 403 | PASS | Wrong password. |
| ...and nothing changed | (1, 1, 2, 2) | 200 | PASS | (1, 1, 2, 2) |
| DELETE /users/me?purge=true with the RIGHT password | 200 + purged{reviews:1,comments:2,votes:2} | 200 | PASS | {"message": "Account deleted.", "purged": {"reviews": 1, "comments": 2, "votes": 2}} |
| purge: u4's review is gone | 404 | 404 | PASS | Review 17 not found. |
| purge: unhelpful recounted to 0, u3's vote and comment stay | (1, 0, 1, 1) | 200 | PASS | (1, 0, 1, 1) |
| purge: u4's subject is gone from /subjects | none | 200 | PASS |  |
| delete flows: clean-up of u1's review (takes u3's comment and vote with it) | 200 | 200 | PASS | Review 16 deleted. |
| clean-up: delete user u1 | 200 | 200 | PASS | Account deleted. |
| clean-up: deleted u1 can no longer log in | 401 | 401 | PASS | Invalid email or password. |
| clean-up: delete user u2 | 200 | 200 | PASS | Account deleted. |
| clean-up: deleted u2 can no longer log in | 401 | 401 | PASS | Invalid email or password. |
| clean-up: delete user ab | 200 | 200 | PASS | Account deleted. |
| clean-up: deleted ab can no longer log in | 401 | 401 | PASS | Invalid email or password. |
| clean-up: no reviews left on test subject | total 0 | 200 | PASS | total=0 |
| clean-up: test subjects gone from /subjects | none | 200 | PASS | left: [] |
| X-RateLimit-Remaining only goes down within a window (same X-RateLimit-Reset) | no increase inside a window | 200 | FAIL | 173 responses, 4 windows, increases: [{'window_reset': '1793486580', 'call': 4, 'from': 18, 'to': 19}, {'window_reset': '1793486580', 'call': 12, 'fro |

## Not tested and why

* `POST /api/admin/purge`: not called on this key, by decision.
* `POST /api/users/forgot`, `/reset`, `/register/confirm`: need a real inbox; forgot is capped at 20 a day per key.
* Registering the key owner's own email (the `202` admin path) and every admin-only behaviour.
* The `429` response itself (could not be provoked, see above); `per_page` clamping at 50; the 512-byte `meta` limit.
* Races, cross-key isolation, and keys that use an external auth service (`409` on `DELETE /users/me`).
* The deployed Pages site in a real browser; widget tests use a fake HTTP client.
* The live `/docs-api.json` was not re-compared with the code.
