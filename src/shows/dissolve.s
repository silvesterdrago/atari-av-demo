;======================================================================
;  DISSOLVE -- the corridor flying, broken apart live.
;
;  Their dissolve is not a fade: rectangular regions are lifted out,
;  blanked where they came from, and most of them pasted back displaced,
;  the break-up growing toward the edges. Their loop does it to the
;  MOVING corridor while the amount of break-up breathes, so the source
;  here is the corridor's own flipbook and the break-up is computed.
;
;  What that costs is a frame rate. Clean, the scene only writes the
;  screen base register, so it plays at the flipbook's 2 VBLs a frame.
;  Breaking, every picture has to be composed: 32000 bytes of frame
;  copied, then the blocks laid into it. At 16 blocks that is four VBLs
;  a picture, about 18 Hz, and at the cap of 40 it is seven, about 10 Hz.
;  The drop is only ever there while the picture is shattered, where it
;  reads as part of the glitch.
;
;  Composition goes into a back buffer a chunk at a time -- one copy
;  chunk or one batch of blocks per VBL -- so no picture is ever shown
;  half built and MIDI is still polled every frame.
;
;  tools/gendis.py guarantees the two things that make a block cheap:
;  every x, width and horizontal shift is a multiple of 4 bytes, so both
;  ends of a copy are long-aligned, and every block lies inside the
;  screen once displaced. So the ST needs no clipping and no bit
;  shifting, and cannot write outside its buffer. The tile is always read
;  from the untouched frame, as in the reference, so blocks that overlap
;  compose the same way.
;
;  Both CORRIDOR.DAT (the frames) and DISSOLVE.DAT (the table) must sit
;  beside the binary.
;======================================================================
POOL_SIZE   equ 1024            ; no noise, no scrolling window
RANGE_PAGES equ 1
    include "src/core/head.s"

NFRAMES     equ 24              ; must match tools/genflip.py
FRAMESZ     equ 32000
NBLK        equ 60              ; must match tools/gendis.py: the table is
BLKSZ       equ 14              ; read whole, so a count that disagrees with
TABSZ       equ 2+NBLK*BLKSZ    ; the file is a file we do not know

FB_WRAP     equ NFRAMES*256     ; phase is 8.8 frames, so it wraps exactly
FB_CRUISE   equ 128             ; one frame every two VBLs when it is clean
BLKCAP      equ 40              ; blocks at most, which is 7 VBLs a picture
KICK        equ 40              ; blocks per unit of velocity, in 8.8
DECAY       equ 48              ; 8.8 a VBL: the cap mends in about 3 seconds
COPYCH      equ 16000           ; bytes of frame a VBL, so two VBLs a copy
PERBATCH    equ 8               ; blocks a VBL
    ifnd AUTOHIT                    ; -DAUTOHIT=<frames> hits by itself, so the
AUTOHIT     equ 0                   ; scene can be checked with no MIDI and no
    endif                           ; keyboard, which is how it is captured

;----------------------------------------------------------------------
show_init:
    lea     frames,a1           ; the base register has no low byte, so every
    move.l  a1,d0               ; screen has to start on a 256 boundary
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    lea     work,a1
    move.l  a1,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,work0            ; FRAMESZ is a multiple of 256, so the second
    add.l   #FRAMESZ,d0         ; buffer is aligned too
    move.l  d0,work1
    move.l  work0,back

    lea     cor_name,a0         ; the frames, read once
    move.l  frame0,a1
    move.l  #NFRAMES*FRAMESZ,d1
    bsr     load_file
    tst.w   d0
    beq     .out

    lea     dis_name,a0         ; the table
    lea     tab,a1
    move.l  #TABSZ,d1
    bsr     load_file
    tst.w   d0
    beq     .out

    move.w  tab,d0
    beq     .out
    cmp.w   #NBLK,d0            ; a count we would walk off the end of
    bhi     .out
    move.w  d0,nblk
    move.w  #1,dis_ready
    move.w  #1,auto_ctr
    move.l  frame0,d0
    bsr     set_screen_base
.out:                           ; a missing file leaves the scene blank, quiet
    rts

;----------------------------------------------------------------------
; a0 = name, a1 = buffer, d1 = length. d0 = 1 when the whole length was
; read; a short read is not our file. GEMDOS keeps d3-d7/a3-a6 and
; nothing else, so the buffer, the length and the handle live in those.
;----------------------------------------------------------------------
load_file:
    movem.l d1-d5/a0-a1,-(sp)
    move.l  a1,d3
    move.l  d1,d4
    clr.w   -(sp)               ; Fopen, read only
    move.l  a0,-(sp)
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi.s   .fail
    move.w  d0,d5               ; the handle

    move.l  d3,-(sp)            ; Fread, straight into the buffer
    move.l  d4,-(sp)
    move.w  d5,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,d3               ; the count read, past the close

    move.w  d5,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp

    cmp.l   d4,d3
    bne.s   .fail
    moveq   #1,d0
    bra.s   .done
.fail:
    moveq   #0,d0
.done:
    movem.l (sp)+,d1-d5/a0-a1
    rts

;----------------------------------------------------------------------
show_frame:
    tst.w   dis_ready
    beq     .out
    if AUTOHIT
    subq.w  #1,auto_ctr
    bgt.s   .noauto
    move.w  #AUTOHIT,auto_ctr
    movem.l d0-d1,-(sp)
    move.w  #170,d0
    moveq   #0,d1
    bsr     show_note_on
    movem.l (sp)+,d0-d1
.noauto:
    endif

    move.w  fphase,d0           ; the flipbook runs whatever else happens
    add.w   #FB_CRUISE,d0
    cmp.w   #FB_WRAP,d0
    bcs.s   .ok
    sub.w   #FB_WRAP,d0
