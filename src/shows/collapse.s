;======================================================================
;  COLLAPSE -- acts VII and VIII, the space folding up and going out.
;
;      compression -> square -> four corners -> two lines -> one line ->
;      dash -> point -> black
;
;  The end of their arc, frames 58-65, and the mirror of act I: there the
;  point opened into a square, here everything shuts back down to a point
;  and then to nothing. Five of the eight shapes are act I's own, which is
;  why the act is keyframes and no new engine -- the trapezoid morph is
;  src/shows/morph.inc, shared with act II.
;
;  Compression is their tunnel squeezed into a window, so it is drawn as
;  two rings, four corner edges and the end wall rather than baked: a
;  still of it could not then collapse into the square, and the collapse
;  is the act.
;
;  Slots split every shape at the middle of its sides, as act II does, so
;  a piece always has somewhere of its own to go: the square's four sides
;  break in half and the halves pull out to the four corners. A piece with
;  nowhere to go collapses into its own sibling rather than into the
;  centre -- the bottom verticals sink into the top ones -- which keeps
;  the movement local instead of everything rushing the middle.
;
;  Two rings, not three: a ring's two verticals are its whole cost, and
;  the nest is the one state here heavy enough to drop frames.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 20              ; one slot count for every act, so the
NSTATE      equ 9               ; tables are interchangeable
HOLD        equ 70
MORPH       equ 130

    include "src/shows/morph.inc"

;----------------------------------------------------------------------
    section data
    even
keys:
    include "src/shows/acts7.inc"
