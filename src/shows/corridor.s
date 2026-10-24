;======================================================================
;  CORRIDOR -- the mitred corridor, flying.
;
;  The same geometry the test screens settled, now moving: panels and
;  floor bars travel one panel period over the 24 baked frames, so the
;  set maps onto itself and the loop is seamless at any speed. Drawing
;  it live is out of the question -- one frame is some 50 filled quads
;  over most of the screen -- so it is played back, not drawn.
;======================================================================
    include "src/shows/flipbook.inc"

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "CORRIDOR.DAT",0
    even
