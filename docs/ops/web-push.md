# Web Push

Web Push is an optional third notification channel. A native Perl worker sends
RFC 8030 / 8291 / 8292 messages directly to browser Push services. Publishing
requests never wait for delivery. A separate PostgreSQL outbox shares the
notification transaction, including batched fanout and delivery with email
and the in-app channel disabled.

## Enable

From the release directory, as the service account, generate persistent keys:

```sh
bin/gpforum push-keys --directory var/keys/web-push
```

Run migrations and provision the new function grants using the existing
[SQL API role deployment procedure](sql-api-role.md). The web application
and Push worker use the runtime role, not the administrative database role.
Set the service environment, then restart the application:

```text
GPFORUM_PUSH_ENABLED=1
GPFORUM_PUSH_KEY_DIRECTORY=var/keys/web-push
GPFORUM_PUSH_CONTACT=mailto:operator@example.org
GPFORUM_PUSH_CONCURRENCY=8
GPFORUM_PUSH_PER_PROVIDER=2
```

Use an absolute key directory when supervisors have different working
directories. Preserve and back up `storage.key`, `private.json` and
`public.json`; losing the storage key makes stored subscriptions unusable.
Rotation is serialized with a file lock, and files/directories are synced before
publishing the active identity. Private files must be regular, owned by the service account, and inaccessible
to group/others (0600 or 0400). Final-component symlinks are refused. Protect
the directory and its parents against other accounts writing them. HTTP
operations read the public ring and storage key; the sending path reads the
private VAPID ring. Storage and signing keys are independent.

With `GPFORUM_PUSH_ENABLED=1` in the loaded environment, `gpforum service
print` includes the dedicated sender and prints the commands that start it:
`gpforum-push.service` on systemd, `gpforum_push` on FreeBSD, and
`com.gpforum.push.plist` on launchd. It uses the web service's account, selected
Perl, working directory and environment file. For example, on systemd:

```sh
sudo gpforum service print systemd --to /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable --now gpforum-push
```

Doctor checks that the configured sender runs and follows deployed code;
configuration restart advice includes it. Disabled installations do not get a
sender in their generated service list. To disable an already installed sender,
stop it before changing the setting to zero.

For a foreground supervised process, use:

```sh
bin/gpforum push --loop
```

Use `bin/gpforum push --once` for one bounded batch. Output is aggregate JSON
without receiver URLs, payloads or keys. SIGTERM/SIGINT stop new batches and
allow the current bounded batch to finish. Configure restart on failure.
Signing/storage files and the active signing identity are checked before
claiming deliveries, so unsafe key-file configuration stops the worker instead
of consuming the queue.

Start with one sender: concurrency settings apply per worker, rather than
forming a global provider quota across several processes.

For an emergency stop, stop the sender; restart with `GPFORUM_PUSH_ENABLED=0`
to keep registration and sending disabled. This does not recall messages
already accepted by a provider or erase stored consent.

## Consent and lifecycle

Settings exposes explicit device activation and choices for replies,
mentions, moderation and private messages. Browser permission is requested
only after a click. That permission belongs to the origin/browser profile,
rather than the signed-in forum account.

Registration creates a pending binding and encrypted two-minute challenge.
The sender displays a visible verification notification. The service worker
confirms receipt through authenticated same-origin CSRF-protected requests.
The nonce is absent from the registration response. Limits are ten bindings
per account and ten registration attempts per account per hour, in addition
to ordinary notification HTTP limits.

An endpoint cannot transfer to another account. Re-registering for the same
account replaces its generation and requires a new receipt proof. Revocation
deletes its queued jobs. Session revocation and account suspension/deletion
remove bindings in the same transaction. Expired sessions fail both claim
and pre-send checks. Browser logout also attempts unsubscribe and closing
displayed alerts. Account exports contain device ids, consent state, kinds
and creation dates, excluding capability URLs, receiver keys and challenges.

## Privacy and transport

Alerts say only “Good Phorum — You have new notifications”. Payloads contain
no author, message, thread title, recipient identity or content URL. A click
opens the fixed same-origin inbox, where current authentication and read
permissions apply. An alert delivered after logout or a permission change
therefore carries no private forum content. Activity and timing metadata
remain visible to the browser's Push service and potentially on the device.

