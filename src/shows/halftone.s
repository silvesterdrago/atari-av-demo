;======================================================================
;  HALFTONE
;
;  A halftone ripple tank. A lattice of dots, small at rest; a pad sends
;  a ripple out from its anchor, swelling the dots it passes and
;  hollowing out its troughs; two ripples add, so they interfere; and
;  each fades as it travels.
;
;  What decides the design is what a full screen costs to touch at all:
;  even a straight copy runs at 4.6 cycles a byte, so 32000 bytes is 1.3
;  frames. Nothing that redraws every cell every frame holds 71 Hz.
;  Three things get it back.
;
;  A dot's sprite covers its WHOLE cell, black surround included, so
;  there is no clearing pass and no ordering to respect. A cell is only
;  touched when its dot changes SIZE. And a frame both LOOKS AT and
;  REDRAWS a bounded number of cells, resuming next frame where it
;  stopped and rotating through the grid -- so a hit that wants the whole
;  grid at once costs the picture a frame or two of lag instead of
;  costing the frame rate.
;
;  Both bounds are needed, which the measurements insisted on: with no
;  bound at all a pass took two frames (35 Hz), and bounding only the
;  redraws still left a third of the frames overrunning, because working
;  out the field costs about what drawing the dots costs.
;
;  Nothing is computed per cell that could be baked. The distance from
;  an anchor is a table, negated, so the frame adds the wavefront
;  position to it and has a phase. The ripple is a table of sixteen
;  amplitudes by 256 phases, holding a local packet -- two cycles that
;  decay -- so the ring reads as a ring and the spreading loss comes
;  free out of the amplitude decay. And the sum of the slots maps to a
;  dot size through a third table, so there is no multiply and no
;  clamping in the frame.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 1
    include "src/core/head.s"

NCOL        equ 20              ; all of these must match tools/genhalf.py
NROW        equ 16
NCELL       equ NCOL*NROW
NRAD        equ 13
CW          equ 4               ; cell width in BYTES
CH          equ 25
SPRITES     equ 0
LEVEL       equ 1300
PACKETS     equ 1556
DISTS       equ 5652
REST        equ 32              ; a slot's neutral contribution
ROWB        equ 80
CELLSZ      equ CH*CW

NSLOT       equ 2               ; ripples at once. Two interfere plainly and
                                ; their four pointers fit in address
                                ; registers, which four slots did not.
IDLE        equ (4-NSLOT)*REST  ; the level table is built around four
TSPEED      equ 3               ; wavefront steps a frame
DECAY       equ 5               ; frames per unit of amplitude lost
BUDGET      equ 32              ; cells redrawn a frame, at most
VISITS      equ 112             ; and cells LOOKED AT, which turned out to
                                ; be the real bill: capping redraws alone
                                ; left a third of the frames overrunning,
                                ; because the field costs as much to work
                                ; out as the dots cost to draw
FLASH_AT    equ 200
FLASH_LEN   equ 3
FREE_EVERY  equ 30              ; frames between ripples when nothing plays

;----------------------------------------------------------------------
show_init:
    lea     sprite_ptr,a0       ; one pointer a dot size, so the frame
    lea     half_data+SPRITES,a1
    moveq   #NRAD-1,d0
.sp:
    move.l  a1,(a0)+
    lea     CELLSZ(a1),a1
    dbra    d0,.sp

    lea     rowbase,a0          ; and one a band of cells
    move.l  cur_base,a1
    moveq   #NROW-1,d0
.rb:
    move.l  a1,(a0)+
    lea     CH*ROWB(a1),a1
    dbra    d0,.rb

    lea     cell_prev,a0        ; nothing on screen yet, so every cell
    move.w  #NCELL-1,d0         ; counts as changed on the first sweep
.zap:
    move.b  #$ff,(a0)+
    dbra    d0,.zap

    lea     slot,a0             ; both ripples silent
    moveq   #NSLOT-1,d0
.sl:
    clr.w   S_AMP(a0)
    clr.w   S_T(a0)
    clr.w   S_TICK(a0)
    move.l  #half_data+DISTS,S_NEG(a0)
    move.l  #half_data+PACKETS,S_PK(a0)
    lea     S_SIZE(a0),a0
    dbra    d0,.sl

    clr.w   scan_cx
    clr.w   scan_cy
    clr.w   hflash
    clr.w   free_ctr
    rts

;----------------------------------------------------------------------
show_frame:
    ; --- with nothing playing, ring an anchor now and then: a field of
    ; identical resting dots is not worth looking at
    cmp.w   #150,idle_ticks
    bcs.s   .played
    addq.w  #1,free_ctr
    cmp.w   #FREE_EVERY,free_ctr
    bcs.s   .played
    clr.w   free_ctr
    bsr     next_rng            ; clobbers d3 and d4, hence nothing of ours
    move.w  d3,d1
    and.w   #7,d1
    add.w   d1,d1               ; pad*2, the way poll_midi passes it
    move.w  #FLASH_AT-1,d0      ; a strong ripple, but one short of the
    bsr     show_note_on        ; threshold that flashes the palette

.played:

    tst.w   hflash
    beq.s   .noflash
    subq.w  #1,hflash
    bne.s   .noflash
    move.w  #$000,PALETTE_HW
.noflash:

    ; --- the ripples travel outward and fade
    lea     slot,a0
    moveq   #NSLOT-1,d7
