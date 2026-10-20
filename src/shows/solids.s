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
    ifnd SCENES
POOL_SIZE   equ 1024
    endif
    ifnd SCENES
RANGE_PAGES equ 8
    endif

    include "src/core/head.s"

SOL_SCALES  equ 8
SOL_ANGLES  equ 24
SOL_STRIDE  equ 96
SOL_POSES   equ 32              ; poses start after the dither table
CLEAR_ROWS  equ 160             ; of the cell's 200; a solid never reaches
                                ; further than 70 rows from the centre
    ifnd ROWB
ROWB        equ 80              ; bytes in a screen row. Mono only, which this
    endif
                                ; whole show is: it lets the span write the
                                ; row below with a displacement instead of a
                                ; second pass over the cell.
    ifnd BOXBLANK
BOXBLANK    equ 0               ; 1 blanks only the rows the last pose used.
    endif                       ; It is a fifth off a solid and it LEAKS:
                                ; frames come up with thin bands of the
                                ; previous pose left behind, in several
                                ; cells at the same rows. Reading the code
                                ; has not found it and the spinning bench
                                ; meant to corner it is itself broken, so
                                ; the default is the whole cell -- which
                                ; still gets the movem.l row below.
    ifnd SEGLOOP
SEGLOOP     equ 1               ; 0 reinstates the per-row chain checks, to
    endif                       ; measure what the segment loop is worth
    ifnd YSTEP
YSTEP       equ 2               ; draw every YSTEP-th row and double it
    endif                       ; afterwards. A span-row costs ~1200 cycles
                                ; and a copied row about 150, so this is the
                                ; cheapest factor of two on the machine.
SOL_DECAY   equ 3
CELLS_PER_FRAME equ 1
GLITCH_AT   equ 240
GLITCH_LEN  equ 16
; The base-register shear moves the whole screen mid-scan. On wireframes
; that read as a glitch; on filled solids it reads as a defect.
SHEAR_AT    equ $7fff
FIX         equ 7               ; fixed-point shift for edge slopes. 8 would
                                ; overflow divs: the widest edge is 254 px and
                                ; 254<<8 does not fit a signed word quotient.

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
so_init:
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
    lea     cell_box,a0         ; the first blanking clears the whole cell
    move.w  cell_rows,d2        ; out of memory: clear_span had d6
    move.w  d2,d3
    sub.w   #CLEAR_ROWS,d3
    lsr.w   #1,d3               ; the top margin inside a cell
    moveq   #0,d0
.zap3:
    move.w  d0,d1
    lsr.w   #2,d1
    mulu    d2,d1
    add.w   d3,d1
    move.w  d1,(a0)+
    move.w  #CLEAR_ROWS,(a0)+
    addq.w  #1,d0
    cmp.w   #8,d0
    bcs.s   .zap3
    ; mask tables, built once
    lea     lmaskt,a0
    lea     rmaskt,a1
    moveq   #0,d0
.mk2:
    move.w  #$00ff,d1
    move.w  d0,d2
    lsr.w   d2,d1
    move.b  d1,(a0)+            ; $ff,$7f,$3f...
    move.w  #$00ff,d1
    moveq   #7,d2
    sub.w   d0,d2
    lsl.w   d2,d1
    move.b  d1,(a1)+            ; $80,$c0,$e0...
    addq.w  #1,d0
    cmp.w   #8,d0
    bcs.s   .mk2

    clr.w   turn
    clr.w   free_ctr
    clr.w   shear_ctr
    clr.w   shear_cool
    rts

;----------------------------------------------------------------------
    ifnd SCENES
show_frame:
    endif
so_frame:
    ifd BENCHSOLID
    ifnd BENCHREP               ; wait_vbl rounds a pass up to whole frames,
BENCHREP    equ 8               ; so draw the thing several times a pass to
    endif                       ; get resolution finer than a frame
    move.w  #BENCHREP-1,benchn
