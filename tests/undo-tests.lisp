;;;===============================================================
;;; File: cl-state/tests/undo-tests.lisp
;;; Unit tests for cl-state.undo module
;;;===============================================================
(uiop:define-package :cl-state-tests.undo
  (:use :cl :fiveam)
  (:import-from #:cl-state.api
                #:history
                #:make-history
                #:history-past
                #:history-future
                #:push-snapshot)
  (:import-from #:cl-state.undo
                #:history-undo
                #:history-redo)
  (:export #:undo-suite
           #:run-undo-tests))

(in-package :cl-state-tests.undo)

(def-suite undo-suite
  :description "Tests for cl-state.undo module (history API)")

(in-suite undo-suite)

;;; make-history tests

(test make-history-empty
  "Creating empty history"
  (let ((hist (make-history)))
    (is (null (history-past hist)))
    (is (null (history-future hist)))))

;;; push-snapshot tests

(test push-snapshot-basic
  "Pushing snapshot to history"
  (let ((hist (make-history))
        (snap1 :state1)
        (snap2 :state2))
    (push-snapshot hist snap1)
    (is (equal (list snap1) (history-past hist)))
    (is (null (history-future hist)))
    (push-snapshot hist snap2)
    (is (equal (list snap2 snap1) (history-past hist)))
    (is (null (history-future hist)))))

(test push-snapshot-clears-future
  "Pushing snapshot clears future"
  (let ((hist (make-history)))
    (push-snapshot hist :state1)
    (push-snapshot hist :state2)
    ;; Undo to build future
    (history-undo hist)
    (is (history-future hist))
    ;; Push new snapshot clears future
    (push-snapshot hist :state3)
    (is (null (history-future hist)))
    (is (equal :state3 (first (history-past hist))))))

(test push-snapshot-returns-hist
  "push-snapshot returns history"
  (let ((hist (make-history)))
    (is (eq hist (push-snapshot hist :state)))))

;;; undo (history API) tests

(test undo-history-basic
  "Undo in history returns previous state"
  (let ((hist (make-history)))
    (push-snapshot hist :state1)
    (push-snapshot hist :state2)
    (let ((result (history-undo hist)))
      (is (eq :state1 result))
      (is (equal (list :state2) (history-future hist)))
      (is (equal (list :state1) (history-past hist))))))

(test undo-empty-past
  "Undo with empty past returns nil"
  (let ((hist (make-history)))
    (is (null (history-undo hist)))))

(test undo-single-state
  "Undo with single state in past"
  (let ((hist (make-history)))
    (push-snapshot hist :state1)
    (let ((result (history-undo hist)))
      (is (eq :state1 result))
      (is (null (history-past hist)))
      (is (equal (list :state1) (history-future hist))))))

(test undo-multiple
  "Multiple undo operations"
  (let ((hist (make-history)))
    (push-snapshot hist :s1)
    (push-snapshot hist :s2)
    (push-snapshot hist :s3)
    (is (eq :s2 (history-undo hist)))
    (is (eq :s1 (history-undo hist)))
    (is (null (history-undo hist)))))

;;; redo (history API) tests

(test redo-history-basic
  "Redo in history returns next state"
  (let ((hist (make-history)))
    (push-snapshot hist :state1)
    (push-snapshot hist :state2)
    (history-undo hist)
    (let ((result (history-redo hist)))
      (is (eq :state2 result))
      (is (equal (list :state2) (history-past hist)))
      (is (equal (list :current) (history-future hist))))))

(test redo-empty-future
  "Redo with empty future returns nil"
  (let ((hist (make-history)))
    (push-snapshot hist :state1)
    (is (null (history-redo hist)))))

(test redo-single-state
  "Redo with single state in future"
  (let ((hist (make-history)))
    (push-snapshot hist :state1)
    (history-undo hist)
    (let ((result (history-redo hist)))
      (is (eq :state1 result))
      (is (equal (list :state1) (history-past hist)))
      (is (null (history-future hist))))))

(test redo-multiple
  "Multiple redo operations"
  (let ((hist (make-history)))
    (push-snapshot hist :s1)
    (push-snapshot hist :s2)
    (push-snapshot hist :s3)
    (history-undo hist)
    (history-undo hist)
    (is (eq :s2 (history-redo hist)))
    (is (eq :s3 (history-redo hist)))
    (is (null (history-redo hist)))))

;;; Undo/Redo round-trip tests

(test undo-redo-round-trip
  "Undo then redo returns to original state"
  (let ((hist (make-history)))
    (push-snapshot hist :s1)
    (push-snapshot hist :s2)
    (push-snapshot hist :s3)
    (history-undo hist)
    (history-redo hist)
    (is (equal (list :s3 :s2 :s1) (history-past hist)))))

(test undo-redo-alternating
  "Alternating undo and redo"
  (let ((hist (make-history)))
    (push-snapshot hist :s1)
    (push-snapshot hist :s2)
    (push-snapshot hist :s3)
    (is (eq :s2 (history-undo hist)))
    (is (eq :s3 (history-redo hist)))
    (is (eq :s2 (history-undo hist)))
    (is (eq :s1 (history-undo hist)))
    (is (eq :s2 (history-redo hist)))
    (is (eq :s3 (history-redo hist)))))

(defun run-undo-tests ()
  (run! 'undo-suite))
