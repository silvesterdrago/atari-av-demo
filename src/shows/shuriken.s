;======================================================================
;  SHURIKEN
;
;  The spinning star from MonogAtari (Cerebral Vortex, SV2013) on a plain
;  STF. Fourteen vertices, two sets of twelve triangles: one filled with
;  backface culling, the other drawn as wireframe over it and scaled by
;  a 16-step pulse, so the wire star breathes around the solid one.
;
;  The 3D code is the demo's own, instruction for instruction: a 1.8
;  rotation matrix built from 512-step tables, perspective at 200/(z-1000)
;  with the object centred at (490,249), a Bresenham line for the wire,
;  and a triangle filler that walks both edges in 16.16 and fills each
;  scanline with ONE JUMP into 2048 unrolled span routines indexed by
;  (first pixel & 15, length) -- see tools/genshuriken.py. The demo's
;  blitter only cleared the window under the star; here that is a movem.
;======================================================================
    ifnd SCENES
POOL_SIZE   equ 1024
RANGE_PAGES equ 141             ; two screens with 8 pages between and after:
    endif                       ; the filler runs to y 416 for the nearest
BACK_OFF    equ SCR_SIZE+2048   ; spikes, and that must not land on the
    include "src/core/head.s"   ; other screen's top rows

CX          equ $1ea            ; the demo's centre of projection
CY          equ $f9
DIST        equ 1000
ROWB        equ 80
WIN_X       equ 32              ; cleared band: x 256..639, and only the
                                ; rows the star covered last time on this
                                ; screen (the demo blitted a fixed window)

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
    clr.w   ang_a
    clr.w   ang_b
    clr.w   ang_c
    clr.w   frame
    lea     rows,a0             ; nothing drawn yet on either screen
    clr.w   (a0)+
    move.w  #-1,(a0)+
    clr.w   (a0)+
    move.w  #-1,(a0)
    rts

;----------------------------------------------------------------------
show_frame:
    movem.l d0-d7/a0-a6,-(sp)
    move.l  buf_base,a0         ; draw into whichever screen is not shown
    lea     rows,a2             ; and take that screen's dirty rows
    cmp.l   cur_base,a0
    bne.s   .back
    add.l   #BACK_OFF,a0
    addq.l  #4,a2
.back:
    move.l  a0,back
    move.l  a2,slot
    ; clear the rows the star covered last time, 48 bytes a row
    move.w  (a2)+,d0
    move.w  (a2),d1
    sub.w   d0,d1
    bmi.s   .clean
    mulu    #ROWB,d0
    lea     WIN_X(a0,d0.l),a0
    exg     d0,d1
    moveq   #0,d1
    moveq   #0,d2
    moveq   #0,d3
    moveq   #0,d4
    moveq   #0,d5
    moveq   #0,d6
    moveq   #0,d7
    movea.l d1,a2
    movea.l d1,a3
    movea.l d1,a4
    movea.l d1,a5
    movea.l d1,a6
.clr:
    movem.l d1-d7/a2-a6,(a0)
    lea     ROWB(a0),a0
    dbra    d0,.clr
.clean:

    ; the pulse, and the three angles at 2, 3 and 4 steps a frame
    move.w  frame,d0
    addq.w  #1,frame
    and.w   #15,d0
    lea     zoomtab,a0
    moveq   #0,d1
    move.b  (a0,d0.w),d1
    move.w  d1,zoom
    movem.w ang_a,d0-d2
    addq.w  #2,d0
    addq.w  #3,d1
    addq.w  #4,d2
    and.w   #$1ff,d0
    and.w   #$1ff,d1
    and.w   #$1ff,d2
    movem.w d0-d2,ang_a
    bsr     matrix

    lea     mesh_fill,a0
    move.w  #DIST,d6
    lea     fill_cull,a6
    bsr     draw_mesh

    ; scale the projected points about the centre by zoom/64
    lea     proj,a2
    moveq   #14-1,d7
    move.w  #CX,d2
    move.w  #CY,d3
    move.w  zoom,d4
