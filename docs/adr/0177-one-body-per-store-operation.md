# ADR 0177: One body per store operation

## Status

Accepted (2026-11-08). Amends ADR 0174 and ADR 0176.

## Context

ADR 0176 gave every service a request reaches a `METHOD_p` twin on the
worker's pooled connections, and kept the blocking `METHOD` for commands,
jobs, workers and in-memory doubles. Many stores then held each operation
up to three times: the blocking body on `rows` and `txn_do`, the promise
body on `row_p` and `transaction_p`, and a DBIx::Class body for fixture
schemas (`if !$self->functions`). On 2026-11-08 `lib/` held 716 promise
methods and 170 such branches in 61 files.

The copies drift. A review of `main` that day found `answers_p` without the
fallback its blocking twin had, and a refusal added to one path had to be
added to the other by hand. Every fix is paid two or three times.

## Decision

A store writes each operation once, as its promise method, against its call
layer (`functions`, or the `$scope` a transaction hands it).

`GPForum::Infrastructure::SqlFunction` has a blocking layer
(`blocking_layer`). On it, `rows_p` and `row_p` run `rows` on the process's
own connection, and `transaction_p` runs `txn_do`, which opens the
transaction or a savepoint of the one already open, as a pooled transaction
nests. Each answers a promise that is already settled. An `async sub` whose
awaits all meet settled promises runs to its end without an event loop.

The blocking method is that body run on the blocking layer, and nothing
else. A store declares its blocking twins instead of writing them:

    GPForum::Infrastructure::SqlFunction->blocking_twins(
        qw(create_suspension revoke_suspension));

installs `create_suspension` as `settle` of `create_suspension_p`, with the
caller's arguments.

`settle` copies the service with its call layer made blocking
(`blocking_copy`), calls the promise method and returns its value, or
raises its failure as it was. `settled` refuses a promise still pending:
blocking code never waits on the event loop.

A service whose promise methods await another service declares it, so the
copy blocks all the way down:

    GPForum::Infrastructure::SqlFunction->blocking_parts('viewer_resolver');

`blocking_copy` then copies that attribute the same way. A part without a
call layer, a test double, is kept as it is.

The DBIx::Class body goes with the conversion. A store converted this way
needs the function layer and throws `GPForum::X::Unavailable` without one;
its tests run on PostgreSQL (`t/integration`), as the moderation stores'
already did. Tests that compared a store with its retained Perl path state
the expected answers instead.

`SuspensionStore` was the first store converted. Amended 2026-11-09: the
whole moderation area followed -- `ActionStore`, `AutomodStore`,
`MemberNoteStore`, `ReportStore`, `ReviewReader`, `ReviewStore` and
`ThreadTransfers`. `ActionStore`'s eight actions became one table of data
(the event, the target kind, whether the target is already there, the
changes) applied by one body. The other areas follow, each with its tests
moved to PostgreSQL in the same change.

Amended 2026-11-09 again: the forum stores that were already function-only
-- `DraftStore`, `Polls`, `ReplyLinks`, `ThreadTags` -- and the two with a
raw-SQL fallback, `ViewerResolver` and `Readability`, whose fallbacks went.
`Readability` is the first store with a part (`viewer_resolver`). A viewer
resolution without the function layer now raises instead of degrading to a
visitor: a missing layer is a wiring fault, not an anonymous reader.

Then the forum readers -- `CategoryReader`, `ThreadReader`, `PostReader`,
`ThreadDetailReader` -- and the read marker, `ReadState` and
`ReadWorkflow`. The readers lose their prepared statements; each keeps the
resultset the query-plan evidence compares with its function
(`categories_resultset`, `category_threads_resultset`,
`latest_threads_resultset`, `thread_posts_resultset`), and nothing else.
`ThreadDetailReader->thread_page` is the snapshot statement whether it is
awaited or not. The read marker is only `api.forum_read_marker_command`:
`ReadWorkflow` requires its command log and writes it with the mark in one
call, and `ReadState` keeps the reads and the refusal. The integration
tests that compared those readers with their retained path now compare the
functions with the evidence resultsets, the snapshot page with the page
read in parts, and the read marker with stated answers. One disagreement
showed and is recorded as a TODO in
`t/integration/postgres-sql-function-forum-reads.t`: for a viewer with
`global_read` and no membership, the category list reads every level and
the lookup still asks a members-only level for membership.

