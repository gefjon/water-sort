# water-sort: a Coalton solution to the "Water Sort Puzzle" genre of apps
## By Phoebe Goldman

This is a somewhat naïve solution to [Sort Water Color
Puzzle](https://apps.apple.com/us/app/sort-water-color-puzzle/id1575680675) and the
various equivalent phone games in [Coalton](https://coalton-lang.github.io/). The code is
heavily commented and intended to be read as a literate document, so take a look at
<package.lisp>.

You can load the code like any Common Lisp package using `asdf:load-system` or
`ql:quickload`, and run tests using `asdf:test-system`, like:

```
CL-USER> (ql:quickload "water-sort")
CL-USER> (asdf:test-system "water-sort")
```

Because of the solution's naïveté, solving nontrivial puzzles will be relatively slow when
using Coalton in debug mode. The tests include one such nontrivial puzzle. I recommend
building in Coalton release mode with non-default SBCL compiler flags, like:

```
CL-USER> (push :coalton-release *features*)
CL-USER> (declaim (optimize (speed 3) (safety 1) (space 1) (debug 1) (compilation-speed 0)))
CL-USER> (asdf:load-system "coalton" :force :all)
CL-USER> (asdf:test-system "water-sort")
```
