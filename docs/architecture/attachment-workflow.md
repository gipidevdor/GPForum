# Attachment Workflow Boundary

New uploaded bytes, including avatar variants, use chunked PostgreSQL storage
by default. Audio/video allow 250 MiB (configurable from 100 to 250), while
images/documents retain 25 MiB. Every production upload supplies a provenance
and rights declaration and is held for independent staff content review as
well as malware scanning. See [ADR 0161](../adr/0161-postgres-media-and-content-review.md)
and [media operation](../ops/media-and-podcasts.md).

`GPForum::Service::Attachment::Workflow` is the application boundary for
attachment uploads, author deletes, and downloads from HTTP controllers.

Responsibilities:

- look up a visible post before linking an upload or deleting a linked file;
- reject uploads and deletes from anyone other than the post author;
- delegate binary storage and linking to `Attachment::UploadPipeline`;
- delegate linked soft-delete to `Attachment::Store`;
- delegate authorized byte delivery to `Attachment::Delivery`;
- leave transaction, event, audit, and object-storage ownership inside those
  services;
- reuse unique attachment-link and variant rows on conflict;
- remint `attachment_id` and `object_key` once when the unique primary
  key conflicts with a different object, and do not return another
  attachment;
- remint `attachment_link_id` once when the unique primary key conflicts,
  and do not return another link;
- remint `attachment_variant_id` once when the unique primary key
  conflicts, and do not return another variant;
- leave download visibility and authorized payloads on
  `Attachment::DownloadAccess`, lifecycle replay, orphan-cleanup policy, and
  link fetch caps on `Attachment::Lifecycle`, event/audit hashes on
  `Attachment::Event`,
  and row access on `Attachment::Record`;
- require `command_id` on upload and delete writes and replay from
  `command_log` when the helper is present;
- hash actor and target ids only, never uploaded bytes;
- return a normalized result hash.

The normalized contract is:

```perl
{
    ok     => 0 | 1,
    status => 'ok' | 'invalid' | 'not_found' | 'forbidden' | 'failed' | 'conflict',
    error  => $message_or_undef,
    errors => $field_errors_or_undef,
    stored => $store_result_or_undef,
}
```

CSRF, authentication, and upload rate limits stay in
`Controller::Attachments::Base`, with rate hashes and filename policy on
`Web::AttachmentAccess`. Successful uploads keep `post` on `stored`
so HTTP can redirect to the thread fragment.

Coverage lives in `t/105-attachment-workflow.t`,
`t/118-attachment-download-access.t`, `t/123-attachment-lifecycle.t`,
`t/127-attachment-event.t`, `t/133-web-attachment-access.t`,
`t/152-write-unavailable.t`, and `t/153-lost-response-retry.t`. HTTP route
ownership is covered by `t/104-attachment-controllers.t`.

Uploads are serialized per owner before source storage is written. The default
allowance is 1024 MiB of retained source bytes and 20 uploads awaiting scanning
or content approval.
`GPFORUM_ATTACHMENT_OWNER_MAX_MIB` and `GPFORUM_ATTACHMENT_OWNER_MAX_PENDING`
can also be changed in the administrator configuration form. An intent or an
upload awaiting either malware scanning or human content review
consumes one pending allowance, even when both decisions are outstanding.
Approval or rejection releases the pending allowance once scanning has finished.
Soft deletion retains source bytes and therefore does not release the
retained-byte allowance.
The allowance applies to both post attachments and profile uploads, on either
storage backend. Operator legacy imports remain an administrative operation.
Advisory lock class `2026110201` is reserved for this owner upload allowance.

Author uploads and attachment deletes hold their thread and post under shared
row locks, in that order, and recheck authorship, visibility, deletion and the
thread lock before changing attachment content.

Image previews are separate stored variants produced by the media worker, with
a maximum 1280-pixel side and without cropping. The thumbnail and preview share
one source read. Only a smaller encoded preview is persisted. The thread page
needs no additional database read to render preview URLs. `preview=1280` passes
through the download workflow to delivery, which authorizes the original before
looking up the fixed variant type. Missing variants use the original. Preview
ETags differ from original ETags; HEAD and Range still stream the chosen asset.
See [ADR 0164](../adr/0164-demand-loaded-clients-and-stored-image-previews.md).
