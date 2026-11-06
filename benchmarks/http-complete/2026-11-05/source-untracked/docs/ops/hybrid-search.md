# Hybrid search with local embeddings

Search combines PostgreSQL full-text/trigram results with cosine nearest
neighbors from pgvector. Both lists are filtered for access before fusion.
Reciprocal rank fusion uses `1 / (60 + position)` for each list; a document
in both receives both contributions. Each list contributes at most 50
documents, with the existing lexical candidate limit still applied.
Cosine distance must be at most 0.6. Autocomplete and queries containing
quoted phrases, negation or `OR` retain their lexical behavior.
Inference runs before the database transaction. Both retrieval statements
share one transaction and one timeout setup, adding one query to the search
endpoint's budget (seven statements at most, including request setup).
The cosine HNSW index uses iterative scans with `ef_search=100` to continue
past filtered candidates. Retrieval remains approximate and can return fewer
results when it reaches the scan or statement-time budget.

## Database prerequisite

[pgvector](https://github.com/pgvector/pgvector) is installed separately from
PostgreSQL, including on versions 16–18. Install the package for the server
major before migration 2040. On Homebrew use `brew install pgvector`. With
the PostgreSQL APT repository, for example, use
`sudo apt install postgresql-18-pgvector` for a PostgreSQL 18 server.
CI uses the `pgvector/pgvector:0.8.7-pg16`, `pg17` and `pg18` service images.

The extension is untrusted. `gpforum setup` creates it administratively
before migrating as the ordinary database owner. For a database managed by
hand, run these once as its administrator in the target database,
substituting the migration/data owner's role for `gpforum`:

```sql
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO gpforum;
```

Run `gpforum migrate` with the migration/data owner's credentials, then
reprovision the runtime login using `gpforum api-role --role ROLE --apply`
as described in the [SQL API role runbook](sql-api-role.md). It receives
the three new typed entry points and no table access. The extension and
empty vector projection are installed even when inference is disabled.

## Enable local inference

No embedding server or external inference API is used. The optional Python
environment and model files live on each web/worker host. A compatible
model is [paraphrase-multilingual-MiniLM-L12-v2](https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2),
which produces 384 dimensions and supports Italian. Provision its weights
before starting the application. For example, with writable directories
and internet access during provisioning only:

```sh
python3 -m venv /opt/gpforum-embeddings
/opt/gpforum-embeddings/bin/pip install sentence-transformers
/opt/gpforum-embeddings/bin/python - <<'PY'
from sentence_transformers import SentenceTransformer
model = SentenceTransformer(
    "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
    revision="e8f8c211226b894fcb81acc59f3b34ba3efd5f42",
    trust_remote_code=False,
)
model.save("/opt/gpforum-models/multilingual-minilm")
PY
```

Pin the Python environment in deployment management after validation. Give
the service account read access to the model and executable. Configure the
same immutable weights and key on every web and worker host:

```sh
GPFORUM_SEARCH_EMBEDDING_MODEL_PATH=/opt/gpforum-models/multilingual-minilm
GPFORUM_SEARCH_EMBEDDING_MODEL_KEY=minilm-e8f8c211-prefix2000-v1
GPFORUM_SEARCH_EMBEDDING_PYTHON=/opt/gpforum-embeddings/bin/python
GPFORUM_SEARCH_EMBEDDING_TIMEOUT_SECONDS=5
```

Restart web/outbox workers, then run `gpforum search-rebuild`. Existing
documents receive missing vectors even when the lexical projection is
unchanged. The admin console rebuild uses the same path. Leaving the model
path empty disables inference and preserves lexical search.

Runtime uses `local_files_only=True`, disables Hub/Transformers network
access, and uses CPU inference with one Torch thread. Text travels over
stdin. Each call loads the model in a local process; its timeout includes
startup, inference and exit. Measure startup, CPU/RAM and rebuild throughput
on the actual host before enabling it under traffic. A batch computes its
documents one at a time and holds its outbox handler until it finishes.

Input is the first 2000 characters of title plus body, or of the query.
The model can truncate further at its token limit. Long discussions remain
searchable lexically in full; semantic chunking is not implemented. Evaluate
relevance on real Italian questions before tuning the cutoff or model.

## Updates, failures and rollback

Lexical indexing commits before inference. Updates invalidate the vector;
deletions cascade to it. Publication locks and compares the source
fingerprint, refusing work based on an older projection. Retrieval checks
live visibility, moderation, category and space. Category, author, date,
thread, entity and combined-tag filters also apply to the semantic branch.

Read failures serve lexical results and log a fixed message without input
text. `ranked_search` exposes `semantic_status`: `disabled`, `ok` or
`degraded`. Indexing failures propagate for outbox retry/dead-letter handling;
the lexical projection remains committed. A stale publication is discarded;
the newer canonical event or a rebuild supplies its replacement.

Model keys identify weights **and preprocessing**, not just dimensions.
Change the key when either changes and rebuild. Retrieval never mixes
different keys. There is one vector per document, so a model change replaces
the old one gradually. Deploy the new key consistently across hosts.

To roll back inference, clear the model path on web and worker hosts and
restart them. Keep the additive migration installed; vectors are rebuildable.

`t/853-embedding.t` tests process transport, deadlines and vector validation.
`t/integration/postgres-hybrid-search.t` exercises real pgvector retrieval,
fusion, filters, privacy, stale publication and recovery with deterministic
fixture vectors. These verify mechanics, not pretrained-model relevance.
