;;; cl-state/src/state/tx.lisp
(in-package :cl-state.tx)

(defstruct tx
  id
  name
  changes)  ; list of (key old new)

(defun %alist-get (key alist &optional default)
  (let ((pair (assoc key alist)))
    (if pair
      (cdr pair)
      default)))

(defun %reserve-transaction (app expected-revision)
  "Reserve APP for one outer transaction and return rollback metadata.

The current log tail is captured by identity. Since mutations PUSH new records,
commit and rollback can later splice only the transaction prefix without
scanning the pre-existing log."
  (bt:with-lock-held ((application-state-lock app))
    (cl-state.core::%assert-state-write-available app :transaction)
    (cl-state.core::%assert-state-revision app expected-revision :transaction)
    (let ((token (gensym "TX-OWNER-")))
      (setf (cl-state.core::application-state-transaction-owner app) token)
      (values token
              (application-state-log app)
              (application-state-version app)
              (application-state-history app)
              (application-state-undone app)))))

(defun %commit-transaction (app token start-log-anchor name)
  "Commit the reserved transaction and return changes in mutation order."
  (bt:with-lock-held ((application-state-lock app))
    (unless (eq token (cl-state.core::application-state-transaction-owner app))
      (error 'state-transaction-conflict :state app :operation :transaction-commit))
    (let* ((newest-changes (%changes-since app start-log-anchor))
           (changes (nreverse (copy-list newest-changes)))
           (tx (make-tx :id (gensym "TX-") :name name :changes changes)))
      (push tx (application-state-history app))
      (setf (application-state-undone app) nil
            (application-state-log app) start-log-anchor)
      (incf (application-state-revision app))
      (setf (cl-state.core::application-state-transaction-owner app) nil)
      changes)))

(defmacro with-transaction ((app &key name expected-revision) &body body)
  "Execute BODY as one reserved logical-state transaction on APP.

EXPECTED-REVISION is an optimistic precondition checked atomically before APP is
reserved. Same-state nesting joins the outer transaction and may repeat the
same revision precondition; it is not a savepoint. Other supported writers are
rejected with STATE-TRANSACTION-CONFLICT while the outer body is active.
Rollback restores logical values, VERSION, log, history, and redo metadata;
REVISION advances exactly once only after a successful outer commit. Observer
callbacks run after reservation is released and after all internal locks are
released."
  `(let ((app# ,app)
         (name# ,name)
         (expected-revision# ,expected-revision))
     (assert-state-mutation-allowed app# :operation :transaction)
     (if (cl-state.core::transaction-active-p app#)
         (progn
           (when expected-revision#
             (assert-state-revision app# expected-revision#
                                    :operation :nested-transaction))
           ,@body)
         (multiple-value-bind
               (token# start-log-anchor# start-version# start-history# start-undone#)
             (%reserve-transaction app# expected-revision#)
           (let ((committedp# nil)
                 (result-values# nil)
                 (ordered-changes# nil))
             (unwind-protect
                  (let ((*transaction-active* t)
                        (cl-state.core::*transaction-states*
                          (cons app# cl-state.core::*transaction-states*))
                        (cl-state.core::*transaction-tokens*
                          (acons app# token# cl-state.core::*transaction-tokens*)))
                    (setf result-values#
                          (multiple-value-list (progn ,@body)))
                    (setf ordered-changes#
                          (%commit-transaction app# token# start-log-anchor# name#)
                          committedp# t))
               (unless committedp#
                 (%restore-transaction-state
                  app# token# start-log-anchor# start-version#
                  start-history# start-undone#)))
             (%notify-transaction-changes app# ordered-changes#)
             (values-list result-values#))))))

(defun undo (app) "Undo the last committed transaction without observer delivery. Successful replay advances REVISION exactly once while retaining the historical compatibility rule that VERSION does not change." (assert-state-mutation-allowed app :operation :undo) (bt:with-lock-held ((application-state-lock app)) (cl-state.core::%assert-state-write-available app :undo) (let ((tx (pop (application-state-history app)))) (when tx (push tx (application-state-undone app)) (dolist (chg (reverse (tx-changes tx))) (let ((key (first chg)) (old (second chg))) (setf (application-state-data app) (if (cl-state.core::%state-missing-value-p old) (cl-state.utils:remove-path (application-state-data app) key) (cl-state.utils:set-path (application-state-data app) key old))))) (incf (application-state-revision app))) tx)))

(defun redo (app) "Redo the last undone transaction without observer delivery. Successful replay advances REVISION exactly once while retaining the historical compatibility rule that VERSION does not change." (assert-state-mutation-allowed app :operation :redo) (bt:with-lock-held ((application-state-lock app)) (cl-state.core::%assert-state-write-available app :redo) (let ((tx (pop (application-state-undone app)))) (when tx (push tx (application-state-history app)) (dolist (chg (tx-changes tx)) (setf (application-state-data app) (if (cl-state.core::%state-deleted-value-p (third chg)) (cl-state.utils:remove-path (application-state-data app) (first chg)) (cl-state.utils:set-path (application-state-data app) (first chg) (third chg))))) (incf (application-state-revision app))) tx)))

(defun %changes-since (app start-log-anchor)
  "Return changes prepended after START-LOG-ANCHOR, newest first.

Traversal is bounded by transaction-local changes rather than total retained
log size. If the captured tail is no longer reachable, fail closed instead of
silently committing against corrupted transaction metadata."
  (loop for cursor = (application-state-log app) then (cdr cursor)
        until (eq cursor start-log-anchor)
        do (when (null cursor)
             (error 'state-transaction-conflict
                    :state app
                    :operation :transaction-log-anchor))
        collect (car cursor)))

(defun %restore-transaction-state (app token start-log-anchor start-version start-history start-undone)
  "Roll APP back to the metadata and logical values captured at transaction entry."
  (bt:with-lock-held ((application-state-lock app))
    (unless (eq token (cl-state.core::application-state-transaction-owner app))
      (error 'state-transaction-conflict
             :state app
             :operation :transaction-rollback))
    (unwind-protect
         (let ((changes (%changes-since app start-log-anchor)))
           (dolist (change changes)
             (let ((path (first change))
                   (old (second change)))
               (setf (application-state-data app)
                     (if (cl-state.core::%state-missing-value-p old)
                         (cl-state.utils:remove-path
                          (application-state-data app) path)
                         (cl-state.utils:set-path
                          (application-state-data app) path old)))))
           (setf (application-state-log app) start-log-anchor
                 (application-state-version app) start-version
                 (application-state-history app) start-history
                 (application-state-undone app) start-undone))
      (setf (cl-state.core::application-state-transaction-owner app) nil))))



(defun %notify-transaction-changes (app ordered-changes) "Notify committed transaction changes in mutation order." (dolist (change ordered-changes) (cl-state.core::%deliver-state-change app (first change) (cl-state.core::%external-state-change-value (second change)) (cl-state.core::%external-state-change-value (third change)) :phase :transaction-commit)))
