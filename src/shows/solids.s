;======================================================================
;  SOLIDS
;
;  The eight solids again, but FILLED and dither-shaded rather than drawn
;  as wireframes.
;
;  Why: an outline costs about 50 cycles a pixel -- a read, an OR, a mask
;  rotate and Bresenham bookkeeping, all for one pixel -- and a dense
;  wireframe reads as a heap of pixels anyway. A filled span costs about
;  one cycle a pixel, because a byte write covers eight of them. That is
;  the factor that makes this affordable where VECTORS was not, and it is
;  why demos shade with ordered dither instead of stroking outlines.
;
;  Everything expensive is baked by tools/gensolids.py: rotation,
;  projection, backface culling and the lighting level of each face. The
;  ST sorts three points and fills spans.
;
;  Unlike VECTORS, a cell is blanked and completely redrawn inside one
;  frame, so nothing is ever seen half-built.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 8

    include "src/core/head.s"

SOL_SCALES  equ 8
SOL_ANGLES  equ 24
SOL_STRIDE  equ 72
SOL_POSES   equ 32              ; poses start after the dither table
CLEAR_ROWS  equ 160             ; of the cell's 200; a solid never reaches
                                ; further than 70 rows from the centre
SOL_DECAY   equ 3
CELLS_PER_FRAME equ 1
GLITCH_AT   equ 240
GLITCH_LEN  equ 16
SHEAR_AT    equ $e0
FIX         equ 7               ; fixed-point shift for edge slopes. 8 would
                                ; overflow divs: the widest edge is 254 px and
                                ; 254<<8 does not fit a signed word quotient.

;----------------------------------------------------------------------
show_init:
    move.w  row_bytes,d5
    lsl.w   #1,d5               ; cell width in pixels
    move.w  scr_rows,d6
    lsr.w   #1,d6               ; cell height in rows
    lea     cell_cx,a0
    lea     cell_cy,a1
    lea     cell_clr,a2
    moveq   #0,d4
.mk:
    move.w  d4,d0
    and.w   #3,d0
    mulu    d5,d0
    move.w  d5,d1
    lsr.w   #1,d1
    add.w   d1,d0
    move.w  d0,(a0)+
    move.w  d4,d1
    lsr.w   #2,d1
    mulu    d6,d1
    move.w  d6,d2
    lsr.w   #1,d2
    add.w   d2,d1
    move.w  d1,(a1)+

    move.w  d4,d0
    and.w   #3,d0
    mulu    row_bytes,d0
    lsr.l   #2,d0
    move.w  d4,d1
    lsr.w   #2,d1
    mulu    d6,d1
    mulu    row_bytes,d1
    add.l   d0,d1
    move.l  buf_base,a3
    add.l   d1,a3
    move.l  a3,(a2)+
    addq.w  #1,d4
    cmp.w   #8,d4
    bcs.s   .mk

    move.w  row_bytes,d0
    lsr.w   #2,d0
    move.w  d0,cell_wb
    move.w  d6,cell_rows

    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1
    bsr     clear_span

    lea     cell_level,a0
    moveq   #(8*3)-1,d0         ; level, angle, glitch only
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    lea     cell_last,a0
    moveq   #7,d0
.zap2:
    move.w  #-1,(a0)+
    dbra    d0,.zap2
    clr.w   turn
    clr.w   free_ctr
    clr.w   shear_ctr
    clr.w   shear_cool
    rts

;----------------------------------------------------------------------
show_frame:
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
    add.w   d0,d0
    lea     cell_level,a0
    move.w  (a0,d0.w),d1
    sub.w   #SOL_DECAY,d1
    bpl.s   .lv
    moveq   #0,d1
.lv:
    move.w  d1,(a0,d0.w)
    lea     cell_angle,a0
    move.w  (a0,d0.w),d2
    move.w  d1,d3
    lsr.w   #4,d3
    addq.w  #4,d3
    add.w   d3,d2
    move.w  d2,(a0,d0.w)
    lea     cell_glitch,a0
    move.w  (a0,d0.w),d4
    beq.s   .noglitch
    subq.w  #1,d4
    move.w  d4,(a0,d0.w)
.noglitch:
    addq.w  #1,d7
    cmp.w   #8,d7
    bcs.s   .each

    ; --- redraw whole cells, one per frame, skipping any that has not moved
    moveq   #CELLS_PER_FRAME,d6
    moveq   #8,d5
.scan:
    move.w  turn,d7
    addq.w  #1,turn
    cmp.w   #8,turn
    bcs.s   .tok
    clr.w   turn
