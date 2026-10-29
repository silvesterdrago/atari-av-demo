;======================================================================
;  DISSOLVE -- the corridor flying, broken apart live.
;
;  A set defines SCENES and hands the frames over in frame0; on its own
;  it includes the core and reads CORRIDOR.DAT itself.
;
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
;
;  A block whose displacement is zero is a CUT: blanked and never laid back.
;  Nothing else in a table ever has one, so the two scenes -- the break-up and
;  the corridor punched full of holes -- are one engine and two tables.
;---================================================================
    ifnd SCENES
POOL_SIZE   equ 1024            ; no noise, no scrolling window
RANGE_PAGES equ 1
    include "src/core/head.s"
    endif

    ifnd NFRAMES                ; a set has these already
NFRAMES     equ 24              ; must match tools/genflip.py
FRAMESZ     equ 32000
    endif
NLEV        equ 6               ; all three must match tools/gendis.py: the
MAXBLK      equ 16              ; table is read whole, so a length that
BLKSZ       equ 12              ; disagrees is a file we do not know
LEVSZ       equ 2+MAXBLK*BLKSZ
TABSZ       equ 2+NLEV*LEVSZ

    ifnd FB_WRAP
FB_WRAP     equ NFRAMES*256     ; phase is 8.8 frames, so it wraps exactly
FB_CRUISE   equ 128             ; one frame every two VBLs when it is clean
    endif
AMTFULL     equ 4096            ; break-up all the way, scaling both the block
                                ; count and how far each one is displaced
; The break-up has to GROW, not arrive. A hit raises a target, the amount
; climbs toward it at ATTACK a VBL and the target sinks at DECAY -- so one
; hit swells and subsides, and hits that come faster than the target sinks
; stack up and carry it further each time. A hard hit is worth about a third
; of full, so the deep end is reached by playing into it.
KICK        equ 6               ; target per unit of velocity
ATTACK      equ 96              ; a VBL: full break-up grows in about 0.6s
DECAY       equ 20              ; a VBL: and sinks back in about 2.9s
COPYCH      equ 16000           ; bytes of frame a VBL, so two VBLs a copy
PERBATCH    equ 8               ; blocks a VBL
    ifnd AUTOHIT                    ; -DAUTOHIT=<frames> hits by itself, so the
AUTOHIT     equ 0                   ; scene can be checked with no MIDI and no
    endif                           ; keyboard, which is how it is captured

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
dis_init:
    ifnd SCENES
    lea     frames,a1           ; the base register has no low byte, so every
    move.l  a1,d0               ; screen has to start on a 256 boundary
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    endif
    lea     work,a1
    move.l  a1,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,work0            ; FRAMESZ is a multiple of 256, so the second
    add.l   #FRAMESZ,d0         ; buffer is aligned too
    move.l  d0,work1
    move.l  work0,back

    ifnd SCENES
    lea     cor_name,a0         ; the frames, read once -- in a set they are
    move.l  frame0,a1           ; already in the shared buffer
    move.l  #NFRAMES*FRAMESZ,d1
    bsr     load_file
    tst.w   d0
    beq     .out
    endif

    move.l  dis_tab,a0          ; the table; a set may point this elsewhere
    lea     tab,a1
    move.l  #TABSZ,d1
    bsr     load_file
    tst.w   d0
    beq     .out

    cmp.w   #NLEV,tab           ; a table that is not the one we were built
    bne     .out                ; against
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
    ifnd SCENES
show_frame:
    endif
dis_frame:
    tst.w   dis_ready
    beq     .out
    if AUTOHIT                  ; eight hits, then eight rests: the envelope
    subq.w  #1,auto_ctr         ; climbs through every level and falls back
    bgt.s   .noauto
    move.w  #AUTOHIT,auto_ctr
    addq.w  #1,auto_n
    and.w   #15,auto_n
    cmp.w   #8,auto_n
    bcc.s   .noauto
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

    move.w  tgt,d1              ; the target sinks on its own
    beq.s   .notgt
    sub.w   #DECAY,d1
    bcc.s   .tg
    moveq   #0,d1
.tg:
    move.w  d1,tgt
.notgt:
    move.w  amt,d2              ; and the amount climbs toward it
    cmp.w   d1,d2
    bcc.s   .fall
    add.w   #ATTACK,d2
    cmp.w   d1,d2
    bls.s   .rise
.fall:
    move.w  d1,d2
