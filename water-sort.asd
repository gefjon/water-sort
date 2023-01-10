(defsystem "water-sort"
  :author "Phoebe Goldman <phoebe@goldman-tribe.org>"
  :license "MIT"
  :depends-on ("coalton" "queues" "queues.priority-queue")
  :serial t
  :components ((:file "queue")
               (:file "package"))
  :in-order-to ((test-op (test-op "water-sort/test"))))

(defsystem "water-sort/test"
  :depends-on ("water-sort" "coalton/testing")
  :license "MIT"
  :serial t
  :components ((:file "test"))
  :perform (asdf:test-op (o s)
                         (symbol-call :water-sort/test :run-tests)))
