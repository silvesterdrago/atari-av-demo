;======================================================================
;  HYPER
;
;  A hyperspace jump. The machine does nothing but write the screen base
;  register once a frame.
;
;  Two cheaper ideas failed first, both for the same reason. Real streaks
;  are out of reach -- an arbitrary line is ~50 cycles a pixel and the
;  reference holds some 80 000 pixels of them. And a particle with a
;  trail, which IS cheap, cannot draw a streak here: radial speed is
;  proportional to radius, so at r=300 one frame of travel is 37 pixels
;  and the trail comes out as a ring of dots. Slowing the growth enough
;  to join them up takes seven seconds to cross the screen.
;
;  What rescues it is that the field is self-similar: stars sit at radii
;  r0*G^(m+u) for every integer m, so scaling the picture by G maps the
;  set onto itself. Twelve baked screens, each the previous one scaled by
;  G^(1/12), therefore loop seamlessly -- and the generator can then
;  spend whatever it likes on the streaks, because playing them back is
;  free.
;
;  The one catch is hardware: the ST's base register has no low byte, so
;  a screen must start on a 256-byte boundary, and where TOS loads a
;  program is not ours to choose. So the frames are read off the card at
;  start-up, out of HYPER.DAT beside the binary, straight into an aligned
;  buffer. Carrying them inside the program instead costs the same memory
;  twice over -- 375 KB of file AND 375 KB of buffer -- which is what kept
;  this scene out of any binary that holds another.
;======================================================================
    ifnd SCENES
POOL_SIZE   equ 1024            ; no noise, no scrolling window
    endif
    ifnd SCENES
RANGE_PAGES equ 1
    endif
    include "src/core/head.s"

NFRAMES     equ 12              ; must match tools/genhyper.py
FRAMESZ     equ 32000
HY_CRUISE  equ 128             ; one frame every two VBLs: 0.34s a doubling
HY_SLOW equ 12
HY_KICK   equ 6               ; times velocity
    ifnd FLASH_AT
FLASH_AT    equ 200
    endif
    ifnd FLASH_LEN
FLASH_LEN   equ 3
    endif

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
hy_init:
    ifd SHARED
    move.l  sd_base,frame0      ; the set loaded the frames already
    move.w  #1,hy_ready
    else
    bsr     hy_load
    endif
    clr.w   hphase
    move.w  #HY_CRUISE,hspeed
    clr.w   hy_flash
    move.l  frame0,d0           ; show the first one immediately
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
; Read the frames into the aligned buffer, once. Entering the scene again
; must not pay for it twice, and a card without the file must not be asked
; on every entry -- hy_dead then leaves the scene blank, which is wrong but
; quiet, and the other scenes still work.
;----------------------------------------------------------------------
    ifnd SHARED
hy_load:
    movem.l d0-d2/a0-a1,-(sp)
    tst.w   hy_ready
    bne     .out
    tst.w   hy_dead
    bne     .out

    lea     frames,a1           ; round the buffer up to a 256 boundary
    move.l  a1,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0

    clr.w   -(sp)               ; Fopen, read only
    pea     hy_name
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
    move.w  #1,hy_ready
    bra.s   .out
.nofile:
    move.w  #1,hy_dead
.out:
    movem.l (sp)+,d0-d2/a0-a1
    rts
    endif

;----------------------------------------------------------------------
    ifnd SCENES
show_frame:
    endif
hy_frame:
    move.w  hspeed,d0           ; the jump slows back to its cruise
    cmp.w   #HY_CRUISE+HY_SLOW,d0
    bcs.s   .sk
    sub.w   #HY_SLOW,d0
    bra.s   .sp
.sk:
    move.w  #HY_CRUISE,d0
.sp:
    move.w  d0,hspeed
    add.w   d0,hphase

    tst.w   hy_flash              ; one word to the palette, so it is free
    beq.s   .noflash
    subq.w  #1,hy_flash
    bne.s   .noflash
    move.w  #$000,PALETTE_HW
.noflash:

    tst.w   hy_ready            ; no frames, nothing to show
    beq.s   .out
    move.w  hphase,d0
    lsr.w   #8,d0
    and.l   #$ffff,d0
    divu    #NFRAMES,d0         ; twelve is not a power of two
    swap    d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    bsr     set_screen_base
.out:
    rts

;----------------------------------------------------------------------
    ifnd SCENES
show_note_on:
    endif
hy_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d2,-(sp)
    move.w  d0,d2
    mulu    #HY_KICK,d2
    add.w   #HY_CRUISE,d2
    cmp.w   #$1800,d2
    bcs.s   .ok
    move.w  #$1800,d2
.ok:
    move.w  d2,hspeed
    cmp.w   #FLASH_AT,d0
    bcs.s   .done
    move.w  #$777,PALETTE_HW    ; the whole jump inverts for a moment
    move.w  #FLASH_LEN,hy_flash
.done:
    movem.l (sp)+,d0-d2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
hy_name:
    dc.b    "HYPER.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
    ifnd SHARED
frames:         ds.b NFRAMES*FRAMESZ+256
    endif
frame0:         ds.l 1
hphase:         ds.w 1
hspeed:         ds.w 1
hy_flash:       ds.w 1
hy_ready:       ds.w 1
hy_dead:        ds.w 1
    even
