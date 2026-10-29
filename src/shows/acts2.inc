; Act II: thin cross, bold cross, wedges, bold X, horizontals, nothing,
; verticals, and round to the thin cross again.
;
; The assignment is the whole art of it. The cross's horizontal bar is cut
; into four QUARTERS, left-upper to right-lower, so each one has a wedge of
; its own side to become and then an arm of the X on that same side: the
; figure opens out symmetrically instead of one bar crawling across the
; screen. Slots 4 and 5 are the vertical bar's two halves, which collapse
; into the centre for the wedges and the X. 6 and 7 only appear once there
; are eight stripes to fill.
    ; thin cross: the bar in four quarters, so each goes to its own wedge
    dc.w    120,320,120,320,194,200
    dc.w    120,320,120,320,200,206
    dc.w    320,520,320,520,194,200
    dc.w    320,520,320,520,200,206
    dc.w    314,326,314,326, 60,200
    dc.w    314,326,314,326,200,340
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; bold cross
    dc.w      0,320,  0,320,172,200
    dc.w      0,320,  0,320,200,228
    dc.w    320,640,320,640,172,200
    dc.w    320,640,320,640,200,228
    dc.w    292,348,292,348,  0,200
    dc.w    292,348,292,348,200,400
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; wedges: four triangles meeting at a point. The halves TILE -- the
    ; upper one ends on row 200 with its edge exactly at the centre and
    ; the lower one starts there, so the waist closes on that one row and
    ; opens again symmetrically, 5 px either side of it and 43 px eight
    ; rows out. Ending the upper half a row earlier leaves one row where
    ; neither reaches, which is the lens-shaped hole a patch over the
    ; junction used to cover -- and the patch then stuck out past the
    ; triangles as a pair of shoulders.
    dc.w      0,  0,  0,323, 80,201
    dc.w      0,320,  0,  0,200,320
    dc.w    640,640,317,640, 80,201
    dc.w    320,640,640,640,200,320
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; bold X: every wedge narrows into the arm on its own side
    dc.w      0, 70,285,355,  0,200
    dc.w    285,355,  0, 70,200,400
    dc.w    570,640,285,355,  0,200
    dc.w    285,355,570,640,200,400
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; horizontals
    dc.w      0,640,  0,640, 16, 38
    dc.w      0,640,  0,640, 64, 86
    dc.w      0,640,  0,640,112,134
    dc.w      0,640,  0,640,160,182
    dc.w      0,640,  0,640,208,230
    dc.w      0,640,  0,640,256,278
    dc.w      0,640,  0,640,304,326
    dc.w      0,640,  0,640,352,374
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; through the centre: the horizontals collapse to nothing and the
    ; verticals grow back out of it, rather than each stripe standing up
    ; where it is and the eight of them crossing into a staircase
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; verticals
    dc.w     24, 60, 24, 60,  0,400
    dc.w    100,136,100,136,  0,400
    dc.w    176,212,176,212,  0,400
    dc.w    252,288,252,288,  0,400
    dc.w    328,364,328,364,  0,400
    dc.w    404,440,404,440,  0,400
    dc.w    480,516,480,516,  0,400
    dc.w    556,592,556,592,  0,400
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; and round to the thin cross again
    dc.w    120,320,120,320,194,200
    dc.w    120,320,120,320,200,206
    dc.w    320,520,320,520,194,200
    dc.w    320,520,320,520,200,206
    dc.w    314,326,314,326, 60,200
    dc.w    314,326,314,326,200,340
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
