;======================================================================
;  DRIFT -- the corridor losing its axis.
;
;  The vanishing point slides with depth: the near opening stays put and
;  everything behind it leans, so the corridor keeps its mouth and bends
;  away. Their axis_loss holds that offset fixed; the loop it came from
;  sweeps it, so here a full sine over the turn carries it out to one
;  side and back through the other, which also closes the loop.
;======================================================================
    include "src/shows/flipbook.inc"

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "DRIFT.DAT",0
    even
