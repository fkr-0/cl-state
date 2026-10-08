# cl-state

A state management library for Common Lisp inspired by Elm Architecture and Redux patterns. Provides state containers, patches, transactions, undo/redo, and observers.

## Release status

The current in-tree candidate version is **0.2.0** for both `cl-state` and
`cl-state-tests`. This is release-candidate metadata only: the library has not
been published to Quicklisp, Ultralisp, CLPM, or a separate source repository.

The qualified implementation boundary is SBCL on the repository's POSIX/Linux
CLPM environment. Other Common Lisp implementations and non-POSIX platforms
have not yet been qualified. The primary public convenience package is
`cl-state.api`; focused packages such as `cl-state.core`, `cl-state.patch`, and
`cl-state.tx` expose lower-level contracts.

## Features

- **State Container**: Thread-safe application state with hash-table or plist backends
- **Patch System**: Apply changes to state using a declarative patch format
- **Transactions**: Atomic state updates with automatic change tracking
- **Undo/Redo**: Full undo/redo support for transactions and standalone history
- **Observers**: React to state changes with observer pattern
- **Functional API**: Pure functions for state manipulation

## Installation

### Using CLPM

```bash
cd /path/to/cl-state
clpm bundle install
clpm bundle exec --with-client sbcl -- \
  --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-system "cl-state")'
```

### Using a Quicklisp local-project checkout

This describes local ASDF discovery only; it does not imply registry
publication.

Add `cl-state` to your Quicklisp local-projects directory:

```bash
ln -s /path/to/cl-state ~/quicklisp/local-projects/cl-state
```

Then in your Lisp:

```lisp
(ql:quickload :cl-state)
(use-package :cl-state.api)
```

## Quick Start

```lisp
;; Create a new state
(defparameter *app-state* (make-state))

;; Set nested values by passing a path as the KEY argument
(state-set *app-state* '(:user :name) "Alice")
(state-set *app-state* '(:user :age) 30)

;; Get values
(get-state *app-state* '(:user :name)) ; => "Alice"

;; Use transactions for atomic updates
(with-transaction (*app-state* :name :update-user)
  (state-set *app-state* '(:user :name) "Bob")
  (state-set *app-state* '(:user :age) 31))

;; Undo the transaction
(undo *app-state*)

;; Redo the transaction
(redo *app-state*)

;; Add observers
(add-observer *app-state* :user
  (lambda (old new)
    (format t "User changed from ~A to ~A~%" old new)))
```

## API Reference

### Core State Operations

#### `make-state` (&key initial backend)
Create a new application state.

```lisp
(make-state)
(make-state :initial '((:foo . 42)) :backend :plist)
```

#### `state-ref` (state key &optional default)
Access a value in the state by path.

```lisp
(state-ref *app-state* '(:user :name))
(state-ref *app-state* '(:missing) :default-value)
```

#### `state-set` (state key value)
Set a value in the state by path.

```lisp
(state-set *app-state* '(:user :name) "Alice")
```

#### `state-revision` (state)
Return the last committed monotonic revision of an application state. Unlike the
legacy per-mutation `application-state-version`, revision is a commit identity
suitable for optimistic concurrency checks.

```lisp
(state-revision *app-state*) ; => 0, 1, 2, ...
```

#### `state-value-at-revision` (state key &optional default)
Atomically return an owned value and the committed revision that produced the
observation. The call fails with `state-transaction-conflict` rather than pairing
another thread's in-progress transaction value with the previous commit id.

```lisp
(multiple-value-bind (name revision)
    (state-value-at-revision *app-state* '(:user :name))
  (declare (ignore name revision)))
```

#### `state-set-if-revision` (state expected-revision key value)
Compare-and-set a path against the committed revision. A stale expected revision
signals `state-revision-conflict` before model data, version, revision, log,
history, or observers change.

```lisp
(multiple-value-bind (name revision)
    (state-value-at-revision *app-state* '(:user :name))
  (state-set-if-revision *app-state* revision '(:user :name)
                         (string-upcase name)))
```

### Patch Operations

#### `make-patch` (&key path op value)
Create a patch structure.

```lisp
(make-patch :path '(:user :name) :op :set :value "Alice")
```

#### `apply-patch` (state patch)
Apply a single patch to state.

```lisp
(apply-patch *app-state* (make-patch :path '(:foo) :op :set :value 42))
```

#### `merge-patch` (state patch)
Merge a patch into state (functional API - returns modified state).

```lisp
(setf *app-state*
      (merge-patch *app-state* '((:user :name) "Alice")))
```