Then the posting writes. `PostStore` and `ThreadStore` lose their DBIx::Class
writes, their locks and recoveries, and `ContentStore` and `Forum::Event`
go: the writes were already `api.forum_write_command`'s and
`api.forum_create_reply`'s, and the stores keep only the parameters Perl
draws for them and the answers they read back. `PostingWorkflow` has one
path: it reads, checks and composes, and plans the one call; the plan is
run by `PostingNative::written_p`, on the pooled connections or, for a
blocking caller, settled on the blocking layer -- one executor instead of
two. `command_idempotency` is required (its ids, clock and request hash
make the command log's row) and `post_reader` is no longer a collaborator.
Two behaviours of the retired Perl command log are gone with it, as the
function path already had them: a failed command is not recorded, so a
retry runs again, and the logged actor is trimmed.

The unit tests of the workflow run on `t/lib/GPForum/Test/PostingFunctions.pm`,
which keeps the command log in memory and hands each write to a store
double; the tests of the stores' own Perl writes went, and the integration
tests that compared the two paths state their answers. A test that reaches
the store step alone calls it through `t/lib/GPForum/Test/StoreWrites.pm`.

Then the community area. `Community::Workflow` has one path: each command
-- a bookmark, a like, a reaction, a subscription -- is one call with its
command log, described in one table and run by one promise body; a report
runs under the command log's promise with the report store, both declared
as parts of the blocking twin. `command_idempotency` is required.
`BookmarkStore` loses its DBIx::Class writes (the commands write) and keeps
its reads and the row a save draws; `MentionStore`, `Follows`,
`RelationStore`, `FeedProjector` and `MessageStore` keep only their promise
bodies, and their fallbacks for a schema without the function layer go:
they raise `GPForum::X::Unavailable`, as a missing layer is a wiring fault.

`SqlFunction->joined($service, $layer)` puts a service and its declared
parts on a transaction's call layer -- `MentionStore` joins its
readability, relations and recorder to the post's transaction with it.
The doubles that keep a command log in memory share
`t/lib/GPForum/Test/LoggedCalls.pm`; `CommunityFunctions` stands in for the
community commands as `PostingFunctions` does for the posting ones, and
`SettledCalls` answers `transaction_p` for every call-layer double.

Then the notification area. `Notification::Dispatcher` writes each
operation once -- a notification, the inbox's lists and count, a mark --
and its DBIx::Class delivery and read paths go; the fan-out always runs
through `Fanout`. `PreferenceStore`, `SubscriptionStore`,
`CategorySubscriptions` and `RecipientPolicy` keep only their promise
bodies, and `Notification::Workflow` requires its command log, as
`Community::Workflow` does. `SubscriptionStore`'s writes go: a
subscription is written by the community commands. `DigestQueue` keeps its
one blocking body; its skip without a database is the scheduled jobs'
convention, not a second path.

The unit tests of the inbox run on
`t/lib/GPForum/Test/NotificationInboxFunctions.pm`; tests that reach the
subscription store steps alone call them through
`t/lib/GPForum/Test/SubscriptionWrites.pm`. The blocking layer answers
`in_transaction`, so the badge runs in a savepoint only inside a
transaction its caller holds, and after the commit otherwise.

Then the search area. `Search::Searcher` reads through its promise
bodies alone -- ranked, hybrid and autocomplete -- each read in a
read-only transaction under search's statement timeout, the result cache
on both paths; `search_resultset` and `autocomplete_resultset` stay as
query-plan evidence. A hybrid search is two such transactions, the
lexical and the vector read, as it already was on the pooled path.
`Search::Indexer`, `Search::RebuildRun` and `Search::Semantic`'s
`index_entity` keep only their promise bodies: a document is built,
skipped or removed by `api.search_index_entity`, so the Perl builder, the
upsert and the advisory locks of the DBIx::Class path go, and
`DocumentBuilder` names only the text-search configuration. The indexer's
batching runs in the unit tests on
`t/lib/GPForum/Test/SearchIndexFunctions.pm`.

Then the attachment area. `Attachment::Store` writes each operation once
-- an intent, a link, a variant, an upload mark, a scan verdict, a
deletion, a download decision, the orphan purge -- and its DBIx::Class
writes, prepared statements and `txn_do` paths go; the readability a
download awaits is its part. `with_post_write` stays a blocking adapter: it
runs a blocking caller's work under the guard of `with_post_write_p`.
`ScanQueue`, `ContentReview`, `PostgresStorage`'s writes and `LegacyImport`
keep only their promise bodies. `UploadPipeline` has one upload body: a
blocking caller scans the source first, in the process, and runs that body
on the store's blocking layer, which hashes the source in the process
instead of in a child. The unit tests that ran the store on the fixture ORM
moved to `t/integration/postgres-upload-scanning.t`, where
`AttachmentFixtures` builds on a seeded database of its own; the raced
looks of the insert-once writes are scripted by
`t/lib/GPForum/Test/MissedLooks.pm` instead of `RacedSchema`.

Then the privacy area. `Privacy::DeletionWorkflow` writes each step once --
a request, an approval, a hold and its release, an erasure -- in one
transaction on its call layer, and its parts (`Deletion::Core`, `Holds`,
`Requests`, `Erasure`) lose their blocking helpers, their DBIx::Class
writes and the `FOR UPDATE` statements the Perl path sent: an open request
is kept unique by its index, as the function path already did. The events
and audit entries are the recorder's prepared calls on the step's
transaction, so a failing recorder rolls the step back. `RetentionHoldStore`,
`ErasedExports` and `DataRightsReview` keep only their promise bodies;
`Privacy::Workflow` has one body per command, with its stores and command
log as parts. The erasure revokes every source the function layer names,
where the Perl path revoked only credentials and sessions. The fixture-ORM
rollback tests moved to `t/integration/postgres-privacy-rollback.t`, and
the raced lookups of the approval are scripted by
`t/lib/GPForum/Test/MissedPrivacyLooks.pm` instead of `RacedSchema`.

Then the identity stores. `SessionStore`, `TokenStore`, `CredentialStore`,
`AuthStore`, `PreferenceStore`, `RegistrationStore`, `ProfileReader` and
the parts of `AccountStore` (`Account::Core`, `Passwords`, `EmailChange`,
`EmailVerify`) keep only their promise bodies, with declared blocking twins;
`AuthStore` copies its credential, second-factor and session stores as
blocking parts. The DBIx::Class paths go with them: the Perl session check
(its touch interval, expiry and token digest), the three-round credential
lock loop and the token-hash `FOR UPDATE` are `api.session_validate`'s,
`api.identity_lock_passwords`'s and `api.identity_insert_token`'s alone.
Argon2 runs in a child of the CPU lane on the asynchronous layer and in the
process on the blocking one, as the upload pipeline does, since a child
would leave the blocking promise pending. A registration's event and audit
are the recorder's prepared calls on its transaction. `ProfileReader` keeps
`public_threads_resultset` as the plan evidence
`t/integration/postgres-viewer-plan.t` explains. The differential tests
became stated ones: `t/integration/postgres-sql-function-identity.t` and the
session cases of `t/integration/postgres-sql-function-prologue.t` state each
answer and every row it leaves, and `t/160-session-touch-interval.t` and
`t/42-profile-reader.t` stand on `AnsweringFunctions`. In
`t/integration/postgres-sql-function-identity-commands.t` only the command
log keeps its Perl path.

Then the discovery archive. `Discovery::Archive` writes each read once --
a post, a signature, a page of signatures, the mbox spool -- and declares
its blocking twins, with its four readers as parts; `spool` is the spool's
body settled on the blocking layer, as the mail worker and the protocol
tests call it, and `spool_p` hands the same file over as a descriptor. The
blocking spool's DBIx::Class transaction and `spool_descriptor` go. The
spool's transaction joins the archive and its readers with
`SqlFunction->joined`, so a reader's own parts read in it too.
`Discovery::SitemapPages` writes the index, a page and the page count
once each; its blocking read through the cache's `get_or_set` and its
fallback for a call layer without promise reads go, so both paths share
one cache fill, its ticket taken before the build.

Then `Moderation::Workflow`, which the moderation stores' conversion had
left with two executors. Each command is one promise body run under
`CommandIdempotency->result_of_p`, its store joined to the log's
transaction; the blocking commands are its twins, with the three stores
and the log as parts. `command_idempotency` is required, as it is in the
community and notification workflows: a command without its log is a
wiring fault. The unit doubles answer the stores' promise half settled.

`Moderation::ReviewWorkflow` followed: an approval, a rejection and a
withdrawal are written once, with the store, the posting workflow, the
resolver and the follow-up writers as parts, and the `can('..._p')`
fallbacks and `ReviewStore::in_transaction` go. A blocking approval
publishes through `PostingWorkflow::publish_reviewed_p`, which composes
the plan in the process on a blocking layer instead of in a child of the
CPU lane, whose promise the blocking layer would refuse.

Then the rate limiter. `RateLimiter::PostgreSQLStore` held a check three
times -- the promise body, the blocking body and a raw `INSERT ... ON
CONFLICT` for a schema without the function layer -- and a count of live
buckets through DBIx::Class; each is now one promise body on
`api.ops_rate_limit_check` and `api.ops_rate_limit_snapshot`.
`RateLimiter` writes `check_p` once, its refusal's audit awaited before it
answers, with the primary store and the recorder as parts. It builds its
counters and local buckets in its constructor: `blocking_copy` copies the
attributes already built, so a lazy one would have been built again in the
copy, and the first blocking check's counts lost with it. The unit tests
count on `t/lib/GPForum/Test/RateLimitFunctions.pm` instead of a database
handle that answered the raw upsert.

`Forum::HomePageReader` reads its two lists once, its readers as parts. A
body that reads in parallel starts each read and then awaits each:
`Mojo::Promise->all` settles a tick later even when every promise it is
given has settled, so a blocking twin would find it pending.

The thread page's combined reads (`ThreadPageReads`) are read once, as
`answers_p`; `answers` is its declared blocking twin, and `reading`, which
had no caller left, is gone. The promise method did not keep its promise:
its documentation said a failed statement is logged and answers nothing,
so the page reads each part on its own, but a failure rejected and failed
the thread page. The one body now logs and answers `{}`, and
`t/integration/postgres-thread-page-reads.t` proves it. The blocking twin
also reuses the detail reader's snapshot when its key matches, as the
promise method always did.

Then `Attachment::Workflow`, which the store's conversion had left with
two executors. An upload, a deletion and a download are written once; the
blocking ones are their twins, with the command log, the delivery, the
post reader and the store as parts, and the pipeline handed the command's
call layer. `command_idempotency` is required, and the `can('..._p')`
fallbacks go. A blocking upload now scans its source before the command
log opens its transaction, as the asynchronous one did, where it scanned
inside it. `UploadPipeline::prescan_p` is the one scan: on a blocking layer
it runs in the process, otherwise in a child of the CPU lane.
`Delivery::download_p` is the one download, `download` its twin; on a
blocking layer it reads the object's description in the process.
`Store::with_post_write` goes: its only caller was the workflow's blocking
path, and the lock test settles `with_post_write_p` instead.

Then the export, the profile pictures and the stores beside them.
`Portability::ExportBundleBuilder` writes a request and a completion once,
each in one transaction on its call layer; its DBIx::Class reads of the
member's rows (table by table, the post bodies in batches of
`body_batch_size`, which goes) are `api.portability_export_parts`'s alone,
as the blocking path with the function layer already read them, so an
export holds exactly what it held. `Community::Avatars` has one body per
operation on its store's call layer, with the store, the attachments, the
storage and the review as parts; as the upload pipeline does, the image
tool, and a square read from disk, run in a child on the asynchronous
layer and in the process on the blocking one, and a blocking upload hands
the pipeline's blocking upload the source to scan in the process.
`picture_from_input` and its promise go: `picture` is `picture_p`'s twin.
`AvatarStore`, `BookmarkFolders` and `Push::Store` keep only their promise
bodies; `BookmarkFolders` raises `GPForum::X::Unavailable` without the
layer, where it raised `GPForum::X::Argument`. `UnsubscribeToken` stays as
it is: its check is an HMAC that reads no database, and `verify_p` only
answers it. `t/27-export-bundle.t` stands on `AnsweringFunctions`, and the
picture tests of `t/integration/postgres-attachment-write-promises.t`
state each answer on both layers.