.bench:
    moveq   #BENCHSOLID-1,d7    ; 1..8 picks the shape, d7 being both the
    bsr     draw_solid          ; cell index and the shape index
    eori.w  #1,benchodd         ; count every second draw: the bar stops at
    bne.s   .noc                ; 64, and one draw a frame would peg it
    addq.w  #1,show_ctr
.noc:
    subq.w  #1,benchn
    bpl.s   .bench
    rts
    endif

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
    ifd BENCHSOLID
    move.w  #(7*256)+5,d0       ; largest scale, one fixed angle
    rts
    endif
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
    ifnd BENCHSOLID
    if DIAG
    addq.w  #1,show_ctr          ; completed redraws per 64 frames
    endif
    endif

    ; --- blank a row with one instruction. It used to go through an inner
    ; loop of five move.l; a cell row is exactly five longs, so one movem.l
    ; does it with no loop at all, which is where most of the blanking cost
    ; was: cube 1.09 -> 0.94 frames, diamond 1.00 -> 0.88.
    ; Blanking only the rows the figure used (BOXBLANK) would add another
    ; 3% to 7% and leaks -- see the flag.
    move.w  d7,d0
    lsl.w   #2,d0               ; two words a cell: first row, row count
    lea     cell_box,a0
    adda.w  d0,a0
    ifeq BOXBLANK               ; 0 blanks the whole cell, which tells a
    move.w  d7,d0               ; wrong box apart from a wrong span
    lsr.w   #2,d0
    mulu    cell_rows,d0
    move.w  cell_rows,d1
    sub.w   #CLEAR_ROWS,d1
    lsr.w   #1,d1
    add.w   d1,d0
    move.w  d0,(a0)
    move.w  #CLEAR_ROWS,2(a0)
    endif
    move.w  2(a0),d1
    beq.s   .blanked
    move.w  (a0),d0
    and.l   #$ffff,d0
    mulu    row_bytes,d0
    move.l  cur_base,a1
    add.l   d0,a1
    move.w  d7,d0
    and.w   #3,d0
    mulu    #ROWB/4,d0          ; the cell's own byte offset along a row
    adda.w  d0,a1
    move.w  row_bytes,d2
    subq.w  #1,d1
    moveq   #0,d0
    moveq   #0,d3
    moveq   #0,d4
    moveq   #0,d5
    moveq   #0,d6
.crow:
    movem.l d0/d3-d6,(a1)       ; the full 20-byte width of a cell
    adda.w  d2,a1
    dbra    d1,.crow
.blanked:

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
    move.b  (a5)+,d3            ; nfaces
    beq     .out
    move.l  a5,a4               ; a4 = vertex pairs
    add.w   d4,d4
    lea     0(a5,d4.w),a3       ; a3 = face data, walked by fill_poly

    move.w  d7,d0
    add.w   d0,d0
    lea     cell_cx,a0
    move.w  (a0,d0.w),d5
    move.w  d5,poly_cx
    lea     cell_cy,a0
    move.w  (a0,d0.w),d5
    move.w  d5,poly_cy

    ifne BOXBLANK
    ; --- the rows this pose covers, for the next frame's blanking
    move.l  a4,a0
    move.w  d4,d1
    lsr.w   #1,d1               ; d4 is nverts doubled by now
    subq.w  #1,d1
    moveq   #127,d2
    moveq   #-128,d5
.bb:
    move.b  1(a0),d0
    ext.w   d0
    cmp.w   d2,d0
    bge.s   .nmin
    move.w  d0,d2
.nmin:
    cmp.w   d5,d0
    ble.s   .nmax
    move.w  d0,d5
.nmax:
    addq.l  #2,a0
    dbra    d1,.bb
    add.w   poly_cy,d2
    and.w   #$fffe,d2           ; fill_poly rounds a face top down to even
    add.w   poly_cy,d5
    ifne YSTEP-1
    addq.w  #1,d5               ; the twin row under the last one
    endif
    sub.w   d2,d5
    addq.w  #1,d5
    move.w  d7,d0
    lsl.w   #2,d0
    lea     cell_box,a0
    adda.w  d0,a0
    move.w  d2,(a0)
    move.w  d5,2(a0)

    endif

    subq.w  #1,d3
