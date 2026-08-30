(in-package :cl-state.schema)

;; Comprehensive type predicate registry
(defvar *type-predicates* (make-hash-table :test #'equal)
  "Registry of type predicates")

(defvar *type-descriptions* (make-hash-table :test #'equal)
  "Registry of type descriptions")

(defun %canonical-type-name (type-name)
  (etypecase type-name
    (symbol (intern (symbol-name type-name) :keyword))
    (string (intern (string-upcase type-name) :keyword))))

(defun register-type-predicate (type-name predicate &optional description)
  "Register a predicate for a type"
  (let ((key (%canonical-type-name type-name)))
    (setf (gethash key *type-predicates*) predicate)
  (when description
      (setf (gethash key *type-descriptions*) description))
    key))

(defmacro define-type-predicate (name args &body body)
  "Define and register a type predicate"
  `(progn
     (defun ,name ,args ,@body)
     (register-type-predicate ',(intern (symbol-name name) :keyword)
       #',name
       ,(format nil "Must satisfy ~a" name))))

(defun lookup-type-predicate (type-name)
  "Get a predicate for a type"
  (let ((key (%canonical-type-name type-name)))
    (or (gethash key *type-predicates*)
    ;; For simple types, try to find CL built-in type predicate
    (let ((possible-predicate
            (find-symbol (concatenate 'string (symbol-name key) "P") :cl)))
      (when (and possible-predicate (fboundp possible-predicate))
          (register-type-predicate key (symbol-function possible-predicate))
          (symbol-function possible-predicate))))))

(defun list-registered-types ()
  "List all registered type predicates"
  (let ((result nil))
    (maphash (lambda (k v)
               (declare (ignore v))
               (push (list k (gethash k *type-descriptions* "No description"))
                 result))
      *type-predicates*)
    (sort result #'string< :key #'(lambda (x) (string (car x))))))

(defun validate-type (value type &optional context)
  "Validate that a value satisfies a type predicate"
  (flet ((handle-error (msg)
           (error "Type validation error~@[ in ~a~]: ~a~@[~%Expected: ~a~]"
             context msg (gethash type *type-descriptions*))))
    (cond
      ;; Simple type predicate
      ((symbolp type)
        (let ((predicate (lookup-type-predicate type)))
          (if predicate
            (unless (funcall predicate value)
              (handle-error (format nil "~S is not a valid ~a" value type)))
            (handle-error (format nil "Unknown type ~S" type)))))

      ;; Lists of form (or type1 type2)
      ((and (listp type) (eq (first type) 'or))
        (let ((valid nil))
          (dolist (subtype (rest type))
            (handler-case
              (progn
                (validate-type value subtype context)
                (setq valid t)
                (return))
              (error (e)
                (declare (ignore e)))))
          (unless valid
            (handle-error (format nil "~S doesn't match any type in ~S" value type)))))

      ;; Lists of form (and type1 type2)
      ((and (listp type) (eq (first type) 'and))
        (dolist (subtype (rest type))
          (validate-type value subtype context)))

      ;; Lists of form (list element-type)
      ((and (listp type) (eq (first type) 'list))
        (unless (listp value)
          (handle-error (format nil "~S is not a list" value)))
        (let ((elem-type (second type)))
          (loop for elem in value
            for i from 0
            do (validate-type elem elem-type
                 (if context
                   (format nil "~a[~a]" context i)
                   (format nil "list item ~a" i))))))

      ;; Lists of form (vector element-type)
      ((and (listp type) (eq (first type) 'vector))
        (unless (vectorp value)
          (handle-error (format nil "~S is not a vector" value)))
        (let ((elem-type (second type)))
          (loop for elem across value
            for i from 0
            do (validate-type elem elem-type
                 (if context
                   (format nil "~a[~a]" context i)
                   (format nil "vector item ~a" i))))))

      ;; Other compound types
      (t (handle-error (format nil "Unsupported type specification: ~S" type)))))
  t)

;; Register common predefined types
(register-type-predicate :string #'stringp "Must be a string")
(register-type-predicate :integer #'integerp "Must be an integer")
(register-type-predicate :number #'numberp "Must be a number")
(register-type-predicate :keyword #'keywordp "Must be a keyword")
(register-type-predicate :boolean #'(lambda (x) (or (eq x t) (eq x nil))) "Must be a boolean")
(register-type-predicate :function #'functionp "Must be a function")
(register-type-predicate :symbol #'symbolp "Must be a symbol")
(register-type-predicate :list #'listp "Must be a list")
(register-type-predicate :hash-table #'hash-table-p "Must be a hash-table")
(register-type-predicate :array #'arrayp "Must be an array")
(register-type-predicate :character #'characterp "Must be a character")
(register-type-predicate :pathname #'pathnamep "Must be a pathname")
(register-type-predicate :float #'floatp "Must be a float")

;; More specialized predicates
(defun non-empty-string-p (value)
  (and (stringp value) (> (length value) 0)))
(register-type-predicate :non-empty-string #'non-empty-string-p "Must be a non-empty string")

(defun positive-integer-p (value)
  (and (integerp value) (> value 0)))
(register-type-predicate :positive-integer #'positive-integer-p "Must be a positive integer")

(defun non-negative-integer-p (value)
  (and (integerp value) (>= value 0)))
(register-type-predicate :non-negative-integer #'non-negative-integer-p
                         "Must be a non-negative integer")

(defun finite-number-p (value)
  (and (numberp value)
       (or (not (floatp value))
           #+sbcl (and (not (sb-ext:float-infinity-p value))
                       (not (sb-ext:float-nan-p value)))
           #-sbcl (= value value))))
(register-type-predicate :finite-number #'finite-number-p "Must be a finite number")

(defun keyword-symbol-p (value)
  (keywordp value))
(register-type-predicate :keyword-symbol #'keyword-symbol-p "Must be a keyword symbol")

;; Create predicate for enum values
(defun make-enum-predicate (allowed-values)
  "Create a predicate that validates against an enumeration of values"
  (lambda (value)
    (member value allowed-values)))

(defun register-enum-type (type-name allowed-values)
  "Register an enum type with the allowed values"
  (register-type-predicate
    type-name
    (make-enum-predicate allowed-values)
    (format nil "Must be one of: ~{~S~^, ~}" allowed-values)))