Then the identity services. `Identity::Workflow` follows
`Community::Workflow`: its command log is required, each logged command is
one row of a table run through `CommandIdempotency->result_of_p`, and a
registration is one call to `api.identity_register_command` -- the
DBIx::Class registration path, with its own refusals, goes. `SecondFactor`,
`Passkeys`, `Admission`, `Audit` and `SecurityAudit` keep only their
promise bodies with declared twins; `OpenID` does too, except `complete`,
which waits on the provider over HTTP and has no blocking form. Argon2 runs
as `AuthStore`'s does, so the decoy hash and the password check stay on
both layers; `LocalProof` keeps only `verify_local_p`. `Identity::Store`
declares its stores as blocking parts, so a workflow's twin settles on
copies of all of them. Two old paths differed. Without the call layer
`SecondFactor` answered "off" and `open_challenge` answered "none", which
would have let a sign-in through without its second step; the missing layer
now raises Unavailable, failing closed. And `CommandIdempotency->result_of`
recorded the unreduced result where `result_of_p` recorded the command's
`response`; both now record the response. The web tests register through
`GPForum::Test::IdentityFunctions`, the registration command over the
in-memory store and command log.

Then the admin area. `CategoryStore`, `RoleCatalog`, `RoleBindingStore`,
`AnnouncementStore`, `AddressBans`, `AuditReview`, `PermissionGate`,
`PermissionReview`, `ConsoleReader`, `Configuration`, `Maintenance` and
`Diagnostics` keep only their promise bodies, with declared blocking twins;
`Maintenance` copies its indexer and rebuild run as parts, `Diagnostics`
its address and audit readers. `Admin::Workflow` has one body per command,
`_commanded_p`, with the command log and its seven stores as parts, and the
log's blocking `run` settles that body. A blocking write now runs in a
transaction or savepoint of its own: `RoleCatalog`'s writes relied on the
caller's, and an announcement's insert, event and audit were three separate
writes. The console's dashboard and health block have no blocking twin --
readiness and metrics run the host's checks in a CPU child, which a
blocking caller cannot wait on -- so `dashboard_summary` and
`operations_status` go; the diagnostics send and scan in the process on the
blocking layer, as the identity area hashes. `PermissionGate`'s menu read
throws `GPForum::X::Unavailable` without the layer, where it answered "not
available". `AddressBans`' `covering_p` still answers undef without a
layer, so a test double needs none, and `Web::AddressBans` loses its unused
blocking `admits`. `Bootstrapper` looks rows up through its functions alone
and hands its layer to the catalogue and binding stores it builds. The
differential `t/integration/postgres-sql-function-admin.t` states each read
as the query over its tables and each write as the rows and audit entries it
leaves; the fixture-ORM bootstrap tests moved to
`t/integration/postgres-admin-bootstrap.t`, and the console, gate, binding
and attachment-audit tests stand on `AnsweringFunctions` and
`TransactionFunctions`.

