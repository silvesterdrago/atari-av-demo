;======================================================================
;  VECTORS
;
;  The shapes show again, but the wireframes are drawn on the ST from
;  baked vertex tables instead of blitted from baked bitmaps. Bitmaps
;  cost area, which capped the figures at a 96x96 box; vertices cost
;  almost nothing, so here the figures fill their 160x200 cell.
;
;  The price is real-time line drawing. A 1-bit line costs roughly 60
;  cycles a pixel, so a figure of fifteen edges at ninety pixels each is
;  about 80 000 of the frame's 112 000. One cell per frame is all that
;  fits -- so cells are redrawn round-robin, and only when their pose has
;  actually changed. A cell at rest costs nothing.
;
;  That means rotation steps at roughly 9 Hz per cell rather than being
;  smooth. It is the hardware's answer, not a shortcut: 112 000 cycles
;  divided by 60 is about 1 800 pixels of line per frame, whatever we do
;  with them.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 8

    include "src/core/head.s"

VEC_SCALES  equ 8
VEC_ANGLES  equ 32
VEC_DIR     equ 16              ; bytes per shape directory entry
EDGE_BUDGET equ 24              ; edges drawn per frame. One cell per frame
                                ; with no cap overran 40 frames in 64, so the
                                ; work is capped instead. 24 measures zero;
                                ; only the two heaviest solids need a second
                                ; frame.
CLEAR_ROWS  equ 160             ; of the cell's 200
VEC_DECAY   equ 3
GLITCH_AT   equ 240
GLITCH_LEN  equ 20
SHEAR_AT    equ $e0

; directory entry offsets
D_NVERTS    equ 0
D_NEDGES    equ 2
D_STRIDE    equ 4
D_EDGES     equ 8
D_POSES     equ 12

;----------------------------------------------------------------------
show_init:
    ; cell centres, in pixels and rows
    move.w  row_bytes,d5
    lsl.w   #1,d5               ; cell width in pixels (160 in mono)
    move.w  scr_rows,d6
    lsr.w   #1,d6               ; cell height in rows (200)
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
    move.w  d0,(a0)+            ; centre x
    move.w  d4,d1
    lsr.w   #2,d1
    mulu    d6,d1
    move.w  d6,d2
    lsr.w   #1,d2
    add.w   d2,d1
    move.w  d1,(a1)+            ; centre y

    ; where the cell starts on screen, for clearing
    move.w  d4,d0
    and.w   #3,d0
    mulu    row_bytes,d0
    lsr.l   #2,d0               ; col * cell width in bytes
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
    move.w  d0,cell_wb          ; cell width in bytes
    move.w  d6,cell_rows

    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1
    bsr     clear_span

    lea     cell_level,a0
    moveq   #(8*3)-1,d0         ; level, angle, glitch ONLY -- cell_cx and
                                ; cell_cy follow them and were just computed
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    lea     cell_last,a0
    moveq   #7,d0
.zap2:
    move.w  #-1,(a0)+           ; nothing drawn yet
    dbra    d0,.zap2
    clr.w   turn
    clr.w   free_ctr
    clr.w   shear_ctr
    clr.w   shear_cool
    rts

;----------------------------------------------------------------------
show_frame:
    ; free-run when nothing is plugged in
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

    ; --- envelopes and spin for every cell; this part is cheap
    moveq   #0,d7
.each:
    move.w  d7,d0
    add.w   d0,d0
    lea     cell_level,a0
    move.w  (a0,d0.w),d1
    sub.w   #VEC_DECAY,d1
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

    ; --- one bounded slice of drawing work
    tst.w   drawing
    bne     .continue
    moveq   #8,d5
.find:
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
    bne.s   .begin
    subq.w  #1,d5
    bne.s   .find
    bra     .noupd
.begin:
    move.w  d0,(a0,d1.w)
    move.w  d7,cur_cell
    clr.w   cur_edge
    move.w  #1,drawing
    bsr     clear_cell          ; blanking gets its own frame: merged with a
    bra     .noupd              ; full edge batch it overran 45 frames in 64
.continue:
    move.w  cur_cell,d7
    bsr     draw_edges
.noupd:

    ; --- shear accent, two byte writes
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
; d7 = cell -> d0 = (scale << 8) | angle, also the "has it moved" key
;----------------------------------------------------------------------
cell_pose:
    move.w  d7,d1
    add.w   d1,d1
    lea     cell_level,a0
    move.w  (a0,d1.w),d0
    lsr.w   #5,d0               ; scale 0..7
    lsl.w   #8,d0
    lea     cell_angle,a0
    move.w  (a0,d1.w),d2
    lsr.w   #8,d2
    and.w   #VEC_ANGLES-1,d2
    or.w    d2,d0
    rts