.adv:
    tst.w   S_AMP(a0)
    beq.s   .quiet
    add.w   #TSPEED,S_T(a0)
    addq.w  #1,S_TICK(a0)
    cmp.w   #DECAY,S_TICK(a0)
    bcs.s   .quiet
    clr.w   S_TICK(a0)
    subq.w  #1,S_AMP(a0)
    move.w  S_AMP(a0),d0        ; the packet for this amplitude
    lsl.w   #8,d0
    and.l   #$ffff,d0           ; the high word is not ours
    add.l   #half_data+PACKETS,d0
    move.l  d0,S_PK(a0)
.quiet:
    lea     S_SIZE(a0),a0
    dbra    d7,.adv

    ; --- walk the cells from wherever we stopped, redrawing only those
    ; whose dot changed size, and only up to BUDGET of them
    move.w  scan_cy,d7
    move.w  scan_cx,d6
    move.w  d7,d0
    mulu    #NCOL,d0
    add.w   d6,d0               ; the cell we resume at
    lea     cell_prev,a4
    adda.w  d0,a4
    lea     slot,a1
    move.l  S_NEG(a1),a0        ; slot 0: distances, from this cell on
    adda.w  d0,a0
    move.l  S_PK(a1),a2
    move.w  S_T(a1),d4
    move.l  S_NEG+S_SIZE(a1),a1
    adda.w  d0,a1               ; slot 1
    lea     slot+S_SIZE,a3
    move.w  S_T(a3),d5
    move.l  S_PK(a3),a3
    lea     half_data+LEVEL,a5
    move.w  #BUDGET,budget
    move.w  #VISITS,scanleft

.cell:
    moveq   #IDLE,d0            ; the slots this show does not have
    move.b  (a0)+,d1            ; minus the distance from anchor 0
    add.w   d4,d1               ; plus where its wavefront is
    and.w   #$ff,d1
    move.b  0(a2,d1.w),d1       ; the ripple there
    add.w   d1,d0
    move.b  (a1)+,d1
    add.w   d5,d1
    and.w   #$ff,d1
    move.b  0(a3,d1.w),d1
    add.w   d1,d0               ; the two add, so they interfere
    move.b  0(a5,d0.w),d0       ; and that is a dot size
    and.w   #$ff,d0

    cmp.b   (a4),d0
    beq.s   .same
    move.b  d0,(a4)
    movem.l a0-a1,-(sp)         ; a0 and a1 are the two distance cursors;
    lsl.w   #2,d0               ; blit_cell wants the sprite and the cell
    lea     sprite_ptr,a6
    move.l  0(a6,d0.w),a0
    move.w  d7,d1
    lsl.w   #2,d1
    lea     rowbase,a6
    move.l  0(a6,d1.w),a1
    move.w  d6,d1
    lsl.w   #2,d1
    adda.w  d1,a1               ; the cell's top-left
    bsr     blit_cell
    movem.l (sp)+,a0-a1
    subq.w  #1,budget
.same:
    addq.l  #1,a4
    addq.w  #1,d6
    cmp.w   #NCOL,d6
    bcs.s   .onward
    clr.w   d6
    addq.w  #1,d7
    cmp.w   #NROW,d7
    bcs.s   .onward
    clr.w   d7                  ; round the grid and back to the top
    lea     cell_prev,a4
    move.l  slot+S_NEG,a0
    move.l  slot+S_SIZE+S_NEG,a1
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
; a loop another 10, and this runs up to BUDGET times a frame.
;----------------------------------------------------------------------
blit_cell:
    include "src/shows/halftone_blit.inc"
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d3/a0-a1,-(sp)

    lea     slot,a0             ; the quieter slot gives way
    move.w  S_AMP(a0),d2
    cmp.w   S_AMP+S_SIZE(a0),d2
    bls.s   .got
    lea     S_SIZE(a0),a0
.got:
    move.w  d0,d2               ; velocity sets the amplitude, 1..15
    lsr.w   #4,d2
    addq.w  #1,d2
    cmp.w   #16,d2
    bcs.s   .amp
    moveq   #15,d2
.amp:
    move.w  d2,S_AMP(a0)
    clr.w   S_T(a0)             ; a new ripple starts at its anchor
    clr.w   S_TICK(a0)
    lsl.w   #8,d2
    and.l   #$ffff,d2
    add.l   #half_data+PACKETS,d2
    move.l  d2,S_PK(a0)
    lsr.w   #1,d1               ; the pad picks the anchor
    and.w   #7,d1
    mulu    #NCELL,d1
    add.l   #half_data+DISTS,d1
    move.l  d1,S_NEG(a0)

    cmp.w   #FLASH_AT,d0
    bcs.s   .done
    move.w  #$777,PALETTE_HW
    move.w  #FLASH_LEN,hflash
.done:
    movem.l (sp)+,d0-d3/a0-a1
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
half_data:
    incbin  "src/half.bin"

;----------------------------------------------------------------------
; one ripple slot
S_AMP       equ 0               ; 0 = silent
S_T         equ 2               ; where its wavefront has got to
S_TICK      equ 4               ; frames since it last lost amplitude
S_NEG       equ 6               ; its anchor's minus-distance table
S_PK        equ 10              ; the packet for its amplitude
S_SIZE      equ 14

    section bss
    even
slot:           ds.b NSLOT*S_SIZE
    even
sprite_ptr:     ds.l NRAD
rowbase:        ds.l NROW
cell_prev:      ds.b NCELL
    even
scan_cx:        ds.w 1
scan_cy:        ds.w 1
budget:         ds.w 1
scanleft:       ds.w 1
hflash:         ds.w 1
free_ctr:       ds.w 1
    even
