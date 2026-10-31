# Live check of the Reviews API

`live_check.py` exercises every call that `lib/reviews_api.dart` makes, plus
edge cases (bad key, bad input, other users' data, repeat votes, logout and
token reuse), against the real API at https://reviews.simpleapi.dev.
Results and findings are in [REPORT.md](REPORT.md).

## Run it

Python 3.9+ and nothing else (standard library only). From the repo root:

```bash
export SIMPLEAPI_KEY=<your demo key>
python3 tool/live_check/live_check.py
```

The key is read **only** from the `SIMPLEAPI_KEY` environment variable. It is
sent as the `apikey` query parameter and is never written to a file, printed or
committed; tokens and the random test passwords are generated at run time, kept
in memory and scrubbed from all output. Do not paste a key into this folder.

Options:

| Option | Meaning |
| --- | --- |
| `--out results.json` | write every check (expected, actual, note) as JSON |
| `--pace 1.0` | seconds between requests (default 1.0) |
| `--burst N` | after clean-up, send up to N unpaced GETs trying to provoke a 429 |
| `--burst-workers K` | send that burst from K threads at once |
| `--only-burst` | skip the functional checks, only run the burst |

A full run is about 157 checks and 175 requests, roughly 3 minutes at
the default pace. It also exercises `DELETE /api/users/me` (right, wrong and missing
password, `purge=true` with recounted votes) and checks that `X-RateLimit-Remaining` only
goes down inside one `X-RateLimit-Reset` window. It never calls `POST /api/admin/purge`. Exit output ends with a PASS/FAIL count and the 429 events.

## What it does to the API

It registers two throw-away users (`simpleapi-sample-apps+<random>@agentmail.to`;
register returns a token directly, no inbox is read), creates reviews,
comments and votes on a random `livecheck-<hex>` subject, and then deletes all
of it, including every user it registered (`DELETE /api/users/me` with the user's password). A final check confirms
no review or subject is left behind. If the run is interrupted, clean-up still
runs from a `finally` block; if the process is killed, leftovers are only
`livecheck-*` subjects and users with the email pattern above.

## Rate limit

Requests are paced (one per second by default) and a `429` is retried after
its `Retry-After` header (back-off of 5s, 10s, 20s... if there is none).

## Not covered

`/api/users/forgot`, `/reset` and `/register/confirm` need an inbox (and the
forgot call is capped at 20 per day per key), and registering the key owner's
own email makes the admin account. The app uses none of them.