.tok:
    bsr     cell_pose
    move.w  d7,d1
    add.w   d1,d1
    lea     cell_last,a0
    cmp.w   (a0,d1.w),d0
    beq.s   .skip
    move.w  d0,(a0,d1.w)
    bsr     draw_solid
    subq.w  #1,d6
    beq.s   .drawn
.skip:
    subq.w  #1,d5
    bne.s   .scan
.drawn:

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
    bsr     next_rng
    move.w  d3,d1
    and.w   #3,d1
    lsl.w   #8,d1
    and.l   #$ffff,d1
    add.l   d1,d0
.setbase:
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
; d7 = cell -> d0 = (scale << 8) | angle
;----------------------------------------------------------------------
cell_pose:
    move.w  d7,d1
    add.w   d1,d1
    lea     cell_level,a0
    move.w  (a0,d1.w),d0
    lsr.w   #5,d0
    lsl.w   #8,d0
    lea     cell_angle,a0
    move.w  (a0,d1.w),d2
    lsr.w   #8,d2
    and.l   #$ff,d2
    divu    #SOL_ANGLES,d2      ; and.L above: divu takes the whole register
    swap    d2
    or.w    d2,d0
    rts

;----------------------------------------------------------------------
; Blank cell d7 and fill its solid. One frame, start to finish.
;----------------------------------------------------------------------
draw_solid:
    movem.l d0-d7/a0-a6,-(sp)

    ; --- blank
    move.w  d7,d0
    lsl.w   #2,d0
    lea     cell_clr,a0
    move.l  (a0,d0.w),a1
    move.w  cell_rows,d0
    sub.w   #CLEAR_ROWS,d0
    lsr.w   #1,d0
    and.l   #$ffff,d0
    mulu    row_bytes,d0
    add.l   d0,a1
    move.w  #CLEAR_ROWS-1,d0
    move.w  cell_wb,d1
    lsr.w   #2,d1
    subq.w  #1,d1
    move.w  row_bytes,d2
    moveq   #0,d4
.crow:
    move.l  a1,a2
    move.w  d1,d3
.cl:
    move.l  d4,(a2)+
    dbra    d3,.cl
    adda.w  d2,a1
    dbra    d0,.crow

    ; --- the pose
    lea     solid_data,a6
    bsr     cell_pose
    move.w  d0,d1
    and.w   #$ff,d1             ; angle
    lsr.w   #8,d0               ; scale
    move.w  d7,d2
    mulu    #SOL_SCALES,d2
    add.w   d0,d2
    mulu    #SOL_ANGLES,d2
    add.w   d1,d2
    and.l   #$ffff,d2
    mulu    #SOL_STRIDE,d2
    add.l   #SOL_POSES,d2
    lea     0(a6,d2.l),a5       ; a5 = pose blob

    moveq   #0,d4
    move.b  (a5)+,d4            ; nverts
    moveq   #0,d3
    move.b  (a5)+,d3            ; ntris
    beq     .out
    move.l  a5,a4               ; a4 = vertex pairs
    add.w   d4,d4
    lea     0(a5,d4.w),a3       ; a3 = triangles

    move.w  d7,d0
    add.w   d0,d0
    lea     cell_cx,a0
    move.w  (a0,d0.w),d5
    lea     cell_cy,a0
    move.w  (a0,d0.w),d6
    lea     cell_glitch,a0
    move.w  (a0,d0.w),jitter

    subq.w  #1,d3
.tri:
    lea     tri_pts,a2
    moveq   #2,d2
.pt:
    moveq   #0,d0
    move.b  (a3)+,d0
    add.w   d0,d0
    move.b  0(a4,d0.w),d1
    ext.w   d1
    add.w   d5,d1
    move.w  d1,(a2)+
    move.b  1(a4,d0.w),d1
    ext.w   d1
    add.w   d6,d1
    move.w  d1,(a2)+
    dbra    d2,.pt
    moveq   #0,d0
    move.b  (a3)+,d0            ; shading level
    move.w  d0,tlevel

    tst.w   jitter
    beq.s   .straight
    bsr     shatter
.straight:
    bsr     fill_tri
    dbra    d3,.tri
.out:
    movem.l (sp)+,d0-d7/a0-a6
    rts

;----------------------------------------------------------------------
; A hard hit pulls the faces apart rather than merely flashing them.
;----------------------------------------------------------------------
shatter:
    movem.l d0-d4/a0,-(sp)
    bsr     next_rng
    lea     tri_pts,a0
    moveq   #5,d1
