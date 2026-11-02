;======================================================================
;  ARC -- the whole arc in one binary, addressed by POSITION number.
;
;  A command code is the position in their own 66-frame sequence: 15 is
;  the nested squares, 18 the corridor, 58 the compression. Positions we
;  have not built do nothing, so the numbering never moves as scenes are
;  added and a set list in Live is literally a list of numbers off their
;  storyboard. Codes above 66 are ours: 99 is the safety point on black.
;
;  Two families of scene live here, and the difference is visible in the
;  arrangement because it costs time:
;
;    MORPH      acts I, II, III, VII, VIII. No data at all -- trapezoid
;               keyframes in src/shows/acts*.inc, the same files the
;               standalone binaries read. Switching is one frame.
;    DISSOLVE   positions 49, 50 and 52. The same engine over different
;               screens and different tables: 49 breaks the corridor apart,
;               50 the tunnel, and 52 punches the corridor full of holes --
;               a table whose blocks have no displacement, which the engine
;               reads as a cut. All three are the flipbook family plus a
;               composition pass, so they share the buffer and 49 and 52
;               share the corridor's file with 18.
;    STILL      one picture, not a loop -- most of act V. All of them sit in
;               one file and the ST reads just the screen it wants, 32000
;               bytes, about 85 ms off the card against two seconds for a
;               loop. It lands in the break-up's own work buffer, which is
;               idle whenever a still is up, so a still costs no memory.
;    FLIPBOOK   the baked loops, 24 screens of 32000 bytes each. One
;               shared buffer holds whichever is wanted, so entering one
;               costs reading 768 KB off the card -- about two seconds on
;               the machine. The read runs a chunk a frame, so the show
;               stays alive through it and the new loop arrives over the
;               old one a strip at a time.
;
;  The buffer is tracked by the FILE in it, not by the position, so 13
;  and 14 -- the floor, and the floor with a block on the horizon -- share
;  one file and switching between them reads nothing. The block is
;  stamped into the loaded screens, the rows it covers being black in all
;  of them.
;
;  Unlike PRIMS, the acts do not run their own loop: a command morphs from
;  WHAT IS ON THE SCREEN to the commanded composition and holds there, so
;  the arrangement decides every transition. That is what mo_arc does.
;
;  -DGOTO=<position> opens on that position instead of on black, and
;  -DCYCLE=<frames> walks the rehearsal list by itself -- both are for
;  measuring with MIDI and the keyboard out of the loop.
;
;  All the .DAT files must sit beside the binary.
;======================================================================
SCENES      equ 1               ; the core sends commands to scene_select
HAS_SCENE_KEY equ 1             ; and the number keys through our own list
HAS_SHOW_FX equ 1               ; and effect codes the core does not know
    ifd POSTER                  ; BEFORE the include: head.s pulls in tail.s,
HAS_SHOW_KEY equ 1              ; which is where the keyboard is read
    endif
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens for the morph family

    include "src/core/head.s"

NSLOT       equ 20              ; one slot count for every act
NSTATE      equ 28
HOLD        equ 0               ; the arrangement says when, so nothing waits
MORPH       equ 130             ; frames a transition takes

    include "src/shows/morph.inc"

    section text                ; the engine's include ends in bss

NFRAMES     equ 24              ; must match tools/genflip.py
FRAMESZ     equ 32000
SETSZ       equ NFRAMES*FRAMESZ
    ifd POSTER
; The poster is one screen with one band of it moving: 27 rows, 23 down.
; Only the headline's letters ever move, so the file carries the screen once
; and the band 19 times over, and a frame is a 2160-byte copy rather than a
; new picture. PB_REST holds the line still between waves: 18 states at six
; frames is a wave of 1.5 s, and the rest makes the turn 6.0 s.
KIND_POSTER equ 4
PB_ROWS     equ 27
PB_SIZE     equ PB_ROWS*80
PB_STATES   equ 19
PB_TOP      equ 23
PB_HOLD     equ 6
PB_REST     equ 319
PB_SWEEP    equ PB_HOLD*(PB_STATES-1)
    endif
