;======================================================================
;  PRIMS -- the arc's primitive acts in one binary, on the number keys.
;
;      1 ZERO (I)   2 LINE (II)   3 COLLAPSE (VII+VIII)   4 the point
;
;  Every one of them is keyframes on the same trapezoid engine, so the
;  set is not a set in the CORRSET sense at all: there is one table, each
;  act is a range of rows in it, and switching acts moves two words. No
;  file is read, nothing is copied, and the switch costs one frame --
;  against the two seconds a corridor scene takes off the card.
;
;  The act tables are the same files the standalone binaries read, so a
;  keyframe fixed in one place is fixed everywhere:
;
;      src/shows/acts1.inc   ZERO.TOS      and rows 0-5 here
;      src/shows/acts2.inc   LINE.TOS      and rows 6-13
;      src/shows/acts7.inc   COLLAPSE.TOS  and rows 14-22
;
;  Key 4 is their safety roll from the brief -- a point on black, held --
;  and it is two rows of its own rather than act I's point, so that
;  reaching for it never walks on into the next composition.
;
;  -DCYCLE=<frames> walks the acts on its own, for measuring without a
;  keyboard.
;======================================================================
SCENES      equ 1               ; the core sends 1-9 to scene_select
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens to flip between
    include "src/core/head.s"

NSLOT       equ 18              ; one slot count for every act, so the
NSTATE      equ 25              ; tables are interchangeable
HOLD        equ 70
MORPH       equ 130
NACT        equ 4

    include "src/shows/morph.inc"

    section text                ; the engine's include ends in bss

;----------------------------------------------------------------------
show_init:
    bsr     mo_init
    moveq   #0,d0
    bsr     scene_select
    rts

;----------------------------------------------------------------------
show_frame:
    ifd CYCLE
    addq.w  #1,cyc_ctr
    cmp.w   #CYCLE,cyc_ctr
    bcs.s   .noswap
    clr.w   cyc_ctr
    move.w  cur_act,d0
    addq.w  #1,d0
    cmp.w   #NACT,d0
    bcs.s   .wrapped
    moveq   #0,d0
.wrapped:
    bsr     scene_select
.noswap:
    endif
    bra     mo_frame

;----------------------------------------------------------------------
show_note_on:
    bra     mo_note_on

;----------------------------------------------------------------------
; d0 = act 0..NACT-1. Moves the engine's live range of states, and starts
; the act on its first composition. Nothing else happens: the next frame
; finds a shape that does not match what the buffer holds and redraws it
; the way any morph frame does.
;----------------------------------------------------------------------
scene_select:
    movem.l d0-d1/a0,-(sp)
    cmp.w   #NACT,d0
    bcc.s   .out
    move.w  d0,cur_act
    lsl.w   #2,d0
    lea     act_tbl,a0
    move.w  0(a0,d0.w),d1
    move.w  d1,st_lo
    move.w  d1,cstate
    move.w  2(a0,d0.w),st_hi
    clr.w   ph
    move.l  VBCLOCK,t0
.out:
    movem.l (sp)+,d0-d1/a0
    rts

;----------------------------------------------------------------------
    section data
    even
; first and last LIVE state of each act; the row after an act's last is
; its own first again, which is what closes its loop
act_tbl:
    dc.w      0,  4             ; I    black .. square
    dc.w      6, 12             ; II   thin cross .. verticals
    dc.w     14, 21             ; VII  compression .. black
    dc.w     23, 23             ; the point, held

    even
keys:
    include "src/shows/acts1.inc"
    include "src/shows/acts2.inc"
    include "src/shows/acts7.inc"
    ; the safety roll: a point on black, and the state it eases into is
    ; the same point, so it sits there for as long as it is needed
    dc.w    304,336,304,336,187,213
    rept 17
    dc.w    320,320,320,320,200,200
    endr
    dc.w    304,336,304,336,187,213
    rept 17
    dc.w    320,320,320,320,200,200
    endr

;----------------------------------------------------------------------
    section bss
    even
cur_act:        ds.w 1
    ifd CYCLE
cyc_ctr:        ds.w 1
    endif
    even