.jit:
    move.w  d3,d0
    and.w   #7,d0
    subq.w  #4,d0
    add.w   d0,(a0)+
    lsr.l   #3,d3
    dbra    d1,.jit
    movem.l (sp)+,d0-d4/a0
    rts

;----------------------------------------------------------------------
; Fill the triangle in tri_pts, shaded with level tlevel.
; Sorted by y, then two runs of spans: above the middle vertex and below.
;----------------------------------------------------------------------
fill_tri:
    movem.l d0-d7/a0-a2,-(sp)
    lea     tri_pts,a0
    ; --- sort the three points by y
    moveq   #0,d7
.sort:
    move.w  2(a0),d0
    cmp.w   6(a0),d0
    bls.s   .s1
    bsr     swap01
    moveq   #1,d7
.s1:
    move.w  6(a0),d0
    cmp.w   10(a0),d0
    bls.s   .s2
    bsr     swap12
    moveq   #1,d7
.s2:
    tst.w   d7
    beq.s   .sorted
    moveq   #0,d7
    bra.s   .sort
.sorted:
    move.w  2(a0),d4            ; y0
    move.w  10(a0),d5           ; y2
    cmp.w   d4,d5
    beq     .done               ; zero height

    ; long edge 0->2
    move.w  8(a0),d0
    sub.w   0(a0),d0
    ext.l   d0
    asl.l   #FIX,d0
    move.w  d5,d1
    sub.w   d4,d1
    divs    d1,d0
    ext.l   d0
    move.l  d0,t_sa
    move.w  0(a0),d0
    ext.l   d0
    asl.l   #FIX,d0
    move.l  d0,t_xa

    ; --- upper run: 0->1
    move.w  6(a0),d6            ; y1
    cmp.w   d4,d6
    beq     .lower
    move.w  4(a0),d0
    sub.w   0(a0),d0
    ext.l   d0
    asl.l   #FIX,d0
    move.w  d6,d1
    sub.w   d4,d1
    divs    d1,d0
    ext.l   d0
    move.l  d0,t_sb
    move.w  0(a0),d0
    ext.l   d0
    asl.l   #FIX,d0
    move.l  d0,t_xb
    move.w  d4,t_y
    move.w  d6,d0
    subq.w  #1,d0
    move.w  d0,t_yend
    bsr     span_run

.lower:
    ; --- lower run: 1->2
    move.w  10(a0),d0
    sub.w   6(a0),d0
    move.w  d0,d2
    beq     .done
    ext.l   d0
    asl.l   #FIX,d0
    divs    d2,d0
    ext.l   d0
    move.l  d0,t_sb
    move.w  4(a0),d0
    ext.l   d0
    asl.l   #FIX,d0
    move.l  d0,t_xb
    ; the long edge has to be where it was at y1
    move.w  6(a0),d0
    sub.w   d4,d0
    ext.l   d0
    move.l  t_sa,d1
    muls    d0,d1
    move.w  0(a0),d0
    ext.l   d0
    asl.l   #FIX,d0
    add.l   d1,d0
    move.l  d0,t_xa
    move.w  6(a0),t_y
    move.w  10(a0),t_yend
    bsr     span_run
.done:
    movem.l (sp)+,d0-d7/a0-a2
    rts

swap01:
    move.l  0(a0),d1
    move.l  4(a0),0(a0)
    move.l  d1,4(a0)
    rts
swap12:
    move.l  4(a0),d1
    move.l  8(a0),4(a0)
    move.l  d1,8(a0)
    rts

;----------------------------------------------------------------------
; Walk t_y..t_yend filling between the two edge accumulators.
;----------------------------------------------------------------------
span_run:
    ; fill_tri keeps y0/y1/y2 in d4-d6 and the point list in a0 across both
    ; halves of the triangle, so those are saved. Everything else lives in a
    ; register for the duration: the first version kept the edge accumulators
    ; in memory and called out to fill a span, and the per-row overhead came
    ; to 190 cycles against 40 of actual filling.
    movem.l d4-d7/a0-a2,-(sp)
    ; Build this level's four dither bytes doubled into words, once. Doing
    ; it per row cost about 45 cycles and there is no spare register to do
    ; it in, so it goes in a four-word table instead.
    move.w  tlevel,d4
    lsl.w   #2,d4
    lea     solid_data,a1
    adda.w  d4,a1
    lea     pat4,a2
    moveq   #3,d5
