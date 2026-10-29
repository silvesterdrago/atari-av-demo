; Acts VII and VIII: compression, square, four corners, two lines, one
; line, dash, point, black, and round to the compression again.
;
;   0-3    the outer ring's horizontals, each side in halves
;   4-7    its verticals, likewise
;   8-11   the inner ring, whole bars
;   12     the end wall
;   13-16  the four corner edges
;   17     spare
    ; compression: the tunnel shut into a window. The corner edges run from
    ; the outer ring's inside corner to the end wall's, so each one lands on
    ; the wall along the wall's own thickness instead of crossing it -- the
    ; same joint the corridor and the tunnel needed.
    dc.w    176,320,176,320, 90,102
    dc.w    320,464,320,464, 90,102
    dc.w    176,320,176,320,298,310
    dc.w    320,464,320,464,298,310
    dc.w    176,188,176,188, 90,200
    dc.w    176,188,176,188,200,310
    dc.w    452,464,452,464, 90,200
    dc.w    452,464,452,464,200,310
    dc.w    238,402,238,402,152,161
    dc.w    238,402,238,402,239,248
    dc.w    238,247,238,247,152,248
    dc.w    393,402,393,402,152,248
    dc.w    296,344,296,344,186,214
    dc.w    188,196,296,304,102,186
    dc.w    444,452,336,344,102,186
    dc.w    296,304,188,196,214,298
    dc.w    336,344,444,452,214,298
    dc.w    320,320,320,320,200,200
    ; square: the rings and the edges go, the outer ring becomes the square
    dc.w    245,320,245,320,125,143
    dc.w    320,395,320,395,125,143
    dc.w    245,320,245,320,257,275
    dc.w    320,395,320,395,257,275
    dc.w    245,263,245,263,125,200
    dc.w    245,263,245,263,200,275
    dc.w    377,395,377,395,125,200
    dc.w    377,395,377,395,200,275
    rept 9
    dc.w    320,320,320,320,200,200
    endr
    dc.w    320,320,320,320,200,200
    ; four corners: each half-side pulls out to the corner it belongs to
    dc.w    210,280,210,280, 90,104
    dc.w    360,430,360,430, 90,104
    dc.w    210,280,210,280,296,310
    dc.w    360,430,360,430,296,310
    dc.w    210,224,210,224, 90,160
    dc.w    210,224,210,224,240,310
    dc.w    416,430,416,430, 90,160
    dc.w    416,430,416,430,240,310
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    ; two lines: the corner arms fold into one vertical a side, and the
    ; lower arms sink into the upper ones rather than crossing the middle
    rept 4
    dc.w    320,320,320,320,200,200
    endr
    dc.w    272,288,272,288,100,300
    dc.w    280,280,280,280,200,200
    dc.w    352,368,352,368,100,300
    dc.w    360,360,360,360,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    ; one line
    rept 4
    dc.w    320,320,320,320,200,200
    endr
    dc.w    312,328,312,328, 90,310
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    rept 10
    dc.w    320,320,320,320,200,200
    endr
    ; dash: the line lies down
    rept 4
    dc.w    320,320,320,320,200,200
    endr
    dc.w    285,355,285,355,194,206
    rept 13
    dc.w    320,320,320,320,200,200
    endr
    ; point
    rept 4
    dc.w    320,320,320,320,200,200
    endr
    dc.w    313,327,313,327,193,207
    rept 13
    dc.w    320,320,320,320,200,200
    endr
    ; black
    rept 18
    dc.w    320,320,320,320,200,200
    endr
    ; and round to the compression again
    dc.w    176,320,176,320, 90,102
    dc.w    320,464,320,464, 90,102
    dc.w    176,320,176,320,298,310
    dc.w    320,464,320,464,298,310
    dc.w    176,188,176,188, 90,200
    dc.w    176,188,176,188,200,310
    dc.w    452,464,452,464, 90,200
    dc.w    452,464,452,464,200,310
    dc.w    238,402,238,402,152,161
    dc.w    238,402,238,402,239,248
    dc.w    238,247,238,247,152,248
    dc.w    393,402,393,402,152,248
    dc.w    296,344,296,344,186,214
    dc.w    188,196,296,304,102,186
    dc.w    444,452,336,344,102,186
    dc.w    296,304,188,196,214,298
    dc.w    336,344,444,452,214,298
    dc.w    320,320,320,320,200,200