KIND_MORPH  equ 0
KIND_LOOP   equ 1
KIND_DIS    equ 2
KIND_STILL  equ 3
FB_WRAP     equ NFRAMES*256     ; phase is 8.8 screens, so it wraps exactly
FB_CRUISE   equ 128             ; one screen every two frames
FB_KICK     equ 4
FB_MAX      equ 1024
FB_SLOW     equ 16
LOADCH      equ 8192            ; bytes a frame: 22 ms of a 375 KB/s card
POS_MAX     equ 66
SAFE_POS    equ 99              ; ours, not theirs
SAFE_STATE  equ 26

FX_REVERSE  equ 107             ; the loop backwards, while held
FX_HALF     equ 108             ; and at half speed
PT_Y0       equ 100             ; the block of position 14; the horizon bar
PT_ROWS     equ 18              ; starts on row 118, below every row of it
PT_BYTE     equ 39

;----------------------------------------------------------------------
show_init:
    lea     frames,a1           ; the base register has no low byte, so the
    move.l  a1,d0               ; screens must start on a 256 boundary
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,frame0
    clr.w   fphase
    move.w  #FB_CRUISE,fspeed
    clr.l   buf_file
    clr.w   loading
    clr.w   fb_ready
    clr.w   stamped
    clr.w   kind
    lea     work,a1             ; a still lands in the break-up's work buffer,
    move.l  a1,d0               ; and a still can be the first thing asked for
    add.l   #255,d0             ; -- so the two are set up here and not left
    and.l   #$ffffff00,d0       ; to dis_init, which only runs on a break-up
    move.l  d0,work0
    add.l   #FRAMESZ,d0
    move.l  d0,work1
    bsr     mo_init
    ifd FX
    move.w  #FX,d1              ; -DFX=<code> presses an effect at start-up,
    ifd FXV                     ; -DFXV=<0..255> with what strength
    move.w  #FXV,d0
    else
    moveq   #100,d0
    endif
    bsr     cmd_press           ; d1 code, d0 strength
    endif
    ifd GOTO
    move.w  #GOTO,d0            ; -DGOTO=<position> opens on one, which is how
    else                        ; a position is checked with MIDI out of the
    moveq   #1,d0               ; loop entirely -- the emulator's MIDI is too
    endif                       ; lossy to be the instrument
    moveq   #100,d1
    bsr     scene_select
    rts

;----------------------------------------------------------------------
show_frame:
    ifd CYCLE
    addq.w  #1,cyc_ctr
    cmp.w   #CYCLE,cyc_ctr
    bcs.s   .nocyc
    clr.w   cyc_ctr
    move.w  cyc_pos,d0
    addq.w  #1,d0
    cmp.w   #9,d0
    bcs.s   .cycok
    moveq   #0,d0
.cycok:
    move.w  d0,cyc_pos
    bsr     scene_key
.nocyc:
    endif
    ifd KEYTEST
    addq.w  #1,kt_ctr
    cmp.w   #KEYTEST,kt_ctr
    bne.s   .nokt
    bsr     show_key
.nokt:
    endif
    tst.w   loading             ; a loop on its way in, a chunk a frame
    beq.s   .noload
    bsr     load_step
.noload:
    move.w  kind,d0
    beq     mo_frame
    cmp.w   #KIND_STILL,d0      ; a still needs no frame at all; the effects
    beq     .still              ; still work on it, they ride in the core
    cmp.w   #KIND_DIS,d0
    beq     dis_frame
    ifd POSTER
    cmp.w   #KIND_POSTER,d0
    beq     pb_frame
    endif
    bra     fb_frame
.still:
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    cmp.w   #KIND_DIS,kind      ; a hit is what breaks the picture up
    beq     dis_note_on
    tst.w   kind                ; a hit drives the loop's speed; the morph
    beq.s   .out                ; family is driven by the arrangement alone
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
.out:
    rts