Then the realtime area. `Realtime::Hub` writes a subscription, a
broadcast, an event's broadcast, a badge snapshot, the badge resend and
the session check once each; the blocking forms are their twins, with the
authorizer, the badge counter, the readability and the session store as
parts, and its call layer the first part's. Its `_call_p` fallback goes:
the collaborators answer their promise methods, and the doubles get them
from `t/lib/GPForum/Test/SettledTwins.pm`, settled. Reads it made with
`Mojo::Promise->all` are started together and awaited in turn.
`ChannelAuthorizer` and `SubscriptionPolicy` decide once, as
`authorize_p` and `permits_p`; the policy's DBIx::Class user lookup goes,
and a schema without the function layer raises `GPForum::X::Unavailable`.
`PgListener` writes a start, a reconnect and a poll once, the hub as its
part; the backstop reads `api.ops_realtime_poll` alone, so
`outbox_poll_resultset` and its raw clock query go, and
`t/integration/postgres-realtime-listen.t` reads the index range from the
plan of the function's own statement. The hub and the listener build what
a poll moves -- the registry, the counters, the cursor, the status -- in
their constructors, in one shared hash for the listener's scalars, since a
blocking copy would lose what it set. `ListenerSupervisor` writes a start
and a poll once; holding no call layer, its twins settle on the listener as
it is, and refuse to wait for one on the event loop. Its timers and the
reconnect backoff stay event-loop drivers, and `PgNotifications` keeps
`listen_to` and `take` beside their promise methods: they are two
transports, the schema's handle and the native LISTEN connection, not two
copies of one. The old paths differed in four ways. The supervisor's
promise path reconnected through `start_p`, so the listener's
`reconnect_count` never moved in a web worker while the blocking path
counted it; the one body calls the listener's `reconnect_p`, which counts
and starts as before. The blocking hub skipped the promise path's checks
that a socket is still registered before a send, a badge and a session
close; the twins have them. The blocking policy read the channel only for
an account that passed, where the promise path read both together and
raised a channel failure only for such an account; the answers are the
same. And a new channel registered on the native LISTEN connection now
asks the synchronous path to issue its LISTEN too, which only a forked
child reads.

