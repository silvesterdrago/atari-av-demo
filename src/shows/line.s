;======================================================================
;  LINE -- act II, the line opening out.
;
;      thin cross -> bold cross -> wedges -> bold X -> horizontals ->
;      nothing -> verticals -> back
;
;  The beat of nothing between the two stripe fields is deliberate. Each
;  stripe standing up where it stands crosses the others on the way, and
;  eight of them crossing came out as a staircase; collapsing them to the
;  centre and growing the next field out of it says the same thing in the
;  act's own grammar.
;
;  Act I only needed rectangles. This act needs the cross to fall open
;  into an X, so the primitive is a trapezoid and the engine lives in
;  src/shows/morph.inc; what is left here is this act's own keyframes.
;
;  Eight slots. Two carry the figure through every state -- the cross's
;  two bars become the left pair of wedges, then the two diagonals, then
;  the first two stripes -- and the other six grow out of a degenerate
;  span at the centre when a state has more parts than the one before.
;
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 18              ; one slot count for every act, so the
NSTATE      equ 8               ; tables are interchangeable
HOLD        equ 70
MORPH        equ 130

    include "src/shows/morph.inc"

;----------------------------------------------------------------------
    section data
    even
keys:
    include "src/shows/acts2.inc"