;----------------------------------------------------------------------
; d0 = position, d1 = strength. The table says what lives there: nothing,
; a composition of the morph family, or one of the baked loops.
;----------------------------------------------------------------------
scene_select:
    movem.l d0-d7/a0-a2,-(sp)
    cmp.w   #SAFE_POS,d0
    beq     .safety
    tst.w   d0
    beq     .out
    cmp.w   #POS_MAX,d0
    bhi     .out
    subq.w  #1,d0
    add.w   d0,d0
    lea     pos_tbl,a0
    move.w  0(a0,d0.w),d0
    ifd POSTER
    bne.s   .have
    cmp.w   #KIND_POSTER,kind   ; an empty code is still a scene signal, and
    bne     .out                ; the poster comes off on any of them
    moveq   #SAFE_STATE,d5
    bsr     to_morph
    move.w  d5,d0
    bsr     mo_goto
    bra     .out
.have:
    else
    beq     .out                ; a position we have not built
    endif
    move.w  d0,d2
    lsr.w   #8,d2               ; 1 morph, 2 loop, 3 loop and the block,
    and.w   #$ff,d0             ; 4 loop and then break it apart
    cmp.w   #1,d2
    beq     .morph
    cmp.w   #6,d2
    beq     .stillpos

;---- one of the baked loops
    moveq   #0,d4
    cmp.w   #3,d2
    bne.s   .nostamp
    moveq   #1,d4               ; position 14 wants the block
.nostamp:
    moveq   #0,d7               ; 0 plain, 1 the break-up, 2 holes punched
    cmp.w   #4,d2
    bne.s   .nob
    moveq   #1,d7
.nob:
    cmp.w   #5,d2
    bne.s   .nodis
    moveq   #2,d7
.nodis:
    move.w  d0,d3
    lsl.w   #2,d0
    lea     name_tbl,a0
    move.l  0(a0,d0.w),a1
    cmp.l   buf_file,a1         ; the same screens we are already holding,
    beq     .entered            ; so there is nothing to read
    bsr     load_abort          ; a command mid-read drops that read
    clr.l   buf_file
    clr.w   fb_ready
    move.l  a1,d6               ; GEMDOS keeps d3-d7, and nothing else
    clr.w   -(sp)               ; Fopen, read only
    move.l  a1,-(sp)
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi     .out
    move.w  d0,ld_handle
    move.l  d6,ld_file
    move.w  d4,ld_stamp
    move.w  d7,ld_dis
    clr.l   ld_done
    move.w  #1,loading
    clr.w   fx_auto
    move.w  #KIND_LOOP,kind     ; the loop owns the screen from here, and
    bra     .out                ; plays the screens as they land
.entered:
    move.w  #KIND_LOOP,kind
    move.w  #1,fb_ready
    move.w  d4,d0
    bsr     set_stamp
    tst.w   d7
    beq     .out
    move.w  d7,d0
    bsr     dis_table           ; which table this position breaks it with
    bsr     dis_init            ; it, and the two work buffers
    move.w  #KIND_DIS,kind
    bra     .out

;---- one still, read on its own
.stillpos:
    bsr     load_still
    bra.s   .out

;---- a composition of the morph family
.morph:
    move.w  d0,d5
    bsr     to_morph
    move.w  d5,d0
    bsr     mo_goto
    bra.s   .out
.safety:
    moveq   #SAFE_STATE,d5
    bsr     to_morph
    move.w  d5,d0
    bsr     mo_goto
.out:
    movem.l (sp)+,d0-d7/a0-a2
    rts

;----------------------------------------------------------------------
; d0 = 0..8 off the number keys. They cannot carry a position between 1 and
; 66, so they carry a rehearsal list instead: enough of both families to
; watch every kind of switch there is, including 6 -> 8, which share the
; corridor's file and so read nothing.
;----------------------------------------------------------------------
key_list:
    dc.w    1, 5, 11, 15, 16, 18, 44, 49, 58

scene_key:
    movem.l d0-d1/a0,-(sp)
    cmp.w   #9,d0
    bcc.s   .out
    add.w   d0,d0
    lea     key_list,a0
    move.w  0(a0,d0.w),d0
    moveq   #100,d1             ; a key enters at a middling strength
    bsr     scene_select
.out:
    movem.l (sp)+,d0-d1/a0
    rts