Then the operations snapshot and readiness. `MetricsSnapshot` collects
once, as `collect_p`, `collect` its twin; `Readiness` builds its report
once, as `check_p`, with `check` and `recent_check` twins of `check_p` and
`recent_check_p`. Both read their database sections on their call layer,
and the host's sections -- ps, the OS preflight, the cache and antivirus
pings -- run in a child of the CPU lane on the pooled layer and in the
process on the blocking one. The two statements that are not functions,
the `SELECT 1` and `pg_settings`, run on a pooled connection or, on a
blocking layer, on the process's own handle. The DBIx::Class reads for a
schema without the function layer go: without a call layer the snapshot's
database sections are empty, as they were without a schema, and readiness's
database checks fail with `GPForum::X::Unavailable` -- its partition and
slot checks no longer answer "no catalog". `Readiness` keeps the memo
`recent_check_p` shares in an attribute built in its constructor, and
`MetricsSnapshot` its `started_at`, so a blocking copy shares them. The old
paths differed once: on the pooled path a `pg_settings` read that failed
rejected the whole report, and the request with it, where the blocking path
reported the check failed; the one body reports it failed. The unit tests
read through `t/lib/GPForum/Test/ReadinessFunctions.pm` and
`t/lib/GPForum/Test/ReplicationFunctions.pm`, which answer the probe, the
stored budgets, the partition horizon and the replication functions.