.face:
    bsr     fill_poly           ; advances a3 past the face it just filled
    dbra    d3,.face
.out:
    movem.l (sp)+,d0-d7/a0-a6
    rts

;----------------------------------------------------------------------
; Fill one convex face, walking a left and a right chain of edges.
;
; Filling a quad as a quad rather than as two triangles is the whole
; point: a scanline costs roughly 180 cycles of overhead against 40 of
; actual filling, so what matters is how many rows get walked, not how
; fast each one is. Two triangles walk their rows twice.
;
; a3 = face data: level.b, nA.b, nB.b, then nA and nB vertex indices.
; a4 = the pose's vertex array. a3 is left pointing past this face.
; The generator cut the chains, so there is no topmost-vertex search, no
; wrapping round the polygon and no direction to work out here.
;----------------------------------------------------------------------
fill_poly:
    movem.l d0-d7/a0-a2/a5,-(sp)    ; a3 deliberately not saved
    moveq   #0,d0
    move.b  (a3)+,d0
    move.w  d0,tlevel
    moveq   #0,d1
    move.b  (a3)+,d1            ; nA
    moveq   #0,d2
    move.b  (a3)+,d2            ; nB
    move.l  a3,chA
    move.w  d1,chA+12
    move.l  a3,d3
    add.l   d1,d3
    move.l  d3,chB
    move.w  d2,chB+12
    add.l   d2,d3
    move.l  d3,a3               ; caller continues after this face

    ; top and bottom row, from the ends of chain A
    move.l  chA,a0
    moveq   #0,d4
    move.b  (a0),d4
    add.w   d4,d4
    move.b  1(a4,d4.w),d5
    ext.w   d5
    add.w   poly_cy,d5
    ifne YSTEP-1
    and.w   #$fffe,d5           ; the doubling pass works on even rows
    endif
    move.w  d5,t_y
    subq.w  #1,d5
    move.w  d5,chA+14           ; forces both chains to load an edge on the
    move.w  d5,chB+14           ; first row
    move.w  chA+12,d4
    subq.w  #1,d4
    adda.w  d4,a0
    moveq   #0,d4
    move.b  (a0),d4
    add.w   d4,d4
    move.b  1(a4,d4.w),d5
    ext.w   d5
    add.w   poly_cy,d5
    move.w  d5,poly_ymax

    ; this level's four fills, doubled so they can go out as words
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
    or.w    d7,d6
    move.w  d6,(a2)+
    dbra    d5,.mkpat
    lea     pat4,a2

    move.w  t_y,d4
    and.l   #$ffff,d4
    mulu    row_bytes,d4
    move.l  cur_base,a0
    add.l   d4,a0               ; a0 = row address, stepped from here
    move.w  row_bytes,d4
    ifne YSTEP-1
    add.w   d4,d4
    endif
    movea.w d4,a5               ; one row step, out of memory
    moveq   #0,d0
    moveq   #0,d1
    moveq   #0,d2
    moveq   #0,d3

    ; --- one segment: the rows until either chain reaches its next vertex.
    ; Inside a segment nothing can change, so the row loop below runs with
    ; no compares at all -- the chain checks used to cost every row what
    ; they now cost once per vertex.
.seg:
    move.w  t_y,d4
    cmp.w   poly_ymax,d4
    bhi     .out
    cmp.w   chA+14,d4
    bls.s   .aok
    lea     chA,a1
    bsr     adv_chain
    move.l  chA+4,d0
    move.l  chA+8,d2
    ifne YSTEP-1
    add.l   d2,d2
    endif
.aok:
    cmp.w   chB+14,d4
    bls.s   .bok
    lea     chB,a1
    bsr     adv_chain
    move.l  chB+4,d1
    move.l  chB+8,d3
    ifne YSTEP-1
    add.l   d3,d3
    endif
