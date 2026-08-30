;;; cl-state/src/state/observer.lisp
(in-package :cl-state.observer)

(defun %alist-get (key alist &optional default)
  (let ((pair (assoc key alist)))
    (if pair
        (cdr pair)
        default)))

(define-condition observer-notification-error (error)
  ((state :initarg :state :reader observer-notification-error-state)
   (key :initarg :key :reader observer-notification-error-key)
   (observer :initarg :observer :reader observer-notification-error-observer)
   (old-value :initarg :old-value :reader observer-notification-error-old-value)
   (new-value :initarg :new-value :reader observer-notification-error-new-value)
   (phase :initarg :phase :reader observer-notification-error-phase)
   (cause :initarg :cause :reader observer-notification-error-cause))
  (:documentation "Inspect an observer callback failure without hiding the original cause.")
  (:report
   (lambda (condition stream)
     (format stream "Observer ~S failed for ~S during ~S: ~A"
             (observer-notification-error-observer condition)
             (observer-notification-error-key condition)
             (observer-notification-error-phase condition)
             (observer-notification-error-cause condition)))))

(defun add-observer (app key fn)
  "Register runtime observer FN for KEY in APP.

Observer registration is runtime metadata, not logical model mutation. It is
therefore allowed on frozen snapshots, does not increment model VERSION or
REVISION, and is copied into a descendant strict snapshot only when that
descendant is committed."
  (check-type fn function)
  (bt:with-lock-held ((application-state-lock app))
    (let* ((observers (application-state-observers app))
           (pair (assoc key observers)))
      (if pair
          ;; Preserve registration order for deterministic notifications.
          (setf (cdr pair) (append (cdr pair) (list fn)))
          (push (cons key (list fn)) (application-state-observers app)))))
  fn)

(defun remove-observer (app key fn)
  "Remove runtime observer FN for KEY from APP.

This metadata operation is allowed on frozen snapshots and does not change the
logical model/version/revision/history. Returns true only when FN was registered
and removed."
  (bt:with-lock-held ((application-state-lock app))
    (let* ((observers (application-state-observers app))
           (pair (assoc key observers)))
      (when (and pair (member fn (cdr pair)))
        (setf (cdr pair) (remove fn (cdr pair)))
        (when (null (cdr pair))
          (setf (application-state-observers app)
                (remove pair (application-state-observers app) :test #'eq)))
        t))))

(defun notify-observers (app key old new &key (phase :manual))
  "Notify APP observers for KEY in registration order.

The observer list is captured while APP's internal lock is held, then the lock
is released before any callback executes. Observers fail fast by default. An
arbitrary callback error is wrapped in OBSERVER-NOTIFICATION-ERROR with the
callback, values, phase, and original cause. A handler may explicitly invoke
CONTINUE-OBSERVER-NOTIFICATION to skip that failed callback and continue with
later observers. Notification never rolls back logical state."
  (let ((observers
          (bt:with-lock-held ((application-state-lock app))
            (copy-list (%alist-get key (application-state-observers app))))))
    (dolist (fn observers)
      (restart-case
          (handler-case
              (funcall fn old new)
            (observer-notification-error (condition)
              (error condition))
            (error (cause)
              (error 'observer-notification-error
                     :state app
                     :key key
                     :observer fn
                     :old-value old
                     :new-value new
                     :phase phase
                     :cause cause)))
        (continue-observer-notification ()
          :report "Skip the failed observer and continue notifying later observers."
          nil)))))