`CacheInvalidationBus` publishes once, as `publish_p`, through
`api.ops_publish_notification`; `publish` is its twin, and its counters are
built in its constructor. Its `pg_notify` on the schema's handle for a
schema without the function layer goes: without a call layer a publish is
counted unavailable and answers 0, as one without a handle was, since the
bus never fails the write it rides on. The unit tests publish through
`t/lib/GPForum/Test/NotifyingFunctions.pm`, which sends the notification on
the test's handle.

`Web::MemberNotes` held each notes block twice, `for_member` and
`for_reports` beside their promise methods, with no caller left for the
blocking pair outside its own test. Each block is now read once, through the
controller's promise boundary; the two reads a block makes start together
and are awaited in turn instead of through `Mojo::Promise->all`, so the test
double's settled promises answer it at once.

`CommandIdempotency->result_of_p` ran a command log without the function
layer through the blocking `result_of`, so every workflow that logs its
commands handed it a second copy of the command, its promise settled, as
`run`. The fallback and the six copies go: `result_of_p` shapes what
`run_p` answers, and `run_p`, the log's steps in one transaction on the
call layer, throws `GPForum::X::Unavailable` without one.
`GPForum::Test::CommandIdempotency` overrides `run_p`, and the web tests
that ran the real log on a fixture schema run it on
`t/lib/GPForum/Test/CommandLogFunctions.pm`, the three command log
functions over rows in memory, a failed transaction taking its rows back.

