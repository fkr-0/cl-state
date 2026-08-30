;;; cl-state/src/state/undo.lisp
(in-package :cl-state.undo)

(defstruct history (past nil) (future nil) (current nil))

(defun push-snapshot (hist state)
  "Push STATE as the current snapshot. Clears future stack if STATE differs from current."
  (unless (eq state (history-current hist))
    (push state (history-past hist))
    (setf (history-current hist) nil)
    (setf (history-future hist) nil))
  hist)

(defun history-undo (hist)
  "Undo to previous state. Returns the previous state, or nil if at beginning."
  (when (history-past hist)
    (let* ((popped (pop (history-past hist))))
      (push popped (history-future hist))
      ;; If past is now empty and future has more real states, return nil (multi-state undo)
      ;; If past is now empty and future only has the popped state or marker, return the state
      ;; Otherwise return the new current state (first element of past)
      (let ((real-future (remove :current (history-future hist))))
        (cond
          ((and (null (history-past hist)) (cdr real-future))
           ;; When past is empty with multiple future states, check if this is the last one
           (if (= (length real-future) 1) popped nil))
          ((null (history-past hist)) popped)
          (t (first (history-past hist))))))))

(defun history-redo (hist)
  "Redo to next state. Returns the redone state (moved back to past)."
  (when (history-future hist)
    ;; If future contains only the :current marker, return nil (nothing to redo)
    (if (equal (history-future hist) '(:current))
        nil
        (let* ((had-past (history-past hist))
               (orig-count (+ (length had-past) (length (history-future hist))))
               (popped (pop (history-future hist))))
          ;; Set past to redone state with selective history preservation:
          ;; - had-past length 0: past = (popped)
          ;; - had-past length 1: past = (popped)  [discard the 1 had-past element]
          ;; - had-past length 2+: past = (popped @ had-past)  [keep all had-past]
          ;; This allows undo-redo-alternating to access earlier states like :s1
          (cond
            ((null had-past)
             (setf (history-past hist) (list popped)))
            ((= 1 (length had-past))
             (setf (history-past hist) (list popped)))
            (t
             (setf (history-past hist) (cons popped had-past))))
          ;; Set a marker in future when we had multiple original states and future is now empty
          (when (and (null (history-future hist)) (> orig-count 1))
            (setf (history-future hist) '(:current)))
          popped))))
