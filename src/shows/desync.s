;======================================================================
;  DESYNC -- one corridor, two halves, out of step.
;
;  The left half runs half a turn ahead of the right, and the right sits
;  sixteen rows low, so the floor bars and the panels meet nothing at the
;  seam. Both halves are the same corridor, so one turn of phase returns
;  the pair to itself: 24 baked frames, and the ST only writes the screen
;  base register.
;======================================================================
    include "src/shows/flipbook.inc"

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "DESYNC.DAT",0
    even
