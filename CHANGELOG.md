# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Candidate version: **0.2.0**. This remains an in-tree candidate and is not a
registry publication or separate-repository release.

### Added
- Monotonic committed revisions via `state-revision`, atomic value/revision reads via `state-value-at-revision`, revision-conditional mutation via `state-set-if-revision`, and `:expected-revision` transaction preconditions.
- Typed `state-revision-conflict` and `state-transaction-conflict` conditions with inspectable operation and revision context.
- Structurally shared persistent patch application plus an eager persistent correctness oracle.
- Frozen strict-state snapshots and explicit value-ownership helpers for Elm-style state semantics.
- Deterministic transactional/eager/shared differential traces and retained-snapshot tests.
- Inspectable observer-notification failures with state/key/callback/value/cause context.
- Path-independent CLPM bundle metadata and independent ASDF test execution.
- Typed patch validation conditions and an internal conservative composition/inversion model with deterministic hash-table/plist law tests.

### Changed
- Transactions now reserve a state for the outer dynamic boundary without holding the state lock across user code; foreign managed reads/writes fail closed while same-state nesting still joins the outer transaction.
- Managed reads, owned values, snapshots, and state cloning now perform backing-store access under the state lock; extensible copy callbacks run only after a built-in container snapshot has been detached and the lock released. Backend conversion remains revision-neutral representation metadata.
- `:merge`/`:update` application-state patches use an owned value plus expected committed revision, preventing lost writes while keeping update callbacks outside internal locks.
- Structurally shared commits atomically capture mutable sources, reject foreign transaction ownership before patch callbacks, detach mutable built-in branches before freezing, and retain path sharing between frozen descendants.
- Clarified transaction nesting, rollback, observer ordering, revision, and snapshot ownership semantics with an explicit semantic matrix.
- Public `application-state-data` is now a deprecated owned-snapshot read; explicit low-level live representation access remains in `cl-state.core`.
- Initial project structure with state management, patches, transactions, undo/redo, and observers is retained as the 0.1.x compatibility surface.
- Comprehensive test suite uses FiveAM and fails the ASDF test operation on real failures.
- Patch normalization now validates paths, operations, and operation-specific values before mutation; `diff-states` round-trips additions/changes/deletions across hash-table and plist snapshots using the canonical deletion shorthand while accepting the historical `:removed` deletion form.
- Formal patch composition remains internal: adjacent same-path `:set`/`:remove` patches may collapse to the later patch, while `:merge`, opaque `:update`, and ancestor/descendant overlaps preserve sequential order and report explicit non-collapse conflicts.
- Patch inversion requires captured prior state; raw functional `:update` is explicitly non-invertible/non-serializable, while a captured concrete change record can be inverted without re-running callback code.

- Renamed `cl-state.undo:undo` and `cl-state.undo:redo` to `history-undo` and `history-redo` to avoid naming conflicts with transaction-based undo/redo
- Exported `undo` and `redo` from `cl-state.tx` for application-state based undo/redo operations

### Fixed
- Observer callbacks are no longer invoked while the application-state lock is held; registry snapshots are captured under lock and delivered afterward.
- Extensible `copy-state-value` / `freeze-state-value` callbacks and patch update functions are no longer invoked while an internal state lock is held.
- Structurally shared frozen descendants no longer alias mutable built-in source branches, and shared commits no longer ingest another thread's uncommitted transaction state.
- Public component-path lookup now participates in the managed transaction-ownership read boundary.
- Direct update races now report a stale revision conflict instead of silently overwriting a newer committed value.
- Fixed undo/redo history behavior to return the correct state after operations
- Fixed API exports to properly expose transaction-based undo/redo functions
- Updated tests to use the correct undo/redo function names
- Managed transaction/shared change records no longer use user-storable keywords as internal missing/deletion sentinels, so literal `:not-present` and `:elmtui-delete-path` values survive rollback/undo/redo; observer-facing compatibility markers are unchanged.
- `diff-states` deletion output now applies as an actual deletion instead of storing `:removed` as a value.

## [0.1.0] - 2025-01-14

### Added
- Initial release of cl-state library
- State container with hash-table and plist backends
- Patch system for applying changes to state
- Transaction support for atomic state updates
- Undo/redo functionality with history tracking
- Observer pattern for state change notifications
- Thread-safe operations using bordeaux-threads
- Full test coverage using FiveAM framework

### API Documentation

#### Core State API
- `make-state` - Create a new application state
- `state-ref` - Access state values by path
- `state-set` - Set state values by path
- `get-state` - Convenience wrapper for state-ref

#### Patch API
- `make-patch` - Create a patch structure
- `apply-patch` - Apply a single patch to state
- `apply-patches` - Apply multiple patches to state
- `merge-patch` - Merge a patch into state (functional - returns modified state)
- `merge-patches` - Merge multiple patches into state (functional - returns modified state)
- `diff-states` - Compute differences between two states

#### Transaction API
- `make-tx` - Create a transaction
- `with-transaction` - Execute state updates in a transaction
- `undo` - Undo the last transaction (works on application-state)
- `redo` - Redo the last undone transaction (works on application-state)

#### History API
- `make-history` - Create a new history structure
- `push-snapshot` - Push a state snapshot to history
- `history-undo` - Undo to previous state in history
- `history-redo` - Redo to next state in history
- `history-past` - Access past states in history
- `history-future` - Access future states in history

#### Observer API
- `add-observer` - Add an observer for state changes
- `remove-observer` - Remove an observer
- `notify-observers` - Notify all observers of state changes

### Design Decisions

#### Functional vs Imperative API
The `merge-patch` and `merge-patches` functions follow a **functional API design**:
- They return the modified state for chaining
- This enables functional programming patterns
- Error handling is done via conditions/signals

#### Undo/Redo Dual API
The library provides two separate undo/redo implementations:
1. **Transaction-based** (`cl-state.tx:undo`/`redo`) - Works on `application-state` objects, integrates with transactions
2. **History-based** (`cl-state.undo:history-undo`/`history-redo`) - Standalone history data structure for general use

Both serve different purposes and are kept separate for clarity.

### Known Issues
- FiveAM test framework may treat bare expressions in test bodies as implicit checks expecting NIL
- Workaround: Wrap expressions in `progn` with explicit `nil` return or bind results to variables

### License
MIT License - See LICENSE file for details
