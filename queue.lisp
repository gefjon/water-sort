;;;; This file defines a pretty trivial Coalton wrapper around Eric O'Connor's queues library,
;;;; https://github.com/oconnore/queues.
;; The implementation of A* in water-sort/package:find-solution uses a PriorityQueue to track its frontier of
;; nodes to search.
(uiop:define-package :water-sort/queue
  (:use :coalton :coalton-prelude)
  (:local-nicknames (#:q :queues))
  (:export
   #:PriorityQueue
   #:new
   #:insert!
   #:remove-min!
   #:peek-min!))
(in-package :water-sort/queue)

(coalton-toplevel
  (repr :native q:priority-queue)
  (define-type (PriorityQueue :cost :value))

  (declare get-queue-lt? (Ord :cost => Unit -> (Tuple :cost :value -> Tuple :cost :value -> Boolean)))
  (define (get-queue-lt?)
    (fn (a b)
      (match (Tuple a b)
        ((Tuple (Tuple a _) (Tuple b _)) (< a b)))))

  (declare make-priority-queue-from-lt? (Ord :cost =>
                                             (Tuple :cost :value -> Tuple :cost :value -> Boolean)
                                             -> PriorityQueue :cost :value))
  (define (make-priority-queue-from-lt? lt?)
    (lisp (PriorityQueue :cost :value) (lt?)
      (cl:flet ((coalton-priority-queue-lt? (a b)
                  (call-coalton-function lt? a b)))
        (q:make-queue ':priority-queue :compare #'coalton-priority-queue-lt?))))

  (declare new (Ord :cost => Unit -> PriorityQueue :cost :value))
  (define (new)
    (make-priority-queue-from-lt? (get-queue-lt?)))

  (declare insert! (Ord :cost => PriorityQueue :cost :value -> :cost -> :value -> Unit))
  (define (insert! q cost val)
    (let pair = (Tuple cost val))
    (lisp Unit (q pair)
      (q:qpush q pair)
      Unit))

  (declare remove-min! (Ord :cost => PriorityQueue :cost :value -> Optional (Tuple :cost :value)))
  (define (remove-min! q)
    (lisp (Optional (Tuple :cost :value)) (q)
      (cl:multiple-value-bind (pair presentp) (q:qpop q)
        (cl:if presentp
               (Some pair)
               None))))

  (declare peek-min! (Ord :cost => PriorityQueue :cost :value -> Optional (Tuple :cost :value)))
  (define (peek-min! q)
    (lisp (Optional (Tuple :cost :value)) (q)
      (cl:multiple-value-bind (pair presentp) (q:qtop q)
        (cl:if presentp
               (Some pair)
               None)))))