.bok:
    ifne SEGLOOP
    move.w  chA+14,d5           ; the nearest of: both chain ends and the
    cmp.w   chB+14,d5           ; bottom of the face
    bls.s   .m1
    move.w  chB+14,d5
.m1:
    cmp.w   poly_ymax,d5
    bls.s   .m2
    move.w  poly_ymax,d5
.m2:
    sub.w   d4,d5
    ifne YSTEP-1
    lsr.w   #1,d5
    endif
    move.w  d5,segcnt           ; rows left in the segment, minus one
    else
    clr.w   segcnt              ; one row per pass through .seg: the old
    endif                       ; shape of the loop, checked every row

.row:

    ifd ROWCOUNT                ; how many span-rows a solid REALLY walks:
    ifnd ROWDIV
ROWDIV      equ 512
    endif
    addq.w  #1,rowacc           ; every ROWDIV rows bumps bar three, so the
    cmp.w   #ROWDIV,rowacc      ; bar reads rows-per-64-frames / ROWDIV
    bcs.s   .nocnt
    clr.w   rowacc
    addq.w  #1,show_ctr
.nocnt:
    endif

    ifd PROBE
    if PROBE=1
    bra     .next
    endif
    endif

    ; --- span ends, ordered
    move.l  d0,d6
    swap    d6                  ; 8 cycles, where asr.l #7 cost 22
    move.l  d1,d7
    swap    d7
    cmp.w   d7,d6
    bls.s   .ord
    exg     d6,d7
.ord:
    move.w  d6,d4
    lsr.w   #3,d4
    move.l  a0,a1
    adda.w  d4,a1
    move.w  d7,d5
    lsr.w   #3,d5
    sub.w   d4,d5               ; d5 = last byte - first byte

    and.w   #7,d6
    move.b  8(a2,d6.w),d4       ; left mask, from the table beside pat4
    and.w   #7,d7
    move.b  16(a2,d7.w),d7      ; right mask

    move.w  t_y,d6
    if YSTEP=2
    and.w   #6,d6               ; (t_y/2) & 3, in words, in one step
    else
    and.w   #3,d6
    add.w   d6,d6
    endif
    move.w  0(a2,d6.w),d6       ; this row's fill, doubled

    ifd PROBE
    if PROBE=2
    bra     .next
    endif
    endif

    ; Every store has a twin ROWB bytes down when YSTEP is 2. The value is
    ; already in a register at that point, so the twin needs no registers
    ; and no second pass: it costs about as much as the stores themselves,
    ; where a pass over the whole cell cost three times the rows it saved.
    tst.w   d5
    bne.s   .wide
    and.b   d7,d4
    and.b   d6,d4
    or.b    d4,(a1)
    ifne YSTEP-1
    or.b    d4,ROWB(a1)
    endif
    bra.s   .next
.wide:
    and.b   d6,d4
    ifne YSTEP-1
    or.b    d4,ROWB(a1)         ; before the postincrement moves a1 on
    endif
    or.b    d4,(a1)+            ; end bytes are shared with the neighbour
    subq.w  #2,d5
    bmi.s   .right
    move.l  a1,d4
    btst    #0,d4
    beq.s   .even
    ifne YSTEP-1
    move.b  d6,ROWB(a1)
    endif
    move.b  d6,(a1)+
    subq.w  #1,d5
    bmi.s   .right
.even:
    addq.w  #1,d5
    move.w  d5,d4
    lsr.w   #1,d5
    beq.s   .noword
    subq.w  #1,d5
.mid:
    ifne YSTEP-1
    move.w  d6,(a1)
    move.w  d6,ROWB(a1)
    addq.l  #2,a1
    else
    move.w  d6,(a1)+
    endif
    dbra    d5,.mid
.noword:
    btst    #0,d4               ; odd leftover AFTER the words: doing it
    beq.s   .right              ; first leaves the address odd, and a move.w
    ifne YSTEP-1                ; to an odd address is an address error
    move.b  d6,ROWB(a1)
    endif
    move.b  d6,(a1)+