;----------------------------------------------------------------------
; d0 = 1 for the break-up, 2 for the holes. Points the engine at one table
; or the other before it loads one; the format is the same, and a block with
; no displacement in it is what the engine reads as a cut.
;----------------------------------------------------------------------
dis_table:
    move.l  #dis_name,dis_tab
    cmp.w   #2,d0
    bne.s   .out
    move.l  #cut_name,dis_tab
.out:
    rts

;----------------------------------------------------------------------
; One still, read straight into the break-up's work buffer. Blocking for
; the 85 ms it takes is not worth chunking: six frames, once, against the
; ninety-three a loop needs.
;----------------------------------------------------------------------
load_still:                     ; d0 = which screen
    movem.l d0-d5,-(sp)
    move.w  d0,d3               ; the screen's index; GEMDOS keeps d3-d7
    bsr     load_abort
    clr.w   -(sp)               ; Fopen, read only
    pea     nm_still
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi     .done
    move.w  d0,d4               ; the handle

    clr.w   -(sp)               ; Fseek from the start, to this screen
    move.w  d4,-(sp)
    move.w  d3,d0
    mulu    #FRAMESZ,d0
    move.l  d0,-(sp)
    move.w  #GD_FSEEK,-(sp)
    trap    #1
    lea     10(sp),sp

    move.l  work0,-(sp)         ; Fread, one screen
    move.l  #FRAMESZ,-(sp)
    move.w  d4,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,d5

    move.w  d4,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp

    cmp.l   #FRAMESZ,d5
    bne.s   .done               ; a short read is not our file
    move.w  #KIND_STILL,kind
    bsr     fx_forget_noise     ; the rows saved belong to the picture this
    move.w  #1,fx_auto          ; one replaces          ; nothing in a still moves by itself, so the
                                ; follower is let loose on it
    move.l  work0,d0
    bsr     set_screen_base
.done:
    movem.l (sp)+,d0-d5
    rts

    ifd POSTER
;----------------------------------------------------------------------
; The poster, off the Enter key or off position 66. The screen goes into
; the still's buffer and the band states after it; both are read in one
; blocking pass, like a still, because nothing is on screen worth keeping
; while it lands.
;----------------------------------------------------------------------
load_poster:
    movem.l d0-d6/a0,-(sp)
    bsr     load_abort
    clr.w   loading
    clr.w   -(sp)               ; Fopen, read only
    pea     nm_poster
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi     .done
    move.w  d0,d4               ; GEMDOS keeps d3-d7, and nothing else

    move.l  work0,-(sp)         ; the picture first, one screen
    move.l  #FRAMESZ,-(sp)
    move.w  d4,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    cmp.l   #FRAMESZ,d0
    bne     .shut               ; a short read is not our file

    ; Show it before reading the rest: the bands take another 110 ms, and
    ; they land in the loop buffer, so the beam has to be somewhere else by
    ; then or it spends that time reading memory being overwritten.
    move.w  #KIND_POSTER,kind
    clr.l   buf_file            ; the loop buffer now holds bands, so whatever
    clr.w   fb_ready            ; was in it has to be read again
    clr.w   fx_auto             ; the poster is not a scene: nothing drives it
    clr.w   nz_on               ; and nothing the last scene left running is
    clr.w   nz_held             ; allowed to keep painting over it
    clr.w   sh_held
    clr.w   fx_shift
    bsr     fx_forget_noise
    clr.w   pb_ctr
    move.w  #-1,pb_cur
    move.l  work0,d0
    bsr     set_screen_base

    ; The bands go in chunks of LOADCH. Nothing else in this program asks
    ; the machine for more than one screen in a single read, and the loop
    ; loader does ninety-four of these on every scene change, so this is the
    ; read size the card is known to answer.
    moveq   #0,d6
.band:
    move.l  #PB_STATES*PB_SIZE,d5
    sub.l   d6,d5
    beq.s   .shut               ; all of it in
    cmp.l   #LOADCH,d5
    bls.s   .last
    move.l  #LOADCH,d5
