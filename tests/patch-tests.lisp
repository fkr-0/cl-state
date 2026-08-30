;;;===============================================================
;;; File: cl-state/tests/patch-tests.lisp
;;; Unit tests for cl-state.patch module
;;;===============================================================
(uiop:define-package :cl-state-tests.patch
  (:use :cl :fiveam :cl-state.api)
  (:import-from #:cl-state.patch
                #:apply-patch
                #:apply-patches)
  (:export #:patch-suite
    #:run-patch-tests))

(in-package :cl-state-tests.patch)

(def-suite patch-suite
  :description "Tests for cl-state.patch module")

(in-suite patch-suite)

;;; make-patch tests

(test make-patch-struct
  "Creating patch structure"
  (let ((p (make-patch :path '(:a) :op :set :value 1)))
    (is (patch-p p))
    (is (equal '(:a) (patch-path p)))
    (is (eq :set (patch-op p)))
    (is (= 1 (patch-value p)))))

;;; normalize-patches tests

(test normalize-patches-lists
  "Normalizing list-format patches"
  (let ((patches (normalize-patches '(((:a) 1) ((:b) 2)))))
    (is (= 2 (length patches)))
    (is (equal '(:a) (patch-path (first patches))))
    (is (eq :set (patch-op (first patches))))))

(test normalize-patches-single-key-shorthand
  "A symbol path is the supported shorthand for a one-segment path."
  (let ((patch (first (normalize-patches '((:name "Bob"))))))
    (is (eq :name (patch-path patch)))
    (is (eq :set (patch-op patch)))
    (is (string= "Bob" (patch-value patch)))))

(test normalize-patches-patch-structs
  "Normalizing patch structures returns as-is"
  (let* ((p1 (make-patch :path '(:a) :op :set :value 1))
          (patches (normalize-patches (list p1))))
    (is (= 1 (length patches)))
    (is (eq p1 (first patches)))))

;;; merge-patch tests

(test merge-patch-basic
  "Merging single patch into state"
  (let ((ht (plist->hash-table '(:a 1))))
    (let ((result (merge-patch ht '((:b) 2))))
      (is (= 1 (gethash :a result)))
      (is (= 2 (gethash :b result))))))

(test merge-patch-nested
  "Merging nested patch"
  (let ((ht (plist->hash-table '(:user (:name "Alice")))))
    (let ((result (merge-patch ht '((:user :age) 30))))
      (is (equal "Alice" (get-path '(:user :name) result)))
      (is (= 30 (get-path '(:user :age) result))))))

(test merge-patch-delete
  "Merging delete patch"
  (let ((ht (plist->hash-table '(:a 1 :b 2))))
    (let ((result (merge-patch ht '((:b) :elmtui-delete-path))))
      (is (= 1 (gethash :a result)))
      (is (null (gethash :b result))))))

;;; merge-patches tests

(test merge-patches-multiple
  "Merging multiple patches"
  (let ((ht (plist->hash-table '(:a 1))))
    (let ((result (merge-patches ht '(((:b) 2) ((:c) 3)))))
      (is (= 1 (gethash :a result)))
      (is (= 2 (gethash :b result)))
      (is (= 3 (gethash :c result))))))

;;; apply-patch tests

(test apply-patch-set-op
  "Applying patch with :set operation"
  (let ((ht (plist->hash-table '(:a 1))))
    (let ((result (apply-patch ht (make-patch :path '(:b) :op :set :value 2))))
      (is (= 1 (gethash :a result)))
      (is (= 2 (gethash :b result))))))

(test apply-patch-remove-op
  "Applying patch with :remove operation"
  (let ((ht (plist->hash-table '(:a 1 :b 2))))
    (let ((result (apply-patch ht (make-patch :path '(:b) :op :remove))))
      (is (= 1 (gethash :a result)))
      (is (null (gethash :b result))))))

(test apply-patch-merge-op
  "Applying patch with :merge operation"
  (let ((ht (plist->hash-table '(:lst (1 2)))))
  (let ((result (apply-patch ht (make-patch :path '(:lst) :op :merge :value '(3 4)))))
    (is (equal '(3 4 1 2) (get-path '(:lst) result)))))

(test apply-patch-update-op
  "Applying patch with :update operation"
  (let ((ht (plist->hash-table '(:count 5))))
    (let ((result (apply-patch ht (make-patch :path '(:count) :op :update :value #'1+))))
      (is (= 6 (gethash :count result))))))

;;; apply-patches tests

(test apply-patches-multiple-ops
  "Applying multiple patches with different operations"
  (let ((ht (plist->hash-table '(:a 1 :b 2 :count 5))))
    (let ((patches (list (make-patch :path '(:c) :op :set :value 3)
                     (make-patch :path '(:b) :op :remove)
                     (make-patch :path '(:count) :op :update :value #'1+))))
      (let ((result (apply-patches ht patches)))
        (is (= 1 (gethash :a result)))
        (is (null (gethash :b result)))
        (is (= 3 (gethash :c result)))
        (is (= 6 (gethash :count result)))))))


(test apply-patches-application-state
  "Applying patches to application-state creates one undoable transaction."
  (let ((state (make-state :initial '(:components ()) :backend :hash-table)))
    (let ((result (apply-patches state '(((:components :panel) :ok)))))
      (is (eq state result))
      (is (equal :ok (get-path '(:components :panel) state)))
      (is (= 1 (length (application-state-history state)))))))

(test apply-patches-remove-is-undoable-and-redoable
  (let ((state (make-state :initial '(:item :present))))
    (apply-patches state
                   (list (make-patch :path :item :op :remove)))
    (is (null (get-path :item state)))
    (undo state)
    (is (eq :present (get-path :item state)))
    (redo state)
    (is (null (get-path :item state)))))

(test apply-patches-persistent-preserves-source-state
  "Persistent patch commit returns a replacement while leaving the prior state untouched."
  (let* ((source (make-state :initial '(:counter 1 :nested (:value 2))))
         (source-version (application-state-version source))
         (source-history-count (length (application-state-history source)))
         (next (apply-patches-persistent
                source
                '(((:counter) 2) ((:nested :value) 9))
                :name :strict-elm-test)))
    (is-false (eq source next))
    (is (= 1 (state-ref source :counter)))
    (is (= 2 (state-ref source '(:nested :value))))
    (is (= source-version (application-state-version source)))
    (is (= source-history-count (length (application-state-history source))))
    (is (= 2 (state-ref next :counter)))
    (is (= 9 (state-ref next '(:nested :value))))
    (is (> (application-state-version next) source-version))
    (is (= (1+ source-history-count)
           (length (application-state-history next))))))

(test persistent-and-transactional-commits-have-equivalent-logical-state
  "The strict and fast commit engines implement the same patch transition."
  (let* ((fast (make-state :initial '(:counter 3 :nested (:value 4))))
         (strict-source (deep-copy-application-state fast))
         (patches (list (make-patch :path :counter :op :update :value #'1+)
                        (make-patch :path '(:nested :value) :op :set :value 11)
                        (make-patch :path :new :op :set :value :present))))
    (apply-patches fast patches)
    (let ((strict (apply-patches-persistent strict-source patches)))
      (dolist (path '(:counter (:nested :value) :new))
        (is (equal (get-path path fast)
                   (get-path path strict))))
      (is (= 3 (state-ref strict-source :counter)))
      (is (= 4 (state-ref strict-source '(:nested :value)))))))

;;; diff-states tests

(test diff-states-no-changes
  "Diff of identical states returns empty list"
  (let ((ht1 (plist->hash-table '(:a 1 :b 2)))
         (ht2 (plist->hash-table '(:a 1 :b 2))))
    (is (null (diff-states ht1 ht2)))))

(test diff-states-simple-change
  "Detecting simple value changes"
  (let ((ht1 (plist->hash-table '(:a 1 :b 2)))
         (ht2 (plist->hash-table '(:a 99 :b 2))))
    (let ((diff (diff-states ht1 ht2)))
      (is (= 1 (length diff)))
      (is (equal '(:a) (first (first diff))))
      (is (= 99 (second (first diff)))))))

(test diff-states-new-key
  "Detecting new keys"
  (let ((ht1 (plist->hash-table '(:a 1)))
        (ht2 (plist->hash-table '(:a 1 :b 2))))
    (let ((diff (diff-states ht1 ht2)))
      (is (= 1 (length diff)))
      (is (equal '(:b) (first (first diff))))
      (is (= 2 (second (first diff))))))))

(test diff-states-nested-change
  "Detecting nested changes"
  (let ((ht1 (plist->hash-table '(:user (:name "Alice" :age 30))))
         (ht2 (plist->hash-table '(:user (:name "Bob" :age 30)))))
    (let ((diff (diff-states ht1 ht2)))
      (is (= 1 (length diff)))
      (is (equal '(:user :name) (first (first diff))))
      (is (equal "Bob" (second (first diff)))))))

(test diff-states-nested-new-key
  "Detecting new nested keys"
  (let ((ht1 (plist->hash-table '(:user (:name "Alice"))))
         (ht2 (plist->hash-table '(:user (:name "Alice" :age 30)))))
    (let ((diff (diff-states ht1 ht2)))
      (is (= 1 (length diff)))
      (is (equal '(:user :age) (first (first diff))))
      (is (= 30 (second (first diff)))))))

(test diff-states-multiple-changes
  "Detecting multiple changes"
  (let ((ht1 (plist->hash-table '(:a 1 :b 2 :c (:nested 3))))
         (ht2 (plist->hash-table '(:a 10 :b 2 :c (:nested 30)))))
    (let ((diff (diff-states ht1 ht2)))
      (is (= 2 (length diff)))
      ;; Check that both changes are present
      (is (some (lambda (d) (equal '(:a) (first d))) diff))
      (is (some (lambda (d) (equal '(:c :nested) (first d))) diff)))))

(defun run-patch-tests ()
  (run! 'patch-suite))

(test concurrent-application-state-update-fails-stale-instead-of-losing-write
  (let* ((state (make-state :initial '(:count 0)))
         (gate-lock (bt:make-lock "cl-state-update-race"))
         (gate-condition (bt:make-condition-variable :name "cl-state-update-race-cv"))
         (entered-p nil)
         (release-p nil)
         (observer-calls 0)
         (worker-error nil)
         (worker
           (progn
             (add-observer state :count
                           (lambda (old new)
                             (declare (ignore old new))
                             (incf observer-calls)))
             (bt:make-thread
              (lambda ()
                (handler-case
                    (apply-patch
                     state
                     (make-patch
                      :path :count
                      :op :update
                      :value
                      (lambda (current)
                        (bt:with-lock-held (gate-lock)
                          (setf entered-p t)
                          (bt:condition-notify gate-condition)
                          (loop until release-p
                                do (bt:condition-wait gate-condition gate-lock)))
                        (1+ current))))
                  (error (condition)
                    (setf worker-error condition))))
              :name "cl-state-update-race-worker"))))
    (bt:with-lock-held (gate-lock)
      (loop until entered-p
            do (bt:condition-wait gate-condition gate-lock)))
    (state-set state :count 10)
    (bt:with-lock-held (gate-lock)
      (setf release-p t)
      (bt:condition-notify gate-condition))
    (bt:join-thread worker)
    (is (typep worker-error 'state-revision-conflict))
    (is (= 10 (state-ref state :count)))
    (is (= 1 (state-revision state)))
    (is (= 1 observer-calls))))

(test application-state-update-callback-receives-owned-value
  (let* ((state (make-state :initial '(:payload (:value 1))))
         (borrowed (state-ref state :payload)))
    (apply-patch state
                 (make-patch
                  :path :payload
                  :op :update
                  :value (lambda (value)
                           (setf (gethash :value value) 9)
                           value)))
    (is (= 1 (gethash :value borrowed)))
    (is (= 9 (state-ref state '(:payload :value))))
    (is-false (eq borrowed (state-ref state :payload)))))
