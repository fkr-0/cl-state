
;;(require "slynk")
(require "bordeaux-threads")
;; ;; ;; ;; ;; ;; ;; ;; (require "str")
(require "log4cl")

                                        ; (require "elmtui")
                                        ; (asdf:load-system "elmtui-tests")
                                        ; (in-package :elmtui.tests)
                                        ; (elmtui.tests:run-all-elmtui-tests)
(require "cl-state")
(asdf:load-system "cl-state")
(asdf:load-system "cl-state-tests")
(in-package :cl-state-tests)
(cl-state-tests:run-cl-state-tests)
                                        ; (ignore-errors
                                        ;   (asdf:load-system "cl-styles/tests")
                                        ;   (uiop:symbol-call '#:fiveam '#:run! (uiop:find-symbol* "SUITE" "CL-STYLES/TESTS")))
                                        ;(elmtui.tests:run-all-elmtui-tests)
;; (uiop:quit (if (run-all-elmtui-tests) 0 1))
;;
;;
                                        ; (progn 
                                        ;   (let* ((app-state (make-instance 'elmtui.tests.component-init::test-app-state))
                                        ;          (comp-id :debug-comp)
                                        ;          (comp-instance (make-instance 'elmtui.tests.component-init::test-simple-component :id comp-id))
                                        ;          (id-path `(:components ,comp-id)))
                                        ;     (multiple-value-bind (instance patches commands)
                                        ;         (elmtui.ui.api:init comp-instance :id-path id-path :initial-text "Debug Text" :initial-count 42)
                                        ;       (elmtui.tests.component-init::apply-patches app-state patches)
                                        ;       (format t "~&Accessor result: ~S~%" (elmtui.tests.component-init::test-simple-component-text app-state comp-instance))))
                                        ;   )