.last:
    move.l  frame0,d0
    add.l   d6,d0
    move.l  d0,-(sp)
    move.l  d5,-(sp)
    move.w  d4,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    cmp.l   d5,d0
    bne.s   .shut               ; short: the file is not what we think
    add.l   d5,d6
    bra.s   .band
.shut:
    move.w  d4,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp
.done:
    movem.l (sp)+,d0-d6/a0
    rts

;----------------------------------------------------------------------
; One frame of the poster: work out which band state is due and copy it in
; only when it is not the one already standing there.
;----------------------------------------------------------------------
pb_frame:
    movem.l d0-d3/a0-a1,-(sp)
    move.w  pb_ctr,d0
    addq.w  #1,d0
    cmp.w   #PB_SWEEP+PB_REST,d0
    bcs.s   .keep
    moveq   #0,d0
.keep:
    move.w  d0,pb_ctr
    moveq   #0,d1
    cmp.w   #PB_SWEEP,d0
    bcc.s   .rest               ; between waves the line stands at state 0
    and.l   #$ffff,d0
    divu    #PB_HOLD,d0
    move.w  d0,d1
    addq.w  #1,d1
.rest:
    cmp.w   pb_cur,d1
    beq.s   .out
    move.w  d1,pb_cur
    mulu    #PB_SIZE,d1
    move.l  frame0,a0
    adda.l  d1,a0
    move.l  work0,a1
    adda.w  #PB_TOP*80,a1
    move.w  #PB_SIZE/4-1,d3
.cp:
    move.l  (a0)+,(a1)+
    dbra    d3,.cp
.out:
    movem.l (sp)+,d0-d3/a0-a1
    rts

;----------------------------------------------------------------------
; Enter, or p. The core hands any key it does not use itself to this.
;----------------------------------------------------------------------
show_key:
    bsr     load_poster
    rts
    endif

;----------------------------------------------------------------------
; Hand the screen back to the morph family. Its two buffers still hold the
; last composition and `prev` still describes it exactly, so prev is left
; ALONE -- clearing it was the bug: the engine wipes per slot, by what prev
; says each buffer holds, and with that record gone it cleared only the new
; boxes and left the old composition standing around them.
;
; What does have to be forced is the redraw itself, since the shape may be
; the one that was there before the loop played over it. And `back` has to
; be taken off whatever the break-up left it pointing at -- it shares that
; variable with us -- back to the buffer that which=0 pairs with.
;----------------------------------------------------------------------
to_morph:
    movem.l d0-d1,-(sp)
    clr.w   fx_auto             ; the morph moves on its own
    clr.w   kind
    bsr     load_abort
    move.w  #1,mo_force
    move.l  screen1,back        ; the break-up leaves `back` in a work buffer
    clr.w   which               ; of its own, and which=0 pairs with screen1 --
    move.l  screen0,d0          ; that pairing is what keeps prev honest
    bsr     set_screen_base
    movem.l (sp)+,d0-d1
    rts

;----------------------------------------------------------------------
; Close a read that is still running, without taking its file.
;----------------------------------------------------------------------
load_abort:
    tst.w   loading
    beq.s   .no
    clr.w   loading
    move.w  ld_handle,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp
.no:
    rts

;----------------------------------------------------------------------
; One chunk of the loop being read, once a frame. Reading 768 KB in a
; single call holds the machine for the card's whole transfer and nothing
; else runs, not even MIDI; a chunk a frame costs the same total and
; leaves the show alive.
;----------------------------------------------------------------------
load_step:
    movem.l d0-d3/a0,-(sp)
    move.l  ld_done,d3
    move.l  frame0,a0
    add.l   d3,a0
    move.l  #SETSZ,d2
    sub.l   d3,d2
    cmp.l   #LOADCH,d2
    bls.s   .last
    move.l  #LOADCH,d2
