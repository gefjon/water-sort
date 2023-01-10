(uiop:define-package :water-sort/package
  (:nicknames :water-sort)
  (:use :coalton :coalton-prelude)
  (:local-nicknames (#:iter :coalton-library/iterator)
                    (#:list :coalton-library/list)
                    (#:map :coalton-library/ord-map)
                    (#:hashtable :coalton-library/hashtable)
                    (#:math :coalton-library/math)
                    (#:queue :water-sort/queue))
  (:export
   #:make-puzzle
   #:Puzzle
   #:Move
   #:puzzle-try-pour
   #:solved?
   #:find-solution))
(in-package :water-sort/package)

(coalton-toplevel
  ;; Recently while on a long subway ride, a friend introduced me to my latest mobile game obsession, the
  ;; "water sort puzzle." There are a bunch of versions of it on the various app stores; the one I'm playing
  ;; is https://apps.apple.com/us/app/sort-water-color-puzzle/id1575680675. I played through about 100 levels
  ;; the next day, and then started to get fed up because it seemed like the kind of problem a computer would
  ;; be better at solving than me. In fact, it's a simpler version of the AI planning and optimization
  ;; problems I've devoted many hours at work to making computers solve. So here I am, writing a solution in
  ;; Coalton instead of progressing through the game's levels.

  ;; The "water sort puzzle" is set up as follows:
  ;; You are presented with some number of beakers, each of which can hold up to 4 units of liquid.

  ;; The beakers are initially filled with a variety of different colors of liquid, which do not mix.

  ;; For each color of liquid in the puzzle, there will always be exactly 4 units of that color distributed
  ;; around the initial state.

  ;; For example, a beaker might have one unit of red unit underneath one unit of blue liquid underneath one
  ;; unit of red liquid. The following is a sample initial state:
  ;; - (red green blue red)
  ;; - (blue green red red)
  ;; - (blue blue green green)
  ;; - ()

  ;; In our notation, the "top" of a beaker is leftmost, and the "bottom" is rightmost.
  ;;
  ;; Your goal is to consolidate the liquids of the same color, so that each vial either contains 4 units of
  ;; the same color of liquid, or is empty.

  ;; For example, the following is a solved state from the above initial state:
  ;; - ()
  ;; - (red red red red)
  ;; - (green green green green)
  ;; - (blue blue blue blue)

  ;; In order to accomplish this, you pour one beaker onto another, under the following constraints:
  ;; - You can only pour from the top of a beaker and onto the top of a beaker.
  ;; - You can only pour liquid onto liquid of the same color.
  ;; - You cannot pour into a full beaker.
  ;; - When you pour, liquid from the source beaker will be transferred into the destination beaker until
  ;;   either:
  ;;   - The next unit of liquid in the source beaker is of a different color.
  ;;   - The destination beaker is full.

  ;; Here are some example legal pours:
  ;; (green blue red red) onto (green blue red) => (blue red red) and (green green blue red)
  ;; (green green red red) onto (green red) => (red red) and (green green green red)
  ;; (green green red red) onto (green red red) => (green red red) and (green green red red)

  ;; Here are some example illegal pours:
  ;; (green blue red red) onto (blue green red) is illegal because the source and destination have different top colors.
  ;; (green blue red red) onto (green blue green red) is illegal because the destination is full.

  ;; An interesting (?) aside is that this is actually a solitaire variant, and you can play it with a deck of
  ;; cards. Determine your number of "colors" and "beakers," making sure that you have more of the latter than
  ;; the former. Assign each "color" to a card face value, and build a deck that has all four cards of each
  ;; "color" and no others. For example, if you're playing with three "colors," you want a deck that has all
  ;; four aces, all four twos and all four threes. Shuffle them, then deal them out into face-up piles of
  ;; four. From here, how to play should be obvious based on the rules above. Be warned: with large numbers of
  ;; colors and few initially-empty beakers, you'll probably get a lot of deals that are impossible to solve.

  ;;; representing game states

  ;; Defining an enum with all of the possible colors seems unnecessary and restrictive, so colors will be a
  ;; newtype around integers.
  (define-type Color
    (Color UFix))

  ;; We'll want to be able to compare colors with == so we know if two colors are compatible for pouring.
  (define-instance (Eq Color)
    (define (== c1 c2)
      (let (Color c1) = c1)
      (let (Color c2) = c2)
      (== c1 c2)))

  ;; We'll want to be able to sort colors with <=> so we can keep them (and collections of them) in ordered
  ;; maps and trees when representing our puzzles.
  (define-instance (Ord Color)
    (define (<=> c1 c2)
      (let (Color c1) = c1)
      (let (Color c2) = c2)
      (<=> c1 c2)))

  ;; We'll want to be able to hash colors so we can store them (and collections of them) when we search for
  ;; solutions.
  (define-instance (Hash Color)
    (define (hash c)
      (let (Color c) = c)
      (hash c)))

  ;; Because we're going to be doing backtracking tree search, we want our representation of beakers and
  ;; puzzles to be immutable and persistent. A beaker will be a list, with its "top" in its first and its
  ;; "bottom" in its last.
  (define-type Beaker
    ;; with length <= 4
    (Beaker (List Color)))

  ;; We want Ord and Hash instances on beakers for the same reasons as for colors, and those both require EQ.
  (define-instance (Eq Beaker)
    (define (== b1 b2)
      (let (Beaker b1) = b1)
      (let (Beaker b2) = b2)
      (== b1 b2)))

  ;; Like colors, we want to be able to sort beakers with <=> so we can keep them in ordered maps and trees
  ;; when representing our puzzles. The actual ordering beakers are sorted into doesn't matter for our
  ;; purpouses, as long as there is a total order between them. Coalton lists use lexographic order
  ;; (dictionary order), which is sufficient for our purposes.
  (define-instance (Ord Beaker)
    (define (<=> b1 b2)
      (let (Beaker b1) = b1)
      (let (Beaker b2) = b2)
      (<=> b1 b2)))

  ;; Like colors, we want to be able to hash beakers (and containers of beakers) when we search for solutions.
  (define-instance (Hash Beaker)
    (define (hash bk)
      (let (Beaker bk) = bk)
      (hash bk)))

  ;; Our first actually interesting representation choice: what is a puzzle? Obviously it's a collection of
  ;; beakers, but what kind of collection? The features we're looking for are:
  ;;
  ;; - Like with beakers, puzzles should be immutable and persistent so that we can do backtracking search on
  ;;   them. That is to say, when I do an operation on a puzzle to produce a new puzzle, I should still be
  ;;   able to hold onto and re-use the original, and it shouldn't have changed in any observable way.
  ;; - We'll be doing a lot of incremental modifications to puzzles, i.e. making individual moves which change
  ;;   the state of only two beakers at a time. These should be relatively fast and waste relatively little
  ;;   memory.
  ;; - It's possible to have multiple beakers with the same contents in a puzzle, but they aren't meaningfully
  ;;   distinct. That is, a puzzle with two empty beakers is different from a puzzle with one empty beaker,
  ;;   but the two empty beakers themselves are interchangeable.
  ;;
  ;; From these desires, what falls out is a persistent tree-based counter, that is, a tree sorted by the
  ;; beakers, and which associates each beaker with a count, representing the number of beakers like that in
  ;; the puzzle. Coalton's ord-map:Map will accomplish this nicely. ord-map is implemented as a persistent
  ;; red-black tree, so it has pretty good (i.e. O(logn)) time and memory usage on inserts and removes.
  ;;
  ;; To avoid the map growing larger than it should (to keep the n in that O(logn) small), we won't store
  ;; beakers with counts of zero, i.e. beakers which aren't in the puzzle.
  (define-type Puzzle
    (Puzzle (map:Map Beaker
                     ;; maps each variety of Beaker to the number of beakers in that configuration in the
                     ;; puzzle. zeros are not present.
                     UFix)))

  ;; We'll need to be able to hash puzzles when we search for solutions, and Hash requires Eq, so...
  (define-instance (Eq Puzzle)
    (define (== p1 p2)
      (let (Puzzle p1) = p1)
      (let (Puzzle p2) = p2)
      (== p1 p2)))

  ;; We'll need to be able to hash puzzles when we search for solutions.
  (define-instance (Hash Puzzle)
    (define (hash puz)
      (let (Puzzle puz) = puz)
      (hash puz)))

  ;;; making moves

  ;; Having a data representation of a pour isn't strictly necessary, and would be superfluous if we were only
  ;; building the game. But we're writing a solver, and our lives will be a lot easier if it spits out a
  ;; sequence of (PourInto SOURCE-BEAKER DESTINATION-BEAKER) than a sequence of game states between which we'd
  ;; have to determine the difference.
  (define-type Move
    (PourInto Beaker ; from
              Beaker ; into
              ))

  ;; Because of our functional programmer's obsession with persistent, immutable data structures, when we make
  ;; a move, we don't just alter the contents of the source and destination beakers. Instead, we construct a
  ;; new puzzle that's like our previous state, but with the old source and destination beakers removed, and
  ;; the new source and destination beakers added. To do that, we need to be able to add and remove beakers
  ;; from a puzzle. Because we don't store beakers which would have a count of zero, each of these functions
  ;; has to handle a few cases.

  ;; To add a beaker:
  ;; - If there are any beakers like that already in the puzzle, increment their count.
  ;; - If not, insert a new sort of beaker into the map with a count of 1.
  (declare add-beaker (Puzzle -> Beaker -> Puzzle))
  (define (add-beaker puz bk)
    (let (Puzzle puz) = puz)
    (match (map:update 1+ puz bk)
      ((Some puz) (Puzzle puz))
      ((None) (Puzzle (map:insert-or-replace puz bk 1)))))

  ;; To remove a beaker:
  ;; - If the beaker wasn't in the puzzle, return None to signal a failure.
  ;; - If there was exactly one such beaker in the puzzle, remove it from the map.
  ;; - If there were multiple such beakers in the puzzle, decrement their count.
  (declare remove-beaker (Puzzle -> Beaker -> Optional Puzzle))
  (define (remove-beaker puz bk)
    (let (Puzzle puz) = puz)
    (match (map:lookup puz bk)
      ((None) None)
      ((Some ct)
       (Some (Puzzle
               (if (> ct 1)
                   ;; both unwraps here are infallible because `lookup' already returned `Some'.
                   ;; if there's multiple beakers like this in the puzzle, decrement the count.
                   (unwrap (map:update 1- puz bk))
                   ;; if there was only one beaker like this in the puzzle, remove it from the map rather than
                   ;; storing a zero.
                   (unwrap (map:remove puz bk))))))))

  ;; This is a helper that does both a remove-beaker and an add-beaker, for when we replace an old beaker with
  ;; its new state after a pour.
  (declare replace-beaker (Puzzle -> Beaker -> Beaker -> Optional Puzzle))
  (define (replace-beaker puz old-bk new-bk)
    "Replace OLD-BK with NEW-BK within PUZ.

PUZ must contain at least one Beaker == to OLD-BK."
    (match (remove-beaker puz old-bk)
      ((None) None)
      ((Some puz) (Some (add-beaker puz new-bk)))))

  ;; Now the fun part: the logic for when it's possible to pour one beaker into another, and what the two
  ;; beakers look like after you do. For a given Move (PourInto SOURCE DESTINATION), we'll return None if it's
  ;; not possible to pour SOURCE into DESTINATION, or (Some (Tuple NEW-SOURCE NEW-DESTINATION)) if it is
  ;; possible.
  ;;
  ;; This function is a bit complex because it has to handle both of the cases that stop you from pouring:
  ;; - If the colors don't match
  ;; - If the destination beaker is full
  ;; and the behavior of pouring multiple units of the same color at once:
  ;; - If there's enough room in the destination to hold all of the same colored liquid on top of the source,
  ;;   it all goes. You can't intentionally do a partial pour.
  ;; - If there's not enough room in the destination to hold all of the same colored liquid on top of the
  ;;   source, as much as possible goes. You get a partial pour if a total pour is impossible.
  (declare try-pour (Move -> Optional (Tuple Beaker Beaker)))
  (define (try-pour pour)
    (let (PourInto (Beaker from) (Beaker into)) = pour)
    (let maybe-keep-pouring =
      ;; the `match' below tries to pour a single unit of liquid from FROM into INTO. this recursive helper
      ;; handles continuing to pour as long as possible.
      (the (List Color -> List Color -> (Tuple Beaker Beaker))
           (fn (from into)
             (match (try-pour (PourInto (Beaker from) (Beaker into)))
               ((Some tpl) tpl)
               ((None) (Tuple (Beaker from) (Beaker into)))))))
    (match (Tuple from into)
      ;; you can't pour from an empty beaker
      ((Tuple (Nil) _) None)
      ;; you can always pour into an empty beaker
      ((Tuple (Cons from-top from-bot)
              (Nil))
       (Some (maybe-keep-pouring from-bot (make-list from-top))))
      ;; you can only pour from a non-empty beaker into a non-empty beaker if:
      ;; - the top colors match
      ;; - the into beaker has space
      ((Tuple (Cons from-top from-bot)
              (Cons into-top into-bot))
       (if (or (/= from-top into-top)
               (>= (list:length into-bot) 3))
           None
           (Some (maybe-keep-pouring from-bot (Cons from-top (Cons into-top into-bot))))))))

  ;; This is a helper that combines try-pour with replace-beaker to return the whole updated puzzle after a
  ;; move, where try-pour just returns the two updated beakers.
  (declare puzzle-try-pour (Puzzle -> Move -> Optional Puzzle))
  (define (puzzle-try-pour puz pour)
    "Attempt to advance PUZ by pouring FROM into INTO.

FROM and INTO must both be Beakers contained in Puzzle. If FROM and INTO are ==, Puzzle must contain at least
two Beakers in that configuration."
    (let (PourInto from into) = pour)
    (match (try-pour pour)
      ((None) None)
      ((Some (Tuple new-from new-into))
       (match (replace-beaker puz from new-from)
         ((None) None)
         ((Some puz) (replace-beaker puz into new-into))))))

  ;; This is an interator over all the sorts of beakers in a puzzle alongside their counts. We'll use the
  ;; beaker when considering all the possible source beakers for all the possible moves in a puzzle, and the
  ;; count to decide if it's possible to pour a beaker into another beaker with the same contents.
  (declare puzzle-beakers-with-counts (Puzzle -> iter:Iterator (Tuple Beaker UFix)))
  (define (puzzle-beakers-with-counts puz)
    (let (Puzzle puz) = puz)
    (map:entries puz))

  ;; This is an iterator over all the sorts of beakers in a puzzle. We'll use it when considering all the
  ;; possible destination beakers for all the possible moves in a puzzle.
  (declare puzzle-unique-beakers (Puzzle -> iter:Iterator Beaker))
  (define (puzzle-unique-beakers puz)
    (let (Puzzle puz) = puz)
    (map:keys puz))

  ;; This is an iterator over all the possible legal moves in a puzzle. For each possible legal move, it
  ;; returns (Tuple MOVE NEW-STATE), where MOVE is the pour you did, and NEW-STATE is the puzzle configuration
  ;; after taking the move. That is, if (possible-pours PUZZLE) contains (Tuple MOVE NEW-STATE), then it is
  ;; possible and legal to take MOVE from PUZZLE, and taking that move results in NEW-PUZZLE. When we search
  ;; for solutions, these iterators will be the possible successor states from a puzzle configuration, and
  ;; we'll choose a sequence of them that gets us to a solution.
  (declare possible-pours (Puzzle -> iter:Iterator (Tuple Move Puzzle)))
  (define (possible-pours puz)
    "An iterator over all of the possible successor states from PUZ by making any valid move."
    (let pour-from = (fn (from count)
                       ;; we're interested only in unique beakers here because the result states from pouring
                       ;; a beaker A into either a beaker B or B' where (== B B') are the same
                       (pipe (puzzle-unique-beakers puz)
                             (map (fn (into)
                                    (if (and (== count 1) (== from into))
                                        ;; you can't pour from a beaker into itself, but you can potentially
                                        ;; pour between two beakers with the same contents. puzzle-try-pour
                                        ;; would catch this and return None, but we can save a bit of compute
                                        ;; by checking and bailing out early here.
                                        None
                                        (progn
                                          (let pour = (PourInto from into))
                                          (match (puzzle-try-pour puz pour)
                                            ((None) None)
                                            ((Some puz) (Some (Tuple pour puz))))))))
                             iter:unwrapped!)))
    ;; once again, we're interested only in unique beakers here, but we need to know the count to know if we
    ;; can pour A into A' where (== A A')
    (pipe (puzzle-beakers-with-counts puz)
          ;; also, it's never useful to pour from a "solved" beaker, i.e. an empty beaker or a full
          ;; consolidated beaker. so we'll skip those when determining our possible source beakers.
          (iter:filter! (uncurry (fn (beaker _) (not (beaker-solved? beaker)))))
          (map (uncurry pour-from))
          iter:flatten!))

  ;;; evaluating states

  ;; We'll be doing heuristic-guided search because I love implementing A* and throwing it at
  ;; problems. Contrary to Randall's guidance in https://xkcd.com/342/, A* is pretty much always better than
  ;; Dijkstra's algorithm, assuming you can write an admissible cost-prediction heuristic. A cost-prediction
  ;; heuristic is a function that, given a state, returns an estimation of the remaining work to reach a
  ;; destination. Such a heuristic is admissible if it's always an under-estimate. Admissible heuristics
  ;; matter because A* with an admissible heuristic will always find an optimal solution, i.e. a shortest path
  ;; from source to destination, but A* with an unadmissible heuristic may return a longer-than-optimal path.

  ;; In this game, it isn't really meaningful to talk about the "cost" of a single step; a pour is a pour. So
  ;; we'll say that each move costs 1.

  ;; The number of runs in a beaker is a good starting place for a cost heuristic, because a beaker with n
  ;; runs in it will take at least (1- n) moves to organize. At the very least you have to pour (1- n) times
  ;; to get the mismatched colors off the top.
  (declare count-runs (Beaker -> UFix))
  (define (count-runs bk)
    "Count the number of distinct groups of liquid, or runs, in BK.

Contiguous units of the same color are a run.

e.g.:
(count-runs Nil) => 0
(count-runs (make-list 0)) => 1
(count-runs (make-list 0 0)) => 1
(count-runs (make-list 0 0 1)) => 2
(count-runs (make-list 0 0 1 0)) => 3
"
    (match bk
      ((Beaker (Nil)) 0)
      ((Beaker (Cons first-clr rest))
       (let ((slurp-run (fn (lst clr count-so-far)
                       (match lst
                         ((Nil) count-so-far)
                         ((Cons other-clr rest)
                          (if (== clr other-clr)
                              (slurp-run rest clr count-so-far)
                              (slurp-run rest other-clr (1+ count-so-far))))))))
         (slurp-run rest first-clr 1)))))

  ;; But the number of runs in a beaker isn't correct as a cost heuristic, because a beaker with one run
  ;; (i.e. all the same color) requires no moves to make sorted, a beaker with two runs requires at least one
  ;; move, and so on. (1- n), like I said. But an empty beaker does not require -1 moves to sort, it requires
  ;; 0. So we need a little wrapper function here that does the 1- and handles the empty-beaker case.
  (declare beaker-cost (Beaker -> UFix))
  (define (beaker-cost bk)
    (match bk
      ((Beaker (Nil)) 0)
      (bk (1- (count-runs bk)))))

  ;; Once we can predict the cost of an individual beaker, the predicted cost of a whole puzzle is just the
  ;; sum of all its beakers.
  (declare puzzle-cost (Puzzle -> UFix))
  (define (puzzle-cost puz)
    (pipe (puzzle-beakers-with-counts puz)
          (map (uncurry (fn (bk count)
                          (* (beaker-cost bk) count))))
          iter:sum!))

  ;; In addition to predicting cost, we also need to know when we're done. We can't just use (== (puzzle-cost
  ;; STATE) 0) to tell if we're done, because that will return true for incomplete puzzles where the colors
  ;; are all separate, but some are not consolidated. For example, that would incorrectly call the following state solved:
  ;; - (red red red red)
  ;; - (blue blue blue)
  ;; - (blue)

  ;; Luckily, deciding if an individual beaker is solved is pretty easy; empty beakers are solved, and full
  ;; beakrs of a single color are solved. All others are not.
  (declare beaker-solved? (Beaker -> Boolean))
  (define (beaker-solved? bk)
    (match bk
      ((Beaker (Nil)) True)
      ((Beaker lst) (and (== (list:length lst) 4)
                         (== (count-runs bk) 1)))))

  ;; And deciding if a puzzle is solved is also easy; a puzzle is solved if all of its beakers are solved; if
  ;; any beakers are unsolved, the puzzle is unsolved.
  (declare solved? (Puzzle -> Boolean))
  (define (solved? puz)
    (iter:every! beaker-solved? (puzzle-unique-beakers puz)))

  ;;; searching for solutions

  ;; Now that we've defined our state space (Puzzles), our state transitions (Moves and possible-pours), our
  ;; cost prediction heuristic (puzzle-cost) and our destination state (solved?), we can just throw A*
  ;; at this thing and go home.

  ;; There are a lot of tree search algorithms, many of which use those same four components (and some of
  ;; which discard the cost prediction heuristic but use the other three). A* is a good place to start because
  ;; it's simple, has acceptible performance on small problems, and always finds an optimal solution given an
  ;; admissible heuristic. However, I feel obligated to give the disclaimer that it's not a great algorithm
  ;; for solving large problems. For large problems, you often don't care about finding an optimal solution,
  ;; you just want one that's pretty good. And ideally, on a modern multi-core computer, you want to be able
  ;; to search in parallel, but A* is woefully single-threaded.

  ;; Anyway, this problem is small, and A* will work. I'm not going to explain A*; if you don't know it, read
  ;; the Wikipedia article at https://en.wikipedia.org/wiki/A*_search_algorithm, and if that doesn't get you
  ;; there, sign up for an algorithms course at your university.

  ;; This implementation of A* is in a procedural style and uses mutable state in the form of hash tables and
  ;; a priority queue. Much as I love immutable, persistent programming, I believe A* (and most search
  ;; algorithms) are most cleanly and intuitively implemented in a procedural style with mutable
  ;; state. Luckily, Coalton makes that easy too!

  (declare find-solution (Puzzle -> Optional (Tuple (List Move) Puzzle)))
  (define (find-solution start)
    ;; a priority queue of states to search. lower-cost states will be searched first.
    (let frontier = (the (queue:PriorityQueue UFix Puzzle)
                         (queue:new)))
    (queue:insert! frontier 0 start)

    ;; for computing search heuristics, a map from states to the cost along the shortest path to reach them.
    (let cost-to-reach = (the (hashtable:Hashtable Puzzle UFix)
                              (hashtable:new)))
    (hashtable:set! cost-to-reach start 0)

    ;; for reconstructing paths, breadcrumb maps from each state to their predecessor and the move between the
    ;; two.
    (let previous-state = (the (hashtable:Hashtable Puzzle Puzzle)
                               (hashtable:new)))
    (let move-from-previous-state = (the (hashtable:Hashtable Puzzle Move)
                                         (hashtable:new)))

    ;; to avoid revisiting states, a map from state to visited? booleans. states not present in the map have
    ;; not been visited.
    (let visited = (the (hashtable:Hashtable Puzzle Boolean)
                        (hashtable:new)))

    (let predict-total-cost
      = (the (UFix -> Puzzle -> UFix)
             (fn (cost-to-reach state)
               (+ cost-to-reach (puzzle-cost state)))))

    (let new-shortest-path!
      = (the (UFix -> Puzzle -> Puzzle -> Move -> Unit)
             (fn (cost-to-new-state new-state predecessor move-from-predecessor)
               (hashtable:set! previous-state new-state predecessor)
               (hashtable:set! move-from-previous-state new-state move-from-predecessor)
               (hashtable:set! cost-to-reach new-state cost-to-new-state)
               (queue:insert! frontier
                              (predict-total-cost cost-to-new-state new-state)
                              new-state))))

    (let find-cost-to-reach
      = (the (Puzzle -> UFix)
             (fn (state)
               (with-default math:maxBound
                 (hashtable:get cost-to-reach state)))))

    (let possible-new-path!
      = (the (UFix -> Puzzle -> Puzzle -> Move -> Unit)
             (fn (cost-to-reach new-state predecessor move-from-predecessor)
               (when (< cost-to-reach (find-cost-to-reach new-state))
                 (new-shortest-path! cost-to-reach new-state predecessor move-from-predecessor)))))

    (let move-cost
      = (the (Move -> UFix)
             (const 1)))

    (let visited? =
      (the (Puzzle -> Boolean)
           (fn (state)
             (with-default False (hashtable:get visited state)))))

    (let queue-neighbors-for-visit!
      = (the (Puzzle -> UFix -> Unit)
             (fn (current-state cost-to-reach-current-state)
               (iter:for-each! (uncurry (fn (move new-state)
                                          (let cost-to-reach-new-state = (+ cost-to-reach-current-state (move-cost move)))
                                          (possible-new-path! cost-to-reach-new-state
                                                              new-state
                                                              current-state
                                                              move)))
                               (possible-pours current-state)))))

    (let ((visit!
            (the (Puzzle -> Optional (Tuple (List Move) Puzzle))
                 (fn (current-state)
                   (cond ((solved? current-state) (Some (Tuple (reverse (reconstruct-path current-state))
                                                               current-state)))
                         ((not (visited? current-state))
                          (progn
                            (hashtable:set! visited current-state True)
                            (queue-neighbors-for-visit! current-state (find-cost-to-reach current-state))
                            (search-loop!)))
                         (True (search-loop!))))))

          (search-loop!
            (the (Unit -> Optional (Tuple (List Move) Puzzle))
                 (fn ()
                   (match (queue:remove-min! frontier)
                     ((None) None)
                     ((Some (Tuple _ state)) (visit! state))))))

          (reconstruct-path
            (the (Puzzle -> List Move)
                 (fn (destination)
                   (match (Tuple (hashtable:get previous-state destination)
                                 (hashtable:get move-from-previous-state destination))
                     ((Tuple (None) (None)) Nil)
                     ((Tuple (Some prev) (Some move)) (Cons move (reconstruct-path prev)))
                     (_ (error "Should be impossible to have either a move-from-previous-state or a previous-state but not both!")))))))
      (search-loop!)))

  ;;; constructing puzzles

  ;; There's one last thing to do before we can solve our puzzles: we have to have a puzzle to solve. To make
  ;; constructing puzzles easy, we'll define a make-puzzle macro. You'll give it a list of colors that will
  ;; appear in your puzzle, and it will assign each of them a number. Then you'll list several beakers, using
  ;; the color names you listed above, and it will construct a puzzle that contains those beakers.

  ;; Macros should always strive to handle syntax only within the DEFMACRO, and keep all runtime logic within
  ;; ordinary functions. The ordinary functions in question are make-beaker, which takes a list of colors,
  ;; verifies that it's not larger than 4, and wraps it in a Beaker; and %make-puzzle, which takes a list of
  ;; lists of colors representing the beakers in a puzzle, calls make-beaker on each of them, and folds the
  ;; result into a Puzzle.

  (declare make-beaker (List Color -> Beaker))
  (define (make-beaker clrs)
    (if (> (list:length clrs) 4)
        (lisp :any (clrs)
          (cl:error "Beaker ~a has length > 4" clrs))
        (Beaker clrs)))

  (declare %make-puzzle (List (List Color) -> Puzzle))
  (define (%make-puzzle beakers)
    (pipe (iter:into-iter beakers)
          (map make-beaker)
          (iter:fold! add-beaker
                      (Puzzle map:empty)))))

(cl:defmacro make-puzzle (colors cl:&body beakers)
  "Construct a Puzzle containing the BEAKERS.

COLORS should be a list of symbols which name colors. Each will be assigned a unique integer for use in Color
objects.

BEAKERS should each be either:
- a list of color names from COLORS, denoting a beaker with those contents. The \"top\" of a beaker is on the
  left, and the \"bottom\" of a beaker is on the right.
- the symbol coalton:Nil denoting an empty beaker.

e.g.:

(make-puzzle (red green blue)
  (red green blue blue)
  (green red blue blue)
  (red green red green)
  Nil)

constructs a puzzle that might look graphically like:

<=====> <=====> <=====> <=====>
 | r |   | g |   | r |   |   |
 | g |   | r |   | g |   |   |
 | b |   | b |   | r |   |   |
 | b |   | b |   | g |   |   |
 \___/   \___/   \___/   \___/
"
  (cl:let ((color-idx -1))
    (cl:labels ((next-color ()
                  `(Color ,(cl:incf color-idx)))
                (color-binding-form (color-name)
                  `(,color-name ,(next-color)))
                (beaker-make-list (beaker)
                  (cl:if (cl:eq beaker 'Nil)
                         'Nil
                         `(make-list ,@beaker))))
      `(let ,(cl:mapcar #'color-binding-form colors)
         (%make-puzzle (make-list ,@(cl:mapcar #'beaker-make-list beakers)))))))

;; As of writing, I was stuck on level 133 of the app, which corresponds to the following make-puzzle form:

;; (make-puzzle (lime blue maroon baby-blue teal yellow navy-blue pink green orange grey magenta)
;;   (lime blue maroon lime)
;;   (blue baby-blue teal yellow)
;;   (yellow navy-blue teal yellow)
;;   (pink baby-blue green yellow)
;;   (orange pink navy-blue grey)
;;   (blue baby-blue navy-blue magenta)
;;   (teal green maroon maroon)
;;   (pink magenta lime maroon)
;;   (orange grey grey pink)
;;   (green lime teal magenta)
;;   (grey baby-blue orange navy-blue)
;;   (magenta blue green orange)
;;   Nil
;;   Nil)

;; I typed up said make-puzzle, and ran find-solution on it in the repl. Specifically, I loaded this ASDF
;; system with :COALTON-RELEASE enabled and my SBCL compiler optimization flags tuned for performance before
;; finding a solution, so my repl session looked like:

;; CL-USER> (push :coalton-release *features*)
;; (:COALTON-RELEASE #| other features elided |#)
;; CL-USER> (declaim (optimize (speed 3) (safety 1) (space 1) (debug 1) (compilation-speed 0)))
;; NIL
;; CL-USER> (asdf:load-system "coalton" :force :all)
;; #| boring compiler output elided |#
;; T
;; CL-USER> (asdf:load-system "water-sort")
;; #| boring compiler output elided |#
;; CL-USER> (in-package "water-sort")
;; WATER-SORT/PACKAGE> (coalton (find-solution (make-puzzle (lime blue maroon baby-blue teal yellow navy-blue pink green orange grey magenta)
;;                                               (lime blue maroon lime)
;;                                               (blue baby-blue teal yellow)
;;                                               (yellow navy-blue teal yellow)
;;                                               (pink baby-blue green yellow)
;;                                               (orange pink navy-blue grey)
;;                                               (blue baby-blue navy-blue magenta)
;;                                               (teal green maroon maroon)
;;                                               (pink magenta lime maroon)
;;                                               (orange grey grey pink)
;;                                               (green lime teal magenta)
;;                                               (grey baby-blue orange navy-blue)
;;                                               (magenta blue green orange)
;;                                               Nil
;;                                               Nil)))

;; It chugged along for a few seconds (12ish, according to CL:TIME, on my m1 MacBook Air), then spit out a
;; gnarly debug representation for the solution. I copied out the list of moves and used M-% (Emacs'
;; query-replace) a few times to clean it up and to replace the color numbers with their names. Then I plugged
;; the moves into the app, and sure enough, it worked!

;; The solution, after my cleaning, was:

;; (POURINTO (BEAKER (green lime teal magenta)) (BEAKER Nil))
;; (POURINTO (BEAKER (lime blue maroon lime)) (BEAKER (lime teal magenta)))
;; (POURINTO (BEAKER (blue baby-blue navy-blue magenta)) (BEAKER (blue maroon lime)))
;; (POURINTO (BEAKER (blue baby-blue teal yellow)) (BEAKER Nil))
;; (POURINTO (BEAKER (baby-blue teal yellow)) (BEAKER (baby-blue navy-blue magenta)))
;; (POURINTO (BEAKER (teal green maroon maroon)) (BEAKER (teal yellow)))
;; (POURINTO (BEAKER (green maroon maroon)) (BEAKER (green)))
;; (POURINTO (BEAKER (blue blue maroon lime)) (BEAKER (blue)))
;; (POURINTO (BEAKER (maroon lime)) (BEAKER (maroon maroon)))
;; (POURINTO (BEAKER (lime lime teal magenta)) (BEAKER (lime)))
;; (POURINTO (BEAKER (teal magenta)) (BEAKER (teal teal yellow)))
;; (POURINTO (BEAKER (magenta blue green orange)) (BEAKER (magenta)))
;; (POURINTO (BEAKER (blue green orange)) (BEAKER (blue blue blue)))
;; (POURINTO (BEAKER (green orange)) (BEAKER (green green)))
;; (POURINTO (BEAKER (orange grey grey pink)) (BEAKER (orange)))
;; (POURINTO (BEAKER (orange pink navy-blue grey)) (BEAKER (orange orange)))
;; (POURINTO (BEAKER (pink magenta lime maroon)) (BEAKER (pink navy-blue grey)))
;; (POURINTO (BEAKER (magenta lime maroon)) (BEAKER (magenta magenta)))
;; (POURINTO (BEAKER (grey baby-blue orange navy-blue)) (BEAKER (grey grey pink)))
;; (POURINTO (BEAKER (lime maroon)) (BEAKER (lime lime lime)))
;; (POURINTO (BEAKER (maroon)) (BEAKER (maroon maroon maroon)))
;; (POURINTO (BEAKER (baby-blue orange navy-blue)) (BEAKER Nil))
;; (POURINTO (BEAKER (orange navy-blue)) (BEAKER (orange orange orange)))
;; (POURINTO (BEAKER (baby-blue baby-blue navy-blue magenta)) (BEAKER (baby-blue)))
;; (POURINTO (BEAKER (navy-blue magenta)) (BEAKER (navy-blue)))
;; (POURINTO (BEAKER (magenta)) (BEAKER (magenta magenta magenta)))
;; (POURINTO (BEAKER (teal teal teal yellow)) (BEAKER Nil))
;; (POURINTO (BEAKER (yellow navy-blue teal yellow)) (BEAKER (yellow)))
;; (POURINTO (BEAKER (navy-blue teal yellow)) (BEAKER (navy-blue navy-blue)))
;; (POURINTO (BEAKER (teal yellow)) (BEAKER (teal teal teal)))
;; (POURINTO (BEAKER (yellow)) (BEAKER (yellow yellow)))
;; (POURINTO (BEAKER (pink pink navy-blue grey)) (BEAKER Nil))
;; (POURINTO (BEAKER (navy-blue grey)) (BEAKER (navy-blue navy-blue navy-blue)))
;; (POURINTO (BEAKER (grey grey grey pink)) (BEAKER (grey)))
;; (POURINTO (BEAKER (pink baby-blue green yellow)) (BEAKER (pink)))
;; (POURINTO (BEAKER (baby-blue green yellow)) (BEAKER (baby-blue baby-blue baby-blue)))
;; (POURINTO (BEAKER (green yellow)) (BEAKER (green green green)))
;; (POURINTO (BEAKER (yellow)) (BEAKER (yellow yellow yellow)))
;; (POURINTO (BEAKER (pink pink)) (BEAKER (pink pink)))