Once `Admin::Workflow` was converted no caller was left for the blocking
`result_of` and `run`, and they went with their DBIx::Class path -- the
`txn_do`, the savepoint around the insert, the reuse of a row found under
the colliding id -- rather than becoming twins nobody calls: a command or a
job that logs a command awaits `run_p` on its blocking call layer. `run_p`
refuses an empty command id as `run` did. The tests that ran `run` state
the same behaviour on the functions: `t/87-command-idempotency.t` and
`t/202-command-result.t` on `CommandLogFunctions`, which now refuses a
second row under a command id as the primary key does and can miss a
lookup as a racing request does; `t/integration/postgres-command-failure.t`
and the command log race of `t/integration/postgres-concurrency.t` on the
real functions. One case of the old path is gone with it: a row found under
a colliding command id that held this command's key and no answer was
finished by the new request whatever its fingerprint; the function path's
second attempt finds the row by key and refuses a different request as a
conflict. On PostgreSQL such a row is never visible, as the insert and the
answer commit together.

`EventRecorder` kept a Perl path for a schema without the function layer
-- the event and outbox writes, the audit chain's locks and tip -- while
`Admin`'s stores wrote through it on fixture and raced schemas. Once they
were converted no production caller was left without the layer: every
recorder is made on a `GPForum::Schema`, whose function layer is always
there. The path went, about 400 lines. `record_event` and `record_audit`
are `record_event_p` and `record_audit_p` settled on the blocking layer,
one `api.ops_record_event` or `api.ops_record_audit` call each, and the
recorder throws `GPForum::X::Unavailable` without the layer, as the
command log does; `verify_audit_chain` still answers none without it. The
digests and the chain order are the functions', as they were on
PostgreSQL. The unit tests that wrote through it on a fixture schema
write on `t/lib/GPForum/Test/RecorderFunctions.pm`, the recorder's
functions over rows in memory; the conflicts the functions resolve
themselves -- an outbox id or a drawn audit id already stored, an outbox
row that outlived its event -- are raised on purpose on the database in
`t/integration/postgres-event-recorder.t`. The tests of the Perl path's
own locks, transactions and conflict recovery were retired where the
database covers the scenario: the event id's lock by
`t/integration/postgres-partition-conflicts.t` (an event raced at another
time), the chain's and the audit id's locks by
`t/integration/postgres-audit-chain.t`. A few of them scripted a conflict
the locks leave no window for on PostgreSQL -- an insert racing a lookup
the same lock covers, a constraint the tables do not have -- and went with
the path; the functions keep those branches.

