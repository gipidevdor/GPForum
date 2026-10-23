# Community protocols and verifiable archives

Run migrations before starting this code. If using the restricted application
role, provision its API grants again after migrating. Existing function
versions remain available for workers from the previous release.

## Portable mbox archives

Thread and category pages offer **Download mbox archive**. The routes are
`/t/THREAD_UUID/archive.mbox` and `/c/CATEGORY_UUID/archive.mbox`.
They export every reader page in a consistent snapshot, through a private
temporary file. The file disappears after delivery. Anonymous readers get
public content; signed-in readers get what their account can read.
Hidden and deleted posts are excluded. Actual email addresses are excluded.

The archive is mboxrd, with MIME UTF-8 quoted-printable bodies, stable post
Message-IDs, a category List-ID, and In-Reply-To/References within a thread.
It can be imported into Thunderbird, mutt or an mbox-compatible mail library.

## Server attestations

Set `GPFORUM_POST_SIGNING_KEY=/var/lib/gpforum/keys/post-signing.pem` on every
web and worker process, pointing at the same persistent file. The first
signed write creates a missing Ed25519 PEM atomically with mode 0600.
Existing private keys with group or other permissions are refused.
The default for development is `var/keys/post-signing.pem`.

New posts and edits store their signature in the same database transaction
as the content. Old content remains explicitly unsigned until an operator runs:

```sh
gpforum sign-posts --json
```

This attests the old revisions as they are now; it cannot establish their
history before attestation. It never replaces an existing signature. Export
verifies persisted signatures and fails if the content or signature has been
altered, including substitution of an attacker-controlled public key.

`/.well-known/gpforum-signing-keys` publishes the trusted public JWK set.
`/p/POST_UUID/signature` returns the current authorized post's detached
envelope. mbox messages carry the same envelope as base64url JSON in
`X-GPForum-Signature`; unsigned messages say so explicitly.

The signed bytes are canonical, sorted-key UTF-8 JSON with `type` equal to
`GPForum.post.v1` and fields `post_id`, `body_format`, `body_source`.
Source line endings are normalized to LF for transport-independent verification.
The envelope contains its SHA-256 and an Ed25519 signature encoded as
unpadded base64url, plus a public JWK. Its key id is the SHA-256 of the
32-byte public key. Verifiers must pin the trusted well-known key set;
trusting a public key merely because it accompanies an export is insufficient.
Creation time, author identity, placement and moderation metadata are outside
this signature. These attestations are separate from ActivityPub transport
signatures.

Each used public key is archived beside the PEM as
`post-signing.pem.KEY_ID.pub.json`. Preserve those files when rotating the
private key and restart workers. Back up the private PEM and public key
archive separately from the database; keep their filesystem write access
restricted to the service account. A database writer cannot introduce a
trusted key by editing a signature envelope.

## Replies through email

Set `GPFORUM_MAIL_REPLY_ADDRESS=reply@forum.example.org`. Outbound thread
notifications then include a recipient-specific Message-ID and Reply-To.
When a currently readable post is available, its plain source is included.
The Message-ID contains a recipient-bound HMAC capability; the public
mbox Message-ID cannot authorize posting. The local mail server should
deliver that address to the service account running:

```sh
/srv/gpforum/bin/gpforum --env-file /etc/gpforum/gpforum.env mail-in --json
```

For a Postfix local alias, configure the pipe under a dedicated unprivileged
delivery account with access to that environment file, then run `newaliases`:

```text
reply: "|/srv/gpforum/bin/gpforum --env-file /etc/gpforum/gpforum.env mail-in --json"
```

Check the local MTA's pipe execution identity and permissions before enabling
delivery. Route rejected messages to an operator quarantine, preventing
automatic bounce loops. The command reads one message from stdin, up to one
MiB. It checks the complete In-Reply-To capability, one verified active From
address, current suspension status and per-account posting limits. It accepts
inline text/plain with MIME decoding, excludes attachments, and rejects
automatic replies and HTML-only messages. Message-ID supplies the durable
idempotency key. Re-delivery cannot create another post. Locked threads,
visibility rules, automod and review use the normal posting workflow.

Treat forwarded notification capabilities like signed action links. Session
signing secret rotation also rotates reply capabilities; configured previous
secrets continue accepting earlier notifications.

## WebSub

Set `GPFORUM_WEBSUB_HUB_URL` to a trusted HTTPS WebSub hub, self-hosted or
operated by a provider. The public Atom feed advertises it in XML and HTTP
Link headers. `/websub` also accepts subscription forms and forwards only
valid requests for the fixed public `/feed.atom` topic to that hub.

The hub verifies callback ownership, maintains finite subscription leases,
signs deliveries when a subscriber supplies `hub.secret`, and retries failed
deliveries. GPForum never connects to callback URLs supplied by subscribers.
Its durable outbox publishes changes to the hub with bounded timeouts and
retries on failure. Keep the outbox worker running. With no hub configured,
the feed retains ordinary polling and the subscription route answers 404.

This is a publisher with a subscription gateway, not an embedded hub. The
protocol responsibilities follow the [WebSub recommendation](https://www.w3.org/TR/websub/).

## Gemini

Run the separate listener alongside HTTP under a service supervisor:

```sh
gpforum gemini --listen 0.0.0.0 --port 1965 \
  --hostname forum.example.org \
  --cert /etc/gpforum/gemini.crt --key /etc/gpforum/gemini.key
```

It requires TLS 1.2 or newer and explicit certificate/key files; self-signed
certificates are supported. It defaults to loopback when `--listen` is
omitted. `/`, `/c/CATEGORY_UUID` and `/t/THREAD_UUID` serve paginated Gemtext
through the existing anonymous readers. Private content is excluded.
Requests have a 1024-byte URL limit, one response per connection, a ten-second
idle timeout and a read rate limit. User text stays inside literal fences.
The implementation follows the [Gemini protocol specification](https://geminiprotocol.net/docs/protocol-specification.gmi).

## Reputation and verified backups

Authenticated readers and writers have per-account buckets, independent of
their shared IP. Trust levels zero through four multiply the read budget by
1, 4, 16, 64 and 256, and ordinary write budgets by 1, 2, 4, 8 and 16.
Reports retain their stricter bound. Trust comes from the active account in
the database; clients cannot supply it. Anonymous traffic uses the IP bucket.

```sh
gpforum backup --to /var/backups/gpforum --verify --json
```

`--verify` needs a database role with CREATEDB. It exports one repeatable-read
snapshot, counts users, threads, posts, post bodies, signatures and migrations, and gives
that same snapshot to pg_dump. It restores the resulting dump into a randomly
named database with pg_restore's exit-on-error, compares every count and drops
the temporary database on success or failure. Only successful cleanup records
`verification.status=verified` and the counts in the manifest. A concurrent
post cannot cause a false mismatch. Upload archive checks and checksum checks
remain available through `gpforum restore --check`.
