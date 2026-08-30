#!/usr/bin/env bash
clpm bundle exec --with-client sbcl -- --load ~/.sbclrc --load run-tests-clpm-state.lisp --non-interactive | tee test.log
