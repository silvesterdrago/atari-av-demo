;======================================================================
;  SPARKS
;
;  Every pad owns a cell in a 4x2 grid. A hit throws a burst of sparks
;  out of that cell; they arc under gravity and die at the screen edge.
;  Velocity sets how many and how hard.
;
;  Single pixels, so the cost is per particle and not per screen: erase
;  the one pixel we lit last frame, integrate, light the new one. About
;  20 000 cycles for 160 particles, against a frame budget of 112 000.
;======================================================================
    include "src/core/head.s"

NPART       equ 160
PART_SIZE   equ 24
GRAVITY     equ 14              ; 8.8 fixed, added to dy each frame
LIFE_BASE   equ 40
SP_FREE_EVERY equ 26    ; frames between bursts when nothing plays

; particle record
P_X         equ 0               ; long, 24.8
P_Y         equ 4               ; long, 24.8
P_DX        equ 8               ; word, 8.8
P_DY        equ 10              ; word, 8.8
P_LIFE      equ 12              ; word, 0 = dead
P_ADDR      equ 16              ; long, where we lit a pixel last frame
P_MASK      equ 20              ; word, which bit; 0 = nothing lit

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
sp_init:
    lea     parts,a0
    move.w  #(NPART*PART_SIZE)/4-1,d0
.zap:
    clr.l   (a0)+
    dbra    d0,.zap

    move.w  row_bytes,d0
    lsl.w   #3,d0
    and.l   #$ffff,d0
    move.l  d0,scr_w            ; pixels across
    move.w  scr_rows,d0
    and.l   #$ffff,d0
    move.l  d0,scr_h
    clr.w   spawn_at
    rts

;----------------------------------------------------------------------
    ifnd SCENES
show_frame:
    endif
sp_frame:
    ; with nothing playing this scene has nothing to show, so throw a burst
    ; of its own now and then
    cmp.w   #150,idle_ticks
    bcs.s   .played
    addq.w  #1,sp_free
    cmp.w   #SP_FREE_EVERY,sp_free
    bcs.s   .played
    clr.w   sp_free
    bsr     next_rng            ; clobbers d3 and d4, hence nothing of ours
    move.w  d3,d1
    and.w   #7,d1
    add.w   d1,d1               ; pad*2, the way poll_midi passes it
    move.w  #220,d0
    bsr     sp_note_on
.played:

    move.l  cur_base,a1
    lea     parts,a5
    move.w  #NPART-1,d7
.each:
    ; --- unlight last frame's pixel
    move.w  P_MASK(a5),d0
    beq.s   .clean
    move.l  P_ADDR(a5),a0
    not.b   d0
    and.b   d0,(a0)
    clr.w   P_MASK(a5)
.clean:
    move.w  P_LIFE(a5),d0
    beq     .next
    subq.w  #1,d0
    move.w  d0,P_LIFE(a5)

    ; --- integrate, with gravity on the vertical
    move.w  P_DY(a5),d1
    add.w   #GRAVITY,d1
    move.w  d1,P_DY(a5)
    ext.l   d1
    add.l   d1,P_Y(a5)
    move.w  P_DX(a5),d1
    ext.l   d1
    add.l   d1,P_X(a5)

    ; --- fixed point down to pixels, dying at any edge
    move.l  P_X(a5),d1
    asr.l   #8,d1
    bmi     .kill
    cmp.l   scr_w,d1
    bcc     .kill
    move.l  P_Y(a5),d2
    asr.l   #8,d2
    bmi     .kill
    cmp.l   scr_h,d2
    bcc     .kill

    ; --- light it
    mulu    row_bytes,d2
    move.l  d1,d3
    lsr.l   #3,d3
    add.l   d3,d2
    move.l  a1,a0
    add.l   d2,a0
    and.w   #7,d1
    move.w  #$0080,d0
    lsr.w   d1,d0
    or.b    d0,(a0)
    move.l  a0,P_ADDR(a5)
    move.w  d0,P_MASK(a5)
    bra.s   .next
.kill:
    clr.w   P_LIFE(a5)
.next:
    lea     PART_SIZE(a5),a5
    dbra    d7,.each
    rts

;----------------------------------------------------------------------
; d0 = strength 0..255, d1 = pad index * 2
;----------------------------------------------------------------------
    ifnd SCENES
show_note_on:
    endif
sp_note_on:
    movem.l d0-d7/a0-a2,-(sp)
    move.w  d0,d6               ; strength
    lsr.w   #1,d1               ; pad 0..7

    ; cell centre: four across, two down
    move.w  row_bytes,d2
    lsl.w   #1,d2               ; cell width in pixels (160 in mono)
    move.w  d1,d3
    and.w   #3,d3
    mulu    d2,d3
    lsr.w   #1,d2
    add.w   d2,d3               ; centre x

    move.w  scr_rows,d4
    lsr.w   #1,d4               ; cell height
    move.w  d1,d5
    lsr.w   #2,d5
    mulu    d4,d5
    lsr.w   #1,d4
    add.w   d4,d5               ; centre y

    ; stash the centre: next_rng eats d3/d4, so we reload it per spark
    move.w  d3,spawn_cx
    move.w  d5,spawn_cy

    ; how many, and how fast
    move.w  d6,d0
    lsr.w   #4,d0
    add.w   #8,d0               ; 8..23 sparks
    lea     parts,a2

.spawn:
    ; take the next slot round-robin, so a burst does not all land in one
    ; corner of the array and starve later hits
    move.w  spawn_at,d1
    addq.w  #1,d1
    cmp.w   #NPART,d1
    bcs.s   .wrap
    moveq   #0,d1
.wrap:
    move.w  d1,spawn_at
    mulu    #PART_SIZE,d1
    lea     0(a2,d1.l),a0

    move.w  d3,d1
    and.l   #$ffff,d1
    lsl.l   #8,d1
    move.l  d1,P_X(a0)
    move.w  d5,d1
    and.l   #$ffff,d1
    lsl.l   #8,d1
    move.l  d1,P_Y(a0)

    bsr     next_rng            ; d3/d4 clobbered -- careful below
    move.l  d3,d1
    and.w   #$1ff,d1
    sub.w   #256,d1             ; -256..255
    muls    d6,d1
    asr.l   #6,d1
    move.w  d1,P_DX(a0)

    move.l  d3,d1
    lsr.l   #8,d1
    lsr.l   #1,d1               ; 68000 shifts by at most 8 per instruction
    and.w   #$1ff,d1
    sub.w   #400,d1             ; biased upward, so it looks thrown
    muls    d6,d1
    asr.l   #6,d1
    move.w  d1,P_DY(a0)

    move.w  d6,d1
    lsr.w   #3,d1
    add.w   #LIFE_BASE,d1
    move.w  d1,P_LIFE(a0)
    clr.w   P_MASK(a0)

    ; next_rng ate d3, so rebuild the cell centre for the next spark
    move.w  spawn_cx,d3
    move.w  spawn_cy,d5
    subq.w  #1,d0
    bne     .spawn

    movem.l (sp)+,d0-d7/a0-a2
    rts

    include "src/core/tail.s"

    section bss
    even
scr_w:          ds.l 1
scr_h:          ds.l 1
spawn_at:       ds.w 1
sp_free:        ds.w 1
spawn_cx:       ds.w 1
spawn_cy:       ds.w 1
    even
parts:          ds.b NPART*PART_SIZE