.mkpat:
    moveq   #0,d6
    move.b  (a1)+,d6
    move.w  d6,d7
    lsl.w   #8,d7
    or.w    d7,d6               ; d6 = pattern in both halves
    move.w  d6,(a2)+
    dbra    d5,.mkpat
    lea     pat4,a2
    move.w  t_y,d4
    and.l   #$ffff,d4
    mulu    row_bytes,d4
    move.l  cur_base,a0
    add.l   d4,a0               ; a0 = row address, stepped from here
    move.l  t_xa,d0
    move.l  t_xb,d1
    move.l  t_sa,d2
    move.l  t_sb,d3

.row:
    move.w  t_y,d4
    cmp.w   t_yend,d4
    bhi     .out

    ; --- span ends, ordered
    move.l  d0,d6
    asr.l   #FIX,d6
    move.l  d1,d7
    asr.l   #FIX,d7
    cmp.w   d7,d6
    bls.s   .ord
    exg     d6,d7
.ord:
    ; --- first byte into a1, and how many bytes the span covers
    move.w  d6,d4
    lsr.w   #3,d4
    move.l  a0,a1
    adda.w  d4,a1
    move.w  d7,d5
    lsr.w   #3,d5
    sub.w   d4,d5               ; d5 = last byte - first byte

    ; --- edge masks, shifted rather than looked up: a table would need an
    ; address register and there is none spare
    and.w   #7,d6
    move.w  #$00ff,d4
    lsr.w   d6,d4               ; d4 = left mask
    and.w   #7,d7
    moveq   #7,d6
    sub.w   d7,d6
    move.w  #$00ff,d7
    lsl.w   d6,d7               ; d7 = right mask

    ; --- this row's doubled pattern
    move.w  t_y,d6
    and.w   #3,d6
    add.w   d6,d6
    move.w  0(a2,d6.w),d6

    tst.w   d5
    bne.s   .wide
    and.b   d7,d4               ; one byte: both masks at once
    and.b   d6,d4
    or.b    d4,(a1)
    bra.s   .next
.wide:
    and.b   d6,d4               ; left edge byte is shared, so OR it
    or.b    d4,(a1)+
    subq.w  #2,d5               ; d5 = middle bytes - 1
    bmi.s   .right
    ; The middle belongs entirely to this span. Write words where alignment
    ; allows: a byte loop spends more on the dbra than on the store.
    move.l  a1,d4
    btst    #0,d4
    beq.s   .even
    move.b  d6,(a1)+            ; one byte to reach an even address
    subq.w  #1,d5
    bmi.s   .right
.even:                          ; a1 is even here
    addq.w  #1,d5               ; d5 = middle bytes remaining
    move.w  d5,d4               ; keep the count for the parity test
    lsr.w   #1,d5               ; whole words
    beq.s   .noword
    subq.w  #1,d5
.mid:
    move.w  d6,(a1)+
    dbra    d5,.mid
.noword:
    ; The odd leftover byte goes AFTER the words, not before: writing it
    ; first left a1 odd, and a move.w to an odd address is an address error.
    btst    #0,d4
    beq.s   .right
    move.b  d6,(a1)+
.right:
    and.b   d7,d6
    or.b    d6,(a1)
.next:
    add.l   d2,d0
    add.l   d3,d1
    addq.w  #1,t_y
    adda.w  row_bytes,a0
    bra     .row
.out:
    movem.l (sp)+,d4-d7/a0-a2
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
lmask:  dc.b $ff,$7f,$3f,$1f,$0f,$07,$03,$01
rmask:  dc.b $80,$c0,$e0,$f0,$f8,$fc,$fe,$ff
    even
; 32 bytes of dither table, then the poses
solid_data:
    incbin  "src/solids.bin"

    section bss
    even
t_xa:           ds.l 1
t_xb:           ds.l 1
t_sa:           ds.l 1
t_sb:           ds.l 1
cell_level:     ds.w 8
cell_angle:     ds.w 8
cell_glitch:    ds.w 8
cell_cx:        ds.w 8
cell_cy:        ds.w 8
cell_last:      ds.w 8
tri_pts:        ds.w 6
tlevel:         ds.w 1
t_y:            ds.w 1
t_yend:         ds.w 1
cell_wb:        ds.w 1
cell_rows:      ds.w 1
turn:           ds.w 1
free_ctr:       ds.w 1
shear_ctr:      ds.w 1
shear_cool:     ds.w 1
jitter:         ds.w 1
    even
pat4:           ds.w 4
    even
cell_clr:       ds.l 8