.right:
    and.b   d7,d6
    or.b    d6,(a1)
    ifne YSTEP-1
    or.b    d6,ROWB(a1)
    endif
.next:
    add.l   d2,d0
    add.l   d3,d1
    addq.w  #YSTEP,t_y
    adda.w  a5,a0
    subq.w  #1,segcnt
    bpl     .row
    bra     .seg
.out:
    movem.l (sp)+,d0-d7/a0-a2/a5
    rts

;----------------------------------------------------------------------
; Load the next downward edge of the chain whose state block is in a1.
; Block: ptr.l, x.l, slope.l, left.w, yend.w
;----------------------------------------------------------------------
adv_chain:
    movem.l d0-d7/a0,-(sp)
.again:
    move.w  12(a1),d0
    subq.w  #1,d0
    ble     .dead               ; fewer than two points left: no edge
    move.l  0(a1),a0
    moveq   #0,d1
    move.b  (a0),d1
    add.w   d1,d1
    moveq   #0,d2
    move.b  1(a0),d2
    add.w   d2,d2
    move.b  1(a4,d1.w),d3
    ext.w   d3                  ; y of this vertex
    move.b  1(a4,d2.w),d4
    ext.w   d4                  ; y of the next
    cmp.w   d3,d4
    bgt.s   .good
    addq.l  #1,0(a1)            ; flat edge: step over it
    subq.w  #1,12(a1)
    bra     .again
.good:
    move.b  0(a4,d1.w),d5
    ext.w   d5
    add.w   poly_cx,d5
    move.b  0(a4,d2.w),d6
    ext.w   d6
    add.w   poly_cx,d6
    move.w  d5,d7
    ext.l   d7
    swap    d7                  ; 16.16: the integer part is then just a swap
    move.l  d7,4(a1)            ; x starts exactly on the vertex
    move.w  d6,d7
    sub.w   d5,d7
    ext.l   d7
    asl.l   #FIX,d7
    move.w  d4,d5
    sub.w   d3,d5               ; dy, always positive here
    divs    d5,d7
    ext.l   d7                  ; divs leaves the remainder in the high word
    asl.l   #8,d7               ; 16.FIX up to 16.16, same precision
    asl.l   #1,d7
    move.l  d7,8(a1)
    move.w  d4,d7
    add.w   poly_cy,d7
    move.w  d7,14(a1)
    addq.l  #1,0(a1)
    subq.w  #1,12(a1)
    movem.l (sp)+,d0-d7/a0
    rts
.dead:
    move.w  #32767,14(a1)       ; never asks again
    movem.l (sp)+,d0-d7/a0
    rts

;----------------------------------------------------------------------
; d0 = strength 0..255, d1 = pad index * 2
;----------------------------------------------------------------------
    ifnd SCENES
show_note_on:
    endif
so_note_on:
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
    even
chA:            ds.b 16         ; ptr.l, x.l, slope.l, left.w, yend.w
chB:            ds.b 16
cell_level:     ds.w 8
cell_angle:     ds.w 8
cell_glitch:    ds.w 8
cell_cx:        ds.w 8
cell_cy:        ds.w 8
cell_last:      ds.w 8
cell_box:       ds.w 16     ; per cell: first row drawn, rows drawn
tlevel:         ds.w 1
poly_cx:        ds.w 1
poly_cy:        ds.w 1
poly_ymax:      ds.w 1
t_y:            ds.w 1
cell_wb:        ds.w 1
cell_rows:      ds.w 1
turn:           ds.w 1
free_ctr:       ds.w 1
shear_ctr:      ds.w 1
shear_cool:     ds.w 1
jitter:         ds.w 1
rowacc:         ds.w 1
segcnt:         ds.w 1
benchn:         ds.w 1
benchodd:       ds.w 1
    even
pat4:           ds.w 4          ; a2 points here; the mask tables are at
lmaskt:         ds.b 8          ; +8 and +16 so one register reaches all three
rmaskt:         ds.b 8
    even
cell_clr:       ds.l 8