.ok:
    move.w  d0,fphase

    move.w  amt,d1              ; the break-up mends by itself
    beq     .clean
    sub.w   #DECAY,d1
    bcc.s   .st
    moveq   #0,d1
.st:
    move.w  d1,amt
    lsr.w   #8,d1
    beq     .clean
    cmp.w   #BLKCAP,d1
    bls.s   .cap
    move.w  #BLKCAP,d1
.cap:
    cmp.w   nblk,d1
    bls.s   .have
    move.w  nblk,d1
.have:
    tst.w   composing
    bne.s   .step
    move.w  #1,composing        ; start a picture: which frame, how broken
    clr.w   copied
    clr.w   cblk
    move.w  d1,cn
    lsr.w   #8,d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    move.l  d0,csrc
.step:
    move.w  copied,d0
    cmp.w   #FRAMESZ/COPYCH,d0
    bcc.s   .blocks
    bsr     copy_chunk
    bra.s   .out
.blocks:
    move.w  #PERBATCH,d7
    subq.w  #1,d7
.lp:
    move.w  cblk,d0
    cmp.w   cn,d0
    bcc.s   .flip
    addq.w  #1,cblk
    mulu    #BLKSZ,d0
    lea     tab+2,a3
    add.l   d0,a3
    bsr     apply_block
    dbra    d7,.lp
    bra.s   .out
.flip:                          ; show the finished picture, and build the
    move.l  work0,d1            ; next one in the other buffer. The swap has
    cmp.l   back,d1             ; to be settled BEFORE the call: it returns
    bne.s   .w0                 ; with d0 shifted down by sixteen
    move.l  work1,d1
.w0:
    move.l  back,d0
    move.l  d1,back
    clr.w   composing
    bsr     set_screen_base
.out:
    rts

.clean:                         ; nothing broken: just show the frame itself
    clr.w   composing
    lsr.w   #8,d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d1,-(sp)
    tst.w   dis_ready
    beq.s   .out
    mulu    #KICK,d0
    add.w   amt,d0
    bcs.s   .max                ; 8.8 overflowed, so it is past the cap anyway
    cmp.w   #BLKCAP*256,d0
    bls.s   .set
.max:
    move.w  #BLKCAP*256,d0
.set:
    move.w  d0,amt
.out:
    movem.l (sp)+,d0-d1
    rts

;----------------------------------------------------------------------
; A dbra per long costs more than the move does -- 10 cycles against 20 --
; which put a 16000-byte chunk at 7.5 cycles a byte and over the frame. In
; 32-byte steps the loop overhead is a fourteenth of that.
copy_chunk:                     ; one slice of the frame into the back buffer
    movem.l d0-d7/a0-a2,-(sp)
    move.w  copied,d0
    mulu    #COPYCH,d0
    move.l  csrc,a1
    add.l   d0,a1
    move.l  back,a0
    add.l   d0,a0
    move.w  #COPYCH/32-1,d7
.lp:
    movem.l (a1)+,d0-d6/a2
    movem.l d0-d6/a2,(a0)
    lea     32(a0),a0
    dbra    d7,.lp
    addq.w  #1,copied
    movem.l (sp)+,d0-d7/a0-a2
    rts

;----------------------------------------------------------------------
; a3 -> block, advanced past it. Blank where the tile was, then lay it
; down from the untouched FRAME at its displaced place; a removed tile is
; only blanked.
;----------------------------------------------------------------------
apply_block:
    movem.l d0-d7/a0-a2,-(sp)
    movem.w (a3)+,d0-d6         ; xb y wb h dxb dy keep
    move.w  d6,d7
    move.l  d1,d6
    mulu    #80,d6
    move.l  back,a0
    add.l   d6,a0
    add.w   d0,a0               ; where the tile was, in the back buffer
    move.l  csrc,a1
    add.l   d6,a1
    add.w   d0,a1               ; the same place in the frame
    add.w   d5,d1
    add.w   d4,d0
    move.l  d1,d6
    mulu    #80,d6
    move.l  back,a2
    add.l   d6,a2
    add.w   d0,a2               ; where it lands
    move.w  d2,d4
    lsr.w   #2,d4
    subq.w  #1,d4               ; longs a row, less one
    move.w  d3,d5
    subq.w  #1,d5               ; rows, less one
    move.w  d5,d3
    moveq   #0,d0
.brow:
    move.w  d4,d1
    move.l  a0,d6
.bl:
    move.l  d0,(a0)+
    dbra    d1,.bl
    move.l  d6,a0
    add.w   #80,a0
    dbra    d5,.brow

    tst.w   d7
    beq.s   .done
    move.w  d3,d5
.crow:
    move.w  d4,d1
    move.l  a1,d6
    move.l  a2,d2
.cl:
    move.l  (a1)+,(a2)+
    dbra    d1,.cl
    move.l  d6,a1
    add.w   #80,a1
    move.l  d2,a2
    add.w   #80,a2
    dbra    d5,.crow
.done:
    movem.l (sp)+,d0-d7/a0-a2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
cor_name:
    dc.b    "CORRIDOR.DAT",0
    even
dis_name:
    dc.b    "DISSOLVE.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
frames:         ds.b NFRAMES*FRAMESZ+256
work:           ds.b 2*FRAMESZ+256
tab:            ds.b TABSZ
frame0:         ds.l 1
work0:          ds.l 1
work1:          ds.l 1
back:           ds.l 1
csrc:           ds.l 1
fphase:         ds.w 1
amt:            ds.w 1
nblk:           ds.w 1
cn:             ds.w 1
cblk:           ds.w 1
copied:         ds.w 1
composing:      ds.w 1
dis_ready:      ds.w 1
auto_ctr:       ds.w 1
    even
