;======================================================================
;  SHAPES
;
;  The cubes show, but every pad gets a different solid: cube, cut stone,
;  octahedron, plus, tetrahedron, star, hex prism, pyramid. A hit swells
;  its shape and spins it faster; the swell decays back down. Hard hits
;  tear the shape into horizontal slabs, and dense playing slips the whole
;  picture sideways.
;
;  As with the cubes, the rotation is baked by tools/genshapes.py and the
;  ST only blits. Eight solids at eight scales and twelve angles in a
;  64x64 box is 384 KB; the cubes show's 96x96 box would have been 663 KB,
;  which is uncomfortable in 1 MB next to ~100 KB of BSS.
;======================================================================
    include "src/core/head.s"

SH_W_BYTES  equ 8               ; 64 px
SH_H        equ 64
SH_SPRITE   equ SH_W_BYTES*SH_H
SH_SCALES   equ 8
SH_ANGLES   equ 12
SH_DECAY    equ 5
GLITCH_AT   equ 240             ; curved strength at which the shape tears
GLITCH_LEN  equ 14
SHEAR_AT    equ $e0             ; accumulated energy, not single-hit velocity

;----------------------------------------------------------------------
show_init:
    ; grid: four cells across, two down, same as the pads
    move.w  row_bytes,d5
    lsr.w   #2,d5               ; cell width in bytes
    move.w  scr_rows,d6
    lsr.w   #1,d6               ; cell height in rows
    move.w  d5,d2
    sub.w   #SH_W_BYTES,d2
    lsr.w   #1,d2               ; box x offset within the cell
    move.w  d6,d3
    sub.w   #SH_H,d3
    lsr.w   #1,d3               ; box y offset within the cell

    lea     cell_org,a0
    moveq   #0,d4
.mk:
    move.w  d4,d0
    and.w   #3,d0
    mulu    d5,d0
    add.w   d2,d0
    and.l   #$ffff,d0
    move.w  d4,d1
    lsr.w   #2,d1
    mulu    d6,d1
    add.w   d3,d1
    and.l   #$ffff,d1
    mulu    row_bytes,d1
    add.l   d0,d1
    move.l  buf_base,a1
    add.l   d1,a1
    move.l  a1,(a0)+
    addq.w  #1,d4
    cmp.w   #8,d4
    bcs.s   .mk

    ; clear past the visible screen so the shear slides black into view
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1
    bsr     clear_span

    lea     cell_level,a0
    moveq   #(8*3)-1,d0
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    clr.w   free_ctr
    clr.w   shear_ctr
    clr.w   shear_cool
    rts

;----------------------------------------------------------------------
show_frame:
    ; with nothing plugged in, hit shapes at random so the screen lives
    cmp.w   #150,idle_ticks
    bcs.s   .nofree
    addq.w  #1,free_ctr
    cmp.w   #14,free_ctr
    bcs.s   .nofree
    clr.w   free_ctr
    bsr     next_rng
    move.w  d3,d0
    and.w   #7,d0
    add.w   d0,d0
    lea     cell_level,a0
    move.w  #$ff,(a0,d0.w)
.nofree:

    moveq   #0,d7
.each:
    move.w  d7,d0
    add.w   d0,d0               ; word index

    lea     cell_level,a0
    move.w  (a0,d0.w),d1
    sub.w   #SH_DECAY,d1
    bpl.s   .lv
    moveq   #0,d1
.lv:
    move.w  d1,(a0,d0.w)

    lea     cell_angle,a0
    move.w  (a0,d0.w),d2
    move.w  d1,d3
    lsr.w   #4,d3
    addq.w  #6,d3
    add.w   d3,d2
    move.w  d2,(a0,d0.w)

    lea     cell_glitch,a0
    move.w  (a0,d0.w),d4
    beq.s   .noglitch
    subq.w  #1,d4
    move.w  d4,(a0,d0.w)
.noglitch:

    ; --- pick the sprite: ((shape*SCALES + scale)*ANGLES + angle)
    move.w  d1,d5
    lsr.w   #5,d5               ; scale 0..7
    cmp.w   #SH_SCALES,d5
    bcs.s   .sok
    moveq   #SH_SCALES-1,d5
