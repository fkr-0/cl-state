(in-package :cl-state.core)

(defgeneric copy-state-value (value)
  (:documentation "Return an owned logical copy of VALUE for crossing a state ownership boundary.

Built-in hash tables, cons trees, and vectors are copied recursively. Immutable
atoms are returned as-is. Custom mutable leaf types should specialize this
generic and return an independent value."))

(defgeneric freeze-state-value (value)
  (:documentation "Return VALUE in a representation suitable for persistent structural sharing.

Built-in containers are recursively copied. Custom mutable leaf types should
specialize this generic to return an immutable/persistent representation when
strict snapshot semantics require more than COPY-STATE-VALUE."))

(defgeneric persistent-state-value-p (value)
  (:documentation "Return true when VALUE is known safe for persistent sharing under the state contract.

The predicate is diagnostic rather than an admission gate: unknown custom leaf
types return NIL for compatibility, while applications can specialize it after
providing COPY-STATE-VALUE/FREEZE-STATE-VALUE methods."))

(defmethod copy-state-value ((value hash-table))
  (let ((copy (make-hash-table :test (hash-table-test value)
                               :size (hash-table-size value)
                               :rehash-size (hash-table-rehash-size value)
                               :rehash-threshold (hash-table-rehash-threshold value))))
    (maphash (lambda (key item)
               (setf (gethash (copy-state-value key) copy)
                     (copy-state-value item)))
             value)
    copy))

(defmethod copy-state-value ((value cons))
  (cons (copy-state-value (car value))
        (copy-state-value (cdr value))))

(defmethod copy-state-value ((value vector))
  (let ((copy (copy-seq value)))
    (dotimes (index (length copy) copy)
      (setf (aref copy index)
            (copy-state-value (aref value index))))))

(defmethod copy-state-value ((value t)) value)

(defmethod freeze-state-value ((value hash-table))
  (let ((copy (make-hash-table :test (hash-table-test value)
                               :size (hash-table-size value)
                               :rehash-size (hash-table-rehash-size value)
                               :rehash-threshold (hash-table-rehash-threshold value))))
    (maphash (lambda (key item)
               (setf (gethash (freeze-state-value key) copy)
                     (freeze-state-value item)))
             value)
    copy))

(defmethod freeze-state-value ((value cons))
  (cons (freeze-state-value (car value))
        (freeze-state-value (cdr value))))

(defmethod freeze-state-value ((value vector))
  (let ((copy (copy-seq value)))
    (dotimes (index (length copy) copy)
      (setf (aref copy index)
            (freeze-state-value (aref value index))))))

(defmethod freeze-state-value ((value t)) value)

(defmethod persistent-state-value-p ((value hash-table))
  (loop for key being the hash-keys of value using (hash-value item)
        always (and (persistent-state-value-p key)
                    (persistent-state-value-p item))))

(defmethod persistent-state-value-p ((value cons))
  (and (persistent-state-value-p (car value))
       (persistent-state-value-p (cdr value))))

(defmethod persistent-state-value-p ((value vector))
  (loop for item across value
        always (persistent-state-value-p item)))

(defmethod persistent-state-value-p ((value t))
  (or (null value)
      (symbolp value)
      (numberp value)
      (characterp value)
      (functionp value)))