.last:
    move.l  a0,-(sp)            ; Fread into where we left off
    move.l  d2,-(sp)
    move.w  ld_handle,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    cmp.l   d2,d0
    bne.s   .short              ; a chunk that came up short is not our file
    add.l   d2,d3
    move.l  d3,ld_done
    cmp.l   #SETSZ,d3
    bcs.s   .out
    bsr     load_abort          ; done: close it and take the file
    move.l  ld_file,buf_file
    bsr     fx_forget_noise     ; the rows saved belong to the screens these
    clr.w   stamped             ; fresh screens carry no block
    move.w  #1,fb_ready
    move.w  ld_stamp,d0
    bsr     set_stamp
    tst.w   ld_dis
    beq.s   .out
    move.w  ld_dis,d0
    bsr     dis_table
    bsr     dis_init
    move.w  #KIND_DIS,kind
    bra.s   .out
.short:
    bsr     load_abort
.out:
    movem.l (sp)+,d0-d3/a0
    rts

;----------------------------------------------------------------------
; Effect codes past the core's own. Both are about the baked loops, which
; is why they are ours: the core has no idea there is a loop.
;----------------------------------------------------------------------
show_fx:                        ; d1 = code
    cmp.w   #FX_REVERSE,d1
    bne.s   .h
    move.w  #1,fx_rev
    rts
.h:
    cmp.w   #FX_HALF,d1
    bne.s   .out
    move.w  #1,fx_half
.out:
    rts

show_fx_off:
    clr.w   fx_rev
    clr.w   fx_half
    rts

;----------------------------------------------------------------------
; d0 = 1 to stand the block on the horizon, 0 to take it away. Two BYTE
; writes a row: 16 px centred on 320 begin at byte 39, and a word write to
; an odd address is an address error on a 68000.
;----------------------------------------------------------------------
set_stamp:
    movem.l d0-d3/a0-a1,-(sp)
    cmp.w   stamped,d0
    beq.s   .out
    move.w  d0,stamped
    moveq   #0,d1
    tst.w   d0
    beq.s   .val
    moveq   #-1,d1
.val:
    move.w  #PT_Y0,d0
    mulu    row_bytes,d0
    add.l   #PT_BYTE,d0
    move.l  frame0,a0
    add.l   d0,a0
    moveq   #NFRAMES-1,d3
.frame:
    move.l  a0,a1
    moveq   #PT_ROWS-1,d2
.row:
    move.b  d1,(a1)
    move.b  d1,1(a1)
    adda.w  row_bytes,a1
    dbra    d2,.row
    add.l   #FRAMESZ,a0
    dbra    d3,.frame
.out:
    movem.l (sp)+,d0-d3/a0-a1
    rts

;----------------------------------------------------------------------
; A baked loop playing: the machine writes one register and nothing else.
;----------------------------------------------------------------------
fb_frame:
    move.w  follow,d1           ; the follower raises the FLOOR the speed
    mulu    #3,d1               ; decays to, so the loop breathes with the
    add.w   #FB_CRUISE,d1       ; sound and a hit still punches above it
    move.w  fspeed,d0           ; a kick decays back to that cruise
    move.w  d1,d2
    add.w   #FB_SLOW,d2
    cmp.w   d2,d0
    bcs.s   .sk
    sub.w   #FB_SLOW,d0
    bra.s   .sp
.sk:
    move.w  d1,d0
.sp:
    move.w  d0,fspeed
    tst.w   fx_half             ; held: half the step, so the loop crawls
    beq.s   .full
    asr.w   #1,d0
.full:
    tst.w   fx_rev              ; held: the step goes the other way, and the
    beq.s   .fwd                ; phase wraps at the bottom as well as the top
    neg.w   d0
.fwd:
    add.w   fphase,d0           ; wrap on the loop itself, not on 65536
    bpl.s   .wrap
    add.w   #FB_WRAP,d0
.wrap:
    cmp.w   #FB_WRAP,d0
    bcs.s   .ok
    sub.w   #FB_WRAP,d0
    bra.s   .wrap
.ok:
    move.w  d0,fphase
    tst.w   fb_ready            ; mid-read, or a file that is not ours
    beq.s   .out
    lsr.w   #8,d0
    and.l   #$ffff,d0
    mulu    #FRAMESZ,d0
    add.l   frame0,d0
    bsr     set_screen_base
.out:
    rts

;----------------------------------------------------------------------
    include "src/shows/dissolve.inc"

    section data
    even
