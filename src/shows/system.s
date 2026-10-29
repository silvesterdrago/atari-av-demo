;======================================================================
;  SYSTEM -- act III, the nested squares falling into a stack.
;
;      nested squares -> the pyramid of steps -> back
;
;  Frames 15 and 16 of their sequence. The act's other two, 13 and 14,
;  are the perspective floor, which is a flipbook off the card and so
;  lives in FLOOR.TOS -- these two are primitives and need nothing but
;  keyframes.
;
;  The table is src/shows/acts3.inc, shared with PRIMS.TOS.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 20              ; one slot count for every act, so the
NSTATE      equ 3               ; tables are interchangeable
HOLD        equ 70
MORPH       equ 130

    include "src/shows/morph.inc"

;----------------------------------------------------------------------
    section data
    even
keys:
    include "src/shows/acts3.inc"
