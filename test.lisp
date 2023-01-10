(uiop:define-package :water-sort/test
  (:use :coalton :coalton-prelude :coalton-testing :water-sort/package)
  (:local-nicknames (#:list :coalton-library/list))
  (:export
   #:run-tests))
(in-package :water-sort/test)

(fiasco:define-test-package :water-sort/fiasco-test-package)

(cl:defun run-tests ()
  (fiasco:run-package-tests
   :packages '(:water-sort/fiasco-test-package)
   :interactive cl:t))

(coalton-fiasco-init :water-sort/fiasco-test-package)

(define-test empty-puzzle-is-solved ()
  (matches (Some (Tuple (Nil) _))
      (find-solution (make-puzzle () Nil))))

(define-test malformed-puzzle-no-solution ()
  (matches (None)
      (find-solution (make-puzzle (red)
                       (red red)
                       (red)))))

(define-test find-easy-solution ()
  (let puzzle = (make-puzzle (red)
                  (red red)
                  (red red)))
  (match (find-solution puzzle)
    ((None) (is False "Found no solution to easy puzzle"))
    ((Some (Tuple (Cons one-move (Nil)) end-state))
     (progn
       (is (== (Some end-state) (puzzle-try-pour puzzle one-move)))
       (is (solved? end-state))))
    (_ (is False "Found solution longer than 1 move to easy puzzle"))))

(define-test find-hard-solution ()
  ;; This is level 133 from https://apps.apple.com/us/app/sort-water-color-puzzle/id1575680675.

  ;; As of writing, I was stuck on this puzzle. I typed out this make-puzzle form, and in the repl, evaluated
  ;; find-solution on it. It took a few seconds on
  (let puzzle = (make-puzzle (lime blue maroon baby-blue teal yellow navy-blue pink green orange grey magenta)
                  (lime blue maroon lime)
                  (blue baby-blue teal yellow)
                  (yellow navy-blue teal yellow)
                  (pink baby-blue green yellow)
                  (orange pink navy-blue grey)
                  (blue baby-blue navy-blue magenta)
                  (teal green maroon maroon)
                  (pink magenta lime maroon)
                  (orange grey grey pink)
                  (green lime teal magenta)
                  (grey baby-blue orange navy-blue)
                  (magenta blue green orange)
                  Nil
                  Nil))
  (matches (Some (Tuple _ _))
      (find-solution puzzle)))
