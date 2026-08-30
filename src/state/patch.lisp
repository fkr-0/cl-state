;;; cl-state/src/state/patch.lisp
(in-package :cl-state.patch)

(define-condition patch-validation-error (error) ((input :initarg :input :reader patch-validation-error-input) (reason :initarg :reason :reader patch-validation-error-reason)) (:report (lambda (condition stream) (format stream "Invalid patch ~S: ~S." (patch-validation-error-input condition) (patch-validation-error-reason condition)))))

(define-condition invalid-patch-format (patch-validation-error) ())

(define-condition invalid-patch-path (patch-validation-error) ((path :initarg :path :reader invalid-patch-path-path)))

(define-condition invalid-patch-operation (patch-validation-error) ((operation :initarg :operation :reader invalid-patch-operation-operation)))

(define-condition invalid-patch-value (patch-validation-error) ((operation :initarg :operation :reader invalid-patch-value-operation) (value :initarg :value :reader invalid-patch-value-value)))

(defstruct (patch (:constructor %make-patch (&key path op value))) path op value)

(defun %valid-patch-path-p (path) (or (and path (symbolp path)) (and (consp path) (alexandria:proper-list-p path) (every (lambda (part) (and part (symbolp part))) path))))

(defun %assert-patch-path (path input) (unless (%valid-patch-path-p path) (error 'invalid-patch-path :input input :reason :invalid-path :path path)) path)

(defun %assert-patch-operation (operation input) (unless (member operation ' (:set :remove :merge :update) :test #'eq) (error 'invalid-patch-operation :input input :reason :unsupported-operation :operation operation)) operation)

(defun %assert-patch-value (operation value input) (case operation (:merge (unless (alexandria:proper-list-p value) (error 'invalid-patch-value :input input :reason :merge-requires-proper-list :operation operation :value value))) (:update (unless (or (functionp value) (and (symbolp value) (fboundp value))) (error 'invalid-patch-value :input input :reason :update-requires-function-designator :operation operation :value value)))) value)

(defun %validate-patch (patch &optional (input patch)) (%assert-patch-path (patch-path patch) input) (%assert-patch-operation (patch-op patch) input) (%assert-patch-value (patch-op patch) (patch-value patch) input) patch)

(defun make-patch (&key path op value) (%validate-patch (%make-patch :path path :op op :value value) (list :path path :op op :value value)))

(defun %deletion-shorthand-p (value) (or (eq value :elmtui-delete-path) (eq value :removed)))
;; path: list designating a place in your state (e.g., (:components :main :count))
;; op  : :set | :update | :remove | :merge
;; value: depends on op

(defun %normalize-patch (p) (cond ((patch-p p) (%validate-patch p p)) ((and (alexandria:proper-list-p p) (= (length p) 2)) (let ((path (first p)) (value (second p))) (%assert-patch-path path p) (if (%deletion-shorthand-p value) (make-patch :path path :op :remove :value nil) (make-patch :path path :op :set :value value)))) (t (error 'invalid-patch-format :input p :reason :unsupported-format))))

(defun normalize-patches (patches)
  (mapcar #'%normalize-patch patches))

(defun merge-patch (state patch) "Merge one shorthand patch into STATE and return the modified state." (let ((normalized (%normalize-patch patch))) (ecase (patch-op normalized) (:set (set-path state (patch-path normalized) (patch-value normalized))) (:remove (multiple-value-bind (state* removedp) (remove-path state (patch-path normalized)) (declare (ignore removedp)) state*)) (:merge (%apply-patch-to-container state normalized)) (:update (%apply-patch-to-container state normalized)))))

(defun merge-patches (state patches)
  "Merge a list of PATCHES into STATE.
Returns the modified STATE (functional API)."
  (reduce #'merge-patch patches :initial-value state))

(defun %apply-patch-to-container (state patch)
  "Apply normalized PATCH to a raw hash-table/plist container."
  (let ((path (patch-path patch))
         (op (patch-op patch))
         (value (patch-value patch)))
    (ecase op
      (:set
        (set-path state path value))
      (:remove
        (multiple-value-bind (state* _) (remove-path state path)
          (declare (ignore _))
          state*))
      (:merge
        (let* ((cur (get-path path state nil))
                (new (append value cur)))
          (set-path state path new)))
      (:update
        (let* ((cur (get-path path state nil))
                (fn value))
          (set-path state path (funcall fn cur)))))))

(defun %remove-from-application-state (state path) "Remove PATH while preserving the application-state log and observer contract." (assert-state-mutation-allowed state :path path :operation :remove) (multiple-value-bind (old removedp notify-p) (bt:with-lock-held ((application-state-lock state)) (cl-state.core::%assert-state-write-available state :remove) (let* ((data (application-state-data state)) (old (get-path path data cl-state.core::+state-missing-value+))) (multiple-value-bind (updated removedp) (remove-path data path) (when removedp (setf (application-state-data state) updated) (push (list path old cl-state.core::+state-deleted-value+) (application-state-log state)) (incf (application-state-version state)) (unless (cl-state.core::transaction-active-p state) (incf (application-state-revision state)))) (values old removedp (and removedp (not (cl-state.core::transaction-active-p state))))))) (when notify-p (cl-state.core::%deliver-state-change state path (cl-state.core::%external-state-change-value old) :elmtui-delete-path :phase :direct-mutation)) (values state removedp)))

(defun %apply-patch-to-application-state (state patch)
  "Apply PATCH through the application-state mutation/logging protocol.

MERGE and UPDATE capture an owned input plus its committed revision before
computing outside the state lock. Their final write is revision-conditional, so
a concurrent commit fails with STATE-REVISION-CONFLICT instead of overwriting a
newer value. UPDATE functions therefore never run while an internal state lock
is held and cannot mutate the live container graph through their input."
  (let ((path (patch-path patch))
        (op (patch-op patch))
        (value (patch-value patch)))
    (ecase op
      (:set
       (state-set state path value))
      (:remove
       (%remove-from-application-state state path))
      (:merge
       (multiple-value-bind (current revision)
           (state-value-at-revision state path nil)
         (state-set-if-revision state revision path
                                (append value current))))
      (:update
       (multiple-value-bind (current revision)
           (state-value-at-revision state path nil)
         (let ((updated (funcall value current)))
           (state-set-if-revision state revision path updated)))))
    state))

(defun apply-patch (state p)
  "Apply P to a raw container or APPLICATION-STATE.

APPLICATION-STATE operations mutate the supported logical model path and use the
same log/version/observer policy as STATE-SET. A remove patch records a deletion
only when the path exists. Example: APPLY-PATCH with a SET patch at :COUNT and
value 3 changes :COUNT to 3."
  (let ((patch (%normalize-patch p)))
    (if (application-state-p state)
        (%apply-patch-to-application-state state patch)
        (%apply-patch-to-container state patch))))

(defun apply-patches (state patches)
  "Apply PATCHES in order.

For raw containers this is a direct reduction. For APPLICATION-STATE values,
the whole batch joins an existing transaction for STATE or otherwise creates
one undoable transaction. Example: setting (:USER :NAME) to Ada and removing
:STALE in one PATCHES list commits both mutations atomically."
  (if (and (application-state-p state)
           (not (cl-state.core::transaction-active-p state)))
      (cl-state.tx:with-transaction (state :name :apply-patches)
        (reduce #'apply-patch patches :initial-value state))
      (reduce #'apply-patch patches :initial-value state)))

(defun apply-patches-persistent (state patches &key (name :apply-patches-persistent))
  "Return the post-PATCHES state without mutating STATE.

APPLICATION-STATE values are deeply copied across the supported CL-STATE
container graph before the transactional patch engine runs against the fresh
copy. The returned state has normal log/version/history/observer semantics while
the caller's previous state remains observationally unchanged. Raw list/hash-
table containers are also copied before patch application.

This function is the commit primitive used by ElmTUI's :STRICT-ELM application
mode. For example, setting :COUNT on the returned state never changes :COUNT on
STATE. Observer failure is reported for the fresh committed state and does not
mutate or roll back the source STATE.

Custom mutable leaf objects are treated atomically by DEEP-COPY-DATA because
Common Lisp has no portable universal object-copy protocol. Such leaves must be
application-immutable or copied before insertion when strict value semantics are
required."
  (if (application-state-p state)
      (let ((next (deep-copy-application-state state)))
        (if (cl-state.core::transaction-active-p next)
            (reduce #'apply-patch patches :initial-value next)
            (cl-state.tx:with-transaction (next :name name)
              (reduce #'apply-patch patches :initial-value next))))
      (let ((next (deep-copy-data state)))
        (reduce #'apply-patch patches :initial-value next))))

(defun %diff-container-p (value) (or (hash-table-p value) (and (listp value) (cl-state.utils::%plist-like-p value))))

(defun %diff-container-keys (container) (cond ((hash-table-p container) (loop for key being the hash-keys of container collect key)) ((listp container) (loop for key in container by #'cddr collect key))))

(defun %diff-container-value (container key) (cond ((hash-table-p container) (gethash key container)) ((listp container) (let ((marker (gensym "MISSING-"))) (let ((value (getf container key marker))) (values value (not (eq value marker))))))))

(defun diff-states (old new &key (prefix nil)) "Return shorthand patches whose sequential application transforms OLD into NEW." (unless (and (%diff-container-p old) (%diff-container-p new)) (error 'invalid-patch-format :input (list old new) :reason :unsupported-diff-container)) (let ((patches nil)) (dolist (key (%diff-container-keys new)) (multiple-value-bind (new-value new-present-p) (%diff-container-value new key) (declare (ignore new-present-p)) (multiple-value-bind (old-value old-present-p) (%diff-container-value old key) (let ((path (append prefix (list key)))) (cond ((not old-present-p) (push (list path (copy-state-value new-value)) patches)) ((and (%diff-container-p old-value) (%diff-container-p new-value)) (setf patches (nconc (nreverse (diff-states old-value new-value :prefix path)) patches))) ((not (equal old-value new-value)) (push (list path (copy-state-value new-value)) patches))))))) (dolist (key (%diff-container-keys old)) (multiple-value-bind (new-value new-present-p) (%diff-container-value new key) (declare (ignore new-value)) (unless new-present-p (push (list (append prefix (list key)) :elmtui-delete-path) patches)))) (nreverse patches)))
