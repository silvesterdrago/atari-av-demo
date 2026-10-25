;======================================================================
;  ZERO -- act I, the shapes flowing into one another.
;
;      black -> point -> line -> two lines -> square -> black
;
;  Every composition in the act is axis-aligned bars, so the morph is an
;  interpolation of four rectangles and nothing else. Four slots carry
;  the whole act: in `line` they are the two halves of the bar, so it
;  splits symmetrically into the two verticals, and the square's top and
;  bottom grow out of zero-width bars parked at the centre.
;
;  Nothing is cleared but the four rectangles the other buffer last held,
;  which is about 3800 bytes rather than the screen's 32000. Drawing
;  masks the two edge bytes, so a bar's edge lands on the pixel rather
;  than the byte -- without that the morph steps eight pixels at a time,
;  which is the one thing a slow morph cannot hide.
;
;  A hit cuts the hold short and starts the next morph at once.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 4
NSTATE      equ 6               ; the last is the first again, so it loops
HOLD        equ 90              ; frames a composition sits still
MORPH       equ 150             ; frames it takes to become the next one

;----------------------------------------------------------------------
show_init:
    move.l  buf_base,d0
    move.l  d0,screen0
    add.l   #SCR_SIZE,d0
    move.l  d0,screen1
    move.l  screen1,back

    move.l  screen0,a0          ; both start black; nothing clears them again
    move.l  a0,a1
    add.l   #SCR_SIZE,a1
    bsr     clear_span
    move.l  screen1,a0
    move.l  a0,a1
    add.l   #SCR_SIZE,a1
    bsr     clear_span

    lea     prev,a0             ; neither buffer holds anything yet
    moveq   #(2*NSLOT*4)-1,d0
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    clr.w   cstate
    clr.w   ph
    move.l  screen0,d0
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
show_frame:
    addq.w  #1,ph               ; the clock: hold, then morph, then the next
    cmp.w   #HOLD+MORPH,ph
    bcs.s   .clock
    clr.w   ph
    move.w  cstate,d0
    addq.w  #1,d0
    cmp.w   #NSTATE-1,d0
    bcs.s   .stok
    moveq   #0,d0
.stok:
    move.w  d0,cstate
.clock:
    move.w  ph,d0               ; t, 0..256 across the morph
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
.ease:                          ; ease in and out, so nothing starts or
    cmp.w   #128,d0             ; stops with a jerk
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
    move.w  d0,d6               ; d6 = eased t

    ; --- this frame's four rectangles, between the two keyframes
    move.w  cstate,d0
    mulu    #NSLOT*4*2,d0
    lea     keys,a1
    add.l   d0,a1               ; this state
    lea     (NSLOT*4*2)(a1),a4  ; the next one
    lea     cur,a2
    moveq   #NSLOT-1,d7
.slot:
    moveq   #3,d5
.coord:
    move.w  (a4)+,d0            ; b
    sub.w   (a1),d0             ; b - a
    muls    d6,d0
    asr.l   #8,d0
    add.w   (a1)+,d0            ; a + (b-a)*t
    move.w  d0,(a2)+
    dbra    d5,.coord
    dbra    d7,.slot

    ; --- nothing to do at all if this buffer already holds this shape,
    ; which is every frame of a hold after the first two
    move.w  which,d0
    lsl.w   #(1+2+2),d0
    lea     prev,a4
    add.w   d0,a4
    lea     cur,a2
    moveq   #(NSLOT*4)-1,d5
.same:
    move.w  (a2)+,d0
    cmp.w   (a4)+,d0
    bne.s   .changed
    dbra    d5,.same
    rts
.changed:

    ; --- wipe only what this frame will not cover anyway. Every morph but
    ; the last is a shape growing, and there the wipe is pure waste: it is
    ; what used to put this scene over the frame.
    move.w  which,d0
    lsl.w   #(1+2+2),d0         ; NSLOT*4 words a buffer
    lea     prev,a4
    add.w   d0,a4               ; what the back buffer still holds
    lea     cur,a2
    move.l  back,a3
    moveq   #NSLOT-1,d7
.wipe:
    move.w  (a2),d0
    cmp.w   (a4),d0
    bhi.s   .mustwipe
    move.w  2(a2),d0
    cmp.w   2(a4),d0
    bhi.s   .mustwipe
    move.w  4(a2),d0
    cmp.w   4(a4),d0
    bcs.s   .mustwipe
    move.w  6(a2),d0
    cmp.w   6(a4),d0
    bcc.s   .kept
.mustwipe:
    move.l  a3,a0
    move.w  (a4),d0
    move.w  2(a4),d1
    move.w  4(a4),d2
    move.w  6(a4),d3
    bsr     clear_box
.kept:
    lea     8(a4),a4
    lea     8(a2),a2
    dbra    d7,.wipe

    ; --- draw, and leave the four behind for the other buffer to wipe
    move.w  which,d0
    lsl.w   #(1+2+2),d0
    lea     prev,a4
    add.w   d0,a4
    lea     cur,a2
    moveq   #NSLOT-1,d7
.draw:
    move.l  back,a0
    move.w  (a2)+,d0
    move.w  (a2)+,d1
    move.w  (a2)+,d2
    move.w  (a2)+,d3
    move.w  d0,(a4)+
    move.w  d1,(a4)+
    move.w  d2,(a4)+
    move.w  d3,(a4)+
    bsr     draw_box
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
show_note_on:                   ; d0 = strength, d1 = pad*2
    cmp.w   #HOLD,ph            ; a hit ends the hold and starts the morph
    bcc.s   .out
    move.w  #HOLD,ph
