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