.sok:
    move.w  d7,d6               ; shape index == pad index
    mulu    #SH_SCALES,d6
    add.w   d5,d6
    mulu    #SH_ANGLES,d6
    move.w  d2,d5
    lsr.w   #8,d5
    and.l   #$ff,d5             ; and.L: divu divides the whole 32-bit
                                ; register, so leftovers in the high word
                                ; corrupt the result -- or overflow it, in
                                ; which case divu leaves the register alone
    divu    #SH_ANGLES,d5       ; remainder is the angle
    swap    d5
    add.w   d5,d6
    and.l   #$ffff,d6
    mulu    #SH_SPRITE,d6
    lea     shape_data,a1
    add.l   d6,a1

    move.w  d7,d6
    lsl.w   #2,d6
    lea     cell_org,a0
    move.l  (a0,d6.w),a0

    tst.w   d4
    bne.s   .torn
    bsr     blit_shape
    bra.s   .next
.torn:
    bsr     blit_shape_torn
.next:
    addq.w  #1,d7
    cmp.w   #8,d7
    bcs     .each

    ; --- the whole picture slips on dense playing. Two byte writes.
    tst.w   shear_cool
    beq.s   .cooled
    subq.w  #1,shear_cool
.cooled:
    tst.w   shear_ctr
    bne.s   .armed
    tst.w   shear_cool
    bne.s   .armed
    cmp.w   #SHEAR_AT,level
    bcs.s   .armed
    move.w  #6,shear_ctr
    move.w  #45,shear_cool
.armed:
    move.l  buf_base,d0
    tst.w   shear_ctr
    beq.s   .setbase
    subq.w  #1,shear_ctr
    bsr     next_rng            ; leaves d0 alone
    move.w  d3,d1
    and.w   #3,d1
    lsl.w   #8,d1
    and.l   #$ffff,d1
    add.l   d1,d0
.setbase:
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
; a0 = destination, a1 = sprite. Tiles are opaque: no erase pass.
;----------------------------------------------------------------------
blit_shape:
    movem.l d0-d7/a0-a3,-(sp)
    move.w  row_bytes,d1
    move.w  #SH_H-1,d0
.row:
    move.l  (a1)+,(a0)
    move.l  (a1)+,4(a0)
    adda.w  d1,a0
    dbra    d0,.row
    movem.l (sp)+,d0-d7/a0-a3
    rts

;----------------------------------------------------------------------
; Same, sheared into slabs. As in the cubes: shift what is READ, not where
; it is written, or pixels smear outside the box and nothing erases them;
; and keep the shift EVEN, because a move.l to an odd address is an address
; error on a 68000.
;----------------------------------------------------------------------
blit_shape_torn:
    movem.l d0-d7/a0-a3,-(sp)
    move.w  row_bytes,d1
    move.l  a0,a3
    moveq   #(SH_H/8)-1,d0
.blk:
    bsr     next_rng
    move.w  d3,d5
    and.w   #3,d5
    subq.w  #2,d5
    add.w   d5,d5               ; -4..+2 bytes, and even
    move.l  a1,a2
    adda.w  d5,a2
    moveq   #7,d6
.row:
    move.l  (a2)+,(a3)
    move.l  (a2)+,4(a3)
    adda.w  d1,a3
    dbra    d6,.row
    lea     (SH_W_BYTES*8)(a1),a1
    dbra    d0,.blk
    movem.l (sp)+,d0-d7/a0-a3
    rts

;----------------------------------------------------------------------
; d0 = strength 0..255, d1 = pad index * 2
;----------------------------------------------------------------------
show_note_on:
    movem.l d0-d1/a0,-(sp)
    lea     cell_level,a0
    move.w  d0,(a0,d1.w)
    cmp.w   #GLITCH_AT,d0
    bcs.s   .done
    lea     cell_glitch,a0
    move.w  #GLITCH_LEN,(a0,d1.w)
.done:
    movem.l (sp)+,d0-d1/a0
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
; cube, cut stone, octahedron, plus, tetrahedron, star, hex prism, pyramid
shape_data:
    incbin  "src/shapes.bin"

    section bss
    even
cell_level:     ds.w 8
cell_angle:     ds.w 8
cell_glitch:    ds.w 8
free_ctr:       ds.w 1
shear_ctr:      ds.w 1
shear_cool:     ds.w 1
    even
cell_org:       ds.l 8
