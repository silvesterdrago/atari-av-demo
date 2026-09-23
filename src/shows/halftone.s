;======================================================================
;  HALFTONE
;
;  A printer's halftone screen: a fixed lattice of dots whose SIZES
;  carry the picture. The picture is three summed waves, which drift and
;  which MIDI leans on.
;
;  The arithmetic that decides the whole design is what a full screen
;  costs to touch at all. Even a straight copy runs at 4.6 cycles a
;  byte, so 32000 bytes is 1.3 frames: nothing that redraws every cell
;  every frame can hold 71 Hz. Two things get it back.
;
;  A dot's sprite covers its WHOLE cell, black surround included, so
;  there is no clearing pass and no ordering to respect. And a cell only
;  needs touching when its dot changes SIZE.
;
;  That was not enough on its own: the three waves share a phase, so the
;  field slides wholesale and a single frame can want every cell at once
;  -- measured at two frames a pass, 35 Hz. So the frame carries a
;  BUDGET of cells and the walk resumes next frame where it stopped,
;  rotating through the grid. The picture then lags the field by a frame
;  or two under load, which on a dot lattice is invisible, and the rate
;  stays put.
;
;  320 cells of 32x25, thirteen dot sizes, 700 cycles to redraw one.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 1
    include "src/core/head.s"

NCOL        equ 20              ; all six must match tools/genhalf.py
NROW        equ 16
NRAD        equ 13
CW          equ 4               ; cell width in BYTES
CH          equ 25
WAVES       equ 1300            ; three 256-byte tables
LEVELS      equ 2068            ; sum of waves -> dot size, no multiply
ROWB        equ 80
CELLSZ      equ CH*CW

; Spatial frequency, in wave steps a cell. At 11 a wave managed less than
; one cycle across twenty cells and the field read as a single smooth ramp;
; these give three-odd cycles each way, which is what makes blobs.
KX          equ 37
KY          equ 43
KD          equ 29
SP_BASE     equ 96              ; phase step a frame, 8.8
SP_DECAY    equ 24
SP_HIT      equ 5
FLASH_AT    equ 200
FLASH_LEN   equ 3
BUDGET      equ 68              ; cells redrawn a frame, at most:
                                ; 80*700 + the walk fits inside 112000

;----------------------------------------------------------------------
show_init:
    lea     sprite_ptr,a0       ; one pointer a dot size, so the frame
    lea     half_data,a1        ; needs no multiply to find a sprite
    moveq   #NRAD-1,d0
.sp:
    move.l  a1,(a0)+
    lea     CELLSZ(a1),a1
    dbra    d0,.sp

    lea     cell_prev,a0        ; nothing on screen yet, so every cell
    move.w  #NCOL*NROW-1,d0     ; is "changed" on the first frame
.zap:
    move.b  #$ff,(a0)+
    dbra    d0,.zap

    lea     rowbase,a0          ; where each band of cells starts
    move.l  cur_base,a1
    moveq   #NROW-1,d0
.rb:
    move.l  a1,(a0)+
    lea     CH*ROWB(a1),a1
    dbra    d0,.rb

    clr.w   ph1
    clr.w   ph2
    clr.w   ph3
    clr.w   scan_cx
    clr.w   scan_cy
    move.w  #SP_BASE,hspeed
    clr.w   hflash
    rts

;----------------------------------------------------------------------
show_frame:
    move.w  hspeed,d0           ; the drift settles back to its own pace
    cmp.w   #SP_BASE+SP_DECAY,d0
    bcs.s   .sk
    sub.w   #SP_DECAY,d0
    bra.s   .sp
.sk:
    move.w  #SP_BASE,d0
.sp:
    move.w  d0,hspeed
    add.w   d0,ph1
    add.w   d0,ph2
    add.w   d0,ph3

    tst.w   hflash
    beq.s   .noflash
    subq.w  #1,hflash
    bne.s   .noflash
    move.w  #$000,PALETTE_HW
.noflash:

    ; --- the three waves, sampled once per column, row and diagonal
    ; instead of once per cell: 71 samples instead of 960.
    lea     half_data+WAVES,a2      ; wave 0
    move.w  ph1,d1
    lsr.w   #8,d1
    lea     col_t,a0
    moveq   #0,d2
    moveq   #NCOL-1,d7
.mcol:
    move.w  d1,d3
    and.w   #$ff,d3
    move.b  0(a2,d3.w),(a0)+
    add.w   #KX,d1
    dbra    d7,.mcol

    lea     half_data+WAVES+256,a2  ; wave 1
    move.w  ph2,d1
    lsr.w   #8,d1
    lea     row_t,a0
    moveq   #NROW-1,d7
