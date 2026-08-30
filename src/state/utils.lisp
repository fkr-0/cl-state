;;; cl-state/src/state/utils.lisp
(in-package :cl-state.utils)

(defun %alist-p (obj)
  "True when OBJ is a proper association list (every element is a dotted pair)."
  (and (consp obj)
    (every #'consp obj)))

(defun %plist-like-p (obj)
  "Heuristic predicate for plist-like lists.

Accepts even-length lists with symbol/keyword keys in odd positions."
  (and (listp obj)
    (evenp (length obj))
    (loop for (k v) on obj by #'cddr
      always (symbolp k))))

(defun %empty-container-p (obj)
  (typecase obj
    (null t)
    (hash-table (zerop (hash-table-count obj)))
    (list (null obj))
    (t nil)))

(defun %get-entry (container key default)
  (typecase container
    (hash-table
      (multiple-value-bind (v foundp) (gethash key container)
        (if foundp v default)))
    (list
      (if (%alist-p container)
        (let ((pair (assoc key container :test #'eq)))
          (if pair (cdr pair) default))
        (getf container key default)))
    (t default)))

(defun %set-entry (container key value)
  "Destructively insert KEY => VALUE in CONTAINER; return the container."
  (when (null key)
    (error "SET-ENTRY: KEY cannot be NIL"))
  (cond
    ((hash-table-p container)
      (setf (gethash key container) value)
      container)
    ((null container)
      ;; nil container treated as empty plist
      (list key value))
    ((listp container)
      (if (%alist-p container)
        (let ((pair (assoc key container)))
          (if pair
            (setf (cdr pair) value)
            (nconc container (list (cons key value))))
          container)
        (progn
          (setf (getf container key) value)
          container)))
    (t (error "SET-ENTRY: unsupported container type ~S" (type-of container)))))

(defun %remove-entry (container key)
  "Remove KEY (single level). Returns two values: NEW-CONTAINER, REMOVEDP."
  (cond
    ((hash-table-p container)
      (values container (remhash key container)))
    ((listp container)
      (if (%alist-p container)
        (let* ((before (length container))
                (new (delete key container :key #'car :test #'eq :count 1)))
          (values new (/= before (length new))))
        (let ((foundp (remf container key)))
          (values container foundp))))
    (t (values container nil))))

(defgeneric get-path (path data &optional default)
  (:documentation "Read value at PATH inside DATA; return DEFAULT when missing."))

(defmethod get-path ((path null) data &optional default)
  (declare (ignore default))
  data)

(defmethod get-path ((path symbol) data &optional default)
  (%get-entry data path default))

(defmethod get-path ((path list) data &optional default)
  (let ((next (%get-entry data (car path) default)))
    (if (eq next default)
      default
      (get-path (cdr path) next default))))

(defmethod get-path ((path t) data &optional default)
  (declare (ignore data))
  default)

(defun set-path (data path value &key (createp t))
  "Store VALUE at PATH inside DATA, creating intermediate nodes when CREATEP."
  (etypecase path
    (symbol (%set-entry data path value))
    (list
      (if (= 1 (length path))
        (%set-entry data (car path) value)
        (let* ((key (car path))
                (rest (cdr path))
                (child (%get-entry data key nil)))
          (when (and (null child) (not createp))
            (error "Missing node ~S in path ~S and :CREATEP is NIL" key path))
          (let* ((child* (or child
                           (if (hash-table-p data)
                             (make-hash-table :test 'equal)
                             nil)))
                  (new-child (set-path child* rest value :createp createp)))
            (%set-entry data key new-child)))))
    (t (error "SET-PATH: invalid PATH ~S" path))))

(defun remove-path (data path &key (prune-empty t))
  "Delete item at PATH. Returns two values: NEW-DATA, REMOVEDP."
  (etypecase path
    (symbol (%remove-entry data path))
    (list
      (if (null (cdr path))
        (%remove-entry data (car path))
        (let* ((key (car path))
                (rest (cdr path))
                (child (%get-entry data key nil)))
          (if (null child)
            (values data nil)
            (multiple-value-bind (new-child removedp)
              (remove-path child rest :prune-empty prune-empty)
              (if (not removedp)
                (values data nil)
                (let ((child-empty (%empty-container-p new-child)))
                  (cond
                    ((and prune-empty child-empty)
                      (multiple-value-bind (data* _) (%remove-entry data key)
                        (declare (ignore _))
                        (values data* t)))
                    (child-empty
                      (values (%set-entry data key
                                (typecase child
                                  (hash-table (make-hash-table :test 'equal))
                                  (t nil)))
                        t))
                    (t
                      (values (%set-entry data key new-child) t))))))))))
    (t (values data nil))))

(defun plist->hash-table (plist &key (test 'equal))
  "Convert a plist to a hash-table. Recursively converts nested plist-like lists."
  (let ((ht (make-hash-table :test test)))
    (loop for (k v) on plist by #'cddr
      do (setf (gethash k ht)
           (if (%plist-like-p v)
             (plist->hash-table v :test test)
             v)))
    ht))

(defun hash-table->plist (table)
  "Convert a hash-table to a plist. Recursively converts nested hash-tables."
  (let (plist)
    (maphash (lambda (k v)
               (setf plist (list* k (if (hash-table-p v) (hash-table->plist v) v) plist)))
      table)
    plist))

(defun coerce-data (data backend)
  "Coerce DATA to BACKEND (:hash-table or :plist) when possible."
  (ecase backend
    (:hash-table
      (cond
        ((hash-table-p data) data)
        ((null data) (make-hash-table :test 'equal))
        ((%plist-like-p data) (plist->hash-table data))
        (t data)))
    (:plist
      (cond
        ((listp data) data)
        ((hash-table-p data) (hash-table->plist data))
        ((null data) nil)
        (t data)))))
