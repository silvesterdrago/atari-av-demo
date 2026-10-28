;======================================================================
;  LINE -- act II, the line opening out.
;
;      thin cross -> bold cross -> wedges -> bold X -> horizontals ->
;      nothing -> verticals -> back
;
;  The beat of nothing between the two stripe fields is deliberate. Each
;  stripe standing up where it stands crosses the others on the way, and
;  eight of them crossing came out as a staircase; collapsing them to the
;  centre and growing the next field out of it says the same thing in the
;  act's own grammar.
;
;  Act I only needed rectangles. This act needs the cross to fall open
;  into an X, so the primitive is a TRAPEZOID: each slot is two points at
;  the top and two at the bottom, and the span walks between them a row
;  at a time. Bars, wedges and thick diagonals are then all one routine,
;  and a morph can turn any of them into any other.
;
;  Eight slots. Two carry the figure through every state -- the cross's
;  two bars become the left pair of wedges, then the two diagonals, then
;  the first two stripes -- and the other six grow out of a degenerate
;  span at the centre when a state has more parts than the one before.
;
;  A hit cuts the hold short and starts the next morph.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 8
NWORD       equ 6               ; x0top, x1top, x0bot, x1bot, y0, y1
STATESZ     equ NSLOT*NWORD*2
NSTATE      equ 8               ; the last is the first again, so it loops
HOLD        equ 70
MORPH        equ 130

;----------------------------------------------------------------------
show_init:
    move.l  buf_base,d0
    move.l  d0,screen0
    add.l   #SCR_SIZE,d0
    move.l  d0,screen1
    move.l  screen1,back

    move.l  screen0,a0
    move.l  a0,a1
    add.l   #SCR_SIZE,a1
    bsr     clear_span
    move.l  screen1,a0
    move.l  a0,a1
    add.l   #SCR_SIZE,a1
    bsr     clear_span

    lea     prev,a0
    move.w  #(2*NSLOT*NWORD)-1,d0
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    clr.w   cstate
    clr.w   ph
    move.l  VBCLOCK,t0
    clr.w   which
    move.l  screen0,d0
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
show_frame:
    ; The clock is frames elapsed, not passes taken. A state that cannot
    ; repaint in one frame then drops frames instead of stretching its
    ; morph out: at eight frames a pass the verticals would otherwise take
    ; fifteen seconds to arrive instead of two.
    move.l  VBCLOCK,d0
    sub.l   t0,d0
.roll:
    cmp.l   #HOLD+MORPH,d0
    bcs.s   .clock
    sub.l   #HOLD+MORPH,d0
    add.l   #HOLD+MORPH,t0
    move.w  cstate,d1
    addq.w  #1,d1
    cmp.w   #NSTATE-1,d1
    bcs.s   .stok
    moveq   #0,d1
.stok:
    move.w  d1,cstate
    bra.s   .roll
.clock:
    move.w  d0,ph
    move.w  ph,d0
    sub.w   #HOLD,d0
    bpl.s   .morphing
    moveq   #0,d0
    bra.s   .eased
.morphing:
    mulu    #256,d0
    divu    #MORPH,d0
    and.l   #$ffff,d0
    cmp.w   #256,d0
    bcs.s   .ease
    move.w  #256,d0
.ease:
    cmp.w   #128,d0
    bcc.s   .late
    move.w  d0,d1
    mulu    d1,d0
    lsr.l   #7,d0
    bra.s   .eased
.late:
    move.w  #256,d1
    sub.w   d0,d1
    move.w  d1,d0
    mulu    d1,d0
    lsr.l   #7,d0
    neg.w   d0
    add.w   #256,d0
.eased:
    move.w  d0,d6

    ; --- this frame's eight spans, between the two keyframes
    move.w  cstate,d0
    mulu    #STATESZ,d0
    lea     keys,a1
    add.l   d0,a1
    lea     STATESZ(a1),a4
    lea     cur,a2
    move.w  #(NSLOT*NWORD)-1,d7
