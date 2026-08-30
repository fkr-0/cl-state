;;; cl-state/src/state/packages.lisp


(uiop/package:define-package :cl-state.utils (:use :cl :alexandria)
                             (:export #:get-path #:set-path #:remove-path #:plist->hash-table
                              #:hash-table->plist #:coerce-data))

(uiop/package:define-package :cl-state.core (:use :cl :alexandria :cl-state.utils)
                             (:export #:application-state #:application-state-p
                              #:make-application-state #:application-state-data
                              #:application-state-backend #:application-state-log
                              #:application-state-history #:application-state-undone
                              #:application-state-version #:application-state-revision
                              #:application-state-lock #:application-state-observers
                              #:*state-mutation-policy* #:state-mutation-forbidden
                              #:state-mutation-forbidden-state #:state-mutation-forbidden-path
                              #:state-mutation-forbidden-operation #:assert-state-mutation-allowed
                              #:state-conflict #:state-conflict-state #:state-conflict-operation
                              #:state-revision-conflict
                              #:state-revision-conflict-expected-revision
                              #:state-revision-conflict-actual-revision
                              #:state-transaction-conflict #:assert-state-revision
                              #:state-revision #:state-ref #:valid-state-path-p
                              #:assert-valid-state-path #:get-state #:state-set
                              #:state-set-if-revision #:make-state
                              #:set-application-state-backend #:deep-copy-data
                              #:deep-copy-application-state #:application-state-plist
                              #:get-component-by-path #:*transaction-active* #:copy-state-value
                              #:freeze-state-value #:persistent-state-value-p #:state-value #:state-value-at-revision
                              #:state-snapshot #:state-frozen-p))

(uiop/package:define-package :cl-state.patch (:use :cl :alexandria :cl-state.utils :cl-state.core) (:export #:patch #:patch-p #:make-patch #:patch-path #:patch-op #:patch-value #:apply-patch #:apply-patches #:apply-patches-persistent #:merge-patch #:merge-patches #:diff-states #:normalize-patches #:patch-validation-error #:patch-validation-error-input #:patch-validation-error-reason #:invalid-patch-format #:invalid-patch-path #:invalid-patch-path-path #:invalid-patch-operation #:invalid-patch-operation-operation #:invalid-patch-value #:invalid-patch-value-operation #:invalid-patch-value-value))

(uiop/package:define-package :cl-state.tx (:use :cl :alexandria :cl-state.utils :cl-state.core)
                             (:export #:tx #:tx-p #:make-tx #:tx-id #:tx-name #:tx-changes
                              #:with-transaction #:state-set #:undo #:redo #:*transaction-active*))

(uiop/package:define-package :cl-state.undo (:use :cl :alexandria)
                             (:export #:history #:make-history #:history-past #:history-future
                              #:push-snapshot #:history-undo #:history-redo))

(uiop/package:define-package :cl-state.observer (:use :cl :alexandria :cl-state.core)
                             (:export #:add-observer #:remove-observer #:notify-observers
                              #:observer-notification-error
                              #:observer-notification-error-state
                              #:observer-notification-error-key
                              #:observer-notification-error-observer
                              #:observer-notification-error-old-value
                              #:observer-notification-error-new-value
                              #:observer-notification-error-phase
                              #:observer-notification-error-cause
                              #:continue-observer-notification))

(uiop/package:define-package :cl-state.schema (:use :cl)
                             (:export :register-type-predicate :define-type-predicate
                              :lookup-type-predicate :list-registered-types :validate-type
                              :make-enum-predicate :register-enum-type :non-empty-string-p
                              :positive-integer-p :non-negative-integer-p :finite-number-p
                              :keyword-symbol-p))

(uiop/package:define-package :cl-state.validation (:use :cl)
                             (:import-from :cl-state.schema :register-type-predicate
                              :lookup-type-predicate)
                             (:export :validate-nested :validate-field :with-validation
                              :define-validator :register-type-validator :validate-model-schema
                              :make-validator :type-predicate :validation-error
                              :validation-error-message :validation-error-path
                              :validation-error-value))

(uiop/package:define-package :cl-state.api (:use :cl :cl-state.utils :cl-state.core :cl-state.patch :cl-state.observer :cl-state.tx :cl-state.schema :cl-state.validation) (:shadow #:application-state-data) (:shadowing-import-from :cl-state.undo #:history #:make-history #:history-past #:history-future #:push-snapshot) (:import-from :cl-state.undo #:history-undo #:history-redo) (:export #:get-path #:set-path #:remove-path #:plist->hash-table #:hash-table->plist #:coerce-data #:application-state #:application-state-p #:make-application-state #:application-state-data #:application-state-backend #:application-state-log #:application-state-history #:application-state-undone #:application-state-version #:application-state-revision #:state-revision #:application-state-lock #:application-state-observers #:*state-mutation-policy* #:state-mutation-forbidden #:state-mutation-forbidden-state #:state-mutation-forbidden-path #:state-mutation-forbidden-operation #:assert-state-mutation-allowed #:state-conflict #:state-conflict-state #:state-conflict-operation #:state-revision-conflict #:state-revision-conflict-expected-revision #:state-revision-conflict-actual-revision #:state-transaction-conflict #:assert-state-revision #:state-ref #:valid-state-path-p #:assert-valid-state-path #:get-state #:state-set #:state-set-if-revision #:make-state #:set-application-state-backend #:deep-copy-data #:deep-copy-application-state #:application-state-plist #:get-component-by-path #:patch #:patch-p #:make-patch #:patch-path #:patch-op #:patch-value #:apply-patch #:apply-patches #:apply-patches-persistent #:merge-patch #:merge-patches #:diff-states #:normalize-patches #:tx #:make-tx #:tx-p #:tx-id #:tx-name #:tx-changes #:with-transaction #:undo #:redo #:add-observer #:remove-observer #:notify-observers #:observer-notification-error #:observer-notification-error-state #:observer-notification-error-key #:observer-notification-error-observer #:observer-notification-error-old-value #:observer-notification-error-new-value #:observer-notification-error-phase #:observer-notification-error-cause #:continue-observer-notification #:history #:make-history #:history-past #:history-future #:push-snapshot #:history-undo #:history-redo #:register-type-predicate #:define-type-predicate #:lookup-type-predicate #:list-registered-types #:validate-type #:make-enum-predicate #:register-enum-type #:validate-nested #:validate-field #:with-validation #:define-validator #:register-type-validator #:validate-model-schema #:make-validator #:type-predicate #:validation-error #:validation-error-message #:validation-error-path #:validation-error-value #:copy-state-value #:freeze-state-value #:persistent-state-value-p #:state-value #:state-value-at-revision #:state-snapshot #:state-frozen-p #:patch-validation-error #:patch-validation-error-input #:patch-validation-error-reason #:invalid-patch-format #:invalid-patch-path #:invalid-patch-path-path #:invalid-patch-operation #:invalid-patch-operation-operation #:invalid-patch-value #:invalid-patch-value-operation #:invalid-patch-value-value))
