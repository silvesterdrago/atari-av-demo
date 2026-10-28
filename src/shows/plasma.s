;======================================================================
;  PLASMA
;
;  The ball plasma from MonogAtari (Cerebral Vortex, SV2013), on a plain
;  STF. A 40x25 lattice of 16x16 cells; the field is the demo's own:
;  two signed sines of period 16 and 32 cells summed four ways, then
;  level = 15 - |sum|/8 and the jump table folds that into nine disc
;  sizes, so the dots trace contour rings of the field (details in
;  tools/genplasma.py). Each disc is an unrolled routine of 16 word
;  stores out of mask registers. Nothing
;  in the original pass touches the blitter, so this is the same code
;  shape; the demo's blitter only cleared and copied screens, which the
;  core already does.
;
;  A pass redraws every cell, like the original, so it costs what 16 000
;  word stores cost. Read bar four for frames a pass takes.
;======================================================================
    ifnd SCENES
POOL_SIZE   equ 1024
    endif
    include "src/core/head.s"

NCOL        equ 40              ; must match tools/genplasma.py
NROW        equ 25
CH          equ 16              ; 25 rows of 16 fill the 400 lines
ROWB        equ 80

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
    clr.w   pl_t
    rts

;----------------------------------------------------------------------
show_frame:
    movem.l d0-d7/a0-a6,-(sp)
    move.l  buf_base,a1         ; draw into whichever screen is not shown
    cmp.l   cur_base,a1
    bne.s   .back
    add.l   #SCR_SIZE,a1
.back:
    move.l  a1,pl_back
    addq.w  #1,pl_t
    clr.w   pl_y

    move.w  #$0180,d3           ; disc row masks, widths 2..16
    move.w  #$03c0,d4
    move.w  #$07e0,d5
    move.w  #$0ff0,d6
    move.w  #$1ff8,d7
    move.w  #$3ffc,a4
    move.w  #$7ffe,a5
    move.w  #$ffff,a6
    lea     ball_tbl+512,a0     ; entry 128+s: a signed sum indexes it

.row:
    move.w  pl_y,d0
    move.w  pl_t,d1
    and.w   #127,d1
    lea     sin_a,a2
    lea     sin_b,a3
    adda.w  d1,a2               ; walked along x: sin_a[t+x] ...
    adda.w  d0,a3               ; ... and sin_b[y+x]
    ; the two terms constant along the row, sin_a[t+y] + sin_b[t+y],
    ; read through the walkers: y past sin_a+t, t past sin_b+y
    move.b  (a2,d0.w),d2
    add.b   (a3,d1.w),d2
    move.b  d2,d1
    moveq   #0,d0               ; the disc routines store d0 for an empty row
    rept    NCOL
    move.b  (a2)+,d2
    add.b   (a3)+,d2
    add.b   d1,d2               ; signed, within -124..124
    ext.w   d2
    add.w   d2,d2
    add.w   d2,d2               ; s*4 -> bra.w slot
    jsr     (a0,d2.w)           ; draws the cell, leaves a1 on the next
    endr
    lea     CH*ROWB-NCOL*2(a1),a1
    addq.w  #1,pl_y
    cmpi.w  #NROW,pl_y
    bne     .row

    move.l  pl_back,d0
    bsr     set_screen_base     ; the shifter picks it up at the next VBL
    addq.w  #1,show_ctr
    movem.l (sp)+,d0-d7/a0-a6
    rts

; a hit jumps the phase, so the field lurches with the beat
show_note_on:
    add.w   #8,pl_t
    rts

    include "src/plasma.inc"
    include "src/core/tail.s"

    section bss
pl_back:    ds.l 1
pl_t:       ds.w 1
pl_y:       ds.w 1
