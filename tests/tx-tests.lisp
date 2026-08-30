;;;===============================================================
;;; File: cl-state/tests/tx-tests.lisp
;;; Unit tests for cl-state.tx module
;;;===============================================================
(uiop:define-package :cl-state-tests.tx
  (:use :cl :fiveam :cl-state.api)
  (:export #:tx-suite
           #:run-tx-tests))

(in-package :cl-state-tests.tx)

(def-suite tx-suite
  :description "Tests for cl-state.tx module")

(in-suite tx-suite)

;;; with-transaction tests

(test with-transaction-basic
  "Basic transaction creates history entry"
  (let ((state (make-state)))
    (with-transaction (state :name :test-tx)
      (state-set state :a 1)
      (state-set state :b 2))
    (is (= 1 (length (application-state-history state))))
    (is (= 1 (state-ref state :a)))
    (is (= 2 (state-ref state :b)))))

(test with-transaction-name
  "Transaction stores name"
  (let ((state (make-state)))
    (with-transaction (state :name :my-tx)
      (state-set state :a 1))
    (let ((tx (first (application-state-history state))))
      (is (eq :my-tx (tx-name tx))))))

(test with-transaction-changes
  "Transaction records changes"
  (let ((state (make-state)))
    (state-set state :a 0) ;; Set initial value
    (with-transaction (state :name :test)
      (state-set state :a 1)
      (state-set state :b 2))
    (let ((tx (first (application-state-history state))))
      (is (= 2 (length (tx-changes tx))))
      ;; Changes are (key old new)
      (is (some (lambda (c) (and (eq :a (first c)) (= 0 (second c)) (= 1 (third c))))
                (tx-changes tx))))))

(test with-transaction-clears-undone
  "New transaction clears undone stack"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (undo state)
    (is (= 1 (length (application-state-undone state))))
    (with-transaction (state)
      (state-set state :b 2))
    (is (null (application-state-undone state)))))

(test with-transaction-empty
  "Empty transaction still creates history entry"
  (let ((state (make-state)))
    (with-transaction (state))
    (is (= 1 (length (application-state-history state))))))

(test with-transaction-nested-calls
  "Nested state-set calls work within transaction"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state '(:outer :inner) 42))
    (is (= 42 (state-ref state '(:outer :inner))))))

(test with-transaction-preserves-multiple-values
  "with-transaction should preserve all values produced by the wrapped body."
  (let ((state (make-state)))
    (multiple-value-bind (a b c)
        (with-transaction (state :name :multi-values)
          (state-set state :a 1)
          (values :x :y :z))
      (is (eq :x a))
      (is (eq :y b))
      (is (eq :z c)))))

;;; undo tests

(test undo-single-change
  "Undo single change transaction"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (is (= 1 (state-ref state :a)))
    (undo state)
    (is (null (state-ref state :a nil)))))

(test undo-multiple-changes
  "Undo transaction with multiple changes"
  (let ((state (make-state)))
    (state-set state :a 0)
    (state-set state :b 0)
    (with-transaction (state)
      (state-set state :a 1)
      (state-set state :b 2))
    (undo state)
    (is (= 0 (state-ref state :a)))
    (is (= 0 (state-ref state :b)))))

(test undo-multiple-transactions
  "Undo multiple transactions in sequence"
  (let ((state (make-state)))
    (with-transaction (state :name :tx1)
      (state-set state :a 1))
    (with-transaction (state :name :tx2)
      (state-set state :b 2))
    (is (= 1 (state-ref state :a)))
    (is (= 2 (state-ref state :b)))
    (undo state)
    (is (= 1 (state-ref state :a)))
    (is (null (state-ref state :b nil)))
    (undo state)
    (is (null (state-ref state :a nil)))))

(test undo-moves-to-undone
  "Undo moves transaction to undone stack"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (is (= 1 (length (application-state-history state))))
    (is (null (application-state-undone state)))
    (undo state)
    (is (null (application-state-history state)))
    (is (= 1 (length (application-state-undone state))))))

(test undo-empty-history
  "Undo with empty history does nothing"
  (let ((state (make-state)))
    (is (null (undo state)))))

(test undo-new-key
  "Undo restores state for new keys"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :new-key 42))
    (is (= 42 (state-ref state :new-key)))
    (undo state)
    (is (null (state-ref state :new-key nil)))))