.mrow:
    move.w  d1,d3
    and.w   #$ff,d3
    move.b  0(a2,d3.w),(a0)+
    add.w   #KY,d1
    dbra    d7,.mrow

    lea     half_data+WAVES+512,a2  ; wave 2
    move.w  ph3,d1
    lsr.w   #8,d1
    lea     dia_t,a0
    moveq   #NCOL+NROW-2,d7
.mdia:
    move.w  d1,d3
    and.w   #$ff,d3
    move.b  0(a2,d3.w),(a0)+
    add.w   #KD,d1
    dbra    d7,.mdia

    ; --- walk the cells from wherever we stopped last frame, redrawing
    ; only those whose dot changed size, and only up to BUDGET of them
    lea     col_t,a2
    lea     dia_t,a3
    lea     half_data+LEVELS,a5
    lea     row_t,a6
    move.w  scan_cx,d6
    move.w  scan_cy,d7
    lea     cell_prev,a4
    move.w  d7,d0
    mulu    #NCOL,d0
    add.w   d6,d0
    adda.w  d0,a4
    move.b  0(a6,d7.w),d5
    and.w   #$ff,d5
    move.w  #BUDGET,budget
    move.w  #NCOL*NROW,scanleft
.cell:
    move.b  0(a2,d6.w),d0       ; this column's wave
    and.w   #$ff,d0
    add.w   d5,d0               ; plus this row's
    move.w  d6,d1
    add.w   d7,d1
    move.b  0(a3,d1.w),d1       ; plus this diagonal's
    and.w   #$ff,d1
    add.w   d1,d0               ; 0..252, so the level table takes it whole
    move.b  0(a5,d0.w),d0
    and.w   #$ff,d0
    cmp.b   (a4),d0
    beq.s   .same
    move.b  d0,(a4)
    lsl.w   #2,d0
    lea     sprite_ptr,a0
    move.l  0(a0,d0.w),a0
    move.w  d7,d1
    lsl.w   #2,d1
    lea     rowbase,a1
    move.l  0(a1,d1.w),a1
    move.w  d6,d1
    lsl.w   #2,d1
    adda.w  d1,a1               ; the cell's top-left
    bsr     blit_cell
    subq.w  #1,budget
.same:
    addq.l  #1,a4
    addq.w  #1,d6
    cmp.w   #NCOL,d6
    bcs.s   .onward
    clr.w   d6
    addq.w  #1,d7
    cmp.w   #NROW,d7
    bcs.s   .samerow
    clr.w   d7
    lea     cell_prev,a4        ; round the grid and back to the top
.samerow:
    move.b  0(a6,d7.w),d5
    and.w   #$ff,d5
.onward:
    subq.w  #1,scanleft
    beq.s   .stop
    tst.w   budget
    bne     .cell
.stop:
    move.w  d6,scan_cx
    move.w  d7,scan_cy
    rts

;----------------------------------------------------------------------
; a0 = sprite (CH rows of CW bytes), a1 = the cell's top-left.
; Unrolled: a displacement costs 8 cycles where stepping a1 costs 12 and
; a loop another 10, and this runs 320 times a frame.
;----------------------------------------------------------------------
blit_cell:
    include "src/shows/halftone_blit.inc"
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d2,-(sp)
    move.w  d0,d2
    mulu    #SP_HIT,d2
    add.w   #SP_BASE,d2
    cmp.w   #$0c00,d2
    bcs.s   .ok
    move.w  #$0c00,d2
.ok:
    move.w  d2,hspeed
    add.w   d1,d1               ; the pad also kicks the waves out of step
    add.w   d1,ph2
    sub.w   d1,ph3
    cmp.w   #FLASH_AT,d0
    bcs.s   .done
    move.w  #$777,PALETTE_HW
    move.w  #FLASH_LEN,hflash
.done:
    movem.l (sp)+,d0-d2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
half_data:
    incbin  "src/half.bin"

;----------------------------------------------------------------------
    section bss
    even
sprite_ptr:     ds.l NRAD
cell_prev:      ds.b NCOL*NROW
    even
col_t:          ds.b NCOL
row_t:          ds.b NROW
dia_t:          ds.b NCOL+NROW
    even
rowbase:        ds.l NROW
scan_cx:        ds.w 1
scan_cy:        ds.w 1
budget:         ds.w 1
scanleft:       ds.w 1
ph1:            ds.w 1
ph2:            ds.w 1
ph3:            ds.w 1
hspeed:         ds.w 1
hflash:         ds.w 1
    even