.rise:
    move.w  d2,amt
    beq     .clean
    mulu    #NLEV,d2            ; which level of break-up this depth is in.
    lsr.l   #8,d2               ; Each has its OWN blocks, so crossing into
    lsr.l   #4,d2               ; one re-deals the picture rather than adding
    cmp.w   #NLEV,d2            ; to it
    bcs.s   .lev
    move.w  #NLEV-1,d2
.lev:
    tst.w   composing
    bne.s   .step
    move.w  #1,composing        ; start a picture: which frame, which level
    clr.w   copied              ; and how far out. All three are held for the
    clr.w   cblk                ; whole picture, so its blocks agree with
    move.w  amt,camt            ; each other
    mulu    #LEVSZ,d2
    lea     tab+2,a3
    add.l   d2,a3
    move.w  (a3)+,cn
    move.l  a3,cbase
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
    move.l  cbase,a3
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
    ifnd SCENES
show_note_on:
    endif
dis_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d1,-(sp)
    tst.w   dis_ready
    beq.s   .out
    mulu    #KICK,d0            ; a hit raises the target, never the amount:
    add.w   tgt,d0              ; what the picture does is climb toward it
    bcs.s   .max                ; past full either way
    cmp.w   #AMTFULL,d0
    bls.s   .set
.max:
    move.w  #AMTFULL,d0
.set:
    move.w  d0,tgt
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
    movem.w (a3)+,d0-d5         ; xb y wb h uxb uy, the last two at full
    move.w  camt,d6             ; break-up; scale them by how deep it is now
    muls    d6,d4
    asr.l   #8,d4
    asr.l   #4,d4
    and.w   #$fffe,d4           ; even bytes, so both ends stay word-aligned
    move.w  camt,d6
    muls    d6,d5
    asr.l   #8,d5
    asr.l   #4,d5
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
    move.w  d3,d5
    subq.w  #1,d5               ; rows, less one
    move.w  d5,d3
    moveq   #0,d0
    move.w  #80,d7              ; a row ends where the next one starts, less
    sub.w   d2,d7               ; this

; A row is two or three longs, and a dbra counting them costs 10 cycles
; against the move's 12 -- near half the row. There are only the two
; widths, so each one gets its row straight.
    cmp.w   #8,d2
    bne.s   .b12
.b8:
    move.l  d0,(a0)+
    move.l  d0,(a0)+
    add.w   d7,a0
    dbra    d5,.b8
    bra.s   .blanked
.b12:
    move.l  d0,(a0)+
    move.l  d0,(a0)+
    move.l  d0,(a0)+
    add.w   d7,a0
    dbra    d5,.b12
.blanked:
    move.w  -4(a3),d6           ; a block declared with no displacement at all
    or.w    -2(a3),d6           ; is a CUT: the hole stays and nothing is laid
    beq     .laid               ; back. Their frame 52 is a whole table of them
    move.w  d3,d5               ; the tile always lands: the blank it left is
    cmp.w   #8,d2               ; the black gap, so nothing is ever removed
    bne.s   .c12
.c8:
    move.l  (a1)+,(a2)+
    move.l  (a1)+,(a2)+
    add.w   d7,a1
    add.w   d7,a2
    dbra    d5,.c8
    bra.s   .laid
.c12:
    move.l  (a1)+,(a2)+
    move.l  (a1)+,(a2)+
    move.l  (a1)+,(a2)+
    add.w   d7,a1
    add.w   d7,a2
    dbra    d5,.c12
.laid:
    movem.l (sp)+,d0-d7/a0-a2
    rts

    ifnd SCENES
    include "src/core/tail.s"
    endif

;----------------------------------------------------------------------
    section data
    even
    ifnd SCENES
cor_name:
    dc.b    "CORRIDOR.DAT",0
    even
    endif
dis_tab:    dc.l dis_name
    even
dis_name:
    dc.b    "DISSOLVE.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
    ifnd SCENES
frames:         ds.b NFRAMES*FRAMESZ+256
    endif
work:           ds.b 2*FRAMESZ+256
tab:            ds.b TABSZ
    ifnd SCENES
frame0:         ds.l 1
    endif
work0:          ds.l 1
work1:          ds.l 1
    ifnd HAS_BACK               ; a build that also carries the morph engine
back:           ds.l 1          ; already has one, and the two are never
    endif                       ; composing at the same time

csrc:           ds.l 1
cbase:          ds.l 1
    ifnd SCENES
fphase:         ds.w 1
    endif
amt:            ds.w 1
tgt:            ds.w 1
cn:             ds.w 1
camt:           ds.w 1
cblk:           ds.w 1
copied:         ds.w 1
composing:      ds.w 1
dis_ready:      ds.w 1
auto_ctr:       ds.w 1
auto_n:         ds.w 1
    even