#### `merge-patches` (state patches)
Merge multiple patches into state (functional API - returns modified state).

```lisp
(setf *app-state*
      (merge-patches *app-state* '(((user :age) 30)
                                 ((settings :theme) :dark))))
```

#### Patch normalization and algebra

`patch` is the normalized representation used by patch application. Public
constructors and normalization accept either a `patch` object or the historical
`(path value)` shorthand. A path is one non-`NIL` symbol or a non-empty proper
list of non-`NIL` symbols. Invalid formats, paths, operations, and operation
values fail before mutation with `invalid-patch-format`, `invalid-patch-path`,
`invalid-patch-operation`, or `invalid-patch-value`, all subclasses of
`patch-validation-error` with inspectable input/reason data.

| Input / operation | Accepted contract | Application / change-record semantics |
| --- | --- | --- |
| `(path value)` | Historical shorthand for `:set`; `:elmtui-delete-path` and legacy `:removed` are reserved deletion shorthands. | Normalizes before eager, managed, or structurally shared application. Use an explicit `:set` patch to store either reserved keyword literally. |
| `:set` | Any value. | Replaces the addressed value. |
| `:remove` | Value slot is ignored. | Removes an existing path; a missing path is a logical no-op. |
| `:merge` | Value must be a proper list. | Prepends the patch list to the current list value. Its result depends on current state. |
| `:update` | Value must be a function designator. | The callback receives an owned value outside internal state locks; the operation is opaque to formal composition/inversion. |
| `diff-states` | Hash-table or plist state snapshots. | Emits shorthand patches whose sequential application reconstructs the new state, including canonical deletion shorthand. |
| Transaction/shared change record | `(path old new)` logical transition. | Missing-old and deleted-new are represented by private opaque markers, so legitimate values such as `:not-present` and `:elmtui-delete-path` remain lossless through rollback/undo/redo. Observer callbacks retain their historical external marker values. |

The conservative composition model is intentionally internal while its caller
surface is still being evaluated. It preserves sequential application rather
than inventing state-independent algebra:

| Path relation / operations | Composition law |
| --- | --- |
| Same path, both `:set`/`:remove` | The right patch subsumes the left patch. |
| Same path with `:merge` | Preserve both in order and report a state-dependent conflict; do not collapse or reorder. |
| Same path with `:update` | Preserve both in order and report an opaque-update conflict; composition never invokes the callback. |
| Disjoint paths | Preserve order; no conflict is required. |
| Ancestor / descendant paths | Preserve both in order and report an overlapping-path conflict. |

Inversion is likewise explicit. `:set`, `:remove`, and `:merge` can produce a
restoring patch only when the prior value/presence was captured. A raw
functional `:update` is neither assumed invertible nor serializable and returns
an explicit non-invertible result. Once an update has actually committed, its
captured concrete change record can be inverted without interpreting or
re-running the callback. These algebra helpers operate only on logical patches
and captured values; observer delivery, transaction ownership, revision/CAS,
callback-lock, and history metadata remain runtime concerns.

### Transaction Operations

#### `with-transaction` ((app &key name expected-revision) &body body)
Execute state updates in a transaction. `expected-revision`, when supplied, is
checked atomically before the outer state reservation is established. A stale
precondition signals `state-revision-conflict` and the body does not run.

```lisp
(let ((revision (state-revision *app-state*)))
  (with-transaction (*app-state*
                     :name :update-user
                     :expected-revision revision)
    (state-set *app-state* '(:user :name) "Bob")
    (state-set *app-state* '(:user :age) 31)))
```

#### `undo` (app)
Undo the last transaction (works on application-state).

```lisp
(undo *app-state*)
```

#### `redo` (app)
Redo the last undone transaction (works on application-state).

```lisp
(redo *app-state*)
```

### History Operations

#### `make-history` ()
Create a new history structure.

```lisp
(defparameter *hist* (make-history))
```

#### `push-snapshot` (hist state)
Push a state snapshot to history.

```lisp
(push-snapshot *hist* *current-state*)
```

#### `history-undo` (hist)
Undo to previous state in history.

```lisp
(history-undo *hist*)
```

#### `history-redo` (hist)
Redo to next state in history.

```lisp
(history-redo *hist*)
```

### Observer Operations

#### `add-observer` (state key fn)
Add an observer for state changes at key.

```lisp
(add-observer *app-state* :user
  (lambda (old new)
    (format t "User changed: ~A -> ~A~%" old new)))
```

#### `remove-observer` (state key fn)
Remove an observer.

```lisp
(remove-observer *app-state* :user *observer-fn*)
```

