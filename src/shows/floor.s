;======================================================================
;  FLOOR -- the perspective floor, its transverse lines flying.
;
;  Frame 13 of their sequence; frame 14 is the same picture plus one
;  block standing on the horizon, which is another entry in genflip's
;  table rather than another scene.
;
;  Only the transverse lines move -- the depths ride step**(-phase)
;  while the longitudinal lines stand -- so one turn of phase maps the
;  set onto itself and the 24 baked frames loop seamlessly.
;
;  Three corrections to their generator ride in tools/sysload.py, not
;  here: the step is the depth set's own ratio, the depths are exactly
;  geometric, and the vertical is scaled to our 400 rows. SEQUENCE.md
;  carries why, and the one defect left -- the far line appearing out
;  of nothing partway through the turn.
;======================================================================
    include "src/shows/flipbook.inc"

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "FLOOR.DAT",0
    even