;----------------------------------------------------------------------
; Redraw one cell: blank it, then stroke the wireframe.
; d7 = cell index (also the shape index)
;----------------------------------------------------------------------
clear_cell:
    movem.l d0-d4/a0-a2,-(sp)
    move.w  d7,d0
    lsl.w   #2,d0
    lea     cell_clr,a0
    move.l  (a0,d0.w),a1
    ; a figure never reaches more than 76 rows from the centre, so skip the
    ; dead margin at the top and bottom of the cell
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
    moveq   #0,d4               ; move.l from a register is 12 cycles;
                                ; clr.l to memory is 20
.crow:
    move.l  a1,a2
    move.w  d1,d3
.cl:
    move.l  d4,(a2)+
    dbra    d3,.cl
    adda.w  d2,a1
    dbra    d0,.crow
    movem.l (sp)+,d0-d4/a0-a2
    rts

;----------------------------------------------------------------------
; Stroke up to EDGE_BUDGET edges of cell d7, resuming at cur_edge.
;----------------------------------------------------------------------
draw_edges:
    movem.l d0-d7/a0-a6,-(sp)

    move.w  d7,d0
    mulu    #VEC_DIR,d0
    lea     vec_data,a6
    lea     0(a6,d0.l),a5

    ; the pose that was latched when this cell's redraw began
    move.w  d7,d1
    add.w   d1,d1
    lea     cell_last,a0
    move.w  (a0,d1.w),d0
    move.w  d0,d1
    and.w   #$ff,d1             ; angle
    lsr.w   #8,d0               ; scale
    mulu    #VEC_ANGLES,d0
    add.w   d1,d0
    and.l   #$ffff,d0
    mulu    D_STRIDE(a5),d0
    move.l  D_POSES(a5),d2
    add.l   d2,d0
    lea     0(a6,d0.l),a4

    move.l  D_EDGES(a5),d0
    lea     0(a6,d0.l),a3
    move.w  cur_edge,d0
    add.w   d0,d0
    adda.w  d0,a3               ; resume where we stopped

    move.w  d7,d0
    add.w   d0,d0
    lea     cell_cx,a0
    move.w  (a0,d0.w),d5
    lea     cell_cy,a0
    move.w  (a0,d0.w),d6
    lea     cell_glitch,a0
    move.w  (a0,d0.w),jitter

    ; how many edges are left, capped at the budget
    move.w  D_NEDGES(a5),d3
    sub.w   cur_edge,d3
    move.w  d3,d2               ; remaining
    cmp.w   #EDGE_BUDGET,d3
    bcs.s   .few
    move.w  #EDGE_BUDGET,d3
.few:
    add.w   d3,cur_edge
    sub.w   d3,d2               ; what will be left afterwards
    subq.w  #1,d3
.edge:
    moveq   #0,d0
    move.b  (a3)+,d0
    add.w   d0,d0
    move.b  0(a4,d0.w),d1
    ext.w   d1
    add.w   d5,d1
    move.b  1(a4,d0.w),d4
    ext.w   d4
    add.w   d6,d4
    move.w  d1,lx0
    move.w  d4,ly0

    moveq   #0,d0
    move.b  (a3)+,d0
    add.w   d0,d0
    move.b  0(a4,d0.w),d1
    ext.w   d1
    add.w   d5,d1
    move.b  1(a4,d0.w),d4
    ext.w   d4
    add.w   d6,d4
    move.w  d1,lx1
    move.w  d4,ly1

    tst.w   jitter
    beq.s   .straight
    bsr     shatter
.straight:
    bsr     draw_line
    dbra    d3,.edge

    tst.w   d2
    bne.s   .more
    clr.w   drawing             ; this cell is finished
.more:
    movem.l (sp)+,d0-d7/a0-a6
    rts

;----------------------------------------------------------------------
; Nudge both ends of the pending line, so a hard hit reads as the
; wireframe coming apart rather than merely flickering.
;----------------------------------------------------------------------
shatter:
    movem.l d0-d4,-(sp)
    bsr     next_rng
    move.w  d3,d0
    and.w   #7,d0
    subq.w  #4,d0
    add.w   d0,lx0
    move.w  d3,d0
    lsr.w   #4,d0
    and.w   #7,d0
    subq.w  #4,d0
    add.w   d0,ly0
    move.w  d3,d0
    lsr.w   #8,d0
    and.w   #7,d0
    subq.w  #4,d0
    add.w   d0,lx1
    move.w  d3,d0
    lsr.w   #8,d0
    lsr.w   #4,d0
    and.w   #7,d0
    subq.w  #4,d0
    add.w   d0,ly1
    movem.l (sp)+,d0-d4
    rts

