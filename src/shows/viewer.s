;======================================================================
;  VIEWER -- pages through the screens in TEST.DAT.
;
;  Any key shows the next one, ESC quits. Nothing is drawn: each screen
;  is already an ST framebuffer, so showing one is a write to the base
;  register.
;
;  TEST.DAT must sit beside the binary. Screens, in order:
;    0 calibration   1 thickness
;    2/3 corridor     4/5 tunnel    6/7 spiral    8/9 concentric
;    10 corridor with its corner edges mitred onto the end wall
;  of each pair the first is rendered natively at 640x400 and the second
;  composed at 640x480 and squashed, which is the question being asked.
;======================================================================
POOL_SIZE   equ 1024
RANGE_PAGES equ 1
    include "src/core/head.s"

NSHOT       equ 11              ; must match tools/gentest.py
SHOTSZ      equ 32000

;----------------------------------------------------------------------
show_init:
    lea     shots,a1            ; the base register has no low byte, so the
    move.l  a1,d0               ; screens have to start on a 256 boundary
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,shot0
    clr.w   shot

    clr.w   -(sp)               ; Fopen, read only
    pea     vw_name
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi.s   .nofile
    move.w  d0,d2

    move.l  shot0,-(sp)         ; Fread into the aligned buffer
    move.l  #NSHOT*SHOTSZ,-(sp)
    move.w  d2,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,d1

    move.w  d2,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp

    cmp.l   #NSHOT*SHOTSZ,d1
    bne.s   .nofile
    move.w  #1,ready
    bsr     vw_show
.nofile:
    rts

;----------------------------------------------------------------------
show_frame:
    rts                         ; the picture is the screen; nothing to do

;----------------------------------------------------------------------
show_note_on:                   ; any key, and the pads, step through
    movem.l d0-d2/a0-a1,-(sp)
    tst.w   ready
    beq.s   .out
    move.w  shot,d0
    addq.w  #1,d0
    cmp.w   #NSHOT,d0
    bcs.s   .ok
    moveq   #0,d0
.ok:
    move.w  d0,shot
    bsr     vw_show
.out:
    movem.l (sp)+,d0-d2/a0-a1
    rts

;----------------------------------------------------------------------
vw_show:
    move.w  shot,d0
    and.l   #$ffff,d0
    mulu    #SHOTSZ,d0
    add.l   shot0,d0
    bsr     set_screen_base
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
vw_name:
    dc.b    "TEST.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
shots:          ds.b NSHOT*SHOTSZ+256
shot0:          ds.l 1
shot:           ds.w 1
ready:          ds.w 1
    even