.coord:
    move.w  (a4)+,d0
    sub.w   (a1),d0
    muls    d6,d0
    asr.l   #8,d0
    add.w   (a1)+,d0
    move.w  d0,(a2)+
    dbra    d7,.coord

    ; --- nothing to do if this buffer already holds this shape
    move.w  which,d0
    mulu    #NSLOT*NWORD*2,d0
    lea     prev,a4
    add.l   d0,a4
    lea     cur,a2
    move.w  #(NSLOT*NWORD)-1,d5
.same:
    move.w  (a2)+,d0
    cmp.w   (a4)+,d0
    bne.s   .changed
    dbra    d5,.same
    rts
.changed:

    ; --- wipe only what this frame will not cover anyway
    move.w  which,d0
    mulu    #NSLOT*NWORD*2,d0
    lea     prev,a4
    add.l   d0,a4
    lea     cur,a2
    moveq   #NSLOT-1,d7
.wipe:
    bsr     span_bbox           ; what this frame will cover
    lea     nbb,a3
    move.w  d0,(a3)+
    move.w  d1,(a3)+
    move.w  d2,(a3)+
    move.w  d3,(a3)+
    move.l  a2,-(sp)
    move.l  a4,a2
    bsr     span_bbox           ; and what the buffer still holds, in d0-d3
    move.l  (sp)+,a2
    move.w  nbb,d4
    cmp.w   d0,d4
    bhi.s   .mustwipe
    move.w  nbb+2,d4
    cmp.w   d1,d4
    bhi.s   .mustwipe
    move.w  nbb+4,d4
    cmp.w   d2,d4
    bcs.s   .mustwipe
    move.w  nbb+6,d4
    cmp.w   d3,d4
    bcc.s   .kept
.mustwipe:
    move.l  back,a0
    bsr     clear_box
.kept:
    lea     NWORD*2(a2),a2
    lea     NWORD*2(a4),a4
    dbra    d7,.wipe

    ; --- draw, and leave the spans behind for the other buffer to wipe
    move.w  which,d0
    mulu    #NSLOT*NWORD*2,d0
    lea     prev,a4
    add.l   d0,a4
    lea     cur,a2
    moveq   #NSLOT-1,d7
.draw:
    move.l  back,a0
    move.l  a2,a1
    bsr     draw_span
    moveq   #NWORD-1,d0
.keep:
    move.w  (a2)+,(a4)+
    dbra    d0,.keep
    dbra    d7,.draw

    ; --- show it, and build the next one in the other buffer
    move.l  back,d0
    move.l  screen0,d1
    cmp.l   d0,d1
    bne.s   .other
    move.l  screen1,d1
.other:
    move.l  d1,back
    eor.w   #1,which
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
show_note_on:                   ; a hit ends the hold early
    cmp.w   #HOLD,ph
    bcc.s   .out
    move.l  VBCLOCK,d0
    sub.l   #HOLD,d0
    move.l  d0,t0
.out:
    rts

;----------------------------------------------------------------------
; a2 -> span. d0..d3 = the box it lies inside, x0 y0 x1 y1.
;----------------------------------------------------------------------
span_bbox:
    move.w  (a2),d0             ; x0 top
    move.w  4(a2),d1            ; x0 bottom
    cmp.w   d1,d0
    bls.s   .l
    move.w  d1,d0
.l:
    move.w  2(a2),d2            ; x1 top
    move.w  6(a2),d1            ; x1 bottom
    cmp.w   d1,d2
    bcc.s   .r
    move.w  d1,d2
.r:
    move.w  8(a2),d1            ; y0
    move.w  10(a2),d3           ; y1
    rts

