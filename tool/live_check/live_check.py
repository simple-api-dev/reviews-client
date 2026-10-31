#!/usr/bin/env python3
"""Live check of the Reviews API paths used by this sample app.

Run (from the repo root):

    export SIMPLEAPI_KEY=<your demo key>      # never commit it
    python3 tool/live_check/live_check.py [--out results.json] [--pace 1.0]

Needs only Python 3.9+ (standard library). The key is read from the
environment, sent as the `apikey` QUERY parameter and never printed or written
anywhere: URLs, bodies and output are scrubbed of the key and of every token.
Test passwords are generated at run time and kept in memory only.

It registers two throw-away users, exercises every call in
lib/reviews_api.dart plus edge cases, then deletes everything it created
(reviews, comments, votes and the users). Requests are paced (default one per
second) and a 429 is retried after the Retry-After header (or a back-off).
"""
from __future__ import annotations

import argparse
import email.utils
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.request

HOST = "https://reviews.simpleapi.dev"
RESULTS: list[dict] = []
KEY = os.environ.get("SIMPLEAPI_KEY", "")
SECRETS: set[str] = set()  # tokens / passwords to scrub from anything printed


def scrub(text: str) -> str:
    for s in sorted(SECRETS | ({KEY} if KEY else set()), key=len, reverse=True):
        if s:
            text = text.replace(s, "<redacted>")
    return re.sub(r'("token"\s*:\s*")[^"]+', r"\1<redacted>", text)