;;; redo tests

(test redo-after-undo
  "Redo after undo restores changes"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (undo state)
    (is (null (state-ref state :a nil)))
    (redo state)
    (is (= 1 (state-ref state :a)))))

(test redo-multiple-transactions
  "Redo multiple undone transactions"
  (let ((state (make-state)))
    (with-transaction (state :name :tx1)
      (state-set state :a 1))
    (with-transaction (state :name :tx2)
      (state-set state :b 2))
    (undo state)
    (undo state)
    (redo state)
    (is (= 1 (state-ref state :a)))
    (is (null (state-ref state :b nil)))
    (redo state)
    (is (= 1 (state-ref state :a)))
    (is (= 2 (state-ref state :b)))))

(test redo-moves-to-history
  "Redo moves transaction back to history"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (undo state)
    (is (null (application-state-history state)))
    (is (= 1 (length (application-state-undone state))))
    (redo state)
    (is (= 1 (length (application-state-history state)))
    (is (null (application-state-undone state))))))

(test redo-empty-undone
  "Redo with empty undone stack does nothing"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (is (null (redo state)))))

(test redo-clears-undone-on-new-tx
  "New transaction after undo clears redo stack"
  (let ((state (make-state)))
    (with-transaction (state)
      (state-set state :a 1))
    (undo state)
    (is (= 1 (length (application-state-undone state))))
    (with-transaction (state)
      (state-set state :b 2))
    (is (null (application-state-undone state)))
    (is (null (redo state)))))