RFC 8291 `aes128gcm` uses fresh P-256 ECDH keys and salts, separate from the
ES256 VAPID identity. A bounded cache reuses validated receiver public points;
authentication secrets are decoded for every message and ephemeral sender keys
are never reused. VAPID tokens are cached for at most 15 minutes per
origin/signing identity. Canonical base64url lengths and receiver curve
points are validated. Stored receiver material and challenges use
AES-256-GCM authenticated to their owner/purpose. Endpoint uniqueness uses
an HMAC fingerprint with a derived key.

`GPFORUM_PUSH_PROVIDERS` defaults to:

```text
fcm.googleapis.com updates.push.services.mozilla.com *.push.apple.com *.notify.windows.com
```

Windows Edge uses WNS; the approved Windows domain follows the
[Microsoft WNS domain guidance](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/wns-overview).
Review provider additions before changing it. Wildcards match complete DNS
labels. Only HTTPS on port 443, without credentials or fragments, is allowed.
DNS is asynchronous and only validated public IPv4 answers become peers.
IPv6 literals and AAAA-only destinations are unsupported and fail closed.
Connections pin the checked IP while TLS verifies the original hostname.
Redirects, provider cookies and environment proxy discovery are disabled. Positive DNS caching
respects TTL and is capped at 60 seconds. Caches, responses, payloads and
network timeouts have fixed bounds. Do not enable HTTP client debugging:
library debugging can print capability URLs and authorization headers.

The manifest is linked from the SSR layout and declares standalone display for
Home Screen installation. The privately revalidated service worker has a restricted `/push/` scope and same-origin
CSP. It has no fetch interception or application cache, performs no private
content lookup, and ignores payload-supplied titles, bodies and click URLs.

## Queue and tuning

Ready rows use `SKIP LOCKED` and a 30-second ownership lease. No database
transaction spans network calls. After resolving peers, one query refreshes
all leases, device consent, session/account state, relations and source
readability immediately before sending. Outcomes are committed together.
A normal busy batch uses three database round trips regardless of its size;
bounded retention cleanup adds one when due.

Defaults are eight simultaneous sends and two per provider hostname. Tune
`GPFORUM_PUSH_CONCURRENCY` and `GPFORUM_PUSH_PER_PROVIDER` against provider
latency, queue lag, CPU and memory; hard bounds are 64 and 16. TLS connections
are reused. Empty batches wait one second; productive batches drain without
a fixed polling ceiling. Cache sizes remain bounded with provider subdomains.

Bursts coalesce into one waiting alert per device, possibly alongside an
already leased send. Notification ids are retained for one day for replay
protection. Indexed cleanup removes expired jobs and old receipts in bounded
batches and continues while a retention backlog exists. Queue autovacuum
thresholds match other frequently updated tables.

Alerts expire after 15 minutes, challenges after two. Exponential retry with
jitter and bounded `Retry-After` never extends original expiry. Provider
404/410 disables a subscription; 429 and temporary server/network failures
retry. Other client errors are terminal. Invalid VAPID responses pause that
origin in the current worker and surface as failed counters: check clock,
contact and key configuration.

`accepted` means provider acceptance, not display, receipt or reading. A
timeout can leave acceptance unknown and cause a duplicate retry; stable
notification tags replace the generic visible alert. An in-flight or already
accepted message cannot reliably be recalled.

### Local cryptographic measurement

A local Perl 5.44.0 / CryptX 0.091 run measured 1,000 samples per mode using
process CPU time. Validated receiver-point reuse reduced mean encryption CPU
from 4.00 ms to 2.68 ms (33%); p95 was 4.02 ms versus 2.69 ms. Every sample
still generated a fresh sender ECDH key and salt. Generic alert bodies were
119 bytes on the wire. These are cryptographic measurements, excluding SQL,
TLS and provider latency, and do not establish production delivery capacity.

## Rotation and validation

```sh
bin/gpforum push-keys --directory var/keys/web-push --rotate
```

Rotation publishes private keys before the public identity and preserves old
keys and `storage.key`. The sender reloads its ring on a new identity. Existing
browser subscriptions retain their original VAPID key; the explicit update
button re-subscribes them to the active identity. Keep an old private key
while devices reference it. For compromise, stop sending and revoke affected
bindings instead of silently changing their identity.

Automated tests cover the exact RFC encryption vector, authenticated storage
tampering, provider policies, asynchronous sends, ownership, replay,
rollback, fanout, coalescing, leases, revocations and service-worker isolation.
Run `t/integration/postgres-web-push.t` on a disposable database. Actual
browser/OS delivery still requires staging tests on Chromium, Firefox,
Safari and iOS/iPadOS Home Screen installations. Simulated providers establish
neither real-device behavior nor production capacity.
