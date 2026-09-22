;======================================================================
;  MONOLITH
;
;  One solid, filling the screen, instead of eight in a grid.
;
;  The grid was the wrong composition for this machine. A span-row costs
;  around 375 cycles whatever its width, so eight figures cost eight
;  times one figure while covering a twelfth of the screen each. One
;  figure of the same total row count fills the screen instead.
;
;  Three things differ from SOLIDS:
;
;  * vertices are WORDS. At 350 px across they do not fit a signed byte,
;    and the edge slopes are worked out to a full 16.16 with two divu
;    steps instead of a pre-shift, because a 1/128 px error over 350 rows
;    is a three-pixel skew.
;  * two screens, flipped. A redraw takes a few frames, so on one figure
;    the size of the screen the beam catching it mid-redraw is the
;    loudest defect there is. 32 KB buys it away.
;  * the blanking window is fixed: 48 bytes at byte 16, which contains
;    every pose the generator will emit (it asserts it). SOLIDS worked its
;    blanking box out on the machine and sprang a leak I never found.
;======================================================================
POOL_SIZE   equ 1024            ; no noise in this one
RANGE_PAGES equ 131             ; 256 pages: two whole screens, 32768 apart,
                                ; both on a 256-byte boundary so the base
                                ; register can flip between them
    include "src/core/head.s"

MO_SCALES   equ 4
MO_ANGLES   equ 48
MO_STRIDE   equ 128
MO_POSES    equ 32              ; poses start after the dither table
CX          equ 320             ; screen centre. A multiple of 8, so the
CY          equ 200             ; blanking window needs no rounding
ROWB        equ 80              ; bytes in a screen row; mono only
YSTEP       equ 2               ; draw every second row, double it in the span
BACK        equ 32768           ; the other screen
BLANK_X     equ 16              ; the window that holds every pose:
BLANK_W     equ 48              ; bytes 16..63, x 128..511
MO_DECAY    equ 2
SPIN_REST   equ 1               ; angle steps a redraw when quiet

;----------------------------------------------------------------------
show_init:
    lea     lmaskt,a0
    lea     rmaskt,a1
    moveq   #0,d0
.mk:
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
    bcs.s   .mk

    move.w  #CX,poly_cx
    move.w  #CY,poly_cy

    move.l  buf_base,a0         ; both screens start blank
    move.l  a0,a1
    add.l   #BACK+SCR_SIZE,a1
    bsr     clear_span

    ifd MOSHAPE                 ; lock one shape, for measuring the worst one
    move.w  #MOSHAPE,shape
    else
    clr.w   shape
    endif
    clr.w   angle
    clr.w   mo_level
    move.w  #1,back_side        ; screen A is the one being shown, so the
    move.w  #-1,last_pose       ; first redraw goes into B
    lea     blank_y,a0
    clr.l   (a0)                ; neither screen has anything on it
    clr.l   4(a0)
    rts

;----------------------------------------------------------------------
show_frame:
    move.w  mo_level,d0
    sub.w   #MO_DECAY,d0
    bpl.s   .lv
    moveq   #0,d0
.lv:
    move.w  d0,mo_level

    ; One angle step a redraw at rest, more while a hit is fresh. Stepping
    ; per REDRAW and not per frame is the point: the figure then turns as
    ; fast as the machine can draw it, whatever that turns out to be.
    lsr.w   #6,d0
    add.w   #SPIN_REST,d0
    add.w   angle,d0
.wrap:
    cmp.w   #MO_ANGLES,d0
    bcs.s   .aok
    sub.w   #MO_ANGLES,d0
    bra.s   .wrap
.aok:
    move.w  d0,angle

    move.w  mo_level,d1
    lsr.w   #6,d1               ; 0..3
    cmp.w   #MO_SCALES,d1
    bcs.s   .sok
    moveq   #MO_SCALES-1,d1
.sok:
    move.w  shape,d2
    mulu    #MO_SCALES,d2
    add.w   d1,d2
    mulu    #MO_ANGLES,d2
    add.w   d0,d2
    cmp.w   last_pose,d2
    beq.s   .same
    move.w  d2,last_pose
    bsr     draw_mono
.same:
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d1,-(sp)         ; the caller's parser still needs these
    move.w  d0,mo_level
    ifnd MOSHAPE
    lsr.w   #1,d1
    and.w   #7,d1
    move.w  d1,shape
    endif
    move.w  #-1,last_pose       ; redraw even if the angle has not moved
    movem.l (sp)+,d0-d1
    rts

;----------------------------------------------------------------------
; Draw the pose in last_pose into whichever screen is not being shown,
; then flip to it.
;----------------------------------------------------------------------
draw_mono:
    movem.l d0-d7/a0-a6,-(sp)
    if DIAG
    addq.w  #1,show_ctr
    endif

    move.w  back_side,d6        ; which screen we draw into
    move.l  buf_base,a1
    tst.w   d6
    beq.s   .front
    adda.l  #BACK,a1