; What lives at each of their 66 positions: 0 nothing, $01xx a composition
; of the morph family, $02xx one of the baked loops, $03xx that loop with
; the block of position 14 stamped into it.
pos_tbl:
    dc.w    $0100, $0101, $0102, $0103, $0104       ; I    01-05
    dc.w    $0106, $0107, $0108, $0109, $010a       ; II   06-10
    dc.w    $010c, $0617                            ;      11, 12 radial
    dc.w    $0205, $0305, $010e, $010f              ; III  13-16
    dc.w    $0201, $0200, $0206, $060e, $0207       ; IV   17-21
    dc.w    $0208, $0209, $060f, $020a, $020b       ;      22-26
    dc.w    $0600, $0601, $0602, $0603, $0604       ; V    27-31
    dc.w    $0605, $0606, $0607, $0608, $0609       ;      32-36
    dc.w    $060a, $060b, $060c, $0202              ;      37-40 wave
    dc.w    $060d, $0610, $0204, $0203, $0611       ;      41, VI 42-45
    dc.w    $0618, $0619, $0612, $0400, $0401       ;      46-50
    dc.w    $0613, $0500, $0614, $0615, $040b       ;      51-55, 52 holes
    dc.w    $040a, $0616                            ;      56, 57
    dc.w    $0111, $0112, $0113, $0114, $0115       ; VII  58-62
    dc.w    $0116, $0117, $0118                     ; VIII 63-65
    dc.w    $0000                                   ;      66 title card

    even
name_tbl:
    dc.l    nm_corr, nm_tun, nm_wave, nm_desy, nm_drift, nm_floor
    dc.l    nm_tunp, nm_branch, nm_pit, nm_pitb, nm_walls, nm_expand
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
nm_floor:   dc.b "FLOOR.DAT",0
    even
nm_tunp:    dc.b "TUNPLAIN.DAT",0
    even
nm_branch:  dc.b "BRANCH.DAT",0
    even
nm_pit:     dc.b "PIT.DAT",0
    even
nm_pitb:    dc.b "PITBOLD.DAT",0
    even
nm_walls:   dc.b "WALLS.DAT",0
    even
nm_expand:  dc.b "EXPAND.DAT",0
    even
nm_still:   dc.b "STILLS.DAT",0
    even
    ifd POSTER
nm_poster:  dc.b "POSTER.DAT",0
    even
    endif
cut_name:   dc.b "CUTS.DAT",0
    even

keys:
    include "src/shows/acts1.inc"
    include "src/shows/acts2.inc"
    include "src/shows/acts3.inc"
    include "src/shows/acts7.inc"
    ; the safety roll: a point on black, and the composition it eases into
    ; is the same point, so it sits there for as long as it is needed
    dc.w    304,336,304,336,187,213
    rept 19
    dc.w    320,320,320,320,200,200
    endr
    dc.w    304,336,304,336,187,213
    rept 19
    dc.w    320,320,320,320,200,200
    endr

;----------------------------------------------------------------------
    section bss
    even
frames:         ds.b SETSZ+256
frame0:         ds.l 1
buf_file:       ds.l 1          ; which .DAT the buffer holds, not which position
ld_file:        ds.l 1
ld_done:        ds.l 1
ld_handle:      ds.w 1
ld_stamp:       ds.w 1
loading:        ds.w 1
ld_dis:         ds.w 1
fb_ready:       ds.w 1
fphase:         ds.w 1
fspeed:         ds.w 1
stamped:        ds.w 1
fx_rev:         ds.w 1
fx_half:        ds.w 1
kind:           ds.w 1          ; 0 the morph family, 1 a baked loop
    ifd POSTER
pb_ctr:         ds.w 1
pb_cur:         ds.w 1
    endif
    ifd KEYTEST                 ; press the show's key from the mainloop at a
kt_ctr:         ds.w 1          ; given frame: the key path cannot be reached
    endif                       ; from a headless run any other way
    ifd CYCLE
cyc_ctr:        ds.w 1
cyc_pos:        ds.w 1
    endif
    even