.sc:
    move.w  (a2),d0
    sub.w   d2,d0
    muls    d4,d0
    asr.w   #6,d0
    add.w   d2,d0
    move.w  d0,(a2)+
    move.w  (a2),d0
    sub.w   d3,d0
    muls    d4,d0
    asr.w   #6,d0
    add.w   d3,d0
    move.w  d0,(a2)+
    dbra    d7,.sc

    ; remember the rows the (larger) wire star covers, one row of margin
    lea     proj+2,a2
    moveq   #14-1,d7
    move.w  #$7fff,d0
    move.w  #$8000,d1
.bb:
    move.w  (a2),d2
    addq.l  #4,a2
    cmp.w   d2,d0
    ble.s   .bb1
    move.w  d2,d0
.bb1:
    cmp.w   d2,d1
    bge.s   .bb2
    move.w  d2,d1
.bb2:
    dbra    d7,.bb
    subq.w  #1,d0
    bpl.s   .bb3
    moveq   #0,d0
.bb3:
    addq.w  #1,d1
    cmp.w   #399,d1
    ble.s   .bb4
    move.w  #399,d1
.bb4:
    move.l  slot,a2
    move.w  d0,(a2)+
    move.w  d1,(a2)

    ; the wire star over it: the other twelve faces, no culling
    lea     mesh_wire+8,a0
    move.l  (a0)+,d7
    subq.w  #1,d7
    movea.l (a0)+,a3
    move.l  back,a1
    lea     proj,a2
.wf:
    move.w  (a3)+,d1
    move.w  (a3)+,d3
    move.w  (a3)+,d5
    move.w  (a2,d1.w),d0
    move.w  2(a2,d1.w),d1
    move.w  (a2,d3.w),d2
    move.w  2(a2,d3.w),d3
    move.w  (a2,d5.w),d4
    move.w  2(a2,d5.w),d5
    bsr     wire_nocull
    dbra    d7,.wf

    move.l  back,d0
    bsr     set_screen_base     ; the shifter picks it up at the next VBL
    addq.w  #1,show_ctr
    movem.l (sp)+,d0-d7/a0-a6
    rts

; a hit restarts the pulse from its widest
show_note_on:
    move.w  frame,d0
    and.w   #$fff0,d0
    addq.w  #2,d0
    move.w  d0,frame
    rts

;----------------------------------------------------------------------
; a0 = mesh, d6 = distance, a6 = face routine (d0-d5 = three points).
; Projects every vertex into proj, then calls a6 once per face.
;----------------------------------------------------------------------
draw_mesh:
    move.l  (a0)+,d7
    subq.w  #1,d7
    movea.l (a0)+,a1
    lea     proj,a2
.v:
    move.w  (a1)+,d0
    move.w  (a1)+,d1
    move.w  (a1)+,d2
    bsr     rotproj
    addi.w  #CX,d0
    addi.w  #CY,d1
    move.w  d0,(a2)+
    move.w  d1,(a2)+
    dbra    d7,.v
    move.l  (a0)+,d7
    subq.w  #1,d7
    movea.l (a0)+,a3
    move.l  back,a1
    lea     proj,a2
.f:
    move.w  (a3)+,d1
    move.w  (a3)+,d3
    move.w  (a3)+,d5
    move.w  (a2,d1.w),d0
    move.w  2(a2,d1.w),d1
    move.w  (a2,d3.w),d2
    move.w  2(a2,d3.w),d3
    move.w  (a2,d5.w),d4
    move.w  2(a2,d5.w),d5
    jsr     (a6)
    dbra    d7,.f
    rts

;----------------------------------------------------------------------
; d0,d1,d2 = x,y,z -> d0,d1 = screen offsets from the centre. d6 = distance.
; The matrix is 1.8 so a +-4 vertex lands at +-1020, halved to fit the
; word multiply by the 200 focal length.
;----------------------------------------------------------------------
rotproj:
    lea     mtx,a3
    move.w  d0,d3
    move.w  d1,d4
    muls    (a3)+,d0
    muls    (a3)+,d4
    add.l   d4,d0
    move.w  d2,d4
    muls    (a3)+,d4
    add.l   d4,d0
    move.w  d3,d4
    move.w  d1,d5
    muls    (a3)+,d4
    muls    (a3)+,d1
    add.l   d4,d1
    move.w  d2,d4
    muls    (a3)+,d4
    add.l   d4,d1
    muls    (a3)+,d3
    muls    (a3)+,d5
    muls    (a3)+,d2
    add.l   d3,d5
    add.l   d5,d2
    asr.l   #1,d0
    asr.l   #1,d1
    asr.l   #1,d2
    muls    #200,d0
    muls    #200,d1
    sub.w   d6,d2
    divs    d2,d0
    divs    d2,d1
    rts

