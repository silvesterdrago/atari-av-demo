; Act I: black, point, line, two lines, square, and black again.
;
; Four slots carry the whole act. In `line` they are the two halves of the
; bar, so it splits symmetrically into the two verticals, and the square's
; top and bottom grow out of zero-width bars parked at the centre.
    ; black
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    rept 14
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; point
    dc.w     304, 336, 304, 336, 187, 213
    dc.w     304, 336, 304, 336, 187, 213
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    rept 14
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; line
    dc.w     192, 320, 192, 320, 192, 208
    dc.w     320, 448, 320, 448, 192, 208
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    rept 14
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; two lines
    dc.w     240, 272, 240, 272,  96, 304
    dc.w     368, 400, 368, 400,  96, 304
    dc.w     320, 320, 320, 320,  80, 106
    dc.w     320, 320, 320, 320, 294, 320
    rept 14
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; square
    dc.w     176, 208, 176, 208,  80, 320
    dc.w     432, 464, 432, 464,  80, 320
    dc.w     176, 464, 176, 464,  80, 106
    dc.w     176, 464, 176, 464, 294, 320
    rept 14
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
    ; and round to black again
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    dc.w     320, 320, 320, 320, 200, 200
    rept 14
    dc.w    320,320,320,320,200,200
    endr
    rept 2
    dc.w    320,320,320,320,200,200
    endr