.front:
    move.l  a1,draw_base

    ; --- blank what THIS screen still shows, from two redraws ago
    move.w  d6,d0
    lsl.w   #2,d0               ; two words a screen
    lea     blank_y,a2
    adda.w  d0,a2
    move.w  (a2),d0
    move.w  2(a2),d1
    bsr     blank_rows

    ; --- the pose
    move.w  last_pose,d2
    and.l   #$ffff,d2
    mulu    #MO_STRIDE,d2
    add.l   #MO_POSES,d2
    lea     big_data,a6
    lea     0(a6,d2.l),a5

    moveq   #0,d4
    move.b  (a5)+,d4            ; nverts
    moveq   #0,d3
    move.b  (a5)+,d3            ; nfaces
    beq     .out
    move.w  (a5)+,d0            ; y0, centre-relative and even
    move.w  (a5)+,d1            ; rows
    move.w  (a5)+,d5            ; pad
    add.w   #CY,d0
    move.w  d0,(a2)             ; what the NEXT pass through this screen
    move.w  d1,2(a2)            ; will have to blank

    move.l  a5,a4               ; a4 = vertex words
    lsl.w   #2,d4
    lea     0(a5,d4.w),a3       ; a3 = face data, walked by fill_poly

    subq.w  #1,d3
.face:
    bsr     fill_poly
    dbra    d3,.face

    ; --- show it
    eori.w  #1,back_side
    move.l  draw_base,d0
    bsr     set_screen_base
.out:
    movem.l (sp)+,d0-d7/a0-a6
    rts

;----------------------------------------------------------------------
; Blank d1 rows of the screen at a1 from row d0, across a fixed window of
; BLANK_W bytes at BLANK_X. Two movem.l and no inner loop.
;
; The window is fixed on purpose. The figure is centred and the generator
; guarantees every pose lives inside it, so there is no horizontal extent
; to compute and none to get wrong.
;----------------------------------------------------------------------
blank_rows:
    movem.l d0-d7/a0-a2,-(sp)
    tst.w   d1
    beq.s   .out
    and.l   #$ffff,d0
    mulu    #ROWB,d0
    move.l  a1,a2
    adda.l  d0,a2
    adda.w  #BLANK_X,a2
    and.l   #$ffff,d1
    mulu    #ROWB,d1
    move.l  a2,a0
    adda.l  d1,a0               ; one past the last row
    moveq   #0,d0
    moveq   #0,d1
    moveq   #0,d2
    moveq   #0,d3
    moveq   #0,d4
    moveq   #0,d5
    moveq   #0,d6
    moveq   #0,d7
.row:
    movem.l d0-d7,(a2)          ; 32 bytes
    movem.l d0-d3,32(a2)        ; and 16 more: BLANK_W
    lea     ROWB(a2),a2
    cmpa.l  a0,a2
    bne.s   .row
.out:
    movem.l (sp)+,d0-d7/a0-a2
    rts

;----------------------------------------------------------------------
; Fill one convex face, walking a left and a right chain of edges.
; a3 = face data: level.b, nA.b, nB.b, then nA and nB vertex indices.
; a4 = the pose's vertex array, x.w then y.w. a3 is left past this face.
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
    move.l  d3,a3               ; the caller goes on from here

    ; top and bottom row, from the ends of chain A
    move.l  chA,a0
    moveq   #0,d4
    move.b  (a0),d4
    lsl.w   #2,d4               ; four bytes a vertex now
    move.w  2(a4,d4.w),d5
    add.w   poly_cy,d5
    ifne YSTEP-1
    addq.w  #1,d5               ; every face on the same doubling grid, and
    and.w   #$fffe,d5           ; rounded UP: rounding down puts the first
    endif                       ; row ABOVE the top vertex, where the face
                                ; does not exist yet and the chains have to
                                ; extrapolate backwards -- which on a
                                ; near-horizontal edge lands hundreds of
                                ; pixels off the figure
    move.w  d5,t_y
    subq.w  #1,d5
    move.w  d5,chA+14           ; forces both chains to load an edge on
    move.w  d5,chB+14           ; the first row
    move.w  chA+12,d4
    subq.w  #1,d4
    adda.w  d4,a0
    moveq   #0,d4
    move.b  (a0),d4
    lsl.w   #2,d4
    move.w  2(a4,d4.w),d5
    add.w   poly_cy,d5
    move.w  d5,poly_ymax

    ; this level's four fills, doubled so they can go out as words
    move.w  tlevel,d4
    lsl.w   #2,d4
    lea     big_data,a1
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
    mulu    #ROWB,d4
    move.l  draw_base,a0
    add.l   d4,a0               ; a0 = row address, stepped from here
    movea.w #YSTEP*ROWB,a5      ; one row step, out of memory
    moveq   #0,d0
    moveq   #0,d1
    moveq   #0,d2
    moveq   #0,d3

    ; --- one segment: the rows until either chain reaches its next vertex.
    ; Inside a segment nothing can change, so the row loop runs with no
    ; compares at all.
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
    move.w  chA+14,d5
    cmp.w   chB+14,d5
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
    move.w  d5,segcnt

