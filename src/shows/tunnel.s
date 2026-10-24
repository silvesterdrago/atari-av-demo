;======================================================================
;  TUNNEL -- frames at geometric depths, flowing toward the viewer.
;
;  The depths are ratio**k, so one turn of phase maps the set onto
;  itself: 24 baked frames loop seamlessly, as in HYPER, and the ST
;  only writes the screen base register.
;
;  Two corrections to the reference art, both the corridor's. A frame
;  is a band of the tunnel wall cut across the axis, so it thickens as
;  1/z**2 toward the viewer instead of taking a 1/z number from a
;  formula; and the corner edges are tapered bands sampled at the same
;  depths with the same thickness, so each is exactly as wide as the
;  frame it crosses and the junctions are joints rather than
;  collisions.
;======================================================================
    include "src/shows/flipbook.inc"

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "TUNNEL.DAT",0
    even