;----------------------------------------------------------------------
; a0 = screen, d0/d1 = x0/y0, d2/d3 = x1/y1 exclusive. Whole bytes: the
; wipe may take a few pixels either side, which costs nothing because
; everything is drawn again after it.
;----------------------------------------------------------------------
clear_box:
    cmp.w   d0,d2
    bls     .ret
    cmp.w   d1,d3
    bls     .ret
    movem.l d0-d7/a0-a2,-(sp)
    lsr.w   #3,d0
    addq.w  #7,d2
    lsr.w   #3,d2
    sub.w   d0,d2
    sub.w   d1,d3
    subq.w  #1,d3
    mulu    row_bytes,d1
    add.l   d1,a0
    add.w   d0,a0
    moveq   #0,d5
    moveq   #0,d6
    btst    #0,d0
    beq.s   .al
    moveq   #1,d6
    subq.w  #1,d2
.al:
    move.w  d2,d1
    lsr.w   #2,d1
    and.w   #3,d2
.row:
    move.l  a0,a2
    tst.w   d6
    beq.s   .longs
    move.b  d5,(a2)+
.longs:
    move.w  d1,d4
    beq.s   .tail
    subq.w  #1,d4
.lp:
    move.l  d5,(a2)+
    dbra    d4,.lp
.tail:
    move.w  d2,d4
    beq.s   .next
.tl:
    move.b  d5,(a2)+
    subq.w  #1,d4
    bne.s   .tl
.next:
    adda.w  row_bytes,a0
    dbra    d3,.row
    movem.l (sp)+,d0-d7/a0-a2
.ret:
    rts

;----------------------------------------------------------------------
; a0 = screen, a1 -> x0top, x1top, x0bot, x1bot, y0, y1.
;
; The two edges walk down the rows in 8.8, so one routine draws a bar, a
; wedge and a thick diagonal alike. Both edge bytes are masked, so an
; edge lands on the pixel it was asked for -- and here they have to be
; recomputed every row, because the span moves.
;----------------------------------------------------------------------
draw_span:
    movem.l d0-d7/a0-a2,-(sp)
    move.w  8(a1),d4            ; y0
    move.w  10(a1),d5
    sub.w   d4,d5               ; rows
    ble     .done
    move.w  (a1),d0
    ext.l   d0
    lsl.l   #8,d0               ; left edge, 8.8
    move.w  2(a1),d1
    ext.l   d1
    lsl.l   #8,d1               ; right edge
    moveq   #0,d2
    moveq   #0,d3
    cmp.w   #16,d5              ; too few rows and the divide overflows;
    bcs.s   .flat               ; such a span is a bar in all but name
    move.w  4(a1),d2
    sub.w   (a1),d2
    ext.l   d2
    lsl.l   #8,d2
    divs    d5,d2
    ext.l   d2                  ; drop the remainder divs leaves up there
    move.w  6(a1),d3
    sub.w   2(a1),d3
    ext.l   d3
    lsl.l   #8,d3
    divs    d5,d3
    ext.l   d3
.flat:
    move.l  d2,slope0
    move.l  d3,slope1
    move.w  d4,d6
    mulu    row_bytes,d6
    add.l   d6,a0
    subq.w  #1,d5
    tst.l   d2                  ; edges that do not move: every row is the
    bne     .row                ; same, so the masks are worked out once
    tst.l   d3
    bne     .row
    move.l  d0,d6
    asr.l   #8,d6
    move.l  d1,d7
    asr.l   #8,d7
    bsr     span_clip
    ble     .done
    move.w  d6,d2
    lsr.w   #3,d2
    adda.w  d2,a0
    moveq   #-1,d3
    move.w  d6,d4
    and.w   #7,d4
    lsr.b   d4,d3               ; left mask
    move.w  d7,d4
    subq.w  #1,d4
    move.w  d4,d6
    lsr.w   #3,d6
    sub.w   d2,d6               ; bytes spanned, less one
    and.w   #7,d4
    eor.w   #7,d4
    moveq   #-1,d2
    lsl.b   d4,d2               ; right mask
    tst.w   d6
    bne.s   .barwide
    and.b   d2,d3