(defun run-tx-tests ()
  (run! 'tx-suite))

(test concurrent-writer-is-rejected-while-transaction-reserves-state
  (let* ((state (make-state :initial '(:owner 0)))
         (initial-revision (state-revision state))
         (gate-lock (bt:make-lock "cl-state-race-gate"))
         (gate-condition (bt:make-condition-variable :name "cl-state-race-gate-cv"))
         (entered-p nil)
         (release-p nil)
         (thread-error nil)
         (worker
           (bt:make-thread
            (lambda ()
              (handler-case
                  (with-transaction (state :name :owner
                                           :expected-revision initial-revision)
                    (state-set state :owner 1)
                    (bt:with-lock-held (gate-lock)
                      (setf entered-p t)
                      (bt:condition-notify gate-condition)
                      (loop until release-p
                            do (bt:condition-wait gate-condition gate-lock))))
                (error (condition)
                  (setf thread-error condition)
                  (bt:with-lock-held (gate-lock)
                    (setf entered-p t)
                    (bt:condition-notify gate-condition)))))
            :name "cl-state-race-owner")))
    (bt:with-lock-held (gate-lock)
      (loop until entered-p
            do (bt:condition-wait gate-condition gate-lock)))
    (handler-case
        (progn
          (state-set state :intruder 2)
          (fail "Expected concurrent write ownership conflict."))
      (state-transaction-conflict (condition)
        (is (eq state (state-conflict-state condition)))
        (is (eq :set (state-conflict-operation condition)))))
    (signals state-transaction-conflict
      (state-ref state :owner))
    (is (= initial-revision (state-revision state)))
    (bt:with-lock-held (gate-lock)
      (setf release-p t)
      (bt:condition-notify gate-condition))
    (bt:join-thread worker)
    (is (null thread-error))
    (is (= 1 (state-ref state :owner)))
    (is (eq :missing (state-ref state :intruder :missing)))
    (is (= (1+ initial-revision) (state-revision state)))
    (is (= 1 (length (application-state-history state))))))

(test different-state-nesting-commits-independently-without-lock-ordering
  (let* ((outer (make-state :initial '(:left 0 :right 0)))
         (inner (make-state :initial '(:value 0)))
         (outer-revision (state-revision outer))
         (inner-revision (state-revision inner))
         (events nil))
    (add-observer outer :left
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :outer-left events)))
    (add-observer outer :right
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :outer-right events)))
    (add-observer inner :value
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :inner events)))
    (with-transaction (outer :name :outer :expected-revision outer-revision)
      (state-set outer :left 1)
      (with-transaction (inner :name :inner :expected-revision inner-revision)
        (state-set inner :value 1))
      (state-set outer :right 1))
    (is (= (1+ outer-revision) (state-revision outer)))
    (is (= (1+ inner-revision) (state-revision inner)))
    (is (= 2 (application-state-version outer)))
    (is (= 1 (application-state-version inner)))
    (is (= 1 (length (application-state-history outer))))
    (is (= 1 (length (application-state-history inner))))
    (is (equal '(:inner :outer-left :outer-right)
               (nreverse events)))))

(test transaction-revision-state-machine-has-backend-parity
  (dolist (backend '(:hash-table :plist))
    (let* ((state (make-state :initial '(:count 0) :backend backend))
           (initial-revision (state-revision state))
           (observer-calls 0))
      (add-observer state :count
                    (lambda (old new)
                      (declare (ignore old new))
                      (incf observer-calls)))
      (with-transaction (state :name :outer :expected-revision initial-revision)
        (state-set state :count 1)
        (with-transaction (state :name :inner :expected-revision initial-revision)
          (state-set state :aux 2)))
      (is (= (1+ initial-revision) (state-revision state)))
      (is (= 2 (application-state-version state)))
      (is (= 1 observer-calls))
      (is (= 1 (length (application-state-history state))))
      (let ((committed-revision (state-revision state))
            (before-version (application-state-version state))
            (before-history (application-state-history state))
            (before-observer-calls observer-calls))
        (signals state-revision-conflict
          (with-transaction (state :name :stale
                                   :expected-revision initial-revision)
            (state-set state :count 3)))
        (is (= 1 (state-ref state :count)))
        (is (= committed-revision (state-revision state)))
        (is (= before-version (application-state-version state)))
        (is (eq before-history (application-state-history state)))
        (is (= before-observer-calls observer-calls))
        (signals error
          (with-transaction (state :name :rollback
                                   :expected-revision committed-revision)
            (state-set state :count 4)
            (error "rollback probe")))
        (is (= 1 (state-ref state :count)))
        (is (= committed-revision (state-revision state)))
        (is (= before-version (application-state-version state)))
        (is (eq before-history (application-state-history state)))
        (is (= before-observer-calls observer-calls))
        (undo state)
        (is (= (1+ committed-revision) (state-revision state)))
        (is (= before-version (application-state-version state)))
        (is (= 0 (state-ref state :count)))
        (is (= before-observer-calls observer-calls))
        (redo state)
        (is (= (+ committed-revision 2) (state-revision state)))
        (is (= before-version (application-state-version state)))
        (is (= 1 (state-ref state :count)))
        (is (= before-observer-calls observer-calls))))))

(test frozen-snapshots-reject-history-replay
  (let* ((source (make-state :initial '(:count 0)))
         (frozen (cl-state.patch::apply-patches-shared source '((:count 1)))))
    (is-true (state-frozen-p frozen))
    (signals state-mutation-forbidden (undo frozen))
    (signals state-mutation-forbidden (redo frozen))
    (is (= 1 (state-ref frozen :count)))))

(test transaction-observer-failure-leaves-commit-intact
  (let* ((state (make-state :initial '(:count 0)))
         (before-version (application-state-version state))
         (before-revision (state-revision state)))
    (add-observer state :count
                  (lambda (old new)
                    (declare (ignore old new))
                    (error "commit observer boom")))
    (handler-case
        (progn
          (with-transaction (state :name :observer-failure)
            (state-set state :count 1))
          (fail "Expected observer notification failure."))
      (observer-notification-error (condition)
        (is (eq :transaction-commit
                (observer-notification-error-phase condition)))))
    (is (= 1 (state-ref state :count)))
    (is (= (1+ before-version) (application-state-version state)))
    (is (= (1+ before-revision) (state-revision state)))
    (is (= 1 (length (application-state-history state))))
    (is (null (application-state-undone state)))
    (is (null (application-state-log state)))))

(test transaction-body-failure-restores-state-and-metadata-without-observers
  (let ((state (make-state :initial '(:count 0)))
        (observer-calls 0))
    (state-set state :seed 1)
    (with-transaction (state :name :redo-seed)
      (state-set state :temporary 7))
    (undo state)
    (add-observer state :count
                  (lambda (old new)
                    (declare (ignore old new))
                    (incf observer-calls)))
    (let ((before-version (application-state-version state))
          (before-log (copy-tree (application-state-log state)))
          (before-history (application-state-history state))
          (before-undone (application-state-undone state)))
      (handler-case
          (with-transaction (state :name :failing)
            (state-set state :count 9)
            (state-set state :other 2)
            (error "body failure"))
        (error (condition)
          (declare (ignore condition))))
      (is (= 0 (state-ref state :count)))
      (is (null (state-ref state :other nil)))
      (is (= 1 (state-ref state :seed)))
      (is (= before-version (application-state-version state)))
      (is (equal before-log (application-state-log state)))
      (is (eq before-history (application-state-history state)))
      (is (eq before-undone (application-state-undone state)))
      (is (= 0 observer-calls)))))

(test nested-transactions-join-outer-and-notify-in-deterministic-order
  (let ((state (make-state))
        (events nil))
    (add-observer state :a
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :a-first events)))
    (add-observer state :a
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :a-second events)))
    (add-observer state :b
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :b events)))
    (add-observer state :c
                  (lambda (old new)
                    (declare (ignore old new))
                    (push :c events)))
    (with-transaction (state :name :outer)
      (state-set state :a 1)
      (with-transaction (state :name :inner)
        (state-set state :b 2))
      (state-set state :c 3)
      (is (null events)))
    (is (equal '(:a-first :a-second :b :c) (nreverse events)))
    (is (= 1 (length (application-state-history state))))
    (let ((tx (first (application-state-history state))))
      (is (eq :outer (tx-name tx)))
      (is (equal '(:a :b :c) (mapcar #'first (tx-changes tx)))))))

(test hash-table-and-plist-backends-share-transaction-semantics
  (dolist (backend '(:hash-table :plist))
    (let* ((state (make-state :initial '(:count 0 :gone t) :backend backend))
           (before-version (application-state-version state))
           (events nil))
      (add-observer state :count
                    (lambda (old new)
                      (declare (ignore old new))
                      (push :count events)))
      (add-observer state :gone
                    (lambda (old new)
                      (declare (ignore old new))
                      (push :gone events)))
      (with-transaction (state :name :parity)
        (state-set state :count 1)
        (state-set state '(:nested :value) 2)
        (apply-patch state (make-patch :path :gone :op :remove)))
      (is (= 1 (state-ref state :count)))
      (is (= 2 (state-ref state '(:nested :value))))
      (is (eq :missing (state-ref state :gone :missing)))
      (is (= (+ before-version 3) (application-state-version state)))
      (is (equal '(:count :gone) (reverse events)))
      (is (= 1 (length (application-state-history state))))
      (undo state)
      (is (= 0 (state-ref state :count)))
      (is (eq :missing (state-ref state '(:nested :value) :missing)))
      (is-true (state-ref state :gone))
      (is (= 2 (length events)))
      (redo state)
      (is (= 1 (state-ref state :count)))
      (is (= 2 (state-ref state '(:nested :value))))
      (is (eq :missing (state-ref state :gone :missing)))
      (is (= 2 (length events))))))
