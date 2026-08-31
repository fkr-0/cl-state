;;;===============================================================
;;; File: cl-state/tests/cl-state-tests.lisp
;;; Main test suite loader for cl-state
;;;===============================================================
(uiop:define-package :cl-state-tests
  (:use :cl :fiveam)
  (:import-from :cl-state.api
                #:make-state
                #:state-ref
                #:state-set
                #:get-state
                #:get-path
                #:set-path
                #:remove-path
                #:plist->hash-table
                #:hash-table->plist
                #:coerce-data
                #:merge-patch
                #:merge-patches
                #:apply-patch
                #:apply-patches
                #:normalize-patches
                #:diff-states
                #:make-patch
                #:patch-path
                #:patch-op
                #:patch-value
                #:with-transaction
                #:undo
                #:redo
                #:make-tx
                #:tx-p
                #:tx-id
                #:tx-name
                #:tx-changes
                #:add-observer
                #:remove-observer
                #:notify-observers
                #:application-state
                #:application-state-p
                #:application-state-data
                #:application-state-log
                #:application-state-backend
                #:application-state-history
                #:application-state-undone
                #:application-state-version
                #:application-state-observers
                #:set-application-state-backend
                #:invalid-state-path
                #:invalid-state-path-path
                #:deep-copy-application-state
                #:application-state-plist
                #:get-component-by-path
                #:make-history
                #:history-past
                #:history-future
                #:push-snapshot
                #:validate-type
                #:list-registered-types
                #:register-enum-type
                #:validate-model-schema
                #:validate-nested
                #:validate-field
                #:make-validator
                #:type-predicate)
  (:export #:run-cl-state-tests
           #:run-all-cl-state-tests))

(in-package :cl-state-tests)

(def-suite cl-state-suite
  :description "Master test suite for cl-state")

(in-suite cl-state-suite)

;; Legacy tests that were in the original file
(test make-state-basic
  (let ((state (make-state)))
    (is (application-state-p state))
    (is (hash-table-p (application-state-data state)))
    (is (eq (application-state-backend state) :hash-table))))

(test state-ref-basic
  (let ((state (make-state)))
    (setf (state-ref state '(:a :b)) 1)
    (is (= (state-ref state '(:a :b)) 1))
    (is (= (state-ref state '(:missing) 42) 42))))

(test public-state-log-externalizes-internal-change-markers
  (let ((state (make-state)))
    (state-set state '(:foo) 1)
    (apply-patch state (make-patch :path '(:foo) :op :remove))
    (let ((log (application-state-log state)))
      (is (equal '((:foo) 1 :elmtui-delete-path) (first log)))
      (is (equal '((:foo) :not-present 1) (second log)))
      ;; The public log is owned; editing it must not mutate managed metadata.
      (setf (second (second log)) :changed)
      (is (eq :not-present
              (second (second (application-state-log state))))))))

(test invalid-state-path-is-a-typed-inspectable-error
  (let* ((state (make-state))
         (condition
           (handler-case
               (progn (state-ref state '(nil)) nil)
             (invalid-state-path (error) error))))
    (is (typep condition 'invalid-state-path))
    (is (equal '(nil) (invalid-state-path-path condition)))))

(test merge-patches-basic
  (let* ((state (make-state))
         (data (application-state-data state)))
    ;; Perform merges - functional API returns modified state
    ;; We wrap setf in progn to suppress return values
    (progn (setf data (merge-patch data (list '(:user :name) "Alice"))) nil)
    (progn (setf data (merge-patches data (list (list '(:user :age) 30) (list '(:settings :theme) :dark)))) nil)
    ;; Check results
    (is (equal (get-path '(:user :name) data) "Alice"))
    (is (equal (get-path '(:user :age) data) 30))
    (is (equal (get-path '(:settings :theme) data) :dark))
    ;; Delete and check
    (progn (setf data (merge-patch data (list '(:user :age) :elmtui-delete-path))) nil)
    (is (null (get-path '(:user :age) data)))))

(test transaction-undo-redo
  (let ((state (make-state)))
    (with-transaction (state :name :tx1)
      (state-set state :a 1)
      (state-set state :b 2))
    (is (= (length (application-state-history state)) 1))
    (undo state)
    (is (null (state-ref state :b)))
    (redo state)
    (is (= (state-ref state :b) 2))))

(defun run-all-cl-state-tests () "Run all cl-state test suites and fail ASDF when any check fails." (format t "~&╔════════════════════════════════════════════════════════════╗~%") (format t "║ CL-STATE TEST SUITE - RUNNING ALL TESTS ║~%") (format t "╚════════════════════════════════════════════════════════════╝~%~%") (flet ((run-suite (label suite) (format t "~&━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━~%") (format t "Running ~a...~%" label) (let ((results (run suite))) (explain! results) results))) (let ((results (append (run-suite "Utils Tests" 'cl-state-tests.utils:utils-suite) (run-suite "Core Tests" 'cl-state-tests.core:core-suite) (run-suite "Patch Tests" 'cl-state-tests.patch:patch-suite) (run-suite "Persistent State Tests" 'cl-state-tests.persistent:persistent-suite) (run-suite "Algebra Tests" 'cl-state-tests.algebra:algebra-suite) (run-suite "Transaction Tests" 'cl-state-tests.tx:tx-suite) (run-suite "Observer Tests" 'cl-state-tests.observer:observer-suite) (run-suite "Undo Tests" 'cl-state-tests.undo:undo-suite) (run-suite "Schema Tests" 'cl-state-tests.schema:schema-suite) (run-suite "Validation Tests" 'cl-state-tests.validation:validation-suite) (run-suite "Compatibility Tests" 'cl-state-suite)))) (format t "~%╔════════════════════════════════════════════════════════════╗~%") (format t "║ ALL TESTS COMPLETED ║~%") (format t "╚════════════════════════════════════════════════════════════╝~%") (unless (results-status results) (error "The cl-state test suite failed.")) results)))

;; Alias for compatibility
(setf (symbol-function 'run-cl-state-tests) #'run-all-cl-state-tests)
