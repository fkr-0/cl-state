;;;===============================================================
;;; File: cl-state/tests/observer-tests.lisp
;;; Unit tests for cl-state.observer module
;;;===============================================================
(uiop:define-package :cl-state-tests.observer
  (:use :cl :fiveam :cl-state.api)
  (:export #:observer-suite
    #:run-observer-tests))

(in-package :cl-state-tests.observer)

(def-suite observer-suite
  :description "Tests for cl-state.observer module")

(in-suite observer-suite)

;;; add-observer tests

(test add-observer-single
  "Adding single observer for key"
  (let ((state (make-state))
         (called nil))
    (let ((fn (lambda (old new)
                (setf called (list old new)))))
      (add-observer state :test-key fn)
      (is (= 1 (length (application-state-observers state))))
      ;; Observer is stored - we can't directly test it gets called
      ;; because that happens in with-transaction, but we verify storage
      (let ((pair (assoc :test-key (application-state-observers state))))
        (is (not (null pair)))
        (is (= 1 (length (cdr pair))))))))

(test add-observer-multiple-same-key
  "Adding multiple observers for same key"
  (let ((state (make-state))
         (calls-1 nil)
         (calls-2 nil))
    (let ((fn1 (lambda (old new) (push (list old new) calls-1)))
           (fn2 (lambda (old new) (push (list old new) calls-2))))
      (add-observer state :key fn1)
      (add-observer state :key fn2)
      (let ((pair (assoc :key (application-state-observers state))))
        (is (not (null pair)))
        (is (= 2 (length (cdr pair))))))))

(test add-observer-different-keys
  "Adding observers for different keys"
  (let ((state (make-state)))
    (add-observer state :key1 (lambda (o n) (declare (ignore o n))))
    (add-observer state :key2 (lambda (o n) (declare (ignore o n))))
    (is (= 2 (length (application-state-observers state))))
    (is (assoc :key1 (application-state-observers state)))
    (is (assoc :key2 (application-state-observers state)))))

(test add-observer-returns-fn
  "add-observer returns the function"
  (let ((state (make-state))
         (fn (lambda (o n) (declare (ignore o n)))))
    (is (eq fn (add-observer state :key fn)))))

;;; remove-observer tests

(test remove-observer-existing
  "Removing existing observer"
  (let ((state (make-state))
         (fn (lambda (o n) (declare (ignore o n)))))
    (add-observer state :key fn)
    (is (= 1 (length (application-state-observers state))))
    (is (remove-observer state :key fn))
    ;; Empty observer buckets are removed to keep the registry compact.
    (let ((pair (assoc :key (application-state-observers state))))
      (is (null pair)))))

(test remove-observer-one-of-many
  "Removing one of multiple observers for same key"
  (let ((state (make-state))
         (fn1 (lambda (o n) (declare (ignore o n))))
         (fn2 (lambda (o n) (declare (ignore o n))))
         (fn3 (lambda (o n) (declare (ignore o n)))))
    (add-observer state :key fn1)
    (add-observer state :key fn2)
    (add-observer state :key fn3)
    (is (remove-observer state :key fn2))
    (let ((pair (assoc :key (application-state-observers state))))
      (is (not (null pair)))
      (is (= 2 (length (cdr pair))))
      (is (not (member fn2 (cdr pair)))))))

(test remove-observer-non-existent-key
  "Removing observer for non-existent key returns nil"
  (let ((state (make-state))
         (fn (lambda (o n) (declare (ignore o n)))))
    (is (null (remove-observer state :missing fn)))))

(test remove-observer-non-existent-fn
  "Removing non-existent observer returns nil"
  (let ((state (make-state))
         (fn1 (lambda (o n) (declare (ignore o n))))
         (fn2 (lambda (o n) (declare (ignore o n)))))
    (add-observer state :key fn1)
    (is (null (remove-observer state :key fn2)))))

;;; notify-observers tests

(test notify-observers-single
  "Notifying single observer"
  (let ((state (make-state))
         (received nil))
    (let ((fn (lambda (old new)
                (setf received (list old new)))))
      (add-observer state :key fn)
      (notify-observers state :key 1 2)
      (is (equal '(1 2) received)))))

(test notify-observers-multiple
  "Notifying multiple observers for same key"
  (let ((state (make-state))
         (calls nil))
    (let ((fn1 (lambda (old new) (push (list :fn1 old new) calls)))
           (fn2 (lambda (old new) (push (list :fn2 old new) calls))))
      (add-observer state :key fn1)
      (add-observer state :key fn2)
      (notify-observers state :key :old :new)
      (is (= 2 (length calls)))
      (is (some (lambda (c) (equal '(:fn1 :old :new) c)) calls))
      (is (some (lambda (c) (equal '(:fn2 :old :new) c)) calls)))))

(test notify-observers-no-observers
  "Notifying when no observers does nothing"
  (let ((state (make-state)))
    (notify-observers state :key 1 2)
    ;; Should not error - trivial assertion to verify we got here
    (is (= 1 1))))

(test notify-observers-wrong-key
  "Notifying for key with no observers does nothing"
  (let ((state (make-state))
         (called nil))
    (add-observer state :key1
                  (lambda (old-value new-value)
                    (declare (ignore old-value new-value))
                    (setf called t)))
    (notify-observers state :key2 1 2)
    (is (not called))))

;;; Observer integration with transactions

(test observer-called-in-transaction
  "Observers are called when changes happen in transaction"
  (let ((state (make-state))
         (old-value nil)
         (new-value nil))
    (add-observer state :counter
      (lambda (old new)
        (setf old-value old)
        (setf new-value new)))
    (with-transaction (state)
      (state-set state :counter 10))
    ;; Note: observers are called when transaction completes
    (is (eql :not-present old-value))
    (is (= 10 new-value))))

(test observer-multiple-changes
  "Observer called for each change in transaction"
  (let ((state (make-state))
         (changes nil))
    (state-set state :value 0)
    (add-observer state :value
      (lambda (old new)
        (push (list old new) changes)))
    (with-transaction (state)
      (state-set state :value 1)
      (state-set state :value 2)
      (state-set state :value 3))
    ;; Observer should be called for each change in the transaction
    (is (= 3 (length changes)))))

(defun run-observer-tests ()
  (run! 'observer-suite))

(test observer-callbacks-run-without-state-lock
  (dolist (mode '(:direct :transaction))
    (let ((state (make-state :initial '(:count 0)))
          (lock-acquired-p nil))
      (add-observer state :count
                    (lambda (old new)
                      (declare (ignore old new))
                      (let ((lock (application-state-lock state)))
                        (setf lock-acquired-p (bt:acquire-lock lock nil))
                        (when lock-acquired-p
                          (bt:release-lock lock)))))
      (ecase mode
        (:direct
         (state-set state :count 1))
        (:transaction
         (with-transaction (state :name :lock-proof)
           (state-set state :count 1))))
      (is-true lock-acquired-p))))

(test frozen-snapshot-observer-registry-is-runtime-metadata
  (let* ((source (make-state :initial '(:count 0)))
         (frozen (cl-state.patch::apply-patches-shared source '((:count 1))))
         (version (application-state-version frozen))
         (revision (state-revision frozen))
         (history-length (length (application-state-history frozen)))
         (fn (lambda (old new) (declare (ignore old new)))))
    (is-true (state-frozen-p frozen))
    (is (eq fn (add-observer frozen :count fn)))
    (is (= version (application-state-version frozen)))
    (is (= revision (state-revision frozen)))
    (is (= history-length (length (application-state-history frozen))))
    (is (= 1 (state-ref frozen :count)))
    (is-true (remove-observer frozen :count fn))
    (is (= version (application-state-version frozen)))
    (is (= revision (state-revision frozen)))))

(test strict-descendant-captures-observer-registry-at-commit-time
  (let* ((source (make-state :initial '(:count 0)))
         (first-calls 0)
         (late-calls 0)
         (first-fn (lambda (old new)
                     (declare (ignore old new))
                     (incf first-calls)))
         (late-fn (lambda (old new)
                    (declare (ignore old new))
                    (incf late-calls))))
    (add-observer source :count first-fn)
    (let ((next (cl-state.patch::apply-patches-shared source '((:count 1)))))
      (setf first-calls 0)
      (add-observer source :count late-fn)
      (notify-observers next :count 1 2)
      (is (= 1 first-calls))
      (is (= 0 late-calls))
      (is-true (state-frozen-p next)))))

(test direct-mutation-observer-failure-is-inspectable-and-post-mutation
  (let* ((state (make-state :initial '(:count 0)))
         (before-version (application-state-version state))
         (before-revision (state-revision state))
         (later-called nil)
         (failing (lambda (old new)
                    (declare (ignore old new))
                    (error "observer boom"))))
    (add-observer state :count failing)
    (add-observer state :count
                  (lambda (old new)
                    (declare (ignore old new))
                    (setf later-called t)))
    (handler-case
        (progn
          (state-set state :count 1)
          (fail "Expected observer failure."))
      (observer-notification-error (condition)
        (is (eq state (observer-notification-error-state condition)))
        (is (eq :count (observer-notification-error-key condition)))
        (is (eq failing (observer-notification-error-observer condition)))
        (is (= 0 (observer-notification-error-old-value condition)))
        (is (= 1 (observer-notification-error-new-value condition)))
        (is (eq :direct-mutation
                (observer-notification-error-phase condition)))
        (is (typep (observer-notification-error-cause condition) 'error))))
    (is (= 1 (state-ref state :count)))
    (is (= (1+ before-version) (application-state-version state)))
    (is (= (1+ before-revision) (state-revision state)))
    (is-false later-called)))

(test observer-failure-can-be-explicitly-skipped-with-restart
  (let ((state (make-state :initial '(:count 0)))
        (restart-seen nil)
        (later-called nil))
    (add-observer state :count
                  (lambda (old new)
                    (declare (ignore old new))
                    (error "observer boom")))
    (add-observer state :count
                  (lambda (old new)
                    (declare (ignore old new))
                    (setf later-called t)))
    (handler-bind
        ((observer-notification-error
           (lambda (condition)
             (let ((restart
                     (find-restart 'continue-observer-notification condition)))
               (is-true restart)
               (setf restart-seen t)
               (invoke-restart restart)))))
      (state-set state :count 1))
    (is-true restart-seen)
    (is-true later-called)
    (is (= 1 (state-ref state :count)))))


(test delivery-protocol-remains-private
  "The mutation-to-observer delivery seam stays internal to CL-STATE implementation packages."
  (multiple-value-bind (symbol status)
      (find-symbol "%DELIVER-STATE-CHANGE" :cl-state.core)
    (is-true symbol)
    (is (eq :internal status)))
  (multiple-value-bind (symbol status)
      (find-symbol "%DELIVER-STATE-CHANGE" :cl-state.api)
    (is-false symbol)
    (is-false status)))


(test mutation-paths-preserve-observer-condition-phase-contract
  "Direct, transactional, and persistent commits report the same observer error contract with path-specific phases."
  (dolist (case '((:direct . :direct-mutation)
                  (:transaction . :transaction-commit)
                  (:persistent . :persistent-commit)))
    (destructuring-bind (mode . expected-phase) case
      (let ((state (make-state :initial '(:count 0)))
            (seen nil))
        (add-observer state :count
                      (lambda (old new)
                        (declare (ignore old new))
                        (error "phase probe")))
        (handler-bind
            ((observer-notification-error
               (lambda (condition)
                 (setf seen
                       (list (observer-notification-error-phase condition)
                             (observer-notification-error-old-value condition)
                             (observer-notification-error-new-value condition)))
                 (let ((restart
                         (find-restart 'continue-observer-notification condition)))
                   (is-true restart)
                   (invoke-restart restart)))))
          (ecase mode
            (:direct
             (state-set state :count 1))
            (:transaction
             (with-transaction (state :name :phase-contract)
               (state-set state :count 1)))
            (:persistent
             (cl-state.patch::apply-patches-shared state '((:count 1))))))
        (is (equal (list expected-phase 0 1) seen))))))