class Api:
    def __init__(self, pace: float):
        self.pace = pace
        self.last = 0.0
        self.calls = 0  # real HTTP requests, retries included
        self.rate_events: list[dict] = []
        self.remaining_series: list[tuple[int, float, str, str | None]] = []
        self.limit_header: str | None = None
        self.t0 = time.time()

    def call(self, method, path, *, query=None, body=None, token=None, apikey="default", raw_body=None, retry=True):
        """Returns (status, parsed_json_or_text, headers). Retries 429s."""
        q = dict(query or {})
        if apikey == "default":
            q["apikey"] = KEY
        elif apikey is not None:
            q["apikey"] = apikey
        qs = "&".join(f"{urllib.request.quote(str(k))}={urllib.request.quote(str(v), safe='')}" for k, v in q.items())
        url = f"{HOST}{path}" + (f"?{qs}" if qs else "")
        headers = {"Accept": "application/json"}
        data = None
        if raw_body is not None:
            data, headers["Content-Type"] = raw_body.encode(), "application/json"
        elif body is not None:
            data, headers["Content-Type"] = json.dumps(body).encode(), "application/json"
        if token:
            headers["Authorization"] = f"Bearer {token}"
        for attempt in range(6):
            wait = self.last + self.pace - time.time()
            if wait > 0:
                time.sleep(wait)
            self.last = time.time()
            self.calls += 1
            req = urllib.request.Request(url, data=data, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    status, text, hdrs = r.status, r.read().decode("utf-8", "replace"), r.headers
            except urllib.error.HTTPError as e:
                status, text, hdrs = e.code, e.read().decode("utf-8", "replace"), e.headers
            except Exception as e:  # network trouble
                return 0, f"network error: {type(e).__name__}", {}
            rem = hdrs.get("X-RateLimit-Remaining")
            if rem is not None:
                self.limit_header = hdrs.get("X-RateLimit-Limit")
                self.remaining_series.append((self.calls, round(time.time() - self.t0, 1), rem, hdrs.get("X-RateLimit-Reset")))
            if status == 429:
                ra = hdrs.get("Retry-After")
                delay = None
                if ra:
                    if ra.strip().isdigit():
                        delay = int(ra)
                    else:
                        try:
                            delay = max(1, int(email.utils.parsedate_to_datetime(ra).timestamp() - time.time()))
                        except Exception:
                            pass
                if delay is None:
                    delay = min(5 * 2**attempt, 60)
                delay = min(delay, 120)
                self.rate_events.append({
                    "after_call": self.calls, "seconds_since_start": round(time.time() - self.t0, 1),
                    "retry_after_header": ra, "waited": delay, "body": scrub(text)[:200],
                    "rate_headers": {k: v for k, v in hdrs.items() if re.search("rate|limit|retry", k, re.I)},
                })
                print(f"   429 after call #{self.calls} (Retry-After={ra!r}); waiting {delay}s", flush=True)
                if not retry:
                    return 429, (json.loads(text) if text.strip()[:1] == "{" else text), hdrs
                time.sleep(delay)
                continue
            try:
                parsed = json.loads(text) if text.strip()[:1] in "{[" and text.strip() else text
            except ValueError:
                parsed = text
            return status, parsed, hdrs
        return 429, "still throttled after 6 attempts", {}


def check(name, expected, status, ok, note="", body=None):
    RESULTS.append({
        "check": name, "expected": expected, "actual": status,
        "result": "PASS" if ok else "FAIL", "note": note,
        "body": scrub(json.dumps(body))[:300] if body is not None else "",
    })
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: expected {expected}, got {status} {note}", flush=True)


def msg(body):
    return body.get("message") if isinstance(body, dict) else body


class User:
    def __init__(self, label):
        self.label = label
        self.email = f"simpleapi-sample-apps+{secrets.token_hex(5)}@agentmail.to"
        self.password = secrets.token_urlsafe(14)
        SECRETS.add(self.password)
        self.token = None
        self.id = None

    def set_token(self, t):
        self.token = t
        SECRETS.add(t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", help="write the JSON results here")
    ap.add_argument("--pace", type=float, default=1.0, help="seconds between requests (default 1.0)")
    ap.add_argument("--burst", type=int, default=0, metavar="N", help="after clean-up, send up to N unpaced GETs to provoke and record a 429")
    ap.add_argument("--burst-workers", type=int, default=1, help="send the burst from this many threads at once (default 1 = sequential)")
    ap.add_argument("--only-burst", action="store_true", help="skip the functional checks, run only --burst")
    args = ap.parse_args()
    if not KEY:
        sys.exit("Set SIMPLEAPI_KEY in your environment first (it is never stored).")
    SECRETS.add(KEY)
    api = Api(args.pace)
    u1, u2 = User("u1"), User("u2")
    users = [u1, u2]
    reviews: dict[int, User] = {}  # id -> owner, for clean-up
    subject = f"livecheck-{secrets.token_hex(4)}"
    subject_b = f"livecheck-b-{secrets.token_hex(4)}"
    try:
        if not args.only_burst:
            run(api, u1, u2, reviews, subject, subject_b)
    except Exception as e:  # keep going to clean-up
        check("harness crashed", "no exception", 0, False, f"{type(e).__name__}: {scrub(str(e))}")
    finally:
        if not args.only_burst:
            cleanup(api, users, reviews, subject, subject_b)
        if args.burst:
            burst(api, args.burst, args.burst_workers)
        summary(api, args.out)


def login(api, u, email=None, password=None):
    s, b, _ = api.call("POST", "/api/users/login", body={"email": email or u.email, "password": password or u.password})
    if s == 200 and isinstance(b, dict) and b.get("token"):
        u.set_token(b["token"])
        u.id = b.get("id", u.id)
    return s, b


def run(api, u1, u2, reviews, subject, subject_b):
    # ------------------------------------------------------------------ key
    s, b, _ = api.call("GET", "/api/subjects", apikey=None)
    check("GET /subjects without apikey", "4xx (docs: apikey required; no code listed)", s, s in (400, 401, 403), msg(b), b)
    s, b, _ = api.call("GET", "/api/subjects", apikey="00000000-0000-0000-0000-000000000000")
    check("GET /subjects with a wrong apikey", "401 (docs silent; app expects 'Unauthorized...')", s, s == 401, msg(b), b)
    s, b, _ = api.call("GET", "/api/subjects", apikey="not-a-uuid")
    check("GET /subjects with a malformed apikey", "4xx", s, 400 <= s < 500, msg(b), b)
    s, b, _ = api.call("GET", "/api/subjects")
    check("GET /subjects with the demo key", "200 {subjects:[...]}", s, s == 200 and isinstance(b, dict) and isinstance(b.get("subjects"), list), "", None)
    # apikey must be a QUERY parameter: a header must not be enough
    req = urllib.request.Request(f"{HOST}/api/subjects", headers={"apikey": KEY, "X-API-Key": KEY, "Accept": "application/json"})
    api.last = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            hs = r.status
    except urllib.error.HTTPError as e:
        hs = e.code
    api.calls += 1
    check("apikey as a header only (docs: query param)", "401", hs, hs == 401, "header must not work")

    # ------------------------------------------------------------- register
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "Live One", "email": u1.email, "password": u1.password})
    ok = s in (200, 201) and isinstance(b, dict) and bool(b.get("token"))
    check("register u1 (201 once reviews-api-private PR #2 is deployed)", "201 + token", s, s == 201 and ok, "live answered 200 before the deploy" if s == 200 else "", b)
    if ok:
        u1.set_token(b["token"]); u1.id = b.get("id")
    reg_token_u1 = u1.token
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "Live Two", "email": u2.email, "password": u2.password})
    ok = s in (200, 201) and isinstance(b, dict) and bool(b.get("token"))
    check("register u2", "200 or 201 + token", s, ok, "", b)
    if ok:
        u2.set_token(b["token"]); u2.id = b.get("id")
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "Dup", "email": u1.email, "password": secrets.token_urlsafe(10)})
    check("register duplicate email", "409", s, s == 409, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "Dup", "email": u1.email.upper(), "password": secrets.token_urlsafe(10)})
    check("register duplicate email, different case", "409 (same mailbox)", s, s == 409, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "Bad", "email": "not-an-email", "password": secrets.token_urlsafe(10)})
    check("register bad email", "422 (docs: format email)", s, s == 422, msg(b), b)
    ab = User("ab")
    ab.email = f"ab{secrets.token_hex(4)}@b"
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "NoDot", "email": ab.email, "password": ab.password})
    if s in (200, 201) and isinstance(b, dict) and b.get("token"):
        ab.set_token(b["token"]); ab.id = b.get("id"); api_extra.append(ab)  # created by mistake: clean-up deletes it
    check("register email without a dotted domain (a@b) - PR #2, not deployed yet", "422", s, s == 422, msg(b) if s == 422 else "accepted: user created (fixed by reviews-api-private PR #2)", b)
    s, b, _ = api.call("POST", "/api/users/register", body={"name": "Short", "email": f"simpleapi-sample-apps+{secrets.token_hex(5)}@agentmail.to", "password": "abc"})
    short_created = s == 200 and isinstance(b, dict) and b.get("token")
    check("register short password (3 chars)", "422 (docs give no minimum)", s, s == 422, msg(b) if not short_created else "ACCEPTED - user must be cleaned up", b)
    if short_created:
        extra = User("short"); extra.email = b["email"]; extra.password = "abc"; extra.id = b.get("id"); extra.set_token(b["token"])
        api_extra.append(extra)
    s, b, _ = api.call("POST", "/api/users/register", body={"email": "x@agentmail.to"})
    check("register missing name+password", "422", s, s == 422, msg(b), b)

    # ---------------------------------------------------- login & sessions
    s, b = login(api, u1)  # token B; token from register (A) is now?
    check("login right password", "200 + token", s, s == 200 and bool(u1.token), "", b)
    tokB = u1.token
    s, b, _ = api.call("GET", "/api/users/me", token=reg_token_u1)
    check("session: register token still valid after a later login?", "docs silent ('Returns a new bearer token')", s, True,
          "OLD token rejected -> single active session" if s == 401 else ("old token still works -> multiple sessions" if s == 200 else ""), b)
    single_session = s == 401
    s, b, _ = api.call("GET", "/api/users/me", token=tokB)
    check("session: newest token works", "200", s, s == 200 and isinstance(b, dict) and b.get("email") == u1.email, "", None)
    s, b = login(api, u1)  # token C
    tokC = u1.token
    s2, _, _ = api.call("GET", "/api/users/me", token=tokB)
    check("session: 2nd login invalidates the previous login token?", "docs silent", s2, True, "yes" if s2 == 401 else "no", None)
    s, b = login(api, u1, email=u1.email.upper())
    check("login with upper-cased email", "200 (emails are case-insensitive)", s, s == 200, msg(b), b)
    s, b = login(api, u1, email=u1.email.replace("simpleapi-sample-apps", "Simpleapi-Sample-Apps"))
    check("login with mixed-case local part", "200", s, s == 200, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/login", body={"email": u1.email, "password": secrets.token_urlsafe(12)})
    check("login wrong password", "401 Invalid email or password.", s, s == 401 and msg(b) == "Invalid email or password.", msg(b), b)
    wrong_pw_msg = msg(b)
    s, b, _ = api.call("POST", "/api/users/login", body={"email": f"nobody+{secrets.token_hex(5)}@agentmail.to", "password": "whatever-long-enough"})
    check("login unknown email", "401, same message as a wrong password", s, s == 401 and msg(b) == wrong_pw_msg, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/login", body={"email": u1.email})
    check("login missing password", "422", s, s == 422, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/login", raw_body="{not json")
    check("login malformed JSON", "400", s, s == 400, msg(b), b)
    s, b, _ = api.call("GET", "/api/users/me")
    check("GET /users/me without a token", "401", s, s == 401, msg(b), b)
    s, b, _ = api.call("GET", "/api/users/me", token="definitely-not-a-token")
    check("GET /users/me with a garbage token", "401", s, s == 401, msg(b), b)
    login(api, u2)  # make sure we hold u2's newest token (single session)
    s, b = login(api, u1)  # newest token for u1 for the rest of the run
    me1 = api.call("GET", "/api/users/me", token=u1.token)[1]
    u1.id = me1.get("id") if isinstance(me1, dict) else u1.id

    # ---------------------------------------------------------- post review
    s, b, _ = api.call("POST", "/api/reviews", body={"subject": subject, "rating": 4})
    check("POST /reviews without a token", "401", s, s == 401, msg(b), b)
    s, b, _ = api.call("POST", "/api/reviews", token="garbage", body={"subject": subject, "rating": 4})
    check("POST /reviews with a garbage token", "401", s, s == 401, msg(b), b)
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": subject, "rating": 4, "title": "Live check", "body": "Written by tool/live_check", "tags": ["livecheck"]})
    ok = s == 200 and isinstance(b, dict) and b.get("id")
    check("POST /reviews valid (u1)", "200 + review", s, ok, "", b)
    r1 = b.get("id") if ok else None
    if r1:
        reviews[r1] = u1
        shape = {k: type(v).__name__ for k, v in b.items()}
        check("POST /reviews response has every field of the Swagger Review schema", "id,subject,user_id,author,rating,title,body,tags,meta,helpful_counter,unhelpful_counter,spam,bad,comment_count,reviewed_at",
              s, all(k in b for k in ("id", "subject", "user_id", "author", "rating", "title", "body", "tags", "meta", "helpful_counter", "unhelpful_counter", "spam", "bad", "comment_count", "reviewed_at")),
              "missing: " + ",".join(k for k in ("comment_count",) if k not in b) + " | fields: " + json.dumps(shape), None)
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": subject, "rating": 2})
    check("POST /reviews duplicate subject (same user)", "409 (docs)", s, s == 409, msg(b), b)
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": subject.upper(), "rating": 2})
    dup_case_created = s == 200 and isinstance(b, dict) and b.get("id")
    if dup_case_created:
        reviews[b["id"]] = u1
    check("POST /reviews same subject, different case", "informational: 409 if subjects are case-insensitive, 200 if distinct", s, s in (200, 409), "treated as a DISTINCT subject" if dup_case_created else msg(b), b)
    for label, payload in [
        ("rating 0", {"subject": subject_b, "rating": 0}),
        ("rating 6", {"subject": subject_b, "rating": 6}),
        ("rating -1", {"subject": subject_b, "rating": -1}),
        ("rating 3.5", {"subject": subject_b, "rating": 3.5}),
        ('rating "abc"', {"subject": subject_b, "rating": "abc"}),
        ("missing rating", {"subject": subject_b}),
        ("missing subject", {"rating": 3}),
        ("empty subject", {"subject": "", "rating": 3}),
    ]:
        s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body=payload)
        if s == 200 and isinstance(b, dict) and b.get("id"):
            reviews[b["id"]] = u1
        check(f"POST /reviews {label}", "422 (docs: 422 validation error)", s, s == 422, msg(b) if isinstance(b, dict) else b, b)
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": subject_b, "rating": "5"})
    if s == 200 and isinstance(b, dict) and b.get("id"):
        reviews[b["id"]] = u1
    check('POST /reviews rating "5" (numeric string)', "informational (lenient coercion is fine)", s, s in (200, 422), msg(b), b)
    s, b, _ = api.call("POST", "/api/reviews", token=u2.token, body={"subject": subject, "rating": 2, "title": "Second", "body": "From user two"})
    ok = s == 200 and isinstance(b, dict) and b.get("id")
    check("POST /reviews same subject, different user", "200", s, ok, "", b)
    r2 = b.get("id") if ok else None
    if r2:
        reviews[r2] = u2
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": "x" * 300, "rating": 3})
    if s == 200 and isinstance(b, dict) and b.get("id"):
        reviews[b["id"]] = u1
    check("POST /reviews 300-char subject", "422 or 200 (docs give no limit)", s, s in (200, 422), msg(b) if isinstance(b, dict) else b, b)
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": f"{subject_b}-<b>&é", "rating": 5, "title": "<script>alert(1)</script>", "body": "ünï ✓"})
    uni_id = b.get("id") if s == 200 and isinstance(b, dict) else None
    if uni_id:
        reviews[uni_id] = u1
    check("POST /reviews unicode + HTML in text", "200 and echoed unchanged", s, bool(uni_id) and b.get("body") == "ünï ✓", "title echoed as: " + str(b.get("title")) if uni_id else msg(b), b)

    # ------------------------------------------------------------- reading
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject})
    ok = s == 200 and isinstance(b, dict)
    check("GET /reviews?subject= (list + summary)", "200 {summary,total,reviews}", s, ok and {"summary", "reviews"} <= set(b), "keys: " + ",".join(sorted(b)) if ok else "", None)
    if ok and b.get("reviews"):
        keys = set(b["reviews"][0])
        need = {"id", "subject", "author", "rating", "title", "body", "helpful_counter", "unhelpful_counter", "comment_count", "reviewed_at"}
        check("GET /reviews list items have every field the app reads", "+".join(sorted(need)), s, need <= keys, "missing: " + ",".join(sorted(need - keys)), None)
    if ok and isinstance(b.get("summary"), dict):
        sm = b["summary"]
        check("summary count/average/distribution correct (2 reviews: 4 and 2)", "count 2, average 3.0, distribution 2->1, 4->1", s,
              sm.get("count") == 2 and sm.get("average") == 3 and (sm.get("distribution") or {}).get("4") == 1 and (sm.get("distribution") or {}).get("2") == 1, json.dumps(sm), None)
        check("total field matches", "total 2", s, b.get("total") == 2, f"total={b.get('total')}", None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "rating": 4})
    check("GET /reviews rating=4 filter", "only the 4-star review", s, s == 200 and [x.get("rating") for x in b.get("reviews", [])] == [4], "", None)
    for sort in ("newest", "oldest", "rating_desc", "rating_asc", "helpful"):
        s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "sort": sort})
        ratings = [x.get("rating") for x in b.get("reviews", [])] if s == 200 else None
        want = {"rating_desc": [4, 2], "rating_asc": [2, 4]}.get(sort)
        check(f"GET /reviews sort={sort}", "200" + (f", order {want}" if want else ""), s, s == 200 and (want is None or ratings == want), f"ratings={ratings}", None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "sort": "bogus"})
    check("GET /reviews sort=bogus", "200 (default) or 422", s, s in (200, 422), msg(b) if s != 200 else "silently defaults", None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "per_page": 1, "page": 2})
    check("GET /reviews per_page=1&page=2", "1 review, total still 2", s, s == 200 and len(b.get("reviews", [])) == 1 and b.get("total") == 2, f"total={b.get('total')}", None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "per_page": 500})
    check("GET /reviews per_page=500 (docs: max 50)", "200 clamped, or 422", s, s in (200, 422), msg(b) if s != 200 else f"{len(b.get('reviews', []))} returned", None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "page": 0})
    check("GET /reviews page=0", "200 or 422", s, s in (200, 422), msg(b) if s != 200 else "", None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": f"nope-{secrets.token_hex(4)}"})
    check("GET /reviews unknown subject", "200, empty list", s, s == 200 and b.get("reviews") == [], "summary=" + json.dumps(b.get("summary")), None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "tags": "livecheck"})
    check("GET /reviews tags=livecheck", "the tagged review only", s, s == 200 and b.get("total") == 1, f"total={b.get('total')}", None)
    if r1:
        s, b, _ = api.call("GET", f"/api/reviews/{r1}")
        check("GET /reviews/{id}", "200 review (+ comments)", s, s == 200 and b.get("id") == r1, "keys: " + ",".join(sorted(b)) if isinstance(b, dict) else "", None)
    s, b, _ = api.call("GET", "/api/reviews/999999999")
    check("GET /reviews/{missing}", "404", s, s == 404, msg(b), b)
    s, b, _ = api.call("GET", "/api/reviews/abc")
    check("GET /reviews/abc", "404 or 422", s, s in (404, 422), msg(b), b)

    s, b, _ = api.call("GET", "/api/subjects", query={"q": subject[:-3]})
    got = [x.get("subject") for x in b.get("subjects", [])] if s == 200 else []
    check("GET /subjects?q=<prefix>", "contains our subject", s, subject in got, f"{len(got)} match(es)", None)
    s, b, _ = api.call("GET", "/api/subjects", query={"q": subject[2:-3]})
    check("GET /subjects?q=<middle of name> (docs: prefix only)", "does not match", s, s == 200 and subject not in [x.get("subject") for x in b.get("subjects", [])], "", None)
    s, b, _ = api.call("GET", "/api/subjects", query={"q": subject.upper()[:-3]})
    check("GET /subjects?q=<UPPERCASE prefix>", "informational (case sensitivity)", s, s == 200, "case-INsensitive" if subject in [x.get("subject") for x in b.get("subjects", [])] else "case-SENSITIVE", None)
    for sort in ("most_reviewed", "best", "worst", "name"):
        s, b, _ = api.call("GET", "/api/subjects", query={"sort": sort, "per_page": 5})
        items = b.get("subjects", []) if s == 200 else []
        okord = True
        if sort == "best":
            okord = [x["average"] for x in items] == sorted((x["average"] for x in items), reverse=True)
        if sort == "worst":
            okord = [x["average"] for x in items] == sorted(x["average"] for x in items)
        if sort == "name":
            okord = [x["subject"] for x in items] == sorted(x["subject"] for x in items)
        if sort == "most_reviewed":
            okord = [x["count"] for x in items] == sorted((x["count"] for x in items), reverse=True)
        check(f"GET /subjects sort={sort}", "200, correctly ordered", s, s == 200 and okord, f"{len(items)} items", None)
    s, b, _ = api.call("GET", "/api/subjects", query={"per_page": 2, "page": 1})
    check("GET /subjects per_page=2", "<= 2 items", s, s == 200 and len(b.get("subjects", [])) <= 2, "", None)
    s, b, _ = api.call("GET", "/api/subjects", query={"q": subject[:-3]})
    mine = [x for x in b.get("subjects", []) if x.get("subject") == subject]
    check("subject count/average", "count 2, average 3", s, bool(mine) and mine[0].get("count") == 2 and mine[0].get("average") == 3, json.dumps(mine[:1]), None)

    if u1.id is not None:
        s, b, _ = api.call("GET", f"/api/users/{u1.id}/reviews")
        n = len(b.get("reviews", [])) if isinstance(b, dict) else -1
        check("GET /users/{id}/reviews", "200, only u1's reviews", s, s == 200 and n >= 1 and all(x.get("user_id") == u1.id for x in b["reviews"]), f"{n} review(s)", None)
        s, b, _ = api.call("GET", "/api/users/999999999/reviews")
        check("GET /users/{missing}/reviews", "200 empty or 404", s, s in (200, 404), msg(b) if s != 200 else "empty list", None)

    # ------------------------------------------------------------- editing
    if r1:
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", token=u1.token, body={"rating": 5, "title": "Edited"})
        check("PUT /reviews/{id} own", "200, updated", s, s == 200 and b.get("rating") == 5 and b.get("title") == "Edited", "", b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", token=u2.token, body={"rating": 1})
        check("PUT /reviews/{id} someone else's", "403 (docs: 'Not your review')", s, s == 403, msg(b), b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", body={"rating": 1})
        check("PUT /reviews/{id} without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", token=u1.token, body={"rating": 9})
        check("PUT /reviews/{id} rating 9", "422", s, s == 422, msg(b), b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", token=u1.token, body={"subject": "moved-" + subject, "title": "Edited"})
        check("PUT /reviews/{id} tries to change subject", "subject unchanged (docs: cannot be changed)", s, s in (200, 422) and (s != 200 or b.get("subject") == subject), f"subject now {b.get('subject') if isinstance(b, dict) else '?'}", b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", token=u1.token, body={"spam": True})
        check("PUT /reviews/{id} non-admin sets spam flag", "ignored or 403 (docs: admin only)", s, s in (200, 403, 422) and (s != 200 or not b.get("spam")), f"spam={b.get('spam') if isinstance(b, dict) else '?'}", b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}", token=u1.token, body={"rating": 5, "title": "Edited"})  # restore
    s, b, _ = api.call("PUT", "/api/reviews/999999999", token=u1.token, body={"rating": 3})
    check("PUT /reviews/{missing}", "404", s, s == 404, msg(b), b)

    # ------------------------------------------------------------ comments
    cid = None
    if r1:
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/comments", body={"body": "nope"})
        check("POST comment without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/comments", token=u2.token, body={"body": "Comment from u2"})
        ok = s == 200 and isinstance(b, dict) and b.get("id")
        check("POST comment (u2 on u1's review)", "200 + comment", s, ok, "keys: " + ",".join(sorted(b)) if isinstance(b, dict) else "", b)
        cid = b.get("id") if ok else None
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/comments", token=u2.token, body={"body": ""})
        check("POST comment empty body", "422", s, s == 422, msg(b), b)
        empty_cid = b.get("id") if isinstance(b, dict) else None
        if s == 200 and empty_cid:
            api.call("DELETE", f"/api/reviews/{r1}/comments/{empty_cid}", token=u2.token)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/comments", token=u2.token, body={"body": "   "})
        if s == 200 and isinstance(b, dict) and b.get("id"):
            api.call("DELETE", f"/api/reviews/{r1}/comments/{b['id']}", token=u2.token)
        check("POST comment whitespace-only body", "422", s, s == 422, msg(b), b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/comments", token=u2.token, body={})
        check("POST comment missing body", "422", s, s == 422, msg(b), b)
    s, b, _ = api.call("POST", "/api/reviews/999999999/comments", token=u2.token, body={"body": "x"})
    check("POST comment on missing review", "404 (docs)", s, s == 404, msg(b), b)
    s, b, _ = api.call("GET", "/api/reviews/999999999/comments")
    check("GET comments of missing review", "404 (docs)", s, s == 404, msg(b), b)
    if r1 and cid:
        s, b, _ = api.call("GET", f"/api/reviews/{r1}/comments")
        isl = isinstance(b, list)
        check("GET comments (list)", "200, JSON array, oldest first (app reads a bare array)", s, s == 200 and isl and any(c.get("id") == cid for c in b), "array" if isl else "OBJECT: " + ",".join(sorted(b)) if isinstance(b, dict) else "", None)
        s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject, "sort": "oldest"})
        mine = [x for x in b.get("reviews", []) if x.get("id") == r1] if s == 200 else []
        check("comment_count in GET /reviews list reflects the comment", "1", s, bool(mine) and mine[0].get("comment_count") == 1, f"comment_count={mine[0].get('comment_count') if mine else None}", None)
        s, b, _ = api.call("GET", f"/api/reviews/{r1}")
        check("GET /reviews/{id} has comment_count (Swagger Review schema) and its comments", "comment_count=1 and comments:[1]", s,
              s == 200 and b.get("comment_count") == 1, f"comment_count={b.get('comment_count')}, comments={len(b.get('comments') or [])}", None)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}/comments/{cid}", token=u2.token, body={"body": "Edited by u2"})
        check("PUT comment own", "200, updated", s, s == 200 and b.get("body") == "Edited by u2", "", b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}/comments/{cid}", token=u1.token, body={"body": "hijack"})
        check("PUT comment someone else's (u1 edits u2's)", "403 (docs: 'Not your comment')", s, s == 403, msg(b), b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}/comments/{cid}", body={"body": "hijack"})
        check("PUT comment without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}/comments/{cid}", token=u2.token, body={"body": ""})
        check("PUT comment empty body", "422", s, s == 422, msg(b), b)
        if r2:
            s, b, _ = api.call("PUT", f"/api/reviews/{r2}/comments/{cid}", token=u2.token, body={"body": "wrong review"})
            check("PUT comment via the wrong review id", "404", s, s == 404, msg(b), b)
        s, b, _ = api.call("PUT", f"/api/reviews/{r1}/comments/999999999", token=u2.token, body={"body": "x"})
        check("PUT missing comment", "404 (docs)", s, s == 404, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/comments/{cid}", token=u1.token)
        check("DELETE comment someone else's (review author u1 deletes u2's)", "403 (docs: author or admin only)", s, s == 403, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/comments/{cid}")
        check("DELETE comment without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/comments/{cid}", token=u2.token)
        check("DELETE comment own", "200", s, s == 200, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/comments/{cid}", token=u2.token)
        check("DELETE comment again", "404 (docs)", s, s == 404, msg(b), b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/comments", token=u2.token, body={"body": "left on purpose, goes with the review"})
        check("POST comment (to test cascade on review delete)", "200", s, s == 200, "", b)

    # --------------------------------------------------------------- votes
    if r1:
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/helpful")
        check("vote helpful without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/helpful", token=u2.token)
        check("vote helpful (u2 on u1's review)", "200 counters helpful=1", s, s == 200 and b.get("helpful_counter") == 1 and b.get("unhelpful_counter") == 0, "keys: " + ",".join(sorted(b)) if isinstance(b, dict) else "", b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/helpful", token=u2.token)
        check("vote helpful again (repeat)", "200, still helpful=1 (one vote per user)", s, s == 200 and b.get("helpful_counter") == 1, f"counters {b.get('helpful_counter')}/{b.get('unhelpful_counter')}" if isinstance(b, dict) else "", b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/unhelpful", token=u2.token)
        check("switch helpful -> unhelpful", "200, helpful=0 unhelpful=1", s, s == 200 and b.get("helpful_counter") == 0 and b.get("unhelpful_counter") == 1, f"counters {b.get('helpful_counter')}/{b.get('unhelpful_counter')}" if isinstance(b, dict) else "", b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/helpful", token=u1.token)
        check("vote on own review", "4xx (docs: cannot vote on your own review)", s, 400 <= s < 500, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/vote", token=u2.token)
        check("remove vote", "200, counters 0/0", s, s == 200 and b.get("helpful_counter") == 0 and b.get("unhelpful_counter") == 0, "", b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/vote", token=u2.token)
        check("remove vote when none exists", "200 (idempotent) or 404", s, s in (200, 404), msg(b) if s != 200 else "idempotent", b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}/vote")
        check("remove vote without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("POST", f"/api/reviews/{r1}/helpful", token=u2.token)  # leave a vote to test cascade
    s, b, _ = api.call("POST", "/api/reviews/999999999/helpful", token=u2.token)
    check("vote on missing review", "404", s, s == 404, msg(b), b)
    s, b, _ = api.call("DELETE", "/api/reviews/999999999/vote", token=u2.token)
    check("remove vote on missing review", "404", s, s == 404, msg(b), b)

    # ------------------------------------------------------------ deleting
    if r1 and r2:
        s, b, _ = api.call("DELETE", f"/api/reviews/{r2}", token=u1.token)
        check("DELETE /reviews/{id} someone else's", "403 (docs)", s, s == 403, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r2}")
        check("DELETE /reviews/{id} without token", "401", s, s == 401, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}", token=u1.token)
        check("DELETE /reviews/{id} own (has comment+vote)", "200", s, s == 200, msg(b), b)
        reviews.pop(r1, None)
        s, b, _ = api.call("GET", f"/api/reviews/{r1}")
        check("deleted review is gone", "404", s, s == 404, msg(b), b)
        s, b, _ = api.call("GET", f"/api/reviews/{r1}/comments")
        check("comments of a deleted review are gone", "404 (docs: comments go with it)", s, s == 404, msg(b), b)
        s, b, _ = api.call("DELETE", f"/api/reviews/{r1}", token=u1.token)
        check("DELETE /reviews/{id} again", "404", s, s == 404, msg(b), b)

    # -------------------------------------------------------------- logout
    s, b, _ = api.call("POST", "/api/users/logout")
    check("logout without token", "401", s, s == 401, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/logout", token=u1.token)
    check("logout u1", "200", s, s == 200, msg(b), b)
    old = u1.token
    s, b, _ = api.call("POST", "/api/reviews", token=old, body={"subject": subject_b + "-after", "rating": 3})
    if s == 200 and isinstance(b, dict) and b.get("id"):
        reviews[b["id"]] = u1
    check("reuse token after logout (POST /reviews)", "401 (docs: 'the token no longer works')", s, s == 401, msg(b), b)
    s, b, _ = api.call("GET", "/api/users/me", token=old)
    check("reuse token after logout (GET /users/me)", "401", s, s == 401, msg(b), b)
    s, b, _ = api.call("POST", "/api/users/logout", token=old)
    check("logout twice with the same token", "401", s, s == 401, msg(b), b)
    s, b = login(api, u1)
    check("login again after logout", "200", s, s == 200, msg(b), b)
    s, b, _ = api.call("GET", "/api/subjects", token=old)
    check("read-only call still works with a dead token (key only)", "200", s, s == 200, "", None)
    # users: u1 must not be able to delete u2
    if u2.id:
        s, b, _ = api.call("DELETE", f"/api/users/{u2.id}", token=u1.token)
        check("DELETE /users/{other} as non-admin", "403 (docs: 'Not allowed')", s, s == 403, msg(b), b)
    s, b, _ = api.call("GET", "/api/users", token=u1.token)
    check("GET /users as non-admin", "403 (docs)", s, s == 403, msg(b), b)

    delete_flows(api, u1, reviews)

    # ------------------------------------------------- rate limit snapshot
    print("   (rate-limit headers seen on every response are summarised at the end)")


api_extra: list[User] = []

def register_extra(api, label):
    u = User(label)
    s, b, _ = api.call("POST", "/api/users/register", body={"name": f"Live {label}", "email": u.email, "password": u.password})
    if s in (200, 201) and isinstance(b, dict) and b.get("token"):
        u.set_token(b["token"]); u.id = b.get("id")
        api_extra.append(u)
        return u
    check(f"delete flows: register {label}", "200/201", s, False, msg(b), b)
    return None


def counters(api, rid):
    s, b, _ = api.call("GET", f"/api/reviews/{rid}")
    return (b.get("helpful_counter"), b.get("unhelpful_counter"), len(b.get("comments") or []), b.get("comment_count")) if s == 200 and isinstance(b, dict) else None


def delete_flows(api, u1, reviews):
    """DELETE /api/users/me with a right, wrong and missing password; purge=true with recounted votes.
    Everything is deleted again: u3/u4 by the flows themselves, the review of u1 (and with it u3's comment and vote) at the end."""
    print("\n--- delete flows ---", flush=True)
    subj_a = f"livecheck-da-{secrets.token_hex(4)}"
    subj_b = f"livecheck-db-{secrets.token_hex(4)}"
    s, b = login(api, u1)
    s, b, _ = api.call("POST", "/api/reviews", token=u1.token, body={"subject": subj_a, "rating": 4, "title": "delete flows"})
    if s != 200 or not isinstance(b, dict):
        check("delete flows: u1 review", "200", s, False, msg(b), b)
        return
    ra = b["id"]; reviews[ra] = u1
    u3, u4 = register_extra(api, "u3"), register_extra(api, "u4")
    if not (u3 and u4):
        return

    # u3 leaves a comment and a helpful vote on u1's review, then deletes the account WITHOUT purge
    s, b, _ = api.call("POST", f"/api/reviews/{ra}/comments", token=u3.token, body={"body": "u3 comment"})
    s, b, _ = api.call("POST", f"/api/reviews/{ra}/helpful", token=u3.token)
    check("delete flows: u3 votes helpful on u1's review", "helpful=1", s, s == 200 and b.get("helpful_counter") == 1, "", b)

    s, b, _ = api.call("DELETE", "/api/users/me")
    check("DELETE /users/me without a token", "401", s, s == 401, msg(b), b)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u3.token)
    check("DELETE /users/me with a MISSING password (no body)", "422", s, s == 422, msg(b), b)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u3.token, body={"password": ""})
    check("DELETE /users/me with an EMPTY password", "422", s, s == 422, msg(b), b)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u3.token, query={"password": u3.password})
    check("DELETE /users/me with the right password only in the URL", "422 (body only)", s, s == 422, msg(b), b)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u3.token, body={"password": secrets.token_urlsafe(12)})
    check("DELETE /users/me with a WRONG password", "403", s, s == 403, msg(b), b)
    s, b, _ = api.call("GET", "/api/users/me", token=u3.token)
    check("account and token survive the refused deletes", "200", s, s == 200, msg(b) if s != 200 else "", None)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u3.token, body={"password": u3.password})
    check("DELETE /users/me with the RIGHT password (no purge)", "200 {message}", s, s == 200 and "purged" not in (b or {}), msg(b), b)
    if s == 200:
        u3.deleted = True
    s, b, _ = api.call("GET", "/api/users/me", token=u3.token)
    check("deleted user's token answers 401", "401", s, s == 401, msg(b), None)
    s, b = login(api, u3)
    check("deleted user can no longer log in", "401", s, s == 401, msg(b), None)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u3.token, body={"password": u3.password})
    check("DELETE /users/me twice", "401", s, s == 401, msg(b), None)
    c = counters(api, ra)
    check("no purge: u3's vote and comment stay on u1's review", "helpful=1, 1 comment, comment_count=1", 200, c == (1, 0, 1, 1), f"{c}", None)

    # u4: review of its own, a comment and an unhelpful vote on u1's review; u1 comments on and votes on u4's review. Then purge.
    s, b, _ = api.call("POST", "/api/reviews", token=u4.token, body={"subject": subj_b, "rating": 2, "title": "u4 review"})
    r4 = b.get("id") if s == 200 and isinstance(b, dict) else None
    check("delete flows: u4 writes a review", "200", s, r4 is not None, msg(b) if r4 is None else "", None)
    if r4 is None:
        return
    reviews[r4] = u4
    api.call("POST", f"/api/reviews/{ra}/comments", token=u4.token, body={"body": "u4 comment"})
    s, b, _ = api.call("POST", f"/api/reviews/{ra}/unhelpful", token=u4.token)
    check("delete flows: u4 votes unhelpful on u1's review", "unhelpful=1", s, s == 200 and b.get("unhelpful_counter") == 1, "", b)
    api.call("POST", f"/api/reviews/{r4}/comments", token=u1.token, body={"body": "u1 comments on u4's review"})
    s, b, _ = api.call("POST", f"/api/reviews/{r4}/helpful", token=u1.token)
    c = counters(api, ra)
    check("before purge: u1's review has helpful=1 (u3), unhelpful=1 (u4), 2 comments", "(1, 1, 2, 2)", 200, c == (1, 1, 2, 2), f"{c}", None)

    s, b, _ = api.call("DELETE", "/api/users/me", token=u4.token, query={"purge": "true"}, body={"password": secrets.token_urlsafe(12)})
    check("purge=true with a WRONG password deletes nothing", "403", s, s == 403, msg(b), b)
    c = counters(api, ra)
    check("...and nothing changed", "(1, 1, 2, 2)", 200, c == (1, 1, 2, 2), f"{c}", None)
    s, b, _ = api.call("DELETE", "/api/users/me", token=u4.token, query={"purge": "true"}, body={"password": u4.password})
    purged = (b or {}).get("purged") if isinstance(b, dict) else None
    check("DELETE /users/me?purge=true with the RIGHT password", "200 + purged{reviews:1,comments:2,votes:2}", s,
          s == 200 and purged == {"reviews": 1, "comments": 2, "votes": 2}, f"{json.dumps(b)}", None)
    if s == 200:
        u4.deleted = True
        reviews.pop(r4, None)
    s, b, _ = api.call("GET", f"/api/reviews/{r4}")
    check("purge: u4's review is gone", "404", s, s == 404, msg(b), None)
    c = counters(api, ra)
    check("purge: unhelpful recounted to 0, u3's vote and comment stay", "(1, 0, 1, 1)", 200, c == (1, 0, 1, 1), f"{c}", None)
    s, b, _ = api.call("GET", "/api/subjects", query={"q": "livecheck-db-"})
    check("purge: u4's subject is gone from /subjects", "none", s, s == 200 and not [x for x in b.get("subjects", []) if subj_b in x["subject"]], "", None)
    s, b, _ = api.call("DELETE", f"/api/reviews/{ra}", token=u1.token)
    check("delete flows: clean-up of u1's review (takes u3's comment and vote with it)", "200", s, s == 200, msg(b), None)
    if s == 200:
        reviews.pop(ra, None)



def burst(api, n, workers=1):
    """Unpaced GETs until the API answers 429; records the real 429 response."""
    print(f"\n--- burst: up to {n} unpaced GET /api/subjects?per_page=1 from {workers} thread(s) ---", flush=True)
    import concurrent.futures as cf
    import threading
    saved = api.pace
    api.pace = 0
    first = None
    lock = threading.Lock()
    sent = [0]
    t0 = time.time()

    def one(_):
        nonlocal first
        if first:
            return
        with lock:
            sent[0] += 1
            i = sent[0]
        s, b, h = api.call("GET", "/api/subjects", query={"per_page": 1}, retry=False)
        if s == 429 and not first:
            first = (i, round(time.time() - t0, 1), b, {k: v for k, v in h.items() if re.search("rate|limit|retry|content-type", k, re.I)})

    with cf.ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        list(ex.map(one, range(n)))
    api.pace = saved
    if not first:
        check("burst: unpaced GETs", "informational: a 429 within N calls", 200, True, f"no 429 in {sent[0]} requests from {workers} thread(s) ({time.time() - t0:.0f}s)")
        return
    i, secs, body, hdrs = first
    check("burst: unpaced GETs hit the limit", "429 (throttle)", 429, True, f"after {i} calls in {secs}s; body={json.dumps(body)}; headers={json.dumps(hdrs)}")
    ra = hdrs.get("Retry-After")
    wait = int(ra) if ra and ra.isdigit() else 30
    print(f"   waiting {wait}s then probing recovery", flush=True)
    time.sleep(wait)
    s, b, h = api.call("GET", "/api/subjects", query={"per_page": 1}, retry=False)
    check("burst: usable again after Retry-After", "200", s, s == 200, f"waited {wait}s" + ("" if s == 200 else f"; still {s}"))


def cleanup(api, users, reviews, subject, subject_b):
    print("\n--- clean-up ---", flush=True)
    problems = []
    for u in users + api_extra:
        if not u.password or not u.email or getattr(u, "deleted", False):
            continue
        s, b = login(api, u)
        if s != 200 and u.token is None:
            problems.append(f"could not log in {u.label} ({s})")
            continue
        uid = u.id
        # every remaining review of this user (also catches ones not tracked)
        if uid is not None:
            s, b, _ = api.call("GET", f"/api/users/{uid}/reviews", query={"per_page": 50})
            for rv in (b.get("reviews", []) if s == 200 and isinstance(b, dict) else []):
                reviews[rv["id"]] = u
        for rid, owner in list(reviews.items()):
            if owner is u:
                s, b, _ = api.call("DELETE", f"/api/reviews/{rid}", token=u.token)
                if s not in (200, 404):
                    problems.append(f"review {rid}: {s}")
                reviews.pop(rid, None)
        if uid is not None:
            s, b, _ = api.call("DELETE", "/api/users/me", token=u.token, body={"password": u.password})
            check(f"clean-up: delete user {u.label}", "200", s, s == 200, msg(b), b)
            if s != 200:
                problems.append(f"user {u.label} id={uid} NOT deleted ({s})")
            s, b = login(api, u)
            check(f"clean-up: deleted {u.label} can no longer log in", "401", s, s == 401, msg(b), None)
    s, b, _ = api.call("GET", "/api/reviews", query={"subject": subject})
    check("clean-up: no reviews left on test subject", "total 0", s, s == 200 and b.get("total") == 0, f"total={b.get('total') if isinstance(b, dict) else '?'}", None)
    s, b, _ = api.call("GET", "/api/subjects", query={"q": "livecheck-"})
    left = [x["subject"] for x in b.get("subjects", [])] if s == 200 else []
    mine = [x for x in left if x.lower().startswith(("livecheck-" + subject[10:], subject.lower()))]
    check("clean-up: test subjects gone from /subjects", "none", s, not [x for x in left if subject in x or subject_b in x], f"left: {left}", None)
    for p in problems:
        print("CLEAN-UP PROBLEM:", p)


def summary(api, out):
    n_fail = sum(r["result"] == "FAIL" for r in RESULTS)
    print(f"\n{len(RESULTS)} checks, {n_fail} FAIL; {api.calls} HTTP requests in {time.time() - api.t0:.0f}s; 429 events: {len(api.rate_events)}")
    print(f"X-RateLimit-Limit header: {api.limit_header}")
    if api.rate_events:
        for e in api.rate_events:
            print("  429:", json.dumps(e))
    # X-RateLimit-Remaining must only go down inside one window (same X-RateLimit-Reset)
    ups, windows = [], {}
    for n, t, rem, reset in api.remaining_series:
        windows.setdefault(reset, []).append((n, int(rem)))
    for reset, series in windows.items():
        for (n0, r0), (n1, r1) in zip(series, series[1:]):
            if r1 > r0:
                ups.append({"window_reset": reset, "call": n1, "from": r0, "to": r1})
    print(f"rate-limit windows seen: {len(windows)}; Remaining went UP inside a window {len(ups)} time(s) {ups[:5]}")
    check("X-RateLimit-Remaining only goes down within a window (same X-RateLimit-Reset)", "no increase inside a window", 200, not ups,
          f"{len(api.remaining_series)} responses, {len(windows)} windows, increases: {ups[:5]}")
    data = {
        "checks": RESULTS, "remaining_increases_inside_window": ups, "http_requests": api.calls, "seconds": round(time.time() - api.t0),
        "rate_limit_header": api.limit_header, "rate_429_events": api.rate_events,
        "remaining_series": api.remaining_series,
    }
    if out:
        with open(out, "w") as f:
            f.write(scrub(json.dumps(data, indent=1)))
        print("results written to", out)


if __name__ == "__main__":
    main()