;----------------------------------------------------------------------
; Rotation matrix from ang_a/b/c, the demo's own mix of 1.8 products.
;----------------------------------------------------------------------
matrix:
    lea     costab,a2
    lea     sintab,a4
    move.w  ang_a,d6
    add.w   d6,d6
    move.w  (a2,d6.w),d0        ; cos a
    move.w  d0,mtx+18
    move.w  (a4,d6.w),d1        ; sin a
    move.w  d1,mtx+20
    move.w  ang_b,d6
    add.w   d6,d6
    move.w  (a2,d6.w),d2        ; cos b
    move.w  d2,mtx+22
    move.w  (a4,d6.w),d3        ; sin b
    move.w  d3,mtx+24
    asl.w   #6,d0
    move.w  d3,d6
    muls    d0,d6
    add.l   d6,d6
    add.l   d6,d6
    swap    d6
    move.w  d6,mtx+12           ; m6 = sin b cos a
    move.w  d1,mtx+14           ; m7 = sin a
    move.w  d2,d6
    muls    d0,d6
    add.l   d6,d6
    add.l   d6,d6
    swap    d6
    move.w  d6,mtx+16           ; m8 = cos b cos a
    move.w  ang_c,d6
    add.w   d6,d6
    move.w  (a4,d6.w),d7        ; sin c
    move.w  d7,mtx+28
    move.w  (a2,d6.w),d6        ; cos c
    move.w  d6,mtx+26
    move.w  d0,d4
    muls    d7,d4
    add.l   d4,d4
    add.l   d4,d4
    swap    d4
    neg.w   d4
    move.w  d4,mtx+2            ; m1 = -cos a sin c
    muls    d6,d0
    add.l   d0,d0
    add.l   d0,d0
    swap    d0
    move.w  d0,mtx+8            ; m4 = cos a cos c
    move.w  d3,d4
    asr.w   #1,d4
    asr.w   #1,d1
    muls    d1,d4               ; sin b sin a / 4
    movea.l d2,a1
    asl.w   #6,d2
    move.w  d2,d0
    muls    d6,d0
    move.w  d4,d5
    muls    d7,d5
    add.l   d0,d5
    add.l   d5,d5
    add.l   d5,d5
    swap    d5
    move.w  d5,mtx+0            ; m0
    muls    d7,d2
    muls    d6,d4
    sub.l   d4,d2
    add.l   d2,d2
    add.l   d2,d2
    swap    d2
    move.w  d2,mtx+6            ; m3
    move.l  a1,d2
    asr.w   #1,d2
    muls    d2,d1               ; sin a cos b / 2
    asl.w   #6,d3
    move.w  d1,d5
    muls    d7,d5
    move.w  d3,d0
    muls    d6,d0
    sub.l   d0,d5
    add.l   d5,d5
    add.l   d5,d5
    swap    d5
    move.w  d5,mtx+4            ; m2
    muls    d1,d6
    muls    d3,d7
    add.l   d6,d7
    add.l   d7,d7
    add.l   d7,d7
    swap    d7
    neg.w   d7
    move.w  d7,mtx+10           ; m5
    rts

;----------------------------------------------------------------------
; Wire triangle, d0-d5 = three points, a1 = screen. wire_cull drops the
; triangle when its winding says it faces away.
;----------------------------------------------------------------------
wire_nocull:
    movem.w d0-d7,-(sp)
    bra.s   wire_draw
