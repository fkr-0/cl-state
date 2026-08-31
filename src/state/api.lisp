;;; cl-state/src/state/api.lisp
;;;
;;; Public API for cl-state
;;; This file serves as the main entry point that re-exports all public symbols
;;; from the cl-state subsystems (utils, core, patch, tx, observer, undo).

(in-package :cl-state.api)

(defun application-state-data (state)
  "Deprecated compatibility read returning an owned logical STATE snapshot.

This public façade no longer exposes the live backing container. Prefer
STATE-REF for a borrowed path read, STATE-VALUE for an owned path read, or
STATE-SNAPSHOT for the whole logical model. Framework internals that genuinely
need representation access must name CL-STATE.CORE:APPLICATION-STATE-DATA
explicitly."
  (state-snapshot state))

(defun (setf application-state-data) (new-value state)
  "Reject legacy public backing-store replacement with migration guidance."
  (declare (ignore new-value state))
  (error "CL-STATE.API:APPLICATION-STATE-DATA is a deprecated read-only snapshot API. Use STATE-SET/APPLY-PATCHES for mutation; raw representation access is confined to CL-STATE.CORE."))

(defun %externalize-state-log-entry (entry)
  (destructuring-bind (path old new) entry
    (list (copy-state-value path)
          (copy-state-value (cl-state.core::%external-state-change-value old))
          (copy-state-value (cl-state.core::%external-state-change-value new)))))

(defun application-state-log (state)
  "Return an owned compatibility view of STATE's mutation log.

Opaque internal missing/deletion markers are projected to :NOT-PRESENT and
:ELMTUI-DELETE-PATH.  Internal transaction/undo code continues to use
CL-STATE.CORE:APPLICATION-STATE-LOG directly so rollback identity is not lost."
  (check-type state application-state)
  (let ((log
          (bt:with-lock-held ((cl-state.core:application-state-lock state))
            (cl-state.core::%assert-state-write-available state :log-read)
            (cl-state.core::%detach-state-value-spine
             (cl-state.core:application-state-log state)))))
    (mapcar #'%externalize-state-log-entry log)))

(defun %internal-state-log-value (value)
  (case value
    (:not-present cl-state.core::+state-missing-value+)
    (:elmtui-delete-path cl-state.core::+state-deleted-value+)
    (otherwise (copy-state-value value))))

(defun %internalize-state-log-entry (entry)
  (destructuring-bind (path old new) entry
    (list (copy-state-value path)
          (%internal-state-log-value old)
          (%internal-state-log-value new))))

(defun (setf application-state-log) (new-log state)
  "Compatibility setter for the public externalized mutation-log representation."
  (check-type state application-state)
  (let ((internal (mapcar #'%internalize-state-log-entry new-log)))
    (bt:with-lock-held ((cl-state.core:application-state-lock state))
      (cl-state.core::%assert-state-write-available state :log-replace)
      (setf (cl-state.core:application-state-log state) internal)))
  new-log)

;;; The api.lisp file intentionally contains only package definitions and re-exports.
;;; All actual functionality is provided by the subsystems which are re-exported
;;; via the package definition in packages.lisp.
;;;
;;; To use cl-state, simply use the :cl-state.api package:
;;;   (use-package :cl-state.api)
;;;
;;; Or require individual subsystems:
;;;   (use-package :cl-state.core)
;;;   (use-package :cl-state.patch)
;;;   etc.
