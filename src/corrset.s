;======================================================================
;  CORRSET -- the five flipbooks in one binary, on the number keys.
;
;      1 CORRIDOR   2 TUNNEL   3 WAVE   4 DESYNC   5 DRIFT   6 DISSOLVE
;
;  DISSOLVE breaks the corridor's own frames, so 1 and 6 want the same
;  file and switching between them reads nothing at all -- the buffer is
;  tracked by the FILE in it, not by the scene. That pair is the control
;  for the experiment: the cost is the data, never the code.
;
;  Each is 750 KB of frames and a megabyte holds one, so they share a
;  single buffer and the entered scene is read off the card over the one
;  before it. That read is the whole experiment: the machine can do
;  nothing else while GEMDOS is in it, so the picture freezes for exactly
;  as long as the card takes, and what you see is the new scene's bytes
;  landing on the old one's.
;
;  The phase belongs to the SET, not to a scene, so a switch keeps the
;  frame number it was on: the corridor does not jump, only what is being
;  done to it changes. That is what makes 1 <-> 4 <-> 5 worth watching,
;  since all three are the same corridor.
;
;  With -DDIAG=1 bar three carries how many VBLs the last read took.
;  -DCYCLE=<frames> switches on its own, for measuring without a
;  keyboard.
;
;  All five .DAT files must sit beside the binary.
;======================================================================
SCENES      equ 1               ; the core sends 1-9 to scene_select
POOL_SIZE   equ 1024
RANGE_PAGES equ 1
    include "src/core/head.s"

NSCENE      equ 6
DIS         equ 5               ; the one scene that is not a flipbook
NFRAMES     equ 24              ; must match tools/genflip.py
FRAMESZ     equ 32000
SETSZ       equ NFRAMES*FRAMESZ
FB_WRAP     equ NFRAMES*256     ; phase is 8.8 frames, so it wraps exactly
FB_CRUISE   equ 128             ; one frame every two VBLs
FB_KICK     equ 4
FB_MAX      equ 1024
FB_SLOW     equ 16

;----------------------------------------------------------------------
show_init:
    lea     frames,a1           ; the base register has no low byte, so the
    move.l  a1,d0               ; frames have to start on a 256 boundary
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    clr.w   fphase
    move.w  #FB_CRUISE,fspeed
    move.w  #-1,cur_scene
    moveq   #0,d0
    bsr     scene_select
    rts

;----------------------------------------------------------------------
; d0 = scene 0..NSCENE-1. Reads its frames over whatever is in the
; buffer. The phase is left alone: that is the frame sync.
;----------------------------------------------------------------------
scene_select:
    movem.l d0-d6/a0-a1,-(sp)
    cmp.w   #NSCENE,d0
    bcc     .out
    cmp.w   cur_scene,d0
    beq     .out
    move.w  d0,d4
    lsl.w   #2,d0
    lea     name_tbl,a0
    move.l  0(a0,d0.w),a1
    cmp.l   buf_file,a1         ; the same frames as the scene we are leaving
    beq     .entered            ; (1 and 6), so there is nothing to read
    clr.w   fb_ready            ; the buffer is about to stop being a scene
    move.w  #-1,cur_scene
    clr.l   buf_file
    move.l  VBCLOCK,d5
    move.l  a1,d6               ; GEMDOS keeps d3-d7, and nothing else

    clr.w   -(sp)               ; Fopen, read only
    move.l  a1,-(sp)
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi.s   .out
    move.w  d0,d3               ; the handle, past the next trap

    move.l  frame0,-(sp)        ; Fread: the whole file, in one go
    move.l  #SETSZ,-(sp)
    move.w  d3,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,d2

    move.w  d3,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp

    move.l  VBCLOCK,d0          ; how long the card took, in frames
    sub.l   d5,d0
    add.w   d0,show_ctr         ; bar three, with -DDIAG=1

    cmp.l   #SETSZ,d2
    bne.s   .out                ; a short read is not our file
    move.l  d6,buf_file
.entered:
    move.w  d4,cur_scene
    move.w  #1,fb_ready
    cmp.w   #DIS,d4
    bne.s   .out
    bsr     dis_init            ; its table and its work buffers
.out:
    movem.l (sp)+,d0-d6/a0-a1
    rts

;----------------------------------------------------------------------
show_frame:
    ifd CYCLE
    addq.w  #1,cyc_ctr
    cmp.w   #CYCLE,cyc_ctr
    bcs.s   .noswap
    clr.w   cyc_ctr
    move.w  cur_scene,d0
    addq.w  #1,d0
    cmp.w   #NSCENE,d0
    bcs.s   .wrapped
    moveq   #0,d0
.wrapped:
    bsr     scene_select
.noswap:
    endif
    move.w  fspeed,d0           ; a kick decays back to the cruise
    cmp.w   #FB_CRUISE+FB_SLOW,d0
    bcs.s   .sk
    sub.w   #FB_SLOW,d0
    bra.s   .sp
.sk:
    move.w  #FB_CRUISE,d0
.sp:
    move.w  d0,fspeed

    cmp.w   #DIS,cur_scene      ; dissolve runs the phase itself
    beq     .dis
    add.w   fphase,d0           ; wrap on the loop itself, not on 65536
.wrap:
    cmp.w   #FB_WRAP,d0
    bcs.s   .ok
    sub.w   #FB_WRAP,d0
    bra.s   .wrap
.ok:
    move.w  d0,fphase

    tst.w   fb_ready            ; mid-switch, or a file that is not ours
    beq.s   .done
    lsr.w   #8,d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    bsr     set_screen_base
.done:
    rts
.dis:
    bra     dis_frame

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    cmp.w   #DIS,cur_scene
    beq     dis_note_on
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

    include "src/shows/dissolve.inc"

    section text
    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
name_tbl:
    dc.l    nm_corr, nm_tun, nm_wave, nm_desy, nm_drift, nm_corr
nm_corr:    dc.b "CORRIDOR.DAT",0
    even
nm_tun:     dc.b "TUNNEL.DAT",0
    even
nm_wave:    dc.b "WAVE.DAT",0
    even
nm_desy:    dc.b "DESYNC.DAT",0
    even
nm_drift:   dc.b "DRIFT.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
frames:         ds.b SETSZ+256
frame0:         ds.l 1
fphase:         ds.w 1
fspeed:         ds.w 1
cur_scene:      ds.w 1
buf_file:       ds.l 1          ; which .DAT the buffer holds, not which scene
fb_ready:       ds.w 1
    ifd CYCLE
cyc_ctr:        ds.w 1
    endif
    even
