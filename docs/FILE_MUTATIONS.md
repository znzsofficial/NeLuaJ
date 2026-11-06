# File mutation service

## Ownership

`mods/files/FileMutationService.lua` is the shared entry for synchronous and asynchronous
Agent file tools and file undo/redo. ToolRegistry supplies the mutation classification.
ToolExecutor delegates rather than starting a second snapshot/write pipeline.

`FileMutationEngine` owns the process-wide token, SHA-256 versions, same-directory
staging, strict atomic publication, persistent journals, conditional compensation,
history, result lookup and restart recovery. Scope, working directory and storage
are captured before scheduling; a running publication completes in its original scope.
External writers do not participate in the token protocol: Java filesystem APIs do
not provide atomic hash-compare-and-rename against those writers.

## Results and cancellation

Compatibility callers receive `(text, ok, result)`. The third result carries the
transaction ID, scope, outcome, commit state, actual path effects, history status,
durability, error code and warnings. Chat messages retain `tool_ok` and `file_result`.
The UI uses structured status instead of guessing from error words in file content.

Cancellation before publication prevents the write. Once publication starts, the
transaction finishes or compensates independently of chat continuation. The worker
releases the native token before dispatching the UI callback. Results are queryable
and replayed from durable storage; UI acknowledgments prevent repeated application.

## Editor

Editor saves use the same native coordinator and expected disk version. Each binding
has a document identity and epoch. Successful AI writes force a disk reload of an
affected current document; switching to another document never forces navigation back.
Changes typed during the operation are saved to private `editor-drafts` before reload:
eight slots, at most 1 MiB each. The File menu exposes restoration into the buffer,
without automatically overwriting disk. Draft failures are surfaced as warnings.

Recovery captures UI state without saving stale buffers. Historical effects are
checked against current versions before replay so an old delete/rename cannot act
on a subsequently recreated document. Partial results apply only verified effects;
unknown paths retain their buffer and remain recovery work.

## Persistence and migration

PREPARED journals contain bounded reversible snapshots before publication. Recovery
validates schema, IDs, scope, manifests, paths, reserved staging names and hashes;
unknown versions are never blindly overwritten. Publication and compensation are
not a general multi-file atomic transaction. Directory replacement may expose an
intermediate absence. Unsupported atomic moves fail rather than silently downgrading.
Directory fsync capability is separately reported.

Recovery uses persistent sequence ordering. Active recovery material is retained;
completed journals no longer referenced by history are reduced to result tombstones.
User history is bounded to ten entries / 4 MiB. Snapshots are limited to 1.5 MiB and
2000 entries. Result tombstones and UI acknowledgment records remain for deduplication.

Legacy `changesets.json` import recomputes hashes from validated text/base64 snapshots,
preserves undo/redo order and uses deterministic import IDs. Source files remain as
backups. Invalid scopes, multiple different sources and occupied new history are
isolated with explicit reports rather than overwritten. Original text-only legacy
snapshots cannot reconstruct bytes that were already lost before migration.

## Verification and remaining acceptance

Lua tests cover entry routing, cancellation, identity, recovery replay, draft handling
and structured UI status. Native fault injection covers staging/publication failures,
external changes during compensation, interrupted recovery and history projection,
corrupt journals, bounded history and legacy migration.

Android device acceptance remains necessary: actual shared/external storage providers,
low space/permission failures, real process death and restart, Activity recreation,
rapid project/tab changes and typing during AI operations. Desktop tests and APK builds
do not establish those guarantees. Other IDE file-management and arbitrary MCP/sandbox
writes are external writers unless explicitly routed through this coordinator.
