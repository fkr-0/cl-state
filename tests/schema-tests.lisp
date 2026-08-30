;;;===============================================================
;;; File: cl-state/tests/schema-tests.lisp
;;; Unit tests for cl-state.schema module
;;;===============================================================
(uiop:define-package :cl-state-tests.schema
  (:use :cl :fiveam :cl-state.schema)
  (:export #:schema-suite
    #:run-schema-tests))

(in-package :cl-state-tests.schema)

(def-suite schema-suite
  :description "Tests for cl-state.schema module")

(in-suite schema-suite)

;;; Type predicate registration tests

(test register-type-predicate-basic
  "Registering a simple type predicate"
  (register-type-predicate :even #'evenp "Must be even")
  (let ((pred (lookup-type-predicate :even)))
    (is (not (null pred)))
    (is (funcall pred 4))
    (is (not (funcall pred 5)))))

(test define-type-predicate-macro
  "Using define-type-predicate macro"
  (define-type-predicate positive-number (value)
    (and (numberp value) (> value 0)))
  (let ((pred (lookup-type-predicate :positive-number)))
    (is (not (null pred)))
    (is (funcall pred 42))
    (is (not (funcall pred -5)))
    (is (not (funcall pred 0)))))

(test list-registered-types
  "Listing all registered types"
  (let ((types (list-registered-types)))
    (is (listp types))
    (is (> (length types) 0))
    ;; Check that predefined types are present
    (is (find :string types :key #'car))
    (is (find :integer types :key #'car))
    (is (find :keyword types :key #'car))))

;;; Type validation tests

(test validate-type-simple-symbol
  "Validating with simple symbol type"
  (validate-type "hello" :string)
  (validate-type 42 :integer)
  (validate-type :foo :keyword)
  (signals error (validate-type "not a number" :integer)))

(test validate-type-or-combination
  "Validating with (or ...) type specification"
  (validate-type "hello" '(or string integer))
  (validate-type 42 '(or string integer))
  (signals error (validate-type :keyword '(or string integer))))

(test validate-type-and-combination
  "Validating with (and ...) type specification"
  (define-type-predicate ten-or-greater (x)
    (and (integerp x) (>= x 10)))
  (validate-type 15 '(and integer ten-or-greater))
  (signals error (validate-type 5 '(and integer ten-or-greater)))
  (signals error (validate-type "not an int" '(and integer ten-or-greater))))

(test validate-type-list
  "Validating list types"
  (validate-type '(1 2 3) '(list integer))
  (validate-type '("a" "b") '(list string))
  (signals error (validate-type '(1 2 "three") '(list integer)))
  (signals error (validate-type "not a list" '(list integer))))

(test validate-type-vector
  "Validating vector types"
  (validate-type #(1 2 3) '(vector integer))
  (validate-type #("a" "b") '(vector string))
  (signals error (validate-type #(1 2 "three") '(vector integer)))
  (signals error (validate-type "not a vector" '(vector integer))))

(test validate-type-with-context
  "Validating with context for better error messages"
  (handler-case
    (validate-type "wrong" :integer "user.name")
    (error (c)
      (is (search "user.name" (princ-to-string c))))))

;;; Enum type tests

(test make-enum-predicate-basic
  "Creating enum predicate"
  (let ((color-enum (make-enum-predicate '(:red :green :blue))))
    (is (funcall color-enum :red))
    (is (funcall color-enum :green))
    (is (funcall color-enum :blue))
    (is (not (funcall color-enum :yellow)))
    (is (not (funcall color-enum "red")))))

(test register-enum-type
  "Registering an enum type"
  (register-enum-type :status '(:pending :active :completed))
  (validate-type :pending :status)
  (validate-type :active :status)
  (validate-type :completed :status)
  (signals error (validate-type :cancelled :status)))

;;; Predefined type tests

(test predefined-string-type
  "Testing predefined :string type"
  (validate-type "hello" :string)
  (signals error (validate-type 123 :string)))

(test predefined-integer-type
  "Testing predefined :integer type"
  (validate-type 42 :integer)
  (validate-type -10 :integer)
  (signals error (validate-type "not an int" :integer)))

(test predefined-keyword-type
  "Testing predefined :keyword type"
  (validate-type :foo :keyword)
  (signals error (validate-type "foo" :keyword))
  (signals error (validate-type "foo" :keyword)))

(test predefined-boolean-type
  "Testing predefined :boolean type"
  (validate-type t :boolean)
  (validate-type nil :boolean)
  (signals error (validate-type "yes" :boolean)))

(test predefined-function-type
  "Testing predefined :function type"
  (validate-type #'car :function)
  (signals error (validate-type "not a function" :function)))

(test predefined-list-type
  "Testing predefined :list type"
  (validate-type '(1 2 3) :list)
  (signals error (validate-type "not a list" :list)))

(test predefined-hash-table-type
  "Testing predefined :hash-table type"
  (validate-type (make-hash-table) :hash-table)
  (signals error (validate-type "not a hash-table" :hash-table)))

;;; Specialized predicate tests

(test non-empty-string-predicate
  "Testing non-empty-string predicate"
  (is-true (non-empty-string-p "hello"))
  (validate-type "hello" :non-empty-string)
  (signals error (validate-type "" :non-empty-string)))

(test positive-integer-predicate
  "Testing positive-integer predicate"
  (validate-type 5 :positive-integer)
  (signals error (validate-type -1 :positive-integer))
  (signals error (validate-type 0 :positive-integer)))

(test finite-number-predicate
  "Testing finite-number predicate"
  (validate-type 3.14 :finite-number)
  (validate-type 42 :finite-number)
  (validate-type most-positive-long-float :finite-number)
  #+sbcl
  (signals error
    (validate-type sb-ext:double-float-positive-infinity :finite-number)))

(defun run-schema-tests ()
  (run! 'schema-suite))