## Mutation, Revision, Transaction, and Observer Policy

CL-STATE now exposes two intentionally different counters. `application-state-version`
is the compatibility mutation counter: each successful managed logical mutation
increments it, transaction rollback restores it, and undo/redo leave it unchanged.
`state-revision` is the monotonic committed-transition identity used for optimistic
concurrency. Do not use `application-state-version` as a commit id.

| Operation | `application-state-version` | `state-revision` | Observer delivery / concurrency |
| --- | --- | --- | --- |
| Direct `state-set` or `:set` patch | +1 | +1 | Mutation is protected by the state lock; observers run afterward, never while that lock is held. |
| Direct existing-path `:remove` | +1 | +1 | Same post-lock observer rule. A missing remove changes neither counter and sends no observer event. |
| Direct `:merge` / `:update` patch | +1 | +1 | Input plus revision are captured first; `:update` receives an owned value outside the lock; a concurrent commit causes `state-revision-conflict` rather than a lost write. |
| Internal structurally shared persistent commit | +1 per logical patch on the returned state | +1 once on the returned state | Source is unchanged. A mutable source is atomically captured and detached before freeze/update callbacks; a frozen source may share untouched branches. Foreign transaction ownership fails before patch callbacks. |
| Successful outer transaction | +1 per logical mutation | +1 once per outer commit, including an empty commit | The state is reserved for the transaction without holding its lock across the body. Notifications happen after reservation release in mutation order. |
| Same-state nested transaction | Included in outer mutation count | No extra increment | Joins the outer boundary; no savepoint or extra history entry. An optional nested expected revision is checked against the still-current committed revision. |
| Different-state nested transaction | Per-state | +1 on each independently committed state | Each state has an independent reservation; no cross-state lock is held across either body. |
| Stale transaction precondition / rollback | Restored / unchanged | Unchanged | Body does not run for a stale entry precondition. Rollback restores model, version, transaction-local log, history, and redo metadata and sends no observer events. |
| Successful `undo` / `redo` replay | Unchanged | +1 | Historical compatibility is preserved: no observer delivery and no version increment. No-op replay changes neither counter. |
| Backend conversion | Unchanged | Unchanged | Physical representation only; protected by the state lock and excluded by a foreign transaction reservation. |
| Observer add/remove | Unchanged | Unchanged | Runtime metadata; registry mutation is lock-protected and remains allowed on frozen snapshots. |
| Frozen/strict managed mutation | Unchanged | Unchanged | Rejected before logical mutation. |
| Expert raw backing-store mutation | Bypassed | Bypassed | `cl-state.core:application-state-data` is intentionally outside managed locking, revision, observer, history, and strict-mode guarantees. |

### Optimistic concurrency

Use `state-value-at-revision` when a decision depends on a value and must later be
committed conditionally. It returns an owned value and its committed revision from
one protected observation. `state-set-if-revision` checks that revision under the
same lock as its mutation. A stale write signals `state-revision-conflict`; the
condition exposes the state, operation, expected revision, and actual revision.
The stale path has zero CL-STATE logical side effects and delivers no observers.

`with-transaction` accepts `:expected-revision` for the same entry precondition.
An outer transaction first validates the expected revision and reserves the state
with an opaque ownership token. Managed reads and writes from another thread then
signal `state-transaction-conflict` rather than observing or modifying the
in-progress model. Reads and writes performed by the owning dynamic transaction
continue normally. `state-revision` itself reports the last committed revision and
therefore remains useful while a transaction is in progress.

`state-ref` performs its managed lookup under the state lock, but a container value
returned from it is still borrowed once the call returns. Public component-path
lookup follows the same managed read boundary rather than bypassing transaction
ownership. Use `state-value` for an owned path value, `state-snapshot` for an owned
whole model, or `state-value-at-revision` when the value must be paired with a
commit identity. Managed owned reads and snapshots also reject a foreign
in-progress transaction. The public `cl-state.api:application-state-data` facade
delegates to the owned snapshot boundary; it is not the live representation.

### Callback and commit ordering

Observer registries are captured under the state lock and callbacks are invoked
after that lock has been released. Direct observer failures remain post-commit:
notification stops immediately and CL-STATE re-signals `observer-notification-error`
with the state, key, callback, old/new values, phase, and original cause, while both
the logical mutation and its revision increment remain committed. Transaction
observers are likewise delivered only after the outer commit and reservation
release; a notification failure never rolls the transaction back.

Patch `:update` functions are also user callbacks. They receive an owned current
value and run outside internal state locks. Their result is installed with the
captured expected revision, so another commit during callback execution produces a
typed stale conflict instead of overwriting newer state.