wire_cull:
    movem.w d0-d7,-(sp)
    sub.w   d0,d2
    sub.w   d0,d4
    sub.w   d1,d3
    sub.w   d1,d5
    muls    d3,d4
    muls    d2,d5
    sub.l   d4,d5
    bge.s   wire_draw
    movem.w (sp)+,d0-d7
    rts
wire_draw:
    movem.w 4(sp),d2-d3
    movea.l a1,a0
    bsr     line
    movem.w 4(sp),d0-d3
    movea.l a1,a0
    bsr     line
    movem.w 8(sp),d0-d1
    movem.w (sp),d2-d3
    movea.l a1,a0
    bsr     line
    movem.w (sp)+,d0-d7
    rts

;----------------------------------------------------------------------
; Bresenham. d0,d1 -> d2,d3 on screen a0, OR-ing pixels, 80 bytes a row.
;----------------------------------------------------------------------
line:
    movem.l d0-d6,-(sp)
    cmp.w   d0,d2
    bpl.s   .lr
    exg     d0,d2
    exg     d1,d3
.lr:
    move.w  d1,d4
    lsl.w   #4,d4
    move.w  d4,d5
    lsl.w   #2,d5
    add.w   d5,d4
    move.w  d0,d5
    lsr.w   #3,d5
    add.w   d5,d4
    adda.w  d4,a0
    sub.w   d0,d2               ; dx >= 0
    sub.w   d1,d3               ; dy
    move.w  #ROWB,d4
    tst.w   d3
    bpl.s   .down
    neg.w   d3
    move.w  #-ROWB,d4
.down:
    move.b  #$80,d5
    andi.w  #7,d0
    lsr.w   d0,d5
    cmp.w   d2,d3
    beq.s   .diag
    bpl.s   .steep
    move.w  d2,d1
    lsr.w   #1,d1
    move.w  d2,d6
    subq.w  #1,d6
.sh:
    or.b    d5,(a0)
    sub.w   d3,d1
    bpl.s   .sh2
    add.w   d2,d1
    adda.w  d4,a0
.sh2:
    ror.b   #1,d5
    bcc.s   .sh3
    addq.w  #1,a0
.sh3:
    dbra    d6,.sh
    movem.l (sp)+,d0-d6
    rts
.steep:
    move.w  d3,d1
    lsr.w   #1,d1
    move.w  d3,d6
    subq.w  #1,d6
.st:
    or.b    d5,(a0)
    sub.w   d2,d1
    bpl.s   .st2
    add.w   d3,d1
    ror.b   #1,d5
    bcc.s   .st2
    addq.w  #1,a0
.st2:
    adda.w  d4,a0
    dbra    d6,.st
    movem.l (sp)+,d0-d6
    rts
.diag:
    tst.w   d3                  ; the demo had no guard here: two equal
    beq.s   .dot                ; points would loop 65536 times
    subq.w  #1,d3
.dg:
    or.b    d5,(a0)
    adda.w  d4,a0
    ror.b   #1,d5
    bcc.s   .dg2
    addq.w  #1,a0
.dg2:
    dbra    d3,.dg
    movem.l (sp)+,d0-d6
    rts
.dot:
    or.b    d5,(a0)
    movem.l (sp)+,d0-d6
    rts

;----------------------------------------------------------------------
; Filled triangle, d0-d5 = three points, a1 = screen. Sorts by y, walks
; the long edge (a4 step) against the two short ones (a6, then d3), and
; hands each scanline to span. fill_cull drops back faces.
;----------------------------------------------------------------------
fill_nocull:
    movem.l d0-d7/a0-a6,-(sp)
    bra.s   fill_draw
fill_cull:
    movem.l d0-d7/a0-a6,-(sp)
    sub.w   d0,d2
    sub.w   d0,d4
    sub.w   d1,d3
    sub.w   d1,d5
    muls    d3,d4
    muls    d2,d5
    sub.l   d4,d5
    bge.s   fill_draw
    movem.l (sp)+,d0-d7/a0-a6
    rts
fill_draw:
    movem.l (sp),d0-d5
    cmp.w   d1,d3
    bgt.s   .s1
    exg     d1,d3
    exg     d0,d2
.s1:
    cmp.w   d1,d5
    bgt.s   .s2
    exg     d1,d5
    exg     d0,d4
