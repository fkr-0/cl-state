(in-package :cl-state.validation)

;;; Validation is the condition/reporting layer over cl-state.schema's single
;;; type registry.  Keeping one registry prevents schema and model validation
;;; from silently disagreeing about built-in or user-defined types.

(defun register-type-validator (type-name predicate &optional description)
  "Compatibility name for REGISTER-TYPE-PREDICATE."
  (register-type-predicate type-name predicate description))

(defun type-predicate (type-name)
  "Return the predicate registered for TYPE-NAME."
  (lookup-type-predicate type-name))

(define-condition validation-error (error)
  ((message :initarg :message :reader validation-error-message)
   (path :initarg :path :initform nil :reader validation-error-path)
   (value :initarg :value :initform nil :reader validation-error-value))
  (:report (lambda (condition stream)
             (format stream "Validation error at ~a: ~a"
                     (or (validation-error-path condition) "root")
                     (validation-error-message condition)))))

(defun %validation-error (value path control &rest arguments)
  (error 'validation-error
         :message (apply #'format nil control arguments)
         :path path
         :value value))

(defun make-validator (predicate error-message)
  "Create a validator function from PREDICATE and ERROR-MESSAGE."
  (check-type predicate function)
  (lambda (value &key path)
    (unless (funcall predicate value)
      (%validation-error value path "~a" error-message))
    t))

(defmacro define-validator (name args &body body)
  "Define NAME as a validator whose BODY returns T or an error message."
  (let ((value (first args)))
    `(defun ,name ,args
       (let ((result (progn ,@body)))
         (if (eq result t)
             t
             (%validation-error ,value nil "~a" (or result "Validation failed")))))))

(defun validate-field (value type &key path)
  "Validate VALUE against TYPE and signal VALIDATION-ERROR on mismatch."
  (cond
    ((symbolp type)
     (let ((predicate (type-predicate type)))
       (unless predicate
         (%validation-error value path "No validator defined for type ~a" type))
       (unless (funcall predicate value)
         (%validation-error value path "~S is not a valid ~a" value type))))
    ((and (consp type) (eq (first type) 'or))
     (unless (some (lambda (sub-type)
                     (handler-case
                         (progn (validate-field value sub-type :path path) t)
                       (validation-error () nil)))
                   (rest type))
       (%validation-error value path "Value ~S does not match any type in ~S"
                          value type)))
    ((and (consp type) (eq (first type) 'and))
     (dolist (sub-type (rest type))
       (validate-field value sub-type :path path)))
    ((and (consp type) (eq (first type) 'list))
     (unless (listp value)
       (%validation-error value path "Expected a list"))
     (loop for item in value
           for index from 0
           do (validate-field item (second type)
                              :path (format nil "~@[~a~][~d]" path index))))
    ((and (consp type) (eq (first type) 'vector))
     (unless (vectorp value)
       (%validation-error value path "Expected a vector"))
     (loop for item across value
           for index from 0
           do (validate-field item (second type)
                              :path (format nil "~@[~a~][~d]" path index))))
    (t
     (%validation-error value path "Unsupported type specification: ~S" type)))
  t)

(defun %field-value (object field-name)
  (etypecase object
    (hash-table
     (multiple-value-bind (value presentp) (gethash field-name object)
       (if presentp
           value
           (gethash (intern (symbol-name field-name) :keyword) object))))
    (list
     (or (getf object field-name)
         (getf object (intern (symbol-name field-name) :keyword))))
    (standard-object
     (slot-value object field-name))))

(defun validate-nested (object schema &optional (path ""))
  "Validate OBJECT fields according to SCHEMA entries (FIELD TYPE)."
  (loop for (field-name field-type) in schema
        for field-path = (if (string= path "")
                             (string-downcase (string field-name))
                             (format nil "~a.~(~a~)" path field-name))
        do (validate-field (%field-value object field-name) field-type
                           :path field-path))
  t)

(defmacro with-validation (&body body)
  "Run BODY while reporting validation failures before they unwind normally."
  `(handler-bind ((validation-error
                    (lambda (condition)
                      (format *error-output* "~&~a~%" condition))))
     ,@body))

(defun %object-slot-value-if-present (object slot-name)
  (when (typep object 'standard-object)
    (let* ((class-name (class-name (class-of object)))
           (class-package (and (symbolp class-name) (symbol-package class-name)))
           (local-name (and class-package
                            (find-symbol (symbol-name slot-name) class-package)))
           (effective-name (cond
                             ((slot-exists-p object slot-name) slot-name)
                             ((and local-name (slot-exists-p object local-name)) local-name))))
      (when effective-name
        (slot-value object effective-name)))))

(defun validate-model-schema (model &optional schema)
  "Validate MODEL using SCHEMA or an embedded SCHEMA slot.

When MODEL also has a DATA slot, the embedded schema describes that data
container rather than the wrapper object itself."
  (let* ((effective-schema (or schema
                               (%object-slot-value-if-present model 'schema)))
         (target (if (and (null schema)
                          (%object-slot-value-if-present model 'data))
                     (%object-slot-value-if-present model 'data)
                     model)))
    (unless effective-schema
      (error "No schema provided for validation"))
    (validate-nested target effective-schema)))
