;======================================================================
;  WAVE -- nine lines riding a travelling sine.
;
;  The sine's argument carries 2*pi*phase, so one turn of phase returns
;  every line to itself: 24 baked frames loop seamlessly and the ST only
;  writes the screen base register.
;
;  The reference art needed no correction here -- it is a flat scene, so
;  there are no perspective junctions to get wrong, and poly_line's
;  edges come out clean at this scale. Only the amplitude is ported: it
;  scales with the row spacing, 52 on their 360-row grid being 58 on
;  ours.
;======================================================================
    include "src/shows/flipbook.inc"

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "WAVE.DAT",0
    even
