;;;===============================================================
;;; File: cl-state/tests/utils-tests.lisp
;;; Unit tests for cl-state.utils module
;;;===============================================================
(uiop:define-package :cl-state-tests.utils
  (:use :cl :fiveam :cl-state.utils)
  (:export #:utils-suite
           #:run-utils-tests))

(in-package :cl-state-tests.utils)

(def-suite utils-suite
  :description "Tests for cl-state.utils module")

(in-suite utils-suite)

;;; get-path tests

(test get-path-with-null-path
  "Getting with null path should return data itself"
  (is (equal (get-path nil 'some-data) 'some-data))
  (is (equal (get-path nil '(a b c)) '(a b c))))

(test get-path-with-symbol-key
  "Getting with symbol key from hash-table"
  (let ((ht (plist->hash-table '(:a 1 :b 2 :c 3))))
    (is (= 1 (get-path :a ht)))
    (is (= 2 (get-path :b ht)))
    (is (null (get-path :missing ht nil)))))

(test get-path-with-list-path
  "Getting with nested list path"
  (let ((ht (plist->hash-table
             '(:user (:name "Alice" :age 30)
               :settings (:theme :dark)))))
    (is (equal "Alice" (get-path '(:user :name) ht)))
    (is (= 30 (get-path '(:user :age) ht)))
    (is (eq :dark (get-path '(:settings :theme) ht)))))

(test get-path-with-default
  "Getting with default value for missing keys"
  (let ((ht (plist->hash-table '(:a 1))))
    (is (= 42 (get-path '(:missing) ht 42)))
    (is (= 99 (get-path '(:a :missing) ht 99)))))

(test get-path-from-plist
  "Getting values from plist"
  (let ((plist '(:a 1 :b 2 :c 3)))
    (is (= 1 (get-path :a plist)))
    (is (= 2 (get-path :b plist)))
    (is (null (get-path :missing plist nil)))))

(test get-path-from-alist
  "Getting values from alist"
  (let ((alist '((:a . 1) (:b . 2) (:c . 3))))
    (is (= 1 (get-path :a alist)))
    (is (= 2 (get-path :b alist)))))

;;; set-path tests

(test set-path-symbol-key
  "Setting with symbol key"
  (let ((ht (make-hash-table :test 'equal)))
    (set-path ht :foo 42)
    (is (= 42 (gethash :foo ht)))))

(test set-path-nested-path
  "Setting with nested path"
  (let ((ht (make-hash-table :test 'equal)))
    (set-path ht '(:user :name) "Alice")
    (set-path ht '(:user :age) 30)
    (is (equal "Alice" (get-path '(:user :name) ht)))
    (is (= 30 (get-path '(:user :age) ht)))))

(test set-path-update-existing
  "Updating existing path"
  (let ((ht (plist->hash-table '(:a 1 :b 2))))
    (set-path ht :a 99)
    (is (= 99 (gethash :a ht)))))

(test set-path-on-plist
  "Setting values on plist"
  (let ((plist '(:a 1 :b 2)))
    (let ((new-plist (set-path plist :c 3)))
      (is (equal 3 (getf new-plist :c))))))

;;; remove-path tests

(test remove-path-single-key
  "Removing single key from hash-table"
  (let ((ht (plist->hash-table '(:a 1 :b 2 :c 3))))
    (multiple-value-bind (new-ht removedp) (remove-path ht :b)
      (is (eq removedp t))
      (is (null (get-path :b new-ht nil)))
      (is (= 1 (get-path :a new-ht)))
      (is (= 3 (get-path :c new-ht))))))

(test remove-path-nested
  "Removing nested path"
  (let ((ht (plist->hash-table
             '(:user (:name "Alice" :age 30)
               :other (:data 42)))))
    (multiple-value-bind (new-ht removedp) (remove-path ht '(:user :age))
      (is (eq removedp t))
      (is (equal "Alice" (get-path '(:user :name) new-ht)))
      (is (null (get-path '(:user :age) new-ht nil)))
      (is (= 42 (get-path '(:other :data) new-ht))))))

(test remove-path-with-pruning
  "Removing path with empty pruning"
  (let ((ht (plist->hash-table '(:user (:name "Alice")))))
    (multiple-value-bind (new-ht removedp) (remove-path ht '(:user :name) :prune-empty t)
      (is (eq removedp t))
      (is (null (get-path :user new-ht nil))))))

(test remove-path-missing-key
  "Removing missing key should return same state"
  (let ((ht (plist->hash-table '(:a 1))))
    (multiple-value-bind (new-ht removedp) (remove-path ht :missing)
      (is (not removedp))
      (is (= 1 (get-path :a new-ht))))))

;;; plist->hash-table tests

(test plist->hash-table-basic
  "Converting plist to hash-table"
  (let* ((plist '(:a 1 :b 2 :c 3))
         (ht (plist->hash-table plist)))
    (is (hash-table-p ht))
    (is (= 1 (gethash :a ht)))
    (is (= 2 (gethash :b ht)))
    (is (= 3 (gethash :c ht)))))

(test plist->hash-table-nested
  "Converting nested plist to hash-table"
  (let* ((plist '(:user (:name "Alice" :age 30)
                  :settings (:theme :dark)))
         (ht (plist->hash-table plist)))
    (is (hash-table-p ht))
    (is (equal "Alice" (get-path '(:user :name) ht)))
    (is (= 30 (get-path '(:user :age) ht)))
    (is (eq :dark (get-path '(:settings :theme) ht)))))

;;; hash-table->plist tests

(test hash-table->plist-basic
  "Converting hash-table to plist"
  (let* ((ht (plist->hash-table '(:a 1 :b 2 :c 3)))
         (plist (hash-table->plist ht)))
    (is (listp plist))
    (is (equal 1 (getf plist :a)))
    (is (equal 2 (getf plist :b)))
    (is (equal 3 (getf plist :c)))))

(test hash-table->plist-roundtrip
  "Roundtrip conversion preserves data"
  (let* ((original '(:a 1 :b (:nested 2) :c 3))
         (ht (plist->hash-table original))
         (result (hash-table->plist ht)))
    ;; Note: order may differ, so we check key-value pairs
    (is (= 1 (getf result :a)))
    (is (= 2 (get-path '(:b :nested) result)))
    (is (= 3 (getf result :c)))))

;;; coerce-data tests

(test coerce-data-nil-to-hash-table
  "Coercing nil to hash-table"
  (let ((ht (coerce-data nil :hash-table)))
    (is (hash-table-p ht))
    (is (zerop (hash-table-count ht)))))

(test coerce-data-hash-table-same-backend
  "Coercing hash-table to same backend returns same"
  (let ((ht (plist->hash-table '(:a 1))))
    (is (eq ht (coerce-data ht :hash-table)))))

(test coerce-data-plist-to-hash-table
  "Coercing plist to hash-table"
  (let* ((plist '(:a 1 :b 2))
         (ht (coerce-data plist :hash-table)))
    (is (hash-table-p ht))
    (is (= 1 (gethash :a ht)))
    (is (= 2 (gethash :b ht)))))

(test coerce-data-hash-table-to-plist
  "Coercing hash-table to plist"
  (let* ((ht (plist->hash-table '(:a 1 :b 2)))
         (plist (coerce-data ht :plist)))
    (is (listp plist))
    (is (= 1 (getf plist :a)))
    (is (= 2 (getf plist :b)))))

(defun run-utils-tests ()
  (run! 'utils-suite))