Then the outbox and the workers. `DeadLetterRecorder` and
`DeadLetterReplay` keep only their promise bodies, on
`api.outbox_dead_letter` and `api.outbox_replay_dead_letter`, with
`create_dead_letter` and `replay` their twins; the recorder's
insert-or-reuse under `UniqueConflict` and the replay's locked find, audit
lookup and insert go. `Outbox::Dispatcher` claims once, as
`_claimed_rows_p`: settled on the blocking layer for `dispatch_pending` and
`claim_ready_batch`, awaited on a pooled connection by
`dispatch_pending_p`, whose lanes in child processes are a second
executor, not a second copy, and stay. Its resultset claim, row updates and
`txn_do` go; a failure and its dead letter are one `transaction_p` on the
blocking layer, the recorder joined to it. `EventIdempotencyStore` writes
each claim operation once on `api.ops_event_claim`, `ReputationLedger`
writes `record_event_p` once on `api.community_record_reputation` in a
transaction, and `FeedProjection` and `ReputationUpdate` read a stored
author or thread only through `api.ops_worker_aggregate`. Three answers of
the retired paths differed, and the functions' stand: a dead letter already
recorded answers `{ skipped => 1 }`, where the Perl path merged it into the
stored row; `begin` answers the claim's token, not 1; and `mark_failed`
answers whether it released a claim, not 1 always. The dead-letter check's
simulate mode runs the dispatcher on `ProbeFunctions`, an in-memory call
layer, instead of a fake schema. The unit tests run on
`t/lib/GPForum/Test/OutboxFunctions.pm`, which rolls back a failed
transaction's calls and can crash an acknowledgement; which rows a claim
takes for a pool of workers, a dead letter written once and the event
claim's lifecycle are stated on PostgreSQL in
`t/integration/postgres-outbox-dispatcher.t` and
`t/integration/postgres-idempotency.t`.

## Consequences

- One body per operation: a fix, a refusal or a lock is written once and
  holds on both paths. `SuspensionStore` went from 880 to about 630 lines;
  the other seven moderation stores together from 3,738 to 2,760.
- A test double of the call layer speaks the whole contract: `row_p` and
  `rows_p` answering settled promises, and `blocking_layer`. The doubles
  inherit it from `t/lib/GPForum/Test/SettledCalls.pm` and answer only
  `row` and `rows`; `t/lib/GPForum/Test/AnsweringFunctions.pm` answers each
  function with the rows a test gives and records what was asked.
- A web worker still never blocks: the blocking layer reaches the storage's
  blocking handle, which refuses an HTTP request context as before
  (ADR 0176).
- The unit tier no longer covers a converted store on a fake ORM; the
  integration tier does, on the real functions.
- `t/86-engineering-correctness.t` accepts `transaction_p` and the
  `ops_record_event`/`ops_record_audit` calls as a store's transaction and
  recording boundaries.

## Related Decisions and Implementation

ADR 0126, ADR 0174, ADR 0176. `lib/GPForum/Infrastructure/SqlFunction.pm`
(`blocking_layer`, `settle`, `blocking_copy`, `settled`,
`blocking_twins`, `blocking_parts`), the stores of
`lib/GPForum/Service/Moderation/` and the converted ones of
`lib/GPForum/Service/Forum/`, `t/lib/GPForum/Test/SettledCalls.pm`,
`t/integration/postgres-suspension-races.t`,
`t/integration/postgres-sql-function-prologue.t`,
`t/integration/postgres-moderation-review.t`.