;----------------------------------------------------------------------
; Bresenham into a 1-bit screen. Endpoints in lx0/ly0/lx1/ly1.
; The major axis is normalised to run positive, which halves the cases.
;----------------------------------------------------------------------
draw_line:
    movem.l d0-d7/a0-a1,-(sp)
    move.w  lx1,d4
    sub.w   lx0,d4              ; dx
    move.w  ly1,d5
    sub.w   ly0,d5              ; dy
    move.w  d4,d6
    bpl.s   .adx
    neg.w   d6
.adx:
    move.w  d5,d7
    bpl.s   .ady
    neg.w   d7
.ady:
    cmp.w   d7,d6
    bcs     ymajor

; ================= x major =================
    tst.w   d4
    bpl.s   .xfwd
    move.w  lx0,d0              ; draw it the other way round instead
    move.w  lx1,lx0
    move.w  d0,lx1
    move.w  ly0,d0
    move.w  ly1,ly0
    move.w  d0,ly1
.xfwd:
    move.w  lx1,d4
    sub.w   lx0,d4              ; dx >= 0
    move.w  ly1,d5
    sub.w   ly0,d5
    moveq   #0,d3
    move.w  row_bytes,d3
    tst.w   d5
    bpl.s   .yplus
    neg.l   d3
    neg.w   d5
.yplus:                         ; d3 = y step, d5 = |dy|
    move.w  lx0,d0
    move.w  ly0,d1
    bsr     pixel_addr          ; -> a0, d2 = mask
    move.w  d4,d1               ; err = dx/2
    lsr.w   #1,d1
    move.w  d4,d6               ; count
.xl:
    or.b    d2,(a0)
    ror.b   #1,d2
    bcc.s   .nob
    addq.l  #1,a0
.nob:
    sub.w   d5,d1
    bpl.s   .noy
    add.w   d4,d1
    adda.l  d3,a0
.noy:
    dbra    d6,.xl
    movem.l (sp)+,d0-d7/a0-a1
    rts

; ================= y major =================
ymajor:
    tst.w   d5
    bpl.s   .yfwd
    move.w  lx0,d0
    move.w  lx1,lx0
    move.w  d0,lx1
    move.w  ly0,d0
    move.w  ly1,ly0
    move.w  d0,ly1
.yfwd:
    move.w  lx1,d4
    sub.w   lx0,d4              ; dx, signed
    move.w  ly1,d5
    sub.w   ly0,d5              ; dy >= 0
    move.w  lx0,d0
    move.w  ly0,d1
    bsr     pixel_addr          ; -> a0, d2 = mask
    moveq   #0,d3
    move.w  row_bytes,d3
    move.w  d4,d7
    bpl.s   .xp
    neg.w   d7                  ; d7 = |dx|
.xp:
    move.w  d5,d1
    lsr.w   #1,d1               ; err = dy/2
    move.w  d5,d6               ; count
    tst.w   d4
    bmi     .yminus

.yl:                            ; x increasing
    or.b    d2,(a0)
    adda.l  d3,a0
    sub.w   d7,d1
    bpl.s   .nox
    add.w   d5,d1
    ror.b   #1,d2
    bcc.s   .nox
    addq.l  #1,a0
.nox:
    dbra    d6,.yl
    movem.l (sp)+,d0-d7/a0-a1
    rts

.yminus:                        ; x decreasing
    or.b    d2,(a0)
    adda.l  d3,a0
    sub.w   d7,d1
    bpl.s   .nox2
    add.w   d5,d1
    rol.b   #1,d2
    bcc.s   .nox2
    subq.l  #1,a0
.nox2:
    dbra    d6,.yminus
    movem.l (sp)+,d0-d7/a0-a1
    rts

;----------------------------------------------------------------------
; d0 = x, d1 = y -> a0 = byte address, d2 = bit mask
;----------------------------------------------------------------------
pixel_addr:
    and.l   #$ffff,d1
    mulu    row_bytes,d1
    move.l  cur_base,a0
    add.l   d1,a0
    move.w  d0,d1
    lsr.w   #3,d1
    and.l   #$ffff,d1
    add.l   d1,a0
    move.w  #$0080,d2
    move.w  d0,d1
    and.w   #7,d1
    lsr.w   d1,d2
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
vec_data:
    incbin  "src/vectors.bin"

    section bss
    even
cell_level:     ds.w 8
cell_angle:     ds.w 8
cell_glitch:    ds.w 8
cell_cx:        ds.w 8
cell_cy:        ds.w 8
cell_last:      ds.w 8
cell_wb:        ds.w 1
cell_rows:      ds.w 1
turn:           ds.w 1
drawing:        ds.w 1
cur_cell:       ds.w 1
cur_edge:       ds.w 1
free_ctr:       ds.w 1
shear_ctr:      ds.w 1
shear_cool:     ds.w 1
jitter:         ds.w 1
lx0:            ds.w 1
ly0:            ds.w 1
lx1:            ds.w 1
ly1:            ds.w 1
    even
cell_clr:       ds.l 8
