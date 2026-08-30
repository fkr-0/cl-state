(in-package :cl-state.patch)

(defstruct patch-algebra-conflict left right relation reason)

(defstruct patch-inversion-failure patch reason)

(defun %patch-path-segments (path) (if (symbolp path) (list path) (copy-list path)))

(defun %path-prefix-p (prefix path) (and (< (length prefix) (length path)) (equal prefix (subseq path 0 (length prefix)))))

(defun %patch-path-relation (left right) (let ((left* (%patch-path-segments left)) (right* (%patch-path-segments right))) (cond ((equal left* right*) :same) ((%path-prefix-p left* right*) :ancestor) ((%path-prefix-p right* left*) :descendant) (t :disjoint))))

(defun %terminal-patch-op-p (operation) (member operation ' (:set :remove) :test #'eq))

(defun %compose-patch-pair (left right) "Return an ordered replacement sequence plus an optional non-collapse conflict." (let* ((left* (%normalize-patch left)) (right* (%normalize-patch right)) (relation (%patch-path-relation (patch-path left*) (patch-path right*)))) (cond ((and (eq relation :same) (%terminal-patch-op-p (patch-op left*)) (%terminal-patch-op-p (patch-op right*))) (values (list right*) nil)) ((eq relation :same) (values (list left* right*) (make-patch-algebra-conflict :left left* :right right* :relation relation :reason (if (or (eq (patch-op left*) :update) (eq (patch-op right*) :update)) :opaque-update :state-dependent-operation)))) ((member relation ' (:ancestor :descendant) :test #'eq) (values (list left* right*) (make-patch-algebra-conflict :left left* :right right* :relation relation :reason :overlapping-paths))) (t (values (list left* right*) nil)))))

(defun %compose-patches (patches) "Conservatively compact adjacent patches while preserving sequential application." (let ((result nil) (conflicts nil)) (dolist (patch (normalize-patches patches)) (if (null result) (push patch result) (multiple-value-bind (replacement conflict) (%compose-patch-pair (first result) patch) (when conflict (push conflict conflicts)) (if (= (length replacement) 1) (setf (first result) (first replacement)) (push (second replacement) result))))) (values (nreverse result) (nreverse conflicts))))

(defun %invert-patch (patch prior-value prior-present-p) "Return an inverse patch only when PATCH has an algebraic inverse from captured prior state." (let ((patch* (%normalize-patch patch))) (if (eq (patch-op patch*) :update) (values nil (make-patch-inversion-failure :patch patch* :reason :opaque-update)) (values (if prior-present-p (make-patch :path (patch-path patch*) :op :set :value (copy-state-value prior-value)) (make-patch :path (patch-path patch*) :op :remove :value nil)) nil))))

(defun %invert-change-record (change) "Invert one captured transaction change record without interpreting callback code." (destructuring-bind (path old new) change (declare (ignore new)) (if (cl-state.core::%state-missing-value-p old) (make-patch :path path :op :remove :value nil) (make-patch :path path :op :set :value (copy-state-value old)))))
