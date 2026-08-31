;;; cl-state/src/state/core.lisp
(in-package :cl-state.core)

(defstruct application-state
  (data (make-hash-table :test 'equal))
  (backend :hash-table)
  (lock (bt:make-lock "cl-state.lock"))
  (log nil)
  (history nil)
  (undone nil)
  (version 0)
  (revision 0)
  (observers nil)
  (frozen-p nil)
  (transaction-owner nil))

(defgeneric %deliver-state-change (state key old new &key phase)
  (:documentation
   "Internal one-way protocol for delivering an already-committed state change.

CORE, PATCH, TX, and persistent commit code depend only on this protocol. The
observer layer installs the APPLICATION-STATE method later, keeping callback
registry and condition semantics out of the mutation layers."))

(defmethod %deliver-state-change ((state t) key old new &key phase)
  (declare (ignore state key old new phase))
  nil)

(setf (documentation 'application-state-data 'function)
      "Low-level representation accessor for APPLICATION-STATE.

This accessor exposes the live backing container and is intentionally confined
to CL-STATE.CORE. Application code should use STATE-REF for a borrowed path
read, STATE-VALUE for an owned path value, or STATE-SNAPSHOT for an owned whole
model. Destructive mutation through this representation accessor bypasses state
locking, versioning, observers, history, and strict snapshot guarantees.")

(defparameter *state-mutation-policy* :allow
  "Dynamic policy for APPLICATION-STATE mutation through the CL-STATE API.

:ALLOW permits mutation. :FORBID signals STATE-MUTATION-FORBIDDEN before a
supported mutator changes logical state. ElmTUI binds :FORBID while executing
strict-Elm user decision/view/subscription code, then restores :ALLOW for the
internal fresh-state commit.")

(define-condition state-mutation-forbidden (error)
  ((state :initarg :state :reader state-mutation-forbidden-state)
   (path :initarg :path :initform nil :reader state-mutation-forbidden-path)
   (operation :initarg :operation :initform :mutation
              :reader state-mutation-forbidden-operation))
  (:documentation
   "Signaled when a supported CL-STATE mutator is used during a read-only state phase.")
  (:report
   (lambda (condition stream)
     (format stream "State mutation ~S is forbidden~@[ at path ~S~]; the state is frozen or the current state policy is read-only."
             (state-mutation-forbidden-operation condition)
             (state-mutation-forbidden-path condition)))))

(define-condition state-conflict (error)
  ((state :initarg :state :reader state-conflict-state)
   (operation :initarg :operation :reader state-conflict-operation))
  (:documentation "Base condition for optimistic/concurrent managed-state access conflicts."))

(define-condition state-revision-conflict (state-conflict)
  ((expected-revision :initarg :expected-revision
                      :reader state-revision-conflict-expected-revision)
   (actual-revision :initarg :actual-revision
                    :reader state-revision-conflict-actual-revision))
  (:documentation "Signaled before mutation when an optimistic revision precondition is stale.")
  (:report
   (lambda (condition stream)
     (format stream "State revision conflict during ~S: expected ~D, actual ~D."
             (state-conflict-operation condition)
             (state-revision-conflict-expected-revision condition)
             (state-revision-conflict-actual-revision condition)))))

(define-condition state-transaction-conflict (state-conflict) ()
  (:documentation "Signaled when a managed operation requires a stable state owned by another transaction.")
  (:report
   (lambda (condition stream)
     (format stream "State is owned by another transaction during ~S."
             (state-conflict-operation condition)))))

(define-condition invalid-state-path (error)
  ((path :initarg :path :reader invalid-state-path-path))
  (:documentation "Signaled when a CL-STATE operation receives an invalid logical path.")
  (:report
   (lambda (condition stream)
     (format stream "Invalid state path ~S. Expected a symbol or proper list of non-NIL symbols."
             (invalid-state-path-path condition)))))

(defvar +state-missing-value+ (gensym "CL-STATE-MISSING-") "Opaque internal marker for an absent value in managed change records.")

(defvar +state-deleted-value+ (gensym "CL-STATE-DELETED-") "Opaque internal marker for a deletion in managed change records.")

(defun %state-missing-value-p (value) (eq value +state-missing-value+))

(defun %state-deleted-value-p (value) (eq value +state-deleted-value+))

(defun %external-state-change-value (value) (cond ((%state-missing-value-p value) :not-present) ((%state-deleted-value-p value) :elmtui-delete-path) (t value)))

(setf (documentation 'state-mutation-forbidden 'type)
      "Condition signaled when supported state mutation is forbidden by the current dynamic policy."
      (documentation 'state-mutation-forbidden-state 'function)
      "Return the APPLICATION-STATE whose mutation was rejected."
      (documentation 'state-mutation-forbidden-path 'function)
      "Return the state path associated with a rejected mutation, or NIL when not path-specific."
      (documentation 'state-mutation-forbidden-operation 'function)
      "Return the operation keyword describing the rejected state mutation.")

(defun assert-state-mutation-allowed (state &key path (operation :mutation))
  "Signal STATE-MUTATION-FORBIDDEN when STATE is frozen or dynamically read-only."
  (when (and (application-state-p state)
             (or (application-state-frozen-p state)
                 (eq *state-mutation-policy* :forbid)))
    (error 'state-mutation-forbidden
           :state state
           :path path
           :operation operation))
  state)

(defun %normalize-backend (backend)
  (ecase backend
    (:hash-table :hash-table)
    (:plist :plist)))

(defun %coerce-initial (initial backend)
  (let ((backend* (%normalize-backend backend)))
    (cond
      ((null initial) (coerce-data nil backend*))
      ((application-state-p initial)
       (coerce-data (state-snapshot initial) backend*))
      ((hash-table-p initial)
       (coerce-data (copy-state-value initial) backend*))
      ((listp initial)
       (when (and (eq backend* :hash-table)
                  (not (cl-state.utils::%plist-like-p initial)))
         (error "Expected plist-like initial state for :HASH-TABLE backend, got ~S" initial))
       (coerce-data (copy-state-value initial) backend*))
      (t (error "Unsupported initial state type ~S" (type-of initial))))))

(defun make-state (&key (initial nil) (backend :hash-table))
  "Create an application state object.

Arguments:
+ ~:initial~ — The initial data to populate the state. This can be any data structure compatible with the chosen backend.
+ ~:backend~ — The backend type for storing the state. Defaults to ~:hash-table~. Other supported backends depend on your implementation of ~%normalize-backend~.

Returns:
+ A new application state object created by ~make-application-state~, initialized with the given data and backend.

Usage:
  (make-state :initial '((:foo . 42) (:bar . 99)))
  (make-state :initial '((:foo . 42)) :backend :alist)

Notes:
+ All arguments are keyword arguments; you must use ~:initial~ and ~:backend~ when calling the function.
+ Supported mutable containers in ~:initial~ are recursively copied before storage, so the new state owns its container graph.
+ The function expects that ~%normalize-backend~ and ~%coerce-initial~ are defined elsewhere and handle backend normalization and data coercion.

See Also:
+ ~%normalize-backend~
+ ~%coerce-initial~
+ ~make-application-state~
"

  (let* ((backend* (%normalize-backend backend))
          (data (%coerce-initial initial backend*)))
    (make-application-state :data data :backend backend*)))

(defun set-application-state-backend (state backend)
  "Convert STATE's physical representation without changing logical revision."
  (assert-state-mutation-allowed state :operation :set-backend)
  (bt:with-lock-held ((application-state-lock state))
    (%assert-state-write-available state :set-backend)
    (let* ((backend* (%normalize-backend backend))
           (data (coerce-data (application-state-data state) backend*)))
      (setf (application-state-data state) data
            (application-state-backend state) backend*)))
  state)

(defvar *transaction-active* nil
  "True while a CL-STATE transaction boundary is active.")

(defvar *transaction-states* nil
  "Stack of APPLICATION-STATE values currently owned by transaction boundaries.")

(defvar *transaction-tokens* nil
  "Dynamic alist mapping transaction-owned states to opaque ownership tokens.")

(defun transaction-active-p (&optional state)
  "Return true when a transaction is active, optionally for STATE specifically."
  (and *transaction-active*
       (or (null state)
           (member state *transaction-states* :test #'eq))))

(defun %transaction-token (state)
  (cdr (assoc state *transaction-tokens* :test #'eq)))

(defun %assert-state-write-available (state operation)
  "Reject a managed stable-state operation while another transaction owns STATE."
  (let ((owner (application-state-transaction-owner state))
        (token (%transaction-token state)))
    (when (and owner (not (eq owner token)))
      (error 'state-transaction-conflict
             :state state
             :operation operation)))
  state)

(defun %assert-state-revision (state expected-revision operation)
  "Check EXPECTED-REVISION against STATE while its lock is held."
  (when expected-revision
    (check-type expected-revision (integer 0 *))
    (let ((actual (application-state-revision state)))
      (unless (= expected-revision actual)
        (error 'state-revision-conflict
               :state state
               :operation operation
               :expected-revision expected-revision
               :actual-revision actual))))
  state)

(defun assert-state-revision (state expected-revision &key (operation :revision-check))
  "Atomically require STATE to have EXPECTED-REVISION or signal STATE-REVISION-CONFLICT."
  (check-type expected-revision (integer 0 *))
  (bt:with-lock-held ((application-state-lock state))
    (%assert-state-revision state expected-revision operation)))

(defun state-revision (state)
  "Return STATE's monotonic logical commit revision."
  (bt:with-lock-held ((application-state-lock state))
    (application-state-revision state)))

(defun %detach-state-value-spine (value)
  "Copy built-in container structure without invoking extensible value callbacks.

This helper is safe while an internal state lock is held. Custom leaf objects
remain shared only until COPY-STATE-VALUE or FREEZE-STATE-VALUE runs after the
lock is released."
  (typecase value
    (hash-table
     (let ((copy (make-hash-table :test (hash-table-test value)
                                  :size (hash-table-size value)
                                  :rehash-size (hash-table-rehash-size value)
                                  :rehash-threshold (hash-table-rehash-threshold value))))
       (maphash (lambda (key item)
                  (setf (gethash key copy)
                        (%detach-state-value-spine item)))
                value)
       copy))
    (cons
     (cons (%detach-state-value-spine (car value))
           (%detach-state-value-spine (cdr value))))
    (vector
     (let ((copy (copy-seq value)))
       (dotimes (index (length copy) copy)
         (setf (aref copy index)
               (%detach-state-value-spine (aref value index))))))
    (t value)))

(defun %copy-observer-registry (observers)
  "Copy observer registry cons structure without invoking callbacks."
  (mapcar (lambda (entry)
            (cons (car entry) (copy-list (cdr entry))))
          observers))

(defun deep-copy-data (data)
  "Compatibility alias for COPY-STATE-VALUE.

New state-boundary code should call COPY-STATE-VALUE explicitly so custom leaf
specializations participate in ownership transfer."
  (copy-state-value data))

(defun deep-copy-application-state (app)
  "Return an independent mutable state copied from one stable managed view.

Built-in container spines are detached while APP is locked; extensible
COPY-STATE-VALUE methods run only after that lock has been released."
  (multiple-value-bind (data backend log history undone version revision observers)
      (bt:with-lock-held ((application-state-lock app))
        (%assert-state-write-available app :deep-copy)
        (values (%detach-state-value-spine (application-state-data app))
                (application-state-backend app)
                (%detach-state-value-spine (application-state-log app))
                (copy-list (application-state-history app))
                (copy-list (application-state-undone app))
                (application-state-version app)
                (application-state-revision app)
                (%copy-observer-registry (application-state-observers app))))
    (make-application-state
     :data (copy-state-value data)
     :backend backend
     :lock (bt:make-lock "cl-state.lock")
     :log (copy-state-value log)
     :history history
     :undone undone
     :version version
     :revision revision
     :observers observers
     :frozen-p nil
     :transaction-owner nil)))


(defun valid-state-path-p (path)
  "Return true when PATH is a symbol or a proper list of non-NIL symbols."
  (or (symbolp path)
      (and (listp path)
           (every (lambda (part) (and part (symbolp part))) path))))

(defun assert-valid-state-path (path)
  "Return PATH or signal INVALID-STATE-PATH with the rejected value."
  (unless (valid-state-path-p path)
    (error 'invalid-state-path :path path))
  path)

(defgeneric state-ref (place key &optional default)
  (:documentation "Return the logical value at KEY without copying it.

For APPLICATION-STATE this is a borrowed read: container values may be shared
with strict snapshots and must not be destructively modified. Use STATE-VALUE
when the caller needs an owned mutable copy."))

(defmethod state-ref ((state application-state) (key t) &optional default)
  "Borrow KEY from managed STATE under its internal lock.

A foreign in-progress transaction is reported as STATE-TRANSACTION-CONFLICT so
the managed read cannot expose another transaction's intermediate value. The
returned container, if any, is still a borrowed value after this call returns;
use STATE-VALUE or STATE-VALUE-AT-REVISION for an owned copy."
  (assert-valid-state-path key)
  (bt:with-lock-held ((application-state-lock state))
    (%assert-state-write-available state :read)
    (get-path key (application-state-data state) default)))

(defmethod state-ref ((state hash-table) (key t) &optional default)
  (assert-valid-state-path key)
  (get-path key state default))

(defmethod state-ref ((state list) (key t) &optional default)
  (assert-valid-state-path key)
  (get-path key state default))

(defun state-value (state key &optional default)
  "Return an owned logical copy of the value at KEY in STATE.

For APPLICATION-STATE the lookup and ownership copy occur under one internal
lock and reject a foreign in-progress transaction. Raw containers retain their
historical direct-copy behavior."
  (if (application-state-p state)
      (nth-value 0 (state-value-at-revision state key default))
      (copy-state-value (state-ref state key default))))

(defun state-value-at-revision (state key &optional default)
  "Atomically return an owned KEY value and STATE's committed REVISION.

Unlike separate STATE-VALUE and STATE-REVISION calls, the two values describe
one lock-protected observation. If another transaction currently owns STATE,
STATE-TRANSACTION-CONFLICT is signaled rather than exposing an in-progress value
paired with the last committed revision. Extensible COPY-STATE-VALUE methods run
after the internal state lock is released."
  (check-type state application-state)
  (assert-valid-state-path key)
  (multiple-value-bind (value revision)
      (bt:with-lock-held ((application-state-lock state))
        (%assert-state-write-available state :optimistic-read)
        (values (%detach-state-value-spine
                 (get-path key (application-state-data state) default))
                (application-state-revision state)))
    (values (copy-state-value value) revision)))

(defun state-snapshot (state)
  "Return an owned copy of STATE's complete logical model.

Managed APPLICATION-STATE snapshots detach their built-in container graph under
the state lock and reject a foreign in-progress transaction. Extensible
COPY-STATE-VALUE methods then run after that lock is released. Runtime metadata
such as locks, observers, history, and undo stacks is not part of this value.
Raw hash-table/list inputs are copied directly."
  (etypecase state
    (application-state
     (let ((data
             (bt:with-lock-held ((application-state-lock state))
               (%assert-state-write-available state :snapshot)
               (%detach-state-value-spine (application-state-data state)))))
       (copy-state-value data)))
    (hash-table (copy-state-value state))
    (list (copy-state-value state))))

(defun state-frozen-p (state)
  "Return true when STATE is a frozen APPLICATION-STATE snapshot."
  (and (application-state-p state)
       (application-state-frozen-p state)))

(defmethod get-path (path (state application-state) &optional default)
  (state-ref state path default))

(defmethod get-path ((path list) (state application-state) &optional default)
  (state-ref state path default))

(defmethod get-path ((path symbol) (state application-state) &optional default)
  (state-ref state path default))

(defun %state-set-application (state key value expected-revision) "Store VALUE atomically, optionally requiring EXPECTED-REVISION. Observer callbacks run after lock release." (assert-valid-state-path key) (assert-state-mutation-allowed state :path key :operation :set) (multiple-value-bind (old notify-p revision) (bt:with-lock-held ((application-state-lock state)) (%assert-state-write-available state :set) (%assert-state-revision state expected-revision :set) (let* ((data (application-state-data state)) (old (get-path key data +state-missing-value+)) (data* (set-path data key value)) (transaction-p (transaction-active-p state))) (setf (application-state-data state) data*) (push (list key old value) (application-state-log state)) (incf (application-state-version state)) (unless transaction-p (incf (application-state-revision state))) (values old (not transaction-p) (application-state-revision state)))) (when notify-p (%deliver-state-change state key (%external-state-change-value old) value :phase :direct-mutation)) (values value revision)))

(defmethod (setf state-ref) (value (state application-state) (key t))
  "Atomically store VALUE at KEY inside STATE and log the change."
  (values (%state-set-application state key value nil)))

(defmethod (setf state-ref) (value (state hash-table) (key t))
  (assert-valid-state-path key)
  (set-path state key value))

(defmethod (setf state-ref) (value (state list) (key t))
  (assert-valid-state-path key)
  (set-path state key value))

(defun get-state (state key &optional default)
  "Convenience wrapper for state-ref."
  (state-ref state key default))

(defun state-set (state key value)
  "Set VALUE at KEY through the supported STATE-REF mutation path.

For APPLICATION-STATE this mutates logical state, appends a log entry, increments
VERSION, and increments REVISION for a direct commit. Transaction-local writes
leave REVISION unchanged until their outer transaction commits. Observers run
after the state lock is released; callback failure does not undo a direct
mutation. Strict or frozen application states reject before mutation."
  (setf (state-ref state key) value))

(defun state-set-if-revision (state expected-revision key value)
  "Atomically set KEY only when STATE still has EXPECTED-REVISION.

A stale precondition signals STATE-REVISION-CONFLICT before logical state,
version, revision, log/history, or observer delivery changes. On success return
VALUE and the resulting revision as two values."
  (check-type state application-state)
  (%state-set-application state key value expected-revision))

(defun application-state-plist (state)
  "Return an owned plist representation of STATE's logical model."
  (let ((data (state-snapshot state)))
    (if (hash-table-p data)
        (hash-table->plist data)
        data)))

(defgeneric get-component-by-path (app-state component-id-path)
  (:documentation "Retrieve a component instance from APP-STATE using its ID path."))

(defmethod get-component-by-path ((app-state application-state) component-id-path)
  (declare (type list component-id-path))
  (let ((components-path
          (append '(:components) component-id-path '(:component-instance))))
    (state-ref app-state components-path nil)))
