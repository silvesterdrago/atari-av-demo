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
;  a screen must start on a 256-byte boundary. Where TOS loads the DATA
;  segment is not ours to choose, so the frames are copied once at
;  start-up into an aligned buffer. That costs the memory twice and a
;  tenth of a second, and nothing per frame afterwards.
;======================================================================
POOL_SIZE   equ 1024            ; no noise, no scrolling window
RANGE_PAGES equ 1
    include "src/core/head.s"

NFRAMES     equ 12              ; must match tools/genhyper.py
FRAMESZ     equ 32000
SPEED_BASE  equ 128             ; one frame every two VBLs: 0.34s a doubling
SPEED_DECAY equ 12
SPEED_HIT   equ 6               ; times velocity
    ifnd FLASH_AT
FLASH_AT    equ 200
    endif
    ifnd FLASH_LEN
FLASH_LEN   equ 3
    endif

;----------------------------------------------------------------------
show_init:
    lea     frames,a1           ; round the buffer up to a 256 boundary
    move.l  a1,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    move.l  d0,a1
    lea     hyper_data,a0
    move.w  #(NFRAMES*FRAMESZ)/32-1,d7
.cp:
    movem.l (a0)+,d0-d6/a2
    movem.l d0-d6/a2,(a1)
    lea     32(a1),a1
    dbra    d7,.cp

    clr.w   hphase
    move.w  #SPEED_BASE,hspeed
    clr.w   hflash
    move.l  frame0,d0           ; show the first one immediately
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
show_frame:
    move.w  hspeed,d0           ; the jump slows back to its cruise
    cmp.w   #SPEED_BASE+SPEED_DECAY,d0
    bcs.s   .sk
    sub.w   #SPEED_DECAY,d0
    bra.s   .sp
.sk:
    move.w  #SPEED_BASE,d0
.sp:
    move.w  d0,hspeed
    add.w   d0,hphase

    tst.w   hflash              ; one word to the palette, so it is free
    beq.s   .noflash
    subq.w  #1,hflash
    bne.s   .noflash
    move.w  #$000,PALETTE_HW
.noflash:

    move.w  hphase,d0
    lsr.w   #8,d0
    and.l   #$ffff,d0
    divu    #NFRAMES,d0         ; twelve is not a power of two
    swap    d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d2,-(sp)
    move.w  d0,d2
    mulu    #SPEED_HIT,d2
    add.w   #SPEED_BASE,d2
    cmp.w   #$1800,d2
    bcs.s   .ok
    move.w  #$1800,d2
.ok:
    move.w  d2,hspeed
    cmp.w   #FLASH_AT,d0
    bcs.s   .done
    move.w  #$777,PALETTE_HW    ; the whole jump inverts for a moment
    move.w  #FLASH_LEN,hflash
.done:
    movem.l (sp)+,d0-d2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
hyper_data:
    incbin  "src/hyper.bin"

;----------------------------------------------------------------------
    section bss
    even
frames:         ds.b NFRAMES*FRAMESZ+256
frame0:         ds.l 1
hphase:         ds.w 1
hspeed:         ds.w 1
hflash:         ds.w 1
    even