The extensible value protocol follows the same callback rule. For managed owned
reads, snapshots, cloning, and the mutable-to-frozen shared-commit boundary,
CL-STATE first detaches built-in container structure while holding the state lock,
then invokes custom `copy-state-value` / `freeze-state-value` methods after release.
A custom value type that remains mutable must still implement the value protocol
correctly; the expert raw backing-store escape hatch remains outside this guarantee.

For the internal structurally shared commit engine, the first branch from a mutable
application state establishes an ownership boundary and therefore does not alias
untouched mutable built-in branches. Once the source is already frozen, later
frozen descendants retain path-level structural sharing for untouched branches.

Hash-table and plist application-state backends have the same managed path,
revision, patch, transaction, rollback, undo/redo, and observer guarantees. Their
physical representation and iteration/key order are not semantic guarantees.
Strict Elm mode and frozen snapshots reject managed logical-state mutation before
it occurs. Low-level callers that explicitly select `cl-state.core` representation
access are responsible for synchronization and metadata integrity themselves.

## Testing

Run the test suite:

```bash
clpm bundle exec --with-client sbcl -- \
  --noinform --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:test-system "cl-state")'
```

## Dependencies

- `alexandria` - Common utilities
- `uiop` - Portable Operating System Interface
- `bordeaux-threads` - Threading support

## Development

### Project Structure

```
cl-state/
├── src/state/          # Source files
│   ├── packages.lisp   # Package definitions
│   ├── utils.lisp      # Utility functions
│   ├── value-protocol.lisp # Value ownership/copy protocol
│   ├── core.lisp       # Core state operations
│   ├── tx.lisp         # Transaction support
│   ├── patch.lisp      # Normalization and patch application
│   ├── algebra.lisp    # Internal composition/inversion laws
│   ├── persistent.lisp # Persistent patch application
│   ├── undo.lisp       # Undo/redo history
│   ├── observer.lisp   # Observer pattern
│   └── api.lisp        # Public API re-exports
├── tests/              # Test files, including algebra-tests.lisp
├── cl-state.asd        # ASDF system definition
├── clpmfile            # CLPM bundle configuration
├── rt-state.sh         # Test runner script
└── run-tests-clpm-state.lisp  # Test entry point
```

### Code Style

- Follow Common Lisp conventions
- Use descriptive variable and function names
- Document public APIs with docstrings
- Write tests for all new features

## License

MIT License - See LICENSE file for details

## Contributing

`cl-state` is developed in this standalone repository. ElmTUI consumes a
separately pinned submodule revision; its checkout and manifests must not be
modified as part of this library's release preparation. No registry publication
is implied by a release candidate.

When preparing changes:

1. Add tests for new functionality.
2. Ensure `asdf:test-system "cl-state"` passes from the library CLPM bundle.
3. Run the ElmTUI integration release gate before treating the change as a
   release candidate.

## Reproducible source archive

After committing scoped changes, create a tracked-source-only archive and its
SHA256 digest without publishing or creating a tag:

    bash scripts/release-source.sh /tmp/cl-state-0.2.0.tar.gz

To extract it into an isolated temporary directory and run the standalone ASDF
test operation from that extracted copy (requires CLPM and SBCL):

    COLD_TEST=1 bash scripts/release-source.sh /tmp/cl-state-0.2.0-cold.tar.gz

The archive uses `git archive HEAD` and `gzip -n` to avoid embedding the
checkout path or gzip timestamps. Untracked `bridge.yml` is intentionally not
bundled; CLPM and ASDF metadata are committed standalone inputs. The consumer
integrator must separately verify and update ElmTUI's pinned submodule commit.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.

## Documentation

For detailed API documentation and examples, see the inline documentation in the source files or generate documentation using your preferred Common Lisp documentation tool (e.g., `cl-doc`).

## Common Lisp Documentation Tools

If you're looking for documentation generation tools for Common Lisp, here are some popular options:

- **[SphinxCL](https://github.com/symbolic/sphinxcl)** - Sphinx-based documentation generator for Common Lisp
- **[cl-doc](https://github.com/Shinmera/cl-doc)** - Documentation generator from docstrings
- **[ documenting-common-lisp ](https://gigamonkeys.com/documentation/)** - Guide to documenting Common Lisp code

## Acknowledgments

Inspired by:
- Elm Architecture (The Elm Architecture)
- Redux (JavaScript state management)
- re-frame (ClojureScript framework)

## Contact

For issues, questions, or contributions, please visit the project repository or contact the maintainers.
