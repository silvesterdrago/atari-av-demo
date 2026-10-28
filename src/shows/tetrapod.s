;======================================================================
;  TETRAPOD
;
;  A flat-shaded tetrapod on the shuriken engine: four closed six-sided
;  frustums along the tetrahedral directions, 48 vertices, 32 convex
;  polygons (six quads and two hexagons a leg). The 3D core is still
;  MonogAtari's rotation matrix and perspective; on top of it:
;
;    * faces are culled by the rotated normal's z instead of screen
;      winding, which also gives the shade for free: the same product
;      plus a quarter of the normal's rotated y, so light sits above
;      the eye;
;    * the visible faces are sorted far to near by the depth of two
;      opposite vertices, an insertion sort over at most ~20 records;
;    * a convex polygon filler walks two edge chains from the top
;      vertex and dispatches every row straight into the unrolled span
;      routines, no call, no return, no triangle pairs: a hexagon end
;      is one polygon's rows where six fans were four times that;
;    * the span routines store a dither pattern instead of -1: a 4x4
;      Bayer, one word per row, picked by bits 4-5 of the row pointer
;      (y*80 = 16*5y, and 5y = y mod 4), see tools/gentetrapod.py.
;
;  Coordinates are 16x the star's and the eye 16x further, so the
;  demo's word-sized products stay in range.
;======================================================================
    ifnd SCENES
POOL_SIZE   equ 1024
RANGE_PAGES equ 141             ; two screens with 8 pages between and after:
    endif                       ; the filler may run a few rows past 399
BACK_OFF    equ SCR_SIZE+2048
    include "src/core/head.s"

