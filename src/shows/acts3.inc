; Act III: nested squares, the pyramid of steps, and round again.
;
; Five rings, four bars each, and every ring's two horizontals have a step
; of their own to become: the bottom bar of a ring falls to a wide step low
; down, its top bar rises to a narrow one, and the outermost ring's top bar
; is the block that ends up on the summit. The verticals have nowhere to go,
; so each collapses to no width AT ITS OWN X, on the step its ring landed on
; -- the walls drop out of the picture where they stand instead of sliding
; to the middle.
;
;   0-3    the outer ring: top, bottom, left, right
;   4-7    the second, and so on inward
;   16-19  the innermost
    ; nested squares: side 368 at the rim, 0.7 of the one outside it, and
    ; the thickness shrinking with the side until it bottoms out
    dc.w     136, 504, 136, 504,  16,  32
    dc.w     136, 504, 136, 504, 368, 384
    dc.w     136, 152, 136, 152,  16, 384
    dc.w     488, 504, 488, 504,  16, 384
    dc.w     191, 449, 191, 449,  71,  82
    dc.w     191, 449, 191, 449, 318, 329
    dc.w     191, 202, 191, 202,  71, 329
    dc.w     438, 449, 438, 449,  71, 329
    dc.w     230, 410, 230, 410, 110, 118
    dc.w     230, 410, 230, 410, 282, 290
    dc.w     230, 238, 230, 238, 110, 290
    dc.w     402, 410, 402, 410, 110, 290
    dc.w     257, 383, 257, 383, 137, 144
    dc.w     257, 383, 257, 383, 256, 263
    dc.w     257, 264, 257, 264, 137, 263
    dc.w     376, 383, 376, 383, 137, 263
    dc.w     276, 364, 276, 364, 156, 163
    dc.w     276, 364, 276, 364, 237, 244
    dc.w     276, 283, 276, 283, 156, 244
    dc.w     357, 364, 357, 364, 156, 244
    ; steps: nine bars, each 0.84 of the one below it, and the block on top
    dc.w     288, 352, 288, 352, 110, 166
    dc.w      50, 590,  50, 590, 372, 384
    dc.w     144, 144, 144, 144, 372, 384
    dc.w     496, 496, 496, 496, 372, 384
    dc.w     253, 387, 253, 387, 164, 176
    dc.w      93, 547,  93, 547, 346, 358
    dc.w     196, 196, 196, 196, 346, 358
    dc.w     443, 443, 443, 443, 346, 358
    dc.w     240, 399, 240, 399, 190, 202
    dc.w     130, 511, 130, 511, 320, 332
    dc.w     234, 234, 234, 234, 320, 332
    dc.w     406, 406, 406, 406, 320, 332
    dc.w     225, 415, 225, 415, 216, 228
    dc.w     160, 480, 160, 480, 294, 306
    dc.w     260, 260, 260, 260, 294, 306
    dc.w     379, 379, 379, 379, 294, 306
    dc.w     207, 433, 207, 433, 242, 254
    dc.w     186, 455, 186, 455, 268, 280
    dc.w     279, 279, 279, 279, 268, 280
    dc.w     360, 360, 360, 360, 268, 280
    ; and round to the nested squares again
    dc.w     136, 504, 136, 504,  16,  32
    dc.w     136, 504, 136, 504, 368, 384
    dc.w     136, 152, 136, 152,  16, 384
    dc.w     488, 504, 488, 504,  16, 384
    dc.w     191, 449, 191, 449,  71,  82
    dc.w     191, 449, 191, 449, 318, 329
    dc.w     191, 202, 191, 202,  71, 329
    dc.w     438, 449, 438, 449,  71, 329
    dc.w     230, 410, 230, 410, 110, 118
    dc.w     230, 410, 230, 410, 282, 290
    dc.w     230, 238, 230, 238, 110, 290
    dc.w     402, 410, 402, 410, 110, 290
    dc.w     257, 383, 257, 383, 137, 144
    dc.w     257, 383, 257, 383, 256, 263
    dc.w     257, 264, 257, 264, 137, 263
    dc.w     376, 383, 376, 383, 137, 263
    dc.w     276, 364, 276, 364, 156, 163
    dc.w     276, 364, 276, 364, 237, 244
    dc.w     276, 283, 276, 283, 156, 244
    dc.w     357, 364, 357, 364, 156, 244
