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
  (validate-type #C(3.0 4.0) :finite-number)
  (is-false (finite-number-p :not-a-number))
  #+sbcl
  (is-false (finite-number-p
             (complex 1.0d0 sb-ext:double-float-positive-infinity)))
  (validate-type most-positive-long-float :finite-number)
  #+sbcl
  (signals error
    (validate-type sb-ext:double-float-positive-infinity :finite-number)))

(defun run-schema-tests ()
  (run! 'schema-suite))

(defun %schema-failure-message (value type &optional context)
  "Capture the public diagnostic without depending on condition subclasses."
  (handler-case
      (progn (validate-type value type context) nil)
    (error (condition) (princ-to-string condition))))

(test schema-predicate-registry-canonicalization-and-fallback
  (let* ((type-name :coverage-special-value)
         (description "Coverage special value"))
    (is (eq type-name
            (register-type-predicate "coverage-special-value"
                                     (lambda (value) (eql value 42))
                                     description)))
    (is (funcall (lookup-type-predicate 'coverage-special-value) 42))
    (is (funcall (lookup-type-predicate "coverage-special-value") 42))
    (is (not (funcall (lookup-type-predicate type-name) 41)))
    (is (equal description
               (second (assoc type-name (list-registered-types)))))
    (is (eq :coverage-no-description
            (register-type-predicate :coverage-no-description #'identity)))
    (is (equal "No description"
               (second (assoc :coverage-no-description
                              (list-registered-types)))))
    (is (funcall (lookup-type-predicate :odd) 3))
    (is (null (lookup-type-predicate :unregistered-coverage-type)))
    (is (search "Unknown type"
                (%schema-failure-message 1 :unregistered-coverage-type)))
    (is (search description
                (%schema-failure-message 0 type-name)))))

(test schema-nested-diagnostics-pin-context-and-indices
  (dolist (case (list
                  (list '(1 :bad 3) '(list integer) "records" "records[1]")
                  (list #(1 :bad 3) '(vector integer) "data" "data[1]")
                  (list '(1 :bad) '(list integer) nil "list item 1")
                  (list #(1 :bad) '(vector integer) nil "vector item 1")))
    (destructuring-bind (value type context expected) case
      (is (search expected (%schema-failure-message value type context)))))
  (is (search "is not a list"
              (%schema-failure-message 7 '(list integer))))
  (is (search "is not a vector"
              (%schema-failure-message 7 '(vector integer))))
  (is (search "doesn't match any type"
              (%schema-failure-message :none '(or integer string))))
  (is (search "Unsupported type specification"
              (%schema-failure-message 1 '(unknown integer))))
  (is (search "Expected:"
              (%schema-failure-message nil :non-empty-string "user.name")))
  (is (equal t (validate-type '() '(list integer))))
  (is (equal t (validate-type #() '(vector integer))))
  (is (equal t (validate-type 10 '(and integer positive-integer)))))

(test schema-boundary-predicates-and-enum-rejection
  (dolist (value '("" nil 0 -1 :none))
    (is-false (non-empty-string-p value)))
  (is-true (non-negative-integer-p 0))
  (is-true (non-negative-integer-p 42))
  (dolist (value '(-1 1.5 :none))
    (is-false (non-negative-integer-p value)))
  (is-false (positive-integer-p 0))
  (is-false (positive-integer-p 1.5))
  (is-true (keyword-symbol-p :ok))
  (is-false (keyword-symbol-p 'not-keyword))
  (is-true (finite-number-p 0))
  (is-true (finite-number-p 0.0d0))
  (is-false (finite-number-p :no))
  (register-enum-type :coverage-enum '(0 1 2))
  (is (validate-type 0 :coverage-enum))
  (is (search "Must be one of"
              (%schema-failure-message 9 :coverage-enum))))
