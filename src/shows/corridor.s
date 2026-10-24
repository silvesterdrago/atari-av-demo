;======================================================================
;  CORRIDOR -- the mitred corridor, flying.
;
;  The same geometry the test screens settled, now moving: panels and
;  floor bars travel one panel period over 24 baked frames, so the set
;  maps onto itself and loops seamlessly whatever speed it is played at.
;  Drawing it live is out of the question -- a single frame is some 50
;  filled quads over most of the screen -- so the machine does nothing
;  but write the screen base register, as in HYPER.
;
;  24 frames is 750 KB, which a 1 MB machine holds exactly once: this
;  scene therefore gets its own binary and cannot join a set.
;
;  CORRIDOR.DAT must sit beside the binary. The base register has no low
;  byte, so the frames are read into a buffer rounded up to a 256-byte
;  boundary -- where TOS loads a program is not ours to choose.
;======================================================================
POOL_SIZE   equ 1024            ; no noise, no scrolling window
RANGE_PAGES equ 1
    include "src/core/head.s"

NFRAMES     equ 24              ; must match tools/gencorr.py
FRAMESZ     equ 32000
CR_WRAP     equ NFRAMES*256     ; phase is 8.8 frames, so it wraps exactly
CR_CRUISE   equ 128             ; one frame every two VBLs: 0.67s a period
CR_KICK     equ 4               ; times velocity
CR_MAX      equ 1024            ; four frames a VBL, and no faster
CR_SLOW     equ 16              ; a kick is back at cruise in half a second

;----------------------------------------------------------------------
show_init:
    lea     frames,a1           ; round the buffer up to a 256 boundary
    move.l  a1,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    clr.w   cphase
    move.w  #CR_CRUISE,cspeed

    clr.w   -(sp)               ; Fopen, read only
    pea     cr_name
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi.s   .nofile
    move.w  d0,d2               ; the handle

    move.l  frame0,-(sp)        ; Fread, straight into the aligned buffer
    move.l  #NFRAMES*FRAMESZ,-(sp)
    move.w  d2,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,d1

    move.w  d2,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp

    cmp.l   #NFRAMES*FRAMESZ,d1
    bne.s   .nofile             ; a short read is not our file
    move.w  #1,cr_ready
    move.l  frame0,d0           ; show the first one immediately
    bsr     set_screen_base
.nofile:                        ; no file leaves the scene blank, but quiet
    rts

;----------------------------------------------------------------------
show_frame:
    move.w  cspeed,d0           ; a kick decays back to the cruise
    cmp.w   #CR_CRUISE+CR_SLOW,d0
    bcs.s   .sk
    sub.w   #CR_SLOW,d0
    bra.s   .sp
.sk:
    move.w  #CR_CRUISE,d0
.sp:
    move.w  d0,cspeed

    add.w   cphase,d0           ; wrap on the loop itself, not on 65536:
.wrap:                          ; a phase that wraps anywhere else skips
    cmp.w   #CR_WRAP,d0
    bcs.s   .ok
    sub.w   #CR_WRAP,d0
    bra.s   .wrap
.ok:
    move.w  d0,cphase

    tst.w   cr_ready            ; no frames, nothing to show
    beq.s   .out
    lsr.w   #8,d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    bsr     set_screen_base
.out:
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d2,-(sp)
    move.w  d0,d2
    mulu    #CR_KICK,d2
    add.w   #CR_CRUISE,d2
    cmp.w   #CR_MAX,d2
    bcs.s   .ok
    move.w  #CR_MAX,d2
.ok:
    move.w  d2,cspeed
    movem.l (sp)+,d0-d2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
cr_name:
    dc.b    "CORRIDOR.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
frames:         ds.b NFRAMES*FRAMESZ+256
frame0:         ds.l 1
cphase:         ds.w 1
cspeed:         ds.w 1
cr_ready:       ds.w 1
    even
