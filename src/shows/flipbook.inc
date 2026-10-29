;======================================================================
;  FLIPBOOK -- play a baked loop of whole screens off the card.
;
;  The scene is 24 screens that loop seamlessly, so the machine does
;  nothing per frame but write the screen base register. A scene that
;  includes this supplies only `fb_name`, the name of its .DAT, which
;  must sit beside the binary.
;
;  The base register has no low byte, so a screen must start on a
;  256-byte boundary and where TOS loads a program is not ours to
;  choose: the frames are read at start-up into a buffer rounded up to
;  one. 24 x 32000 is 750 KB, which a 1 MB machine holds exactly once,
;  so a flipbook scene cannot share a binary with another.
;
;  A scene defining FB_STAMP supplies fb_stamp, called once after the read:
;  two scenes that differ by a fixed mark then share one .DAT instead of
;  shipping 750 KB twice over.
;======================================================================
POOL_SIZE   equ 1024            ; no noise, no scrolling window
RANGE_PAGES equ 1
    include "src/core/head.s"

NFRAMES     equ 24              ; must match tools/genflip.py
FRAMESZ     equ 32000
FB_WRAP     equ NFRAMES*256     ; phase is 8.8 frames, so it wraps exactly
FB_CRUISE   equ 128             ; one frame every two VBLs: 0.67s a turn
FB_KICK     equ 4               ; times velocity
FB_MAX      equ 1024            ; four frames a VBL, and no faster
FB_SLOW     equ 16              ; a kick is back at cruise in half a second

;----------------------------------------------------------------------
show_init:
    lea     frames,a1           ; round the buffer up to a 256 boundary
    move.l  a1,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    clr.w   fphase
    move.w  #FB_CRUISE,fspeed

    clr.w   -(sp)               ; Fopen, read only
    pea     fb_name
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
    move.w  #1,fb_ready
    ifd FB_STAMP
    bsr     fb_stamp            ; a scene that is this one plus a fixed mark
    endif
    move.l  frame0,d0           ; show the first one immediately
    bsr     set_screen_base
.nofile:                        ; no file leaves the scene blank, but quiet
    rts

;----------------------------------------------------------------------
show_frame:
    move.w  fspeed,d0           ; a kick decays back to the cruise
    cmp.w   #FB_CRUISE+FB_SLOW,d0
    bcs.s   .sk
    sub.w   #FB_SLOW,d0
    bra.s   .sp
.sk:
    move.w  #FB_CRUISE,d0
.sp:
    move.w  d0,fspeed

    add.w   fphase,d0           ; wrap on the loop itself, not on 65536:
.wrap:                          ; a phase that wraps anywhere else skips
    cmp.w   #FB_WRAP,d0
    bcs.s   .ok
    sub.w   #FB_WRAP,d0
    bra.s   .wrap
.ok:
    move.w  d0,fphase

    tst.w   fb_ready            ; no frames, nothing to show
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
    mulu    #FB_KICK,d2
    add.w   #FB_CRUISE,d2
    cmp.w   #FB_MAX,d2
    bcs.s   .ok
    move.w  #FB_MAX,d2
.ok:
    move.w  d2,fspeed
    movem.l (sp)+,d0-d2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section bss
    even
frames:         ds.b NFRAMES*FRAMESZ+256
frame0:         ds.l 1
fphase:         ds.w 1
fspeed:         ds.w 1
fb_ready:       ds.w 1
    even