.barnarrow:
    or.b    d3,(a0)
    adda.w  row_bytes,a0
    dbra    d5,.barnarrow
    bra     .done
.barwide:
    subq.w  #1,d6               ; bytes between the two edges
    moveq   #0,d4               ; a lead byte, or none
    tst.w   d6
    beq.s   .barcnt
    move.l  a0,d0
    addq.l  #1,d0
    btst    #0,d0
    beq.s   .barcnt
    moveq   #1,d4
    subq.w  #1,d6
.barcnt:
    move.w  d6,d0
    lsr.w   #2,d0               ; longs
    and.w   #3,d6               ; and the tail
    moveq   #-1,d1
.barrow:
    move.l  a0,a2
    or.b    d3,(a2)+
    tst.w   d4
    beq.s   .barl
    move.b  d1,(a2)+
.barl:
    move.w  d0,d7
    beq.s   .bart
    subq.w  #1,d7
.barlp:
    move.l  d1,(a2)+
    dbra    d7,.barlp
.bart:
    move.w  d6,d7
    beq.s   .baredge
.bartb:
    move.b  d1,(a2)+
    subq.w  #1,d7
    bne.s   .bartb
.baredge:
    or.b    d2,(a2)
    adda.w  row_bytes,a0
    dbra    d5,.barrow
    bra     .done
.row:
    move.l  d0,d6
    asr.l   #8,d6               ; x0 in pixels
    move.l  d1,d7
    asr.l   #8,d7               ; x1, exclusive
    cmp.w   d6,d7
    ble     .next
    bsr     span_clip
    ble     .next
    move.w  d6,d2
    lsr.w   #3,d2               ; first byte
    move.l  a0,a2
    adda.w  d2,a2
    moveq   #-1,d3
    move.w  d6,d4
    and.w   #7,d4
    lsr.b   d4,d3               ; left mask
    move.w  d7,d4
    subq.w  #1,d4               ; last pixel
    move.w  d4,d6
    lsr.w   #3,d6
    sub.w   d2,d6               ; bytes spanned, less one
    and.w   #7,d4
    eor.w   #7,d4
    moveq   #-1,d2
    lsl.b   d4,d2               ; right mask
    tst.w   d6
    bne.s   .wide
    and.b   d2,d3
    or.b    d3,(a2)
    bra     .next
.wide:
    or.b    d3,(a2)+
    subq.w  #1,d6               ; bytes between the two edges
    beq     .edge
    moveq   #-1,d3
    move.l  a2,d4
    btst    #0,d4
    beq.s   .even
    move.b  d3,(a2)+
    subq.w  #1,d6
    beq.s   .edge
.even:
    move.w  d6,d4
    lsr.w   #2,d4
    beq.s   .tail
    subq.w  #1,d4
.lp:
    move.l  d3,(a2)+
    dbra    d4,.lp
.tail:
    and.w   #3,d6
    beq.s   .edge
.tb:
    move.b  d3,(a2)+
    subq.w  #1,d6
    bne.s   .tb
.edge:
    or.b    d2,(a2)
.next:
    add.l   slope0,d0
    add.l   slope1,d1
    adda.w  row_bytes,a0
    dbra    d5,.row
.done:
    movem.l (sp)+,d0-d7/a0-a2
    rts

;----------------------------------------------------------------------
; d6/d7 = x0/x1, clipped to the screen. Z and N set on x1-x0, so the
; caller can drop a span that has nothing left.
;----------------------------------------------------------------------
span_clip:
    tst.w   d6
    bpl.s   .l
    moveq   #0,d6
.l:
    cmp.w   #640,d7
    bls.s   .r
    move.w  #640,d7
