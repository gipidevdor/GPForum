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