CX          equ $1ea
CY          equ $f9
DIST        equ 16000
ROWB        equ 80
WIN_X       equ 32              ; cleared band: x 256..639
NVERT       equ 48              ; must match tools/gentetrapod.py
NPOLY       equ 32
MAXN        equ 6               ; vertices a polygon
SPEED_A     equ 2
SPEED_B     equ 3
SPEED_C     equ 4

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
    clr.w   ang_a
    clr.w   ang_b
    clr.w   ang_c
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

    movem.w ang_a,d0-d2
    addq.w  #SPEED_A,d0
    addq.w  #SPEED_B,d1
    addq.w  #SPEED_C,d2
    and.w   #$1ff,d0
    and.w   #$1ff,d1
    and.w   #$1ff,d2
    movem.w d0-d2,ang_a
    bsr     matrix

    ; every vertex: screen x,y into proj, depth into projz (4-byte slots,
    ; so a face's index*4 reads both)
    lea     tp_verts,a1
    lea     proj,a2
    lea     projz,a4
    move.w  #DIST,d6
    move.w  #NVERT-1,d7
.v:
    move.w  (a1)+,d0
    move.w  (a1)+,d1
    move.w  (a1)+,d2
    bsr     rotproj
    addi.w  #CX,d0
    addi.w  #CY,d1
    move.w  d0,(a2)+
    move.w  d1,(a2)+
    move.w  d2,(a4)
    addq.l  #4,a4
    dbra    d7,.v

    ; the visible polygons: record = depth key.w, shade.w, polygon.l
    lea     tp_faces,a3
    lea     vis,a4
    lea     projz,a2
    moveq   #0,d7
    move.w  #NPOLY-1,d6
.f:
    movea.l a3,a5               ; n, k0, k1, nx, ny, nz, indices...
    move.w  6(a3),d0            ; normal
    move.w  8(a3),d1
    move.w  10(a3),d2
    move.w  (a3),d3             ; skip the record: 12 + n*2 bytes
    add.w   d3,d3
    lea     12(a3,d3.w),a3
    move.w  d0,d3
    muls    mtx+12,d3
    move.w  d1,d4
    muls    mtx+14,d4
    add.l   d4,d3
    move.w  d2,d4
    muls    mtx+16,d4
    add.l   d4,d3               ; rotated nz: towards the eye when > 0
    ble.s   .hidden
    muls    mtx+6,d0
    muls    mtx+8,d1
    muls    mtx+10,d2
    add.l   d1,d0
    add.l   d2,d0               ; rotated ny
    asr.l   #2,d0
    add.l   d0,d3               ; nz + ny/4: light above the eye
    moveq   #11,d0
    asr.l   d0,d3
    bgt.s   .lo
    moveq   #1,d3               ; never black: a black face on the
.lo:                            ; silhouette would vanish into the ground
    cmp.w   #15,d3
    ble.s   .hi
    moveq   #15,d3
.hi:
    move.w  2(a5),d0            ; depth of two opposite vertices
    move.w  4(a5),d1
    move.w  (a2,d0.w),d4
    add.w   (a2,d1.w),d4
    move.w  d4,(a4)+
    move.w  d3,(a4)+
    move.l  a5,(a4)+
    addq.w  #1,d7
.hidden:
    dbra    d6,.f
    move.w  d7,nvis

    ; far to near: insertion sort on the key
    lea     vis,a2
    move.w  d7,d6
    subq.w  #2,d6
    bmi.s   .sorted
    lea     8(a2),a3
.si:
    move.w  (a3),d3
    move.l  (a3),d0
    move.l  4(a3),d1
    movea.l a3,a4
.sj:
    cmp.l   a2,a4
    beq.s   .ins
    cmp.w   -8(a4),d3
    bge.s   .ins
    move.l  -8(a4),(a4)
    move.l  -4(a4),4(a4)
    subq.l  #8,a4
    bra.s   .sj
.ins:
    move.l  d0,(a4)
    move.l  d1,4(a4)
    addq.l  #8,a3
    dbra    d6,.si
.sorted:

    lea     vis,a4
    move.w  nvis,d7
    subq.w  #1,d7
    bmi.s   .drawn
.d:
    move.w  2(a4),d0            ; shade -> the four pattern words
    lsl.w   #3,d0
    lea     tp_pats,a2
    move.w  (a2,d0.w),cur_pat
    move.w  2(a2,d0.w),cur_pat+16
    move.w  4(a2,d0.w),cur_pat+32
    move.w  6(a2,d0.w),cur_pat+48
    movea.l 4(a4),a3
    addq.l  #8,a4
    move.w  (a3),d6             ; gather the polygon's screen points
    lea     12(a3),a3
    lea     poly,a2
    lea     proj,a5
    move.w  d6,d5
    subq.w  #1,d5
.g:
    move.w  (a3)+,d0
    move.l  (a5,d0.w),(a2)+
    dbra    d5,.g
    lea     poly,a2
    move.w  d6,d0
    move.l  back,a1
    bsr     poly_fill
    dbra    d7,.d
.drawn:

    ; remember the rows the body covers, one row of margin
    lea     proj+2,a2
    move.w  #NVERT-1,d7
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

    move.l  back,d0
    bsr     set_screen_base
    addq.w  #1,show_ctr
    movem.l (sp)+,d0-d7/a0-a6
    rts

; a hit flips the body a quarter turn on
show_note_on:
    add.w   #128,ang_b
    and.w   #$1ff,ang_b
    rts

;----------------------------------------------------------------------
; d0,d1,d2 = x,y,z -> d0,d1 = screen offsets from the centre, d2 = depth
; (z/2 - DIST, more negative is further). d6 = DIST.
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
    move.w  d6,mtx+12
    move.w  d1,mtx+14
    move.w  d2,d6
    muls    d0,d6
    add.l   d6,d6
    add.l   d6,d6
    swap    d6
    move.w  d6,mtx+16
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
    move.w  d4,mtx+2
    muls    d6,d0
    add.l   d0,d0
    add.l   d0,d0
    swap    d0
    move.w  d0,mtx+8
    move.w  d3,d4
    asr.w   #1,d4
    asr.w   #1,d1
    muls    d1,d4
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
    move.w  d5,mtx+0
    muls    d7,d2
    muls    d6,d4
    sub.l   d4,d2
    add.l   d2,d2
    add.l   d2,d2
    swap    d2
    move.w  d2,mtx+6
    move.l  a1,d2
    asr.w   #1,d2
    muls    d2,d1
    asl.w   #6,d3
    move.w  d1,d5
    muls    d7,d5
    move.w  d3,d0
    muls    d6,d0
    sub.l   d0,d5
    add.l   d5,d5
    add.l   d5,d5
    swap    d5
    move.w  d5,mtx+4
    muls    d1,d6
    muls    d3,d7
    add.l   d6,d7
    add.l   d7,d7
    add.l   d7,d7
    swap    d7
    neg.w   d7
    move.w  d7,mtx+10
    rts

;----------------------------------------------------------------------
; Convex polygon. a2 -> n (x,y) word pairs, d0 = n, a1 = screen base,
; cur_pat holds the face's pattern. Finds the top vertex and walks two
; chains of edges from it, one each way round the polygon, in 16.16
; from a 16.8 division (the demo's precision), and fills every row
; between them with one jump into the span routines. Chains need no
; left/right: the dispatcher swaps the ends. Rows past the bottom of a
; chain's edge pull the next vertex; horizontal edges are stepped over.
;----------------------------------------------------------------------
poly_fill:
    movem.l d0-d7/a0-a6,-(sp)
    move.w  d0,pf_n
    move.w  d0,d7
    subq.w  #1,d7
    moveq   #0,d3               ; index
    move.w  2(a2),d0            ; ymin so far
    move.w  d0,d1               ; ymax so far
    clr.w   pf_top
    movea.l a2,a3
.scan:
    move.w  2(a3),d2
    addq.l  #4,a3
    cmp.w   d2,d0
    ble.s   .notmin
    move.w  d2,d0
    move.w  d3,pf_top
.notmin:
    cmp.w   d2,d1
    bge.s   .notmax
    move.w  d2,d1
.notmax:
    addq.w  #1,d3
    dbra    d7,.scan
    move.w  d1,pf_ybot
    cmp.w   d0,d1
    ble     .done               ; flat: nothing to fill
    move.w  d0,d3               ; y
    mulu    #ROWB,d0
    adda.l  d0,a1               ; row of the top vertex
    move.w  pf_top,pf_ia        ; both chains start there, no rows left
    move.w  pf_top,pf_ib
    moveq   #0,d6
    moveq   #0,d7
    lea     span_tbl,a0
.row:
    tst.w   d6
    bne.s   .aok
    bsr     pf_adva
.aok:
    tst.w   d7
    bne.s   .bok
    bsr     pf_advb
.bok:
    move.l  d0,d4
    swap    d4
    move.l  d1,d5
    swap    d5
    cmp.w   d4,d5
    beq.s   .next
    bgt.s   .ord
    exg     d4,d5
.ord:
    sub.w   d4,d5
    cmp.w   #127,d5
    bhi.s   .long
.one:
    move.w  d4,d2
    lsr.w   #4,d2
    add.w   d2,d2
    lea     (a1,d2.w),a5
    andi.w  #15,d4
    lsl.w   #7,d4
    add.w   d5,d4
    lsl.w   #3,d4
    move.w  a1,d2
    and.w   #48,d2              ; bits 4-5 of y*80 = (y & 3) * 16
    move.w  cur_pat(pc,d2.w),d2
    jsr     (a0,d4.w)           ; the span routine's rts lands here
.next:
    lea     ROWB(a1),a1
    add.l   a4,d0
    add.l   a6,d1
    subq.w  #1,d6
    subq.w  #1,d7
    addq.w  #1,d3
    cmp.w   pf_ybot,d3
    blt.s   .row
.done:
    movem.l (sp)+,d0-d7/a0-a6
    rts
.long:                          ; past 127 pixels: 127 now, the rest after
    move.w  d4,-(sp)
    move.w  d5,-(sp)
    moveq   #127,d5
    move.w  d4,d2
    lsr.w   #4,d2
    add.w   d2,d2
    lea     (a1,d2.w),a5
    andi.w  #15,d4
    lsl.w   #7,d4
    add.w   d5,d4
    lsl.w   #3,d4
    move.w  a1,d2
    and.w   #48,d2
    move.w  cur_pat(pc,d2.w),d2
    jsr     (a0,d4.w)
    move.w  (sp)+,d5
    move.w  (sp)+,d4
    add.w   #127,d4
    sub.w   #127,d5
    beq.s   .next
    cmp.w   #127,d5
    bhi.s   .long
    bra.s   .one
cur_pat:
    dc.w    0,0,0,0,0,0,0,0     ; the face's pattern, one word per row
    dc.w    0,0,0,0,0,0,0,0     ; of the dither, 16 bytes apart
    dc.w    0,0,0,0,0,0,0,0
    dc.w    0

; chain A goes down the polygon by decreasing index. Leaves x in d0
; (16.16), its step in a4 and the edge's rows in d6.
pf_adva:
    move.w  pf_ia,d2
    move.w  d2,d4
    add.w   d4,d4
    add.w   d4,d4
    move.w  (a2,d4.w),d0        ; x, y of the vertex we are at
    move.w  2(a2,d4.w),d5
.an:
    subq.w  #1,d2
    bpl.s   .aw
    add.w   pf_n,d2
.aw:
    move.w  d2,d4
    add.w   d4,d4
    add.w   d4,d4
    move.w  2(a2,d4.w),d6
    sub.w   d5,d6               ; rows to the next vertex
    beq.s   .an                 ; horizontal edge: look past it
    move.w  d2,pf_ia
    move.w  (a2,d4.w),d4
    sub.w   d0,d4               ; dx
    swap    d0
    clr.w   d0
    ext.l   d4
    asl.l   #8,d4
    divs    d6,d4
    ext.l   d4
    asl.l   #8,d4
    movea.l d4,a4
    rts

; chain B by increasing index: x in d1, step in a6, rows in d7
pf_advb:
    move.w  pf_ib,d2
    move.w  d2,d4
    add.w   d4,d4
    add.w   d4,d4
    move.w  (a2,d4.w),d1
    move.w  2(a2,d4.w),d5
.bn:
    addq.w  #1,d2
    cmp.w   pf_n,d2
    blt.s   .bw
    moveq   #0,d2
.bw:
    move.w  d2,d4
    add.w   d4,d4
    add.w   d4,d4
    move.w  2(a2,d4.w),d7
    sub.w   d5,d7
    beq.s   .bn
    move.w  d2,pf_ib
    move.w  (a2,d4.w),d4
    sub.w   d1,d4
    swap    d1
    clr.w   d1
    ext.l   d4
    asl.l   #8,d4
    divs    d7,d4
    ext.l   d4
    asl.l   #8,d4
    movea.l d4,a6
    rts

    include "src/core/tail.s"
    include "src/tetrapod.inc"  ; 48 KB of span code: after the core, so
                                ; the core's own bsr's stay in reach

    section bss
    even
back:       ds.l 1
slot:       ds.l 1
rows:       ds.w 4
mtx:        ds.w 15
ang_a:      ds.w 1
ang_b:      ds.w 1
ang_c:      ds.w 1
nvis:       ds.w 1
pf_n:       ds.w 1
pf_top:     ds.w 1
pf_ybot:    ds.w 1
pf_ia:      ds.w 1
pf_ib:      ds.w 1
proj:       ds.w 2*NVERT
projz:      ds.w 2*NVERT
poly:       ds.w 2*MAXN
vis:        ds.b 8*NPOLY
