# Browser fragment checks

These tests run the real GPForum application and vendored htmx in Chromium with
the application's CSP. Forum services use the doubles from the Perl fragment
tests; PostgreSQL is not required. Request interception also exercises slow,
failed and HTTP 422 responses. The tests cover explicit inheritance, out-of-band
swaps, each reaction submitter's action and command identity, duplicate request
suppression, released controls and the native JavaScript-disabled fallback.
Pagination and rejected replies verify that out-of-band updates neither duplicate
controls nor erase an unsent draft. The reply case intentionally suppresses the
optional JSON composer client to exercise the htmx fallback itself.

Install the test-only browser dependency outside the checkout, then run from
the repository root:

```sh
npm install --prefix /tmp/gpforum-browser --no-audit --no-fund playwright@1.65.0
node /tmp/gpforum-browser/node_modules/playwright/cli.js install chromium
NODE_PATH=/tmp/gpforum-browser/node_modules node --test t/browser/htmx.test.cjs
```

The ordinary client suite remains `node --test t/js/*.test.cjs` and needs only
Node.js. Browser checks are separate so a normal Perl checkout does not acquire
an npm dependency tree or download a browser.

## Persistent posting journeys

`posting.test.cjs` uses a freshly migrated and seeded PostgreSQL database, real
services, real templates, the real composer and Chromium. It creates a temporary
socket-only PostgreSQL cluster when no test DSN is supplied. With a supplied DSN,
only an isolated database clone is written. Missing PostgreSQL or Chromium fails
the tier; it is not converted into a successful skip.

Run both browser suites with `NODE_PATH=/tmp/gpforum-browser/node_modules make
test-browser`. CI runs this tier on every push and pull request. The fixture-only
session/readback endpoints are registered in the test process; production has
neither endpoint. Authentication itself is covered by identity tests, not by this
posting journey.

The data matrix covers `è`, all Italian accented vowels, decomposed accents,
non-Latin scripts and emoji, with JavaScript on and off. A journey checks native
validation focus, publication, reply, editing, rendering after reload and exact
PostgreSQL readback. The enhanced journey also checks a real CSRF refusal:
visible error, retained draft, unlocked controls, successful retry and no duplicate
post. The fragment suite separately covers network failures and duplicate submits.
