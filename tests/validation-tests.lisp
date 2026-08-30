;;;===============================================================
;;; File: cl-state/tests/validation-tests.lisp
;;; Unit tests for cl-state.validation module
;;;===============================================================
(uiop:define-package :cl-state-tests.validation
  (:use :cl :fiveam :cl-state.validation)
  (:export #:validation-suite
    #:run-validation-tests))

(in-package :cl-state-tests.validation)

(def-suite validation-suite
  :description "Tests for cl-state.validation module")

(in-suite validation-suite)

;;; Test object with slots for validation

(defclass test-object ()
  ((name :accessor obj-name :initarg :name)
    (age :accessor obj-age :initarg :age)
    (email :accessor obj-email :initarg :email))
  (:documentation "Simple test object for validation"))

;;; Type validator registration tests

(test register-type-validator-basic
  "Registering a simple type validator"
  (register-type-validator 'positive (lambda (x) (> x 0)) "Must be positive")
  (let ((pred (type-predicate 'positive)))
    (is (not (null pred)))
    (is (funcall pred 5))))

(test predefined-type-validators
  "Testing predefined type validators"
  (is (not (null (type-predicate 'string))))
  (is (not (null (type-predicate 'integer))))
  (is (not (null (type-predicate 'keyword))))
  (is (not (null (type-predicate 'boolean))))
  (is (not (null (type-predicate 'function))))
  (is (not (null (type-predicate 'symbol))))
  (is (not (null (type-predicate 'list))))
  (is (not (null (type-predicate 'hash-table)))))

;;; make-validator tests

(test make-validator-basic
  "Creating a validator function"
  (let ((validator (make-validator #'stringp "Must be a string")))
    (is (funcall validator "hello"))
    (signals validation-error (funcall validator 123))))

(test make-validator-with-path
  "Validator should include path in error"
  (let ((validator (make-validator #'stringp "Must be a string")))
    (handler-case
      (funcall validator 123 :path "user.name")
      (validation-error (c)
        (is (search "user.name" (validation-error-path c)))))))

;;; define-validator tests

(test define-validator-macro
  "Using define-validator macro"
  (define-validator validate-age (age)
    (if (and (integerp age) (>= age 0) (<= age 150))
      t
      "Age must be between 0 and 150"))
  (is (validate-age 25))
  (signals validation-error (validate-age -5))
  (signals validation-error (validate-age 200)))

;;; validate-field tests

(test validate-field-symbol-type
  "Validating field with symbol type"
  (is (validate-field "hello" 'string)))

(test validate-field-or-type
  "Validating field with (or ...) type"
  (register-type-validator 'positive #'plusp "Must be positive")
  (validate-field 5 '(or string positive))
  (validate-field "hello" '(or string positive))
  (signals validation-error (validate-field -1 '(or string positive))))

(test validate-field-and-type
  "Validating field with (and ...) type"
  (register-type-validator 'under-100 (lambda (x) (< x 100)) "Must be under 100")
  (validate-field 50 '(and integer under-100))
  (signals validation-error (validate-field 150 '(and integer under-100))))

(test validate-field-list-type
  "Validating field with (list ...) type"
  (validate-field '(1 2 3) '(list integer))
  (signals validation-error (validate-field '(1 "two" 3) '(list integer)))
  (signals validation-error (validate-field "not a list" '(list integer))))

(test validate-field-vector-type
  "Validating field with (vector ...) type"
  (validate-field #(1 2 3) '(vector integer))
  (signals validation-error (validate-field #(1 "two" 3) '(vector integer)))
  (signals validation-error (validate-field "not a vector" '(vector integer))))

(test validate-field-with-path
  "Validating field with path parameter"
  (handler-case
    (validate-field "wrong" 'integer :path "user.age")
    (validation-error (c)
      (is (string= "user.age" (validation-error-path c))))))

;;; validate-nested tests

(test validate-nested-basic
  "Validating nested object structure"
  (let ((obj (make-instance 'test-object
               :name "Alice"
               :age 30
               :email "alice@example.com")))
    (validate-nested obj '((name string) (age integer) (email string)))))

(test validate-nested-fails
  "Validation should fail for invalid data"
  (let ((obj (make-instance 'test-object
               :name "Alice"
               :age "not an integer"
               :email "alice@example.com")))
    (signals validation-error
      (validate-nested obj '((name string) (age integer) (email string))))))

(test validate-nested-with-path
  "Nested validation should include field paths"
  (let ((obj (make-instance 'test-object
               :name "Alice"
               :age "invalid"
               :email "alice@example.com")))
    (handler-case
      (validate-nested obj '((name string) (age integer)) "user")
      (validation-error (c)
        (is (search "user.age" (validation-error-path c)))))))

;;; with-validation tests

(test with-validation-macro
  "Testing with-validation error handling"
  (with-validation
    (validate-field "hello" 'string)
    (is (validate-field 123 :integer)))
  ;; Should handle errors gracefully
  (let ((*error-output* (make-broadcast-stream)))
    (handler-case
        (with-validation
          (validate-field "wrong" 'integer))
      (validation-error () nil))))

(defclass schema-object ()
  ((data :accessor obj-data :initarg :data)
    (schema :accessor obj-schema :initarg :schema))
  (:documentation "Object with embedded schema"))

;;; validate-model-schema tests

(test validate-model-schema-with-explicit-schema
  "Validating model with explicit schema"
  (let ((obj (make-instance 'test-object
               :name "Bob"
               :age 25
               :email "bob@example.com")))
    (validate-model-schema obj '((name string) (age integer) (email string)))))

(test validate-model-schema-with-embedded-schema
  "Validating model with embedded schema"
  (let ((obj (make-instance 'schema-object
               :data '(:name "Charlie" :age 35)
               :schema '((name string) (age integer)))))
    (validate-model-schema obj)))

(test validate-model-schema-no-schema-error
  "Should error when no schema provided"
  (let ((obj (make-instance 'test-object :name "Dave" :age 40)))
    (signals error (validate-model-schema obj))))

(test validate-model-schema-validation-failure
  "Should fail validation for invalid data"
  (let ((obj (make-instance 'test-object
               :name "Eve"
               :age "invalid"
               :email "eve@example.com")))
    (signals validation-error
      (validate-model-schema obj '((name string) (age integer) (email string))))))

;;; validation-error condition tests

(test validation-error-accessors
  "Testing validation-error condition accessors"
  (handler-case
    (error 'validation-error
      :message "Test error"
      :path "test.path"
      :value 42)
    (validation-error (c)
      (is (string= "Test error" (validation-error-message c)))
      (is (string= "test.path" (validation-error-path c)))
      (is (eql 42 (validation-error-value c))))))

(defun run-validation-tests ()
  (run! 'validation-suite))
