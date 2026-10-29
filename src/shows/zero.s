;======================================================================
;  ZERO -- act I, the shapes flowing into one another.
;
;      black -> point -> line -> two lines -> square -> black
;
;  Every composition in the act is axis-aligned bars, so the morph is an
;  interpolation of four rectangles and nothing else. Four slots carry
;  the whole act: in `line` they are the two halves of the bar, so it
;  splits symmetrically into the two verticals, and the square's top and
;  bottom grow out of zero-width bars parked at the centre.
;
;  Nothing is cleared but the four rectangles the other buffer last held,
;  which is about 3800 bytes rather than the screen's 32000. Drawing
;  masks the two edge bytes, so a bar's edge lands on the pixel rather
;  than the byte -- without that the morph steps eight pixels at a time,
;  which is the one thing a slow morph cannot hide.
;
;  A hit cuts the hold short and starts the next morph at once.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 20              ; one slot count for every act, so the
NSTATE      equ 6               ; tables are interchangeable
HOLD        equ 90              ; frames a composition sits still
MORPH       equ 150             ; frames it takes to become the next one

    include "src/shows/morph.inc"

;----------------------------------------------------------------------
    section data
    even
keys:
    include "src/shows/acts1.inc"