.r:
    move.w  d7,d4
    sub.w   d6,d4
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
; x0top, x1top, x0bot, x1bot, y0, y1 -- eight slots a state.
;
; The assignment is the whole art of it. The cross's horizontal bar is cut
; into four QUARTERS, left-upper to right-lower, so each one has a wedge of
; its own side to become and then an arm of the X on that same side: the
; figure opens out symmetrically instead of one bar crawling across the
; screen. Slots 4 and 5 are the vertical bar's two halves, which collapse
; into the centre for the wedges and the X. 6 and 7 only appear once there
; are eight stripes to fill.
DEGX    equ 320
DEGY    equ 200
keys:
    ; thin cross: the bar in four quarters, so each goes to its own wedge
    dc.w    120,320,120,320,194,200
    dc.w    120,320,120,320,200,206
    dc.w    320,520,320,520,194,200
    dc.w    320,520,320,520,200,206
    dc.w    314,326,314,326, 60,200
    dc.w    314,326,314,326,200,340
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    ; bold cross
    dc.w      0,320,  0,320,172,200
    dc.w      0,320,  0,320,200,228
    dc.w    320,640,320,640,172,200
    dc.w    320,640,320,640,200,228
    dc.w    292,348,292,348,  0,200
    dc.w    292,348,292,348,200,400
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    ; wedges: four triangles meeting at a point. The halves TILE -- the
    ; upper one ends on row 200 with its edge exactly at the centre and
    ; the lower one starts there, so the waist closes on that one row and
    ; opens again symmetrically, 5 px either side of it and 43 px eight
    ; rows out. Ending the upper half a row earlier leaves one row where
    ; neither reaches, which is the lens-shaped hole a patch over the
    ; junction used to cover -- and the patch then stuck out past the
    ; triangles as a pair of shoulders.
    dc.w      0,  0,  0,323, 80,201
    dc.w      0,320,  0,  0,200,320
    dc.w    640,640,317,640, 80,201
    dc.w    320,640,640,640,200,320
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    ; bold X: every wedge narrows into the arm on its own side
    dc.w      0, 70,285,355,  0,200
    dc.w    285,355,  0, 70,200,400
    dc.w    570,640,285,355,  0,200
    dc.w    285,355,570,640,200,400
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    ; horizontals
    dc.w      0,640,  0,640, 16, 38
    dc.w      0,640,  0,640, 64, 86
    dc.w      0,640,  0,640,112,134
    dc.w      0,640,  0,640,160,182
    dc.w      0,640,  0,640,208,230
    dc.w      0,640,  0,640,256,278
    dc.w      0,640,  0,640,304,326
    dc.w      0,640,  0,640,352,374
    ; through the centre: the horizontals collapse to nothing and the
    ; verticals grow back out of it, rather than each stripe standing up
    ; where it is and the eight of them crossing into a staircase
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200
    ; verticals
    dc.w     24, 60, 24, 60,  0,400
    dc.w    100,136,100,136,  0,400
    dc.w    176,212,176,212,  0,400
    dc.w    252,288,252,288,  0,400
    dc.w    328,364,328,364,  0,400
    dc.w    404,440,404,440,  0,400
    dc.w    480,516,480,516,  0,400
    dc.w    556,592,556,592,  0,400
    ; and round to the thin cross again
    dc.w    120,320,120,320,194,200
    dc.w    120,320,120,320,200,206
    dc.w    320,520,320,520,194,200
    dc.w    320,520,320,520,200,206
    dc.w    314,326,314,326, 60,200
    dc.w    314,326,314,326,200,340
    dc.w    320,320,320,320,200,200
    dc.w    320,320,320,320,200,200

;----------------------------------------------------------------------
    section bss
    even
screen0:        ds.l 1
screen1:        ds.l 1
back:           ds.l 1
slope0:         ds.l 1
slope1:         ds.l 1
prev:           ds.w 2*NSLOT*NWORD
cur:            ds.w NSLOT*NWORD
nbb:            ds.w 4
cstate:         ds.w 1
ph:             ds.w 1
t0:             ds.l 1
which:          ds.w 1
    even