.out:
    rts

;----------------------------------------------------------------------
; Both routines take a0 = screen, d0/d1 = x0/y0, d2/d3 = x1/y1 exclusive.
;
; row_bytes is even, so the parity of a row's start is the same all the
; way down a rectangle: the odd-byte fixup that keeps move.l off an odd
; address is therefore worked out ONCE per rectangle. Calling a fill
; routine per row instead cost four times the writes themselves on a bar
; four bytes wide.
;----------------------------------------------------------------------
; Whole bytes, no masks: the wipe may take a few pixels either side,
; which costs nothing because every rectangle is drawn again after it.
;----------------------------------------------------------------------
clear_box:
    cmp.w   d0,d2
    bls     .ret
    cmp.w   d1,d3
    bls     .ret
    movem.l d0-d7/a0-a2,-(sp)
    lsr.w   #3,d0               ; first byte
    addq.w  #7,d2
    lsr.w   #3,d2
    sub.w   d0,d2               ; width in bytes
    sub.w   d1,d3
    subq.w  #1,d3               ; rows, less one
    mulu    row_bytes,d1
    add.l   d1,a0
    add.w   d0,a0
    moveq   #0,d5
    moveq   #0,d6               ; a lead byte, or none
    btst    #0,d0
    beq.s   .al
    moveq   #1,d6
    subq.w  #1,d2
.al:
    move.w  d2,d1
    lsr.w   #2,d1               ; longs a row
    and.w   #3,d2               ; and the tail
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
; The two edge bytes are masked, so an edge lands on the pixel it was
; asked for. Without that a morph steps eight pixels at a time, which is
; the one thing a slow morph cannot hide.
;----------------------------------------------------------------------
draw_box:
    cmp.w   d0,d2
    bls     .ret
    cmp.w   d1,d3
    bls     .ret
    movem.l d0-d7/a0-a2,-(sp)
    subq.w  #1,d2               ; last pixel, inclusive
    move.w  d0,d4
    lsr.w   #3,d4               ; first byte
    move.w  d2,d5
    lsr.w   #3,d5               ; last byte
    moveq   #-1,d6
    and.w   #7,d0
    lsr.b   d0,d6               ; left mask
    moveq   #-1,d7
    and.w   #7,d2
    eor.w   #7,d2
    lsl.b   d2,d7               ; right mask
    sub.w   d1,d3
    subq.w  #1,d3               ; rows, less one
    mulu    row_bytes,d1
    add.l   d1,a0
    add.w   d4,a0
    move.w  d5,d2
    sub.w   d4,d2               ; bytes spanned, less one
    bne.s   .wide
    and.b   d7,d6               ; one byte wide: both masks at once
.nrow:
    or.b    d6,(a0)
    adda.w  row_bytes,a0
    dbra    d3,.nrow
    bra     .done
.wide:
    subq.w  #1,d2               ; bytes between the two edges
    moveq   #0,d0               ; a lead byte, or none
    tst.w   d2
    beq.s   .nomid
    move.w  d4,d1
    addq.w  #1,d1               ; the middle starts after the left edge
    btst    #0,d1
    beq.s   .mideven
    moveq   #1,d0
    subq.w  #1,d2
.mideven:
    move.w  d2,d1
    lsr.w   #2,d1               ; longs a row
    and.w   #3,d2               ; and the tail
    bra.s   .solid
.nomid:
    moveq   #0,d1
.solid:
    moveq   #-1,d5
.wrow:
    move.l  a0,a2
    or.b    d6,(a2)+
    tst.w   d0
    beq.s   .wlongs
    move.b  d5,(a2)+
.wlongs:
    move.w  d1,d4
    beq.s   .wtail
    subq.w  #1,d4
.wlp:
    move.l  d5,(a2)+
    dbra    d4,.wlp
.wtail:
    move.w  d2,d4
    beq.s   .wedge
.wtl:
    move.b  d5,(a2)+
    subq.w  #1,d4
    bne.s   .wtl
.wedge:
    or.b    d7,(a2)
    adda.w  row_bytes,a0
    dbra    d3,.wrow
.done:
    movem.l (sp)+,d0-d7/a0-a2
.ret:
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
; x0, y0, x1, y1 per slot, four slots a state. Slots 0 and 1 are the two
; halves of the bar, so `line` splits into the two verticals without
; either side jumping; 2 and 3 are the square's top and bottom, parked
; with no width until there is one.
keys:
    dc.w    320,200,320,200,  320,200,320,200,  320,200,320,200,  320,200,320,200
    dc.w    304,187,336,213,  304,187,336,213,  320,200,320,200,  320,200,320,200
    dc.w    192,192,320,208,  320,192,448,208,  320,200,320,200,  320,200,320,200
    dc.w    240, 96,272,304,  368, 96,400,304,  320, 80,320,106,  320,294,320,320
    dc.w    176, 80,208,320,  432, 80,464,320,  176, 80,464,106,  176,294,464,320
    dc.w    320,200,320,200,  320,200,320,200,  320,200,320,200,  320,200,320,200

;----------------------------------------------------------------------
    section bss
    even
screen0:        ds.l 1
screen1:        ds.l 1
back:           ds.l 1
prev:           ds.w 2*NSLOT*4
cur:            ds.w NSLOT*4
cstate:         ds.w 1
ph:             ds.w 1
which:          ds.w 1
    even