.row:
    ; --- span ends, ordered
    move.l  d0,d6
    swap    d6                  ; the integer part is just a swap
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
    sub.w   d4,d5               ; last byte - first byte

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

    ; Every store has a twin ROWB bytes down when YSTEP is 2. The value is
    ; already in a register, so the twin needs no registers and no second
    ; pass over the picture.
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
    beq.s   .right              ; first leaves the address odd, and a
    ifne YSTEP-1                ; move.w to an odd address is an error
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
;
; The slope is a full 16.16 worked out with two divu steps. SOLIDS
; pre-shifted by 7 and divided once, which costs up to dy/128 pixels of
; drift -- a pixel on a 140-row figure, three on a 350-row one.
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
    lsl.w   #2,d1
    moveq   #0,d2
    move.b  1(a0),d2
    lsl.w   #2,d2
    move.w  2(a4,d1.w),d3       ; y of this vertex
    move.w  2(a4,d2.w),d4       ; y of the next
    cmp.w   d3,d4
    bgt.s   .good
    addq.l  #1,0(a1)            ; flat edge: step over it
    subq.w  #1,12(a1)
    bra     .again
.good:
    move.w  0(a4,d1.w),d5
    add.w   poly_cx,d5
    move.w  0(a4,d2.w),d6
    add.w   poly_cx,d6
    move.w  d5,d7
    ext.l   d7
    swap    d7                  ; x starts exactly on the vertex, 16.16
    move.l  d7,4(a1)

    move.w  d6,d0
    sub.w   d5,d0               ; dx, signed
    move.w  d4,d1
    sub.w   d3,d1               ; dy, always positive here
    moveq   #0,d2
    tst.w   d0
    bge.s   .pos
    neg.w   d0
    moveq   #1,d2               ; remember the sign, divide unsigned
.pos:
    and.l   #$ffff,d0
    divu    d1,d0               ; low word = whole pixels a row
    moveq   #0,d7
    move.w  d0,d7
    swap    d7
    clr.w   d0                  ; high word is the remainder: << 16
    divu    d1,d0               ; and it is smaller than dy, so this fits
    move.w  d0,d7               ; d7 = the slope, 16.16, exactly
    tst.w   d2
    beq.s   .signed
    neg.l   d7
.signed:
    move.l  d7,8(a1)

    ; The row about to be drawn is usually NOT this vertex's row: YSTEP
    ; rounds the face top down to even and steps two rows at a time, so a
    ; chain is picked up one or two rows past its vertex. Starting x at the
    ; vertex is then wrong by that many slopes -- and on a near-horizontal
    ; edge a slope is hundreds of pixels, which threw the span clean off
    ; the figure and left pixels outside the blanking window.
    move.w  d3,d0
    add.w   poly_cy,d0          ; this vertex's screen row
    move.w  t_y,d1
    sub.w   d0,d1
    beq.s   .onrow
    bmi.s   .back
    move.l  4(a1),d0
.fwd:
    add.l   d7,d0
    subq.w  #1,d1
    bne.s   .fwd
    move.l  d0,4(a1)
    bra.s   .onrow
.back:
    move.l  4(a1),d0
.bk:
    sub.l   d7,d0
    addq.w  #1,d1
    bne.s   .bk
    move.l  d0,4(a1)
.onrow:
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

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
big_data:
    incbin  "src/big.bin"

;----------------------------------------------------------------------
    section bss
    even
chA:            ds.b 16         ; ptr.l, x.l, slope.l, left.w, yend.w
chB:            ds.b 16
draw_base:      ds.l 1
blank_y:        ds.w 4          ; per screen: first row, rows
shape:          ds.w 1
angle:          ds.w 1
mo_level:       ds.w 1
last_pose:      ds.w 1
back_side:      ds.w 1
tlevel:         ds.w 1
poly_cx:        ds.w 1
poly_cy:        ds.w 1
poly_ymax:      ds.w 1
t_y:            ds.w 1
segcnt:         ds.w 1
    even
pat4:           ds.w 4          ; a2 points here; the mask tables are at
lmaskt:         ds.b 8          ; +8 and +16 so one register reaches all three
rmaskt:         ds.b 8
    even