.s2:
    cmp.w   d3,d5
    bgt.s   .s3
    exg     d3,d5
    exg     d2,d4
.s3:
    movea.l d1,a5               ; y0
    movea.l d5,a2               ; y2
    swap    d0
    swap    d2
    swap    d4                  ; x as 16.16
    movea.l d2,a3               ; x1
    move.l  d0,d6               ; x0
    sub.l   d4,d0               ; x0-x2
    sub.l   d2,d4               ; x2-x1
    sub.l   d6,d2               ; x1-x0
    asr.l   #8,d0
    asr.l   #8,d4
    asr.l   #8,d2
    move.w  d3,d7               ; y1
    sub.w   d1,d3               ; y1-y0
    beq.s   .e01z
    divs    d3,d2
    ext.l   d2
    asl.l   #8,d2
    movea.l d2,a6               ; step along 0-1
    bra.s   .e02
.e01z:
    movea.w #0,a6
.e02:
    sub.w   d5,d1               ; y0-y2
    beq.s   .e02z
    divs    d1,d0
    ext.l   d0
    asl.l   #8,d0
    movea.l d0,a4               ; step along 0-2
    bra.s   .e12
.e02z:
    movea.w #0,a4
.e12:
    sub.w   d7,d5               ; y2-y1
    beq.s   .e12z
    divs    d5,d4
    ext.l   d4
    asl.l   #8,d4
    move.l  d4,d3               ; step along 1-2
    bra.s   .go
.e12z:
    moveq   #0,d3
.go:
    move.l  a5,d0               ; y
    move.w  a5,d1
    lsl.w   #4,d1
    adda.w  d1,a1
    lsl.w   #2,d1
    adda.w  d1,a1               ; row of y0
    move.l  d6,d1               ; x along 0-1
    lea     span_tbl,a0
.top:
    cmp.w   d7,d0
    bge.s   .bot
    move.l  d6,d5
    move.l  d1,d4
    swap    d5
    swap    d4
    movea.l a1,a5
    bsr     span
    lea     ROWB(a1),a1
    add.l   a6,d1
    add.l   a4,d6
    addq.w  #1,d0
    bra.s   .top
.bot:
    cmp.w   a2,d7
    bge.s   .done
    move.l  d6,d5
    move.l  a3,d4
    swap    d5
    swap    d4
    movea.l a1,a5
    bsr     span
    lea     ROWB(a1),a1
    adda.l  d3,a3
    add.l   a4,d6
    addq.w  #1,d7
    bra.s   .bot
.done:
    movem.l (sp)+,d0-d7/a0-a6
    rts

;----------------------------------------------------------------------
; One scanline: pixels d4..d5 (either order) on the row at a5, a0 =
; span_tbl. The routine jumped to ends with the rts that returns here's
; caller. Lengths past 127 are clamped; the demo let them index the
; next shift's row.
;----------------------------------------------------------------------
span:
    cmp.w   d4,d5
    bne.s   .nz
    rts
.nz:
    bgt.s   .ord
    exg     d5,d4
.ord:
    sub.w   d4,d5
    cmp.w   #127,d5
    bls.s   .len
    moveq   #127,d5
.len:
    move.w  d4,d2
    lsr.w   #4,d2
    add.w   d2,d2
    adda.w  d2,a5
    andi.w  #15,d4
    lsl.w   #7,d4
    add.w   d5,d4
    lsl.w   #3,d4
    moveq   #-1,d2
    jmp     (a0,d4.w)

    include "src/core/tail.s"
    include "src/shuriken.inc"  ; 48 KB of span code: after the core, so
                                ; the core's own bsr's stay in reach

    section bss
    even
back:       ds.l 1
slot:       ds.l 1              ; -> this screen's pair in rows
rows:       ds.w 4              ; first,last dirty row, per screen
mtx:        ds.w 15             ; 9 matrix words, then the 6 raw sines
ang_a:      ds.w 1
ang_b:      ds.w 1
ang_c:      ds.w 1
frame:      ds.w 1
zoom:       ds.w 1
proj:       ds.w 2*14
