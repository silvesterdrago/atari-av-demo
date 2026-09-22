;======================================================================
;  NOISE AV  --  milestone 2: scene framework + effect prototypes
;  Atari ST (68000 @ 8MHz, plain 1040 STF, SM124 mono 640x400 @ 71Hz)
;
;  Keys:  1-4 pick a scene   0 = auto-cycle   ESC = quit
;         any other key = manual hit (VJing without MIDI)
;
;  Build with -DDIAG=1 for the frame-budget overrun bar.
;======================================================================

    ifnd DIAG
DIAG        equ 0
    endif
    ifnd STARTSCENE
STARTSCENE  equ 0
    endif
    ifnd AUTOCYCLE
AUTOCYCLE   equ 0
    endif
    ; Lowest pad note. Akai MPK Mini mk3 bank A starts at 36, mk2 at 48.
    ; Any contiguous run of 8 notes still gives 8 distinct looks whatever
    ; this is set to -- a wrong base only rotates which pad is which.
    ifnd PAD_BASE
PAD_BASE    equ 36
    endif
    ; -DFORCEGLITCH=1 tears every cube every frame, so the glitch renderer
    ; can be checked without depending on MIDI delivery
    ifnd FORCEGLITCH
FORCEGLITCH equ 0
    endif
    ; -DFAKEMIDI=1 ticks the MIDI counter once per frame, to prove the
    ; diagnostic bar itself works before trusting what it says
    ifnd FAKEMIDI
FAKEMIDI    equ 0
    endif
    ; -DNOPOLL=1 removes the once-per-frame safety drain, leaving only the
    ; interrupt. If bytes still arrive, the interrupt is genuinely firing.
    ifnd NOPOLL
NOPOLL      equ 0
    endif

; ---- GEMDOS (trap #1) ------------------------------------------------
GD_PTERM0   equ 0
GD_CNECIN   equ 8
GD_CCONIS   equ 11
GD_SUPER    equ 32

; ---- BIOS (trap #13) -------------------------------------------------
B_BCONSTAT  equ 1
B_BCONIN    equ 2
DEV_MIDI    equ 3

; ---- XBIOS (trap #14) ------------------------------------------------
XB_PHYSBASE equ 2
XB_GETREZ   equ 4
XB_SETSCREEN equ 5
XB_SETPAL   equ 6
XB_VSYNC    equ 37

; ---- hardware --------------------------------------------------------
SCR_HI      equ $ffff8201       ; screen base, bits 16-23
SCR_MID     equ $ffff8203       ; screen base, bits 8-15
                                ; (no low byte on a plain ST: 256-byte steps)
PALETTE_HW  equ $ffff8240
ACIA_MIDI_CTRL equ $fffffc04    ; 6850 status: bit 0 = receive data full
ACIA_MIDI_DATA equ $fffffc06
ACIA_RX_ON  equ $95             ; /16, 8N1, receive interrupt enabled
VEC_ACIA    equ $118            ; MFP channel 6 -- shared by IKBD and MIDI
VEC_TIMERC  equ $114            ; MFP channel 5 -- TOS already runs it at 200Hz
VEC_TIMERA  equ $134            ; MFP channel 13 -- Timer A, unused by TOS
MFP_IERA    equ $fffffa07       ; bit 5 = Timer A
MFP_ISRA    equ $fffffa0f
MFP_IMRA    equ $fffffa13
MFP_TACR    equ $fffffa19       ; Timer A control (prescaler)
MFP_TADR    equ $fffffa1f       ; Timer A counter
ISRA_NOT_TA equ $df             ; all ones except bit 5
; MFP timer clock is 2457600 Hz. /4 prescaler with a count of 150 gives
; 4096 Hz, a sweep every 244us. A MIDI byte takes 320us at 31250 baud, so
; this looks more often than bytes can possibly arrive.
TA_PRESCALE equ 1               ; 1 = divide by 4
TA_COUNT    equ 150
MFP_IERB    equ $fffffa09       ; bit 6 = ACIA interrupt enable
MFP_IMRB    equ $fffffa15       ; bit 6 = ACIA interrupt mask
MFP_AER     equ $fffffa03       ; active edge; ACIA IRQ is active low
MFP_IPRB    equ $fffffa0d       ; pending; bit 6 set = ACIA is asking
MFP_ISRB    equ $fffffa11       ; in-service; software EOI means the handler
                                ; must clear its bit or the channel never
                                ; interrupts again
ISRB_NOT_ACIA equ $bf           ; all ones except bit 6; writing a 1 is a no-op

MIDI_RING   equ 256             ; power of two
MIDI_MASK   equ MIDI_RING-1
VBCLOCK     equ $462            ; system VBL counter

SCR_SIZE    equ 32000
SCR_PAGES   equ 125             ; 125 * 256 = 32000, one visible screen
RANGE_PAGES equ 128             ; how far the window may travel before wrapping
BUF_PAGES   equ SCR_PAGES+RANGE_PAGES
BUF_TOTAL   equ BUF_PAGES*256

NOISE_HIT   equ $e8             ; only the very top of the envelope punches noise

POOL_SIZE   equ 32768
POOL_MASK   equ $3ffc

LEVEL_DECAY equ 6
CYCLE_FRAMES equ 400            ; auto-cycle dwell, ~5.6s at 71Hz

SC_CUBES    equ 0             ; 4x2 grid of pulsing wireframe cubes, one per pad
SC_FIELD    equ 1             ; moire generated into a scrolling field
SC_MOIRE    equ 2             ; the original full-redraw moire, kept for reference
SC_BAND     equ 3
SC_STROBE   equ 4
SC_COUNT    equ 5

; Cube sprites are baked by tools/gencubes.py -- drawing 8 wireframe cubes
; with real line code would cost ~90k of our ~112k cycles before erasing.
CUBE_W_BYTES  equ 12            ; 96 px
CUBE_H        equ 96
CUBE_SPRITE   equ CUBE_W_BYTES*CUBE_H
CUBE_ANGLES   equ 16
CUBE_SCALES   equ 8
CUBE_DECAY    equ 5
GLITCH_VEL    equ 240           ; curved level at which the cube tears
GLITCH_FRAMES equ 14
SHEAR_VEL     equ $e0           ; accumulated energy at which the picture slips.
                                ; Deliberately NOT single-hit velocity: the pads
                                ; saturate at 127, so hard and very hard are the
                                ; same number. Density still carries information.

    section text

;----------------------------------------------------------------------
start:
    clr.l   -(sp)
    move.w  #GD_SUPER,-(sp)
    trap    #1
    addq.l  #6,sp
    move.l  d0,old_ssp

    move.w  #XB_GETREZ,-(sp)
    trap    #14
    addq.l  #2,sp
    move.w  d0,rez

    move.w  #XB_PHYSBASE,-(sp)
    trap    #14
    addq.l  #2,sp
    move.l  d0,old_phys

    lea     PALETTE_HW,a0
    lea     old_pal,a1
    moveq   #15,d0
.savepal:
    move.w  (a0)+,(a1)+
    dbra    d0,.savepal

    ; --- geometry of whatever mode we booted into --------------------
    move.w  rez,d0
    move.w  #80,d1
    move.w  #200,d2
    tst.w   d0
    bne.s   .not_low
    move.w  #160,d1
.not_low:
    cmp.w   #2,d0
    bne.s   .not_high
    move.w  #400,d2
.not_high:
    move.w  d1,row_bytes
    move.w  d2,scr_rows
    move.w  d2,d3
    lsr.w   #1,d3
    move.w  d3,half_rows
    divu    #3,d2
    and.w   #$fffe,d2
    move.w  d2,max_rows

    ; --- our own screen buffer, 256-byte aligned ---------------------
    lea     screen_mem,a0
    move.l  a0,d0
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,buf_base

    bsr     install_midi
    bsr     build_noise_pool
    bsr     build_stripe_tbl

    pea     new_pal
    move.w  #XB_SETPAL,-(sp)
    trap    #14
    addq.l  #6,sp

    move.w  #STARTSCENE,scene
    clr.w   auto_cycle
    if AUTOCYCLE
    move.w  #1,auto_cycle
    endif
    bsr     scene_enter

;----------------------------------------------------------------------
mainloop:
    bsr     wait_vbl
    if FAKEMIDI
    addq.w  #1,midi_bytes
    endif
    bsr     measure_overrun

    ; --- run the current scene ---------------------------------------
    move.w  scene,d0
    lsl.w   #2,d0
    lea     scene_frame_tbl,a0
    move.l  (a0,d0.w),a0
    jsr     (a0)

    if DIAG
    bsr     draw_overrun_bar
    endif

    if DIAG
    btst    #0,ACIA_MIDI_CTRL   ; a byte sitting unread in the 6850
    beq.s   .noacia
    addq.w  #1,acia_seen
.noacia:
    endif
    bsr     poll_midi
    bsr     poll_keyboard
    bsr     decay_level
    bsr     do_auto_cycle

    tst.w   quit_flag
    beq     mainloop

;----------------------------------------------------------------------
exit:
    bsr     remove_midi
    ; hand the machine back exactly as we found it
    move.w  #-1,-(sp)
    move.l  old_phys,-(sp)
    move.l  old_phys,-(sp)
    move.w  #XB_SETSCREEN,-(sp)
    trap    #14
    lea     12(sp),sp

    move.l  old_phys,a0
    move.l  a0,a1
    add.l   #SCR_SIZE,a1
    bsr     clear_span

    pea     old_pal
    move.w  #XB_SETPAL,-(sp)
    trap    #14
    addq.l  #6,sp

    move.l  old_ssp,-(sp)
    move.w  #GD_SUPER,-(sp)
    trap    #1
    addq.l  #6,sp

    clr.w   -(sp)
    trap    #1

;----------------------------------------------------------------------
; Read the MIDI ACIA ourselves instead of going through the BIOS.
;
; Two reasons. The BIOS costs a trap per byte, which will not survive MIDI
; clock at 24 ppqn plus notes. And more urgently, it does not work: under
; EmuTOS bytes arrive in the 6850 and simply sit there with RDRF stuck on,
; because nothing services the receive interrupt, so Bconstat(3) reports an
; empty buffer forever. Measured with the DIAG build: the 6850 bar full,
; the BIOS bar flat zero.
;
; MFP channel 6 is shared with the keyboard ACIA, so we drain MIDI and then
; chain to whatever was there before, which still services the IKBD.
;----------------------------------------------------------------------
install_midi:
    clr.w   midi_head
    clr.w   midi_tail
    move.w  sr,-(sp)
    move.w  #$2700,sr           ; no interrupts while we swap the vector
    move.b  #ACIA_RX_ON,ACIA_MIDI_CTRL
    bclr    #4,MFP_AER          ; GPIP4 (ACIA) must trigger on the falling edge
    bset    #6,MFP_IERB         ; make sure channel 6 is actually enabled
    bset    #6,MFP_IMRB
    move.b  #ISRB_NOT_ACIA,MFP_ISRB   ; clear a stuck in-service bit
    move.l  VEC_ACIA,old_acia
    move.l  #midi_isr,VEC_ACIA
    ; The ACIA interrupt is never actually raised under Hatari's file-based
    ; MIDI -- proven with -DNOPOLL=1, which receives nothing at all. So take
    ; the 200Hz system tick as well and drain from there: that is one sweep
    ; every 5ms instead of one every 14ms frame.
    move.l  VEC_TIMERC,old_tc
    move.l  #timerc_isr,VEC_TIMERC
    ; 200Hz is still far too slow: bytes arrive every 320us. Timer A is free
    ; on a plain ST, so run it at 4kHz purely to empty the ACIA in time.
    move.l  VEC_TIMERA,old_ta
    move.l  #timera_isr,VEC_TIMERA
    clr.b   MFP_TACR
    move.b  #TA_COUNT,MFP_TADR
    move.b  #TA_PRESCALE,MFP_TACR
    bset    #5,MFP_IERA
    bset    #5,MFP_IMRA
    move.b  #ISRA_NOT_TA,MFP_ISRA
    ; A byte already sitting in the 6850 leaves RDRF stuck on, and there is
    ; no fresh edge to interrupt on, so clear it out before we start.
    bsr     drain_acia
    move.w  (sp)+,sr
    rts

remove_midi:
    move.w  sr,-(sp)
    move.w  #$2700,sr
    clr.b   MFP_TACR            ; stop Timer A before giving the vector back
    bclr    #5,MFP_IERA
    move.l  old_ta,VEC_TIMERA
    move.l  old_tc,VEC_TIMERC
    move.l  old_acia,VEC_ACIA
    move.w  (sp)+,sr
    rts

; 4kHz. Nothing else uses Timer A, so this just empties the ACIA and returns.
timera_isr:
    bsr     drain_acia          ; saves and restores what it touches
    move.b  #ISRA_NOT_TA,MFP_ISRA
    rte

; 200Hz system tick. Drain, then hand on to TOS, which needs this for its
; own clock.
timerc_isr:
    if DIAG
    addq.w  #1,tc_ticks
    endif
    bsr     drain_acia          ; saves and restores what it touches
    move.l  old_tc,-(sp)
    rts

;----------------------------------------------------------------------
; Pull whatever is in the 6850 into the ring. Called from the interrupt
; and, as a safety net, once per frame -- if the interrupt never fires we
; still make progress instead of jamming on one unread byte.
;----------------------------------------------------------------------
drain_acia:
    movem.l d0-d1/a0,-(sp)
.lp:
    btst    #0,ACIA_MIDI_CTRL
    beq.s   .out
    move.b  ACIA_MIDI_DATA,d0
    move.w  midi_head,d1
    lea     midi_ring,a0
    move.b  d0,(a0,d1.w)
    addq.w  #1,d1
    and.w   #MIDI_MASK,d1
    cmp.w   midi_tail,d1
    beq.s   .lp                 ; ring full: drop, but keep clearing the 6850
    move.w  d1,midi_head
    bra.s   .lp
.out:
    movem.l (sp)+,d0-d1/a0
    rts

midi_isr:
    if DIAG
    addq.w  #1,isr_hits
    endif
    movem.l d0-d1/a0,-(sp)
.drain:
    btst    #0,ACIA_MIDI_CTRL
    beq.s   .done
    move.b  ACIA_MIDI_DATA,d0
    move.w  midi_head,d1
    lea     midi_ring,a0
    move.b  d0,(a0,d1.w)
    addq.w  #1,d1
    and.w   #MIDI_MASK,d1
    cmp.w   midi_tail,d1
    beq.s   .full               ; would overtake the reader: drop it instead
    move.w  d1,midi_head
.full:
    bra.s   .drain
.done:
    movem.l (sp)+,d0-d1/a0
    move.b  #ISRB_NOT_ACIA,MFP_ISRB   ; software EOI, or this never fires again
    move.l  old_acia,-(sp)
    rts                         ; chain onward; the old handler does the rte

;----------------------------------------------------------------------
wait_vbl:
    move.w  #XB_VSYNC,-(sp)
    trap    #14
    addq.l  #2,sp
    rts

;----------------------------------------------------------------------
; If the VBL counter moved by more than one while we were drawing, the
; last frame did not fit in its budget. This is the honest way to know
; whether an effect is actually affordable on an 8MHz 68000.
;----------------------------------------------------------------------
measure_overrun:
    move.l  VBCLOCK,d0
    move.l  d0,d1
    sub.l   last_vbl,d1
    move.l  d0,last_vbl
    cmp.l   #1,d1
    bls.s   .ok
    addq.w  #1,overrun_acc
.ok:
    addq.w  #1,window_ctr
    cmp.w   #64,window_ctr
    bcs.s   .done
    clr.w   window_ctr
    move.w  overrun_acc,overrun_disp
    clr.w   overrun_acc
    move.w  midi_bytes,midi_disp
    clr.w   midi_bytes
    move.w  acia_seen,acia_disp
    clr.w   acia_seen
    move.w  tc_ticks,tc_disp
    clr.w   tc_ticks
    move.w  isr_hits,isr_disp
    clr.w   isr_hits
.done:
    rts

;----------------------------------------------------------------------
; d0 = address -> ST screen base register (256-byte granularity)
;----------------------------------------------------------------------
set_screen_base:
    move.l  d0,cur_base
    lsr.l   #8,d0
    move.b  d0,SCR_MID
    lsr.l   #8,d0
    move.b  d0,SCR_HI
    rts

;----------------------------------------------------------------------
build_noise_pool:
    lea     noise_pool,a0
    move.l  #$12345678,d0
    move.w  #(POOL_SIZE/4)-1,d7
.lp:
    move.l  d0,d1
    lsl.l   #3,d1
    eor.l   d1,d0
    move.l  d0,d1
    lsr.l   #5,d1
    eor.l   d1,d0
    move.l  d0,d1
    lsl.l   #4,d1
    eor.l   d1,d0
    move.l  d0,(a0)+
    dbra    d7,.lp
    move.l  d0,rng_state
    rts

;----------------------------------------------------------------------
; 256 vertical-stripe patterns, one per "frequency". Laying these down
; row by row with a drifting index is what produces moire.
;----------------------------------------------------------------------
build_stripe_tbl:
    lea     stripe_tbl,a0
    moveq   #0,d2
.outer:
    moveq   #0,d3               ; pattern word
    moveq   #0,d5               ; phase accumulator
    moveq   #15,d4
.bits:
    lsl.w   #1,d3
    move.w  d5,d6
    lsr.w   #4,d6
    btst    #0,d6
    beq.s   .zero
    bset    #0,d3
.zero:
    add.w   d2,d5
    dbra    d4,.bits
    move.w  d3,(a0)+
    addq.w  #1,d2
    cmp.w   #256,d2
    bcs.s   .outer
    rts

;----------------------------------------------------------------------
; a0 = start, a1 = end (exclusive). Span must be a multiple of 32.
;----------------------------------------------------------------------
clear_span:
    moveq   #0,d0
    moveq   #0,d1
    moveq   #0,d2
    moveq   #0,d3
    moveq   #0,d4
    moveq   #0,d5
    moveq   #0,d6
    moveq   #0,d7
.lp:
    movem.l d0-d7,(a0)
    lea     32(a0),a0
    cmp.l   a0,a1
    bhi.s   .lp
    rts

;----------------------------------------------------------------------
; a0 = start, a1 = end, a2 = source. Fastest bulk copy the 68000 has.
;----------------------------------------------------------------------
fill_span:
.lp:
    movem.l (a2)+,d0-d7
    movem.l d0-d7,(a0)
    lea     32(a0),a0
    cmp.l   a0,a1
    bhi.s   .lp
    rts

;----------------------------------------------------------------------
; a0 = start, a1 = end, d0 = longword pattern
;----------------------------------------------------------------------
fill_pattern:
    move.l  d0,d1
    move.l  d0,d2
    move.l  d0,d3
    move.l  d0,d4
    move.l  d0,d5
    move.l  d0,d6
    move.l  d0,d7
.lp:
    movem.l d0-d7,(a0)
    lea     32(a0),a0
    cmp.l   a0,a1
    bhi.s   .lp
    rts

;----------------------------------------------------------------------
clear_visible:
    move.l  cur_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE,a1
    bra     clear_span

;----------------------------------------------------------------------
; scene entry / dispatch
;----------------------------------------------------------------------
scene_enter:
    clr.w   cycle_ctr
    move.l  buf_base,d0
    bsr     set_screen_base
    move.w  #$000,PALETTE_HW    ; mono: colour 0 dark = black bg, white ink
    bsr     clear_visible
    move.w  scene,d0
    lsl.w   #2,d0
    lea     scene_init_tbl,a0
    move.l  (a0,d0.w),a0
    jmp     (a0)

;======================================================================
; SCENE 1 -- BAND
; A noise band whose height is a MIDI-driven envelope. The baseline.
;======================================================================
band_init:
    clr.w   prev_chunks
    rts

band_frame:
    move.w  prev_chunks,d0
    beq.s   .erased
    move.l  prev_ptr,a0
    move.l  a0,a1
    ext.l   d0
    lsl.l   #5,d0
    add.l   d0,a1
    bsr     clear_span
.erased:
    clr.w   prev_chunks

    move.w  level,d0
    and.l   #$ff,d0
    mulu    max_rows,d0
    lsr.l   #8,d0
    and.w   #$fffe,d0
    move.w  d0,d6
    beq.s   .done

    move.w  scr_rows,d1
    sub.w   d6,d1
    lsr.w   #1,d1
    and.w   #$fffe,d1
    mulu    row_bytes,d1
    move.l  cur_base,a0
    add.l   d1,a0

    move.w  d6,d2
    mulu    row_bytes,d2
    move.l  a0,a1
    add.l   d2,a1

    move.l  a0,prev_ptr
    lsr.l   #5,d2
    move.w  d2,prev_chunks

    bsr     next_rng
    move.w  pool_off,d4
    add.w   d3,d4
    and.w   #POOL_MASK,d4
    move.w  d4,pool_off
    lea     noise_pool,a2
    add.w   d4,a2
    bsr     fill_span
.done:
    rts

;======================================================================
; SCENE 0 -- CUBES
;
; A 4x2 grid of wireframe cubes, laid out to match the pads on the
; controller: pad 1 is top-left, pad 8 is bottom-right. Hitting a pad
; pulses its cube; velocity sets how big it swells and how fast it spins,
; and the swell decays back down.
;
; The rotation is not computed here. Line-drawing 8 cubes would cost about
; 90k of the frame's ~112k cycles before erasing anything, so the frames are
; baked into sprites by tools/gencubes.py and the ST only copies them. Each
; tile is opaque and covers the cube's whole box, so there is no erase pass:
; one write per cube per frame.
;
; Glitches ride on velocity. A hard hit tears that cube horizontally -- the
; destination address is nudged sideways every 8 rows while it blits. Hit
; harder still and the whole picture slips, which costs nothing because it
; is only the screen base register moving.
;======================================================================
cubes_init:
    ; the grid: four cells across, two down
    move.w  row_bytes,d5
    lsr.w   #2,d5               ; cell width in bytes (20 in mono)
    move.w  scr_rows,d6
    lsr.w   #1,d6               ; cell height in rows (200 in mono)
    move.w  d5,d2
    sub.w   #CUBE_W_BYTES,d2
    lsr.w   #1,d2               ; box x offset inside the cell
    move.w  d6,d3
    sub.w   #CUBE_H,d3
    lsr.w   #1,d3               ; box y offset inside the cell

    lea     cube_org,a0
    moveq   #0,d4
.mk:
    move.w  d4,d0
    and.w   #3,d0
    mulu    d5,d0
    add.w   d2,d0
    and.l   #$ffff,d0           ; byte within the row
    move.w  d4,d1
    lsr.w   #2,d1
    mulu    d6,d1
    add.w   d3,d1
    and.l   #$ffff,d1
    mulu    row_bytes,d1        ; -> byte offset of the box top
    add.l   d0,d1
    move.l  buf_base,a1
    add.l   d1,a1
    move.l  a1,(a0)+
    addq.w  #1,d4
    cmp.w   #8,d4
    bcs.s   .mk

    ; clear a little past the visible screen so the shear glitch slides
    ; black into view rather than whatever the last scene left behind
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1
    bsr     clear_span

    lea     cube_level,a0
    moveq   #(8*3)-1,d0         ; level, angle and glitch, 8 words each
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    clr.w   cubes_idle
    rts

cubes_frame:
    ; with nothing plugged in, punch cubes at random so the screen lives
    cmp.w   #150,idle_ticks
    bcs.s   .nofree
    addq.w  #1,cubes_idle
    cmp.w   #14,cubes_idle
    bcs.s   .nofree
    clr.w   cubes_idle
    bsr     next_rng
    move.w  d3,d0
    and.w   #7,d0
    add.w   d0,d0
    lea     cube_level,a0
    move.w  #$ff,(a0,d0.w)
.nofree:

    moveq   #0,d7
.each:
    move.w  d7,d0
    add.w   d0,d0               ; word index

    ; --- swell decays back down
    lea     cube_level,a0
    move.w  (a0,d0.w),d1
    sub.w   #CUBE_DECAY,d1
    bpl.s   .lv
    moveq   #0,d1
.lv:
    move.w  d1,(a0,d0.w)

    ; --- spin: always turning, faster while it is swollen
    lea     cube_angle,a0
    move.w  (a0,d0.w),d2
    move.w  d1,d3
    lsr.w   #4,d3
    addq.w  #6,d3
    add.w   d3,d2
    move.w  d2,(a0,d0.w)

    ; --- glitch runs out on its own
    lea     cube_glitch,a0
    move.w  (a0,d0.w),d4
    beq.s   .noglitch
    subq.w  #1,d4
    move.w  d4,(a0,d0.w)
.noglitch:

    ; --- which sprite: scale from the swell, angle from the spin
    move.w  d1,d5
    lsr.w   #5,d5
    cmp.w   #CUBE_SCALES,d5
    bcs.s   .sok
    moveq   #CUBE_SCALES-1,d5
.sok:
    move.w  d2,d6
    lsr.w   #8,d6
    and.w   #CUBE_ANGLES-1,d6
    mulu    #CUBE_ANGLES,d5
    add.w   d6,d5
    mulu    #CUBE_SPRITE,d5
    lea     cube_data,a1
    add.l   d5,a1

    move.w  d7,d6
    lsl.w   #2,d6
    lea     cube_org,a0
    move.l  (a0,d6.w),a0

    if FORCEGLITCH
    bsr     blit_cube_glitch
    bra.s   .next
    endif
    tst.w   d4
    bne.s   .torn
    bsr     blit_cube
    bra.s   .next
.torn:
    bsr     blit_cube_glitch
.next:
    addq.w  #1,d7
    cmp.w   #8,d7
    bcs     .each

    ; --- whole-picture shear. Two byte writes, so it is free.
    ; Fired as a short burst when the playing gets dense, then locked out.
    ; Held on continuously it just reads as broken sync; as an accent it lands.
    tst.w   shear_cool
    beq.s   .cooled
    subq.w  #1,shear_cool
.cooled:
    tst.w   shear_ctr
    bne.s   .armed
    tst.w   shear_cool
    bne.s   .armed
    cmp.w   #SHEAR_VEL,level
    bcs.s   .armed
    move.w  #6,shear_ctr
    move.w  #45,shear_cool
.armed:
    move.l  buf_base,d0
    tst.w   shear_ctr
    beq.s   .setbase
    subq.w  #1,shear_ctr
    bsr     next_rng            ; leaves d0 alone
    move.w  d3,d1
    and.w   #3,d1
    lsl.w   #8,d1
    and.l   #$ffff,d1
    add.l   d1,d0
.setbase:
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
; a0 = destination on screen, a1 = sprite. Tiles are opaque, so this is
; the only write the cube needs -- nothing to erase first.
;----------------------------------------------------------------------
blit_cube:
    movem.l d0-d7/a0-a3,-(sp)
    move.w  row_bytes,d1
    move.w  #CUBE_H-1,d0
.row:
    move.l  (a1)+,(a0)
    move.l  (a1)+,4(a0)
    move.l  (a1)+,8(a0)
    adda.w  d1,a0
    dbra    d0,.row
    movem.l (sp)+,d0-d7/a0-a3
    rts

;----------------------------------------------------------------------
; Same, but the destination slides sideways a few bytes every 8 rows, so
; the cube comes out sheared into horizontal slabs.
;----------------------------------------------------------------------
blit_cube_glitch:
    movem.l d0-d7/a0-a3,-(sp)
    move.w  row_bytes,d1
    move.l  a0,a3               ; destination box -- deliberately fixed
    moveq   #(CUBE_H/8)-1,d0    ; twelve blocks of eight rows
.blk:
    bsr     next_rng            ; only touches d3/d4
    move.w  d3,d5
    and.w   #7,d5
    subq.w  #4,d5
    add.w   d5,d5               ; -8..+6 bytes, and EVEN: a move.l to an odd
                                ; address is an address error on a 68000
    ; Shift what we read, not where we write. Moving the destination would
    ; smear pixels outside the box, and nothing ever erases out there.
    move.l  a1,a2
    adda.w  d5,a2
    moveq   #7,d6
.row:
    move.l  (a2)+,(a3)
    move.l  (a2)+,4(a3)
    move.l  (a2)+,8(a3)
    adda.w  d1,a3
    dbra    d6,.row
    lea     (CUBE_W_BYTES*8)(a1),a1
    dbra    d0,.blk
    movem.l (sp)+,d0-d7/a0-a3
    rts

;======================================================================
; SCENE 1 -- MOIRE FIELD   (the chosen scene)
;
; Scrolling on a plain ST means moving the screen base register, and there
; is only one of those -- so everything on screen scrolls together. There is
; no way to hold a static layer over a moving one in a single framebuffer.
;
; So instead of drawing moire *over* the scroll, we generate it *into* the
; leading edge of the field. Each frame only the newly exposed strip is
; written; everything already on screen just slides. The vertical axis stops
; being space and becomes time: what you see is the last two seconds of the
; pattern's history, flowing past.
;
; That also makes it far cheaper than redrawing half the screen -- at one
; page per frame it is 512 bytes instead of 16000.
;
; Two details make it seamless:
;   * the base register steps 256 bytes = 3 rows + 128 pixels of shear. The
;     stripe patterns repeat every 16 pixels, and 128 is a whole number of
;     those, so the shear is invisible by construction.
;   * the window wraps after 128 pages, so every page below 125 is written
;     twice -- once at p, once at p+128. The jump back lands on identical
;     bytes and cannot be seen.
;======================================================================
field_init:
    clr.w   base_page
    clr.l   moire_idx
    move.w  #1024,field_step
    ; generate pages 0..127; the mirroring writes 128..252 as a side effect,
    ; so this fills the whole buffer
    moveq   #0,d0
.gen:
    bsr     write_page_mirrored
    addq.w  #1,d0
    cmp.w   #RANGE_PAGES,d0
    bcs.s   .gen
    rts

field_frame:
    ; speed comes from the envelope -- silence freezes the picture, and a
    ; frozen picture costs nothing at all
    move.w  level,d0
    lsr.w   #5,d0
    beq     .frozen
    move.w  d0,d7

    move.w  base_page,d1
    add.w   d7,d1
    cmp.w   #RANGE_PAGES,d1
    bcs.s   .nowrap
    sub.w   #RANGE_PAGES,d1
.nowrap:
    move.w  d1,base_page

    ; write the strip the scroll just uncovered at the bottom of the window
    move.w  d1,d2
    add.w   #SCR_PAGES,d2
    sub.w   d7,d2
    move.w  d7,d6
    subq.w  #1,d6
.pg:
    move.w  d2,d0
    bsr     write_page_mirrored
    addq.w  #1,d2
    dbra    d6,.pg

    move.l  buf_base,d0
    move.w  base_page,d1
    and.l   #$ffff,d1
    lsl.l   #8,d1
    add.l   d1,d0
    bsr     set_screen_base
.frozen:
    rts

;----------------------------------------------------------------------
; d0.w = page, d1.w = pattern word. Fills one 256-byte page.
;----------------------------------------------------------------------
fill_page:
    movem.l d0-d7/a0-a2,-(sp)
    and.l   #$ffff,d0
    lsl.l   #8,d0
    move.l  buf_base,a0
    add.l   d0,a0
    move.l  a0,a1
    add.l   #256,a1
    move.w  d1,d0
    swap    d0
    move.w  d1,d0
    bsr     fill_pattern
    movem.l (sp)+,d0-d7/a0-a2
    rts

;----------------------------------------------------------------------
; d0.w = page, d1.w = byte offset into the noise pool.
;----------------------------------------------------------------------
fill_page_noise:
    movem.l d0-d7/a0-a2,-(sp)
    and.l   #$ffff,d0
    lsl.l   #8,d0
    move.l  buf_base,a0
    add.l   d0,a0
    move.l  a0,a1
    add.l   #256,a1
    lea     noise_pool,a2
    and.l   #$ffff,d1
    add.l   d1,a2
    bsr     fill_span
    movem.l (sp)+,d0-d7/a0-a2
    rts

;----------------------------------------------------------------------
; d0.w = page. Writes it and its mirror with identical content, then
; advances the pattern index. A hard hit writes noise instead of stripes,
; so the hit stays visible as a band scrolling away behind the beat.
;----------------------------------------------------------------------
write_page_mirrored:
    movem.l d0-d7/a0-a2,-(sp)
    move.w  d0,d6               ; page number. NOT d3/d4 -- next_rng clobbers those
    cmp.w   #NOISE_HIT,level
    bcs.s   .stripes
    bsr     next_rng
    move.w  pool_off,d4
    add.w   d3,d4
    and.w   #POOL_MASK,d4
    move.w  d4,pool_off
    st      d5                  ; flag: this page is noise
    bra.s   .have

.stripes:
    move.l  moire_idx,d1
    lsr.l   #8,d1
    and.w   #$ff,d1
    add.w   d1,d1
    lea     stripe_tbl,a2
    move.w  (a2,d1.w),d4
    clr.b   d5
.have:
    move.w  field_step,d1
    ext.l   d1
    add.l   d1,moire_idx

    move.w  d6,d0
    move.w  d4,d1
    bsr     .emit

    cmp.w   #SCR_PAGES,d6
    bcc.s   .high
    move.w  d6,d0
    add.w   #RANGE_PAGES,d0
    move.w  d4,d1
    bsr     .emit
    bra.s   .done
.high:
    cmp.w   #RANGE_PAGES,d6
    bcs.s   .done               ; pages 125..127 are never mirrored
    move.w  d6,d0
    sub.w   #RANGE_PAGES,d0
    move.w  d4,d1
    bsr     .emit
.done:
    movem.l (sp)+,d0-d7/a0-a2
    rts
.emit:
    tst.b   d5
    bne.s   .noise
    bra     fill_page
.noise:
    bra     fill_page_noise

;======================================================================
; SCENE 3 -- MOIRE
; Each pair of rows gets one repeating 16-bit stripe pattern, indexed by
; an accumulator that drifts down the screen. Two nearby frequencies beat
; against each other and you get interference bands. Half the screen is
; redrawn per frame to stay inside the budget; at 71Hz the alternation
; reads as shimmer rather than flicker.
;======================================================================
moire_init:
    clr.w   moire_half
    move.w  #$0140,moire_step
    clr.w   moire_phase
    rts

moire_frame:
    move.w  moire_phase,d0
    add.w   #$0060,d0
    move.w  d0,moire_phase

    move.w  moire_half,d0
    eor.w   #1,moire_half
    move.w  half_rows,d1
    mulu    d0,d1               ; start row
    move.w  d1,d2
    mulu    row_bytes,d2
    move.l  cur_base,a3
    add.l   d2,a3               ; a3 = dest row pointer

    ; index accumulator = phase + startrow*step
    move.w  moire_step,d4
    mulu    d4,d1
    add.w   moire_phase,d1
    move.w  d1,d5               ; d5 = running index

    move.w  half_rows,d6
    lsr.w   #1,d6               ; row pairs to draw
    subq.w  #1,d6

    move.w  row_bytes,d7
    add.w   d7,d7               ; bytes per row pair
    ext.l   d7

    lea     stripe_tbl,a4
.rowpair:
    move.w  d5,d0
    lsr.w   #8,d0
    add.w   d0,d0
    move.w  (a4,d0.w),d0        ; stripe pattern word
    move.w  d0,d1
    swap    d1
    move.w  d0,d1               ; duplicate into a longword

    movem.l d4-d7/a3-a4,-(sp)
    move.l  a3,a0
    move.l  a3,a1
    add.l   d7,a1
    move.l  d1,d0
    bsr     fill_pattern
    movem.l (sp)+,d4-d7/a3-a4

    add.l   d7,a3
    add.w   d4,d5
    add.w   d4,d5
    dbra    d6,.rowpair
    rts

;======================================================================
; SCENE 4 -- STROBE
; A static moire plate, flipped black-for-white by rewriting palette
; register 0. In ST mono that one register inverts the entire display,
; so a full-screen strobe costs a single word write per frame.
;
; NOTE: full-screen flashing is a photosensitive-seizure risk. This is
; deliberately gated on the envelope and limited to ~12Hz rather than
; free-running at 71Hz. See the README before using it in front of an
; audience.
;======================================================================
strobe_init:
    clr.w   strobe_ctr
    ; lay down a static plate: stripe patterns straight down the screen
    move.l  cur_base,a3
    move.w  scr_rows,d6
    lsr.w   #1,d6
    subq.w  #1,d6
    move.w  row_bytes,d7
    add.w   d7,d7
    ext.l   d7
    moveq   #0,d5
    lea     stripe_tbl,a4
.rowpair:
    move.w  d5,d0
    lsr.w   #8,d0
    add.w   d0,d0
    move.w  (a4,d0.w),d0
    move.w  d0,d1
    swap    d1
    move.w  d0,d1

    movem.l d5-d7/a3-a4,-(sp)
    move.l  a3,a0
    move.l  a3,a1
    add.l   d7,a1
    move.l  d1,d0
    bsr     fill_pattern
    movem.l (sp)+,d5-d7/a3-a4

    add.l   d7,a3
    add.w   #$01c0,d5
    dbra    d6,.rowpair
    rts

strobe_frame:
    addq.w  #1,strobe_ctr
    move.w  level,d0
    beq.s   .normal
    move.w  strobe_ctr,d1
    and.w   #3,d1
    bne.s   .hold
    move.w  invert_flag,d1
    eor.w   #1,d1
    move.w  d1,invert_flag
.hold:
    tst.w   invert_flag
    beq.s   .normal
    move.w  #$777,PALETTE_HW
    rts
.normal:
    move.w  #$000,PALETTE_HW
    rts

;======================================================================
; shared bits
;======================================================================
next_rng:
    move.l  rng_state,d3
    move.l  d3,d4
    lsl.l   #3,d4
    eor.l   d4,d3
    move.l  d3,d4
    lsr.l   #5,d4
    eor.l   d4,d3
    move.l  d3,rng_state
    rts

decay_level:
    cmp.w   #150,idle_ticks
    bcc.s   .freerun
    addq.w  #1,idle_ticks
    bra.s   .decay
.freerun:
    addq.w  #1,demo_ctr
    cmp.w   #25,demo_ctr
    bcs.s   .decay
    clr.w   demo_ctr
    move.w  #$ff,level
.decay:
    move.w  level,d0
    sub.w   #LEVEL_DECAY,d0
    bpl.s   .ok
    moveq   #0,d0
.ok:
    move.w  d0,level
    rts

do_auto_cycle:
    tst.w   auto_cycle
    beq.s   .no
    addq.w  #1,cycle_ctr
    cmp.w   #CYCLE_FRAMES,cycle_ctr
    bcs.s   .no
    move.w  scene,d0
    addq.w  #1,d0
    cmp.w   #SC_COUNT,d0
    bcs.s   .ok
    moveq   #0,d0
.ok:
    move.w  d0,scene
    bsr     scene_enter
.no:
    rts

    if DIAG
; a bar along the top row: one byte per overrun in the last 64 frames
draw_overrun_bar:
    move.l  cur_base,a0
    ; blank the top row first, so the bar is the only thing on it and can be
    ; read back out of a screen capture whatever the scene is painting
    move.l  a0,a1
    move.w  row_bytes,d0
    lsr.w   #2,d0
    subq.w  #1,d0
    moveq   #0,d1
.clr:
    move.l  d1,(a1)+
    dbra    d0,.clr
    moveq   #0,d1
    move.w  overrun_disp,d1
    beq.s   .none
    cmp.w   #64,d1
    bcs.s   .ok
    moveq   #64,d1
.ok:
    subq.w  #1,d1
.lp:
    move.b  #$ff,(a0)+
    dbra    d1,.lp
.none:
    ; second bar, four rows down: MIDI bytes consumed in the last 64 frames.
    ; Empty here means nothing is reaching the ACIA at all.
    move.l  cur_base,a0
    move.w  row_bytes,d0
    lsl.w   #2,d0
    adda.w  d0,a0
    move.l  a0,a1
    move.w  row_bytes,d0
    lsr.w   #2,d0
    subq.w  #1,d0
    moveq   #0,d1
.clr2:
    move.l  d1,(a1)+
    dbra    d0,.clr2
    move.w  midi_disp,d1
    beq.s   .none2
    cmp.w   #64,d1
    bcs.s   .ok2
    moveq   #64,d1
.ok2:
    subq.w  #1,d1
.lp2:
    move.b  #$ff,(a0)+
    dbra    d1,.lp2
.none2:
    ; third bar, eight rows down: bytes seen sitting in the 6850 itself.
    ; Lit here but bar two empty means TOS is eating them.
    move.l  cur_base,a0
    move.w  row_bytes,d0
    lsl.w   #3,d0
    adda.w  d0,a0
    move.l  a0,a1
    move.w  row_bytes,d0
    lsr.w   #2,d0
    subq.w  #1,d0
    moveq   #0,d1
.clr3:
    move.l  d1,(a1)+
    dbra    d0,.clr3
    move.w  acia_disp,d1
    beq.s   .none3
    cmp.w   #64,d1
    bcs.s   .ok3
    moveq   #64,d1
.ok3:
    subq.w  #1,d1
.lp3:
    move.b  #$ff,(a0)+
    dbra    d1,.lp3
.none3:
    ; fourth bar, twelve rows down: 200Hz timer ticks. Full means the hook
    ; is firing; empty means it never runs and any conclusion drawn from it
    ; is worthless.
    move.l  cur_base,a0
    move.w  row_bytes,d0
    mulu    #12,d0
    adda.w  d0,a0
    move.l  a0,a1
    move.w  row_bytes,d0
    lsr.w   #2,d0
    subq.w  #1,d0
    moveq   #0,d1
.clr4:
    move.l  d1,(a1)+
    dbra    d0,.clr4
    move.w  isr_disp,d1
    beq.s   .none4
    cmp.w   #64,d1
    bcs.s   .ok4
    moveq   #64,d1
.ok4:
    subq.w  #1,d1
.lp4:
    move.b  #$ff,(a0)+
    dbra    d1,.lp4
.none4:
    rts
    endif

;----------------------------------------------------------------------
poll_midi:
    if NOPOLL=0
    move.w  sr,-(sp)
    move.w  #$2700,sr           ; keep the ISR out while we touch midi_head
    bsr     drain_acia
    move.w  (sp)+,sr
    endif
.next:
    move.w  midi_tail,d1
    cmp.w   midi_head,d1
    beq     .empty
    lea     midi_ring,a0
    moveq   #0,d0
    move.b  (a0,d1.w),d0
    addq.w  #1,d1
    and.w   #MIDI_MASK,d1
    move.w  d1,midi_tail
    addq.w  #1,midi_bytes

    and.w   #$ff,d0
    cmp.b   #$f8,d0
    bcc     .realtime
    btst    #7,d0
    bne.s   .status
    bra.s   .data

.status:
    move.b  d0,midi_status
    clr.w   midi_count
    bra     .next

.data:
    move.w  midi_count,d1
    bne.s   .second
    move.b  d0,midi_d1
    move.w  #1,midi_count
    bra     .next
.second:
    clr.w   midi_count
    move.b  midi_status,d1
    and.b   #$f0,d1
    cmp.b   #$90,d1
    bne     .next
    tst.b   d0
    beq     .next
    ; velocity through the curve
    and.w   #$7f,d0
    lea     vel_tbl,a0
    move.b  (a0,d0.w),d0
    and.w   #$ff,d0             ; d0 = curved strength, 0..255

    ; The global level ACCUMULATES rather than being replaced, so it tracks
    ; how hard you are playing overall. Single-hit velocity tops out at 127
    ; and cannot tell a hard hit from a very hard one; density can.
    move.w  d0,d1
    lsr.w   #1,d1
    add.w   level,d1
    cmp.w   #$ff,d1
    bcs.s   .noclip
    move.w  #$ff,d1
.noclip:
    move.w  d1,level
    clr.w   idle_ticks
    ; note number nudges the moire frequency, so pitch changes the pattern
    moveq   #0,d1
    move.b  midi_d1,d1
    move.w  d1,d2
    lsl.w   #3,d2
    add.w   #$0080,d2
    move.w  d2,moire_step       ; legacy moire scene
    ; Pads, not pitch: fold the note onto one of 8 slots. Masking with 7
    ; means any run of 8 notes lands on 8 distinct patterns, so this works
    ; whatever the controller's base note happens to be.
    sub.w   #PAD_BASE,d1
    and.w   #7,d1
    add.w   d1,d1               ; d1 = pad index * 2
    lea     pad_tbl,a0
    move.w  (a0,d1.w),d2
    move.w  d2,field_step
    ; cubes scene: swell the matching cube, and tear it on a hard hit
    lea     cube_level,a0
    move.w  d0,(a0,d1.w)
    cmp.w   #GLITCH_VEL,d0
    bcs     .next
    lea     cube_glitch,a0
    move.w  #GLITCH_FRAMES,(a0,d1.w)
    bra     .next

.realtime:
    cmp.b   #$f8,d0
    bne     .next
    move.w  level,d1
    cmp.w   #$40,d1
    bcc     .next
    move.w  #$40,level
    clr.w   idle_ticks
    bra     .next

.empty:
    rts

;----------------------------------------------------------------------
poll_keyboard:
    move.w  #GD_CCONIS,-(sp)
    trap    #1
    addq.l  #2,sp
    tst.w   d0
    beq.s   .none

    move.w  #GD_CNECIN,-(sp)
    trap    #1
    addq.l  #2,sp

    cmp.b   #27,d0
    beq.s   .quit
    cmp.b   #'0',d0
    beq.s   .setauto
    cmp.b   #'1',d0
    bcs.s   .hit
    cmp.b   #'5'+1,d0
    bcc.s   .hit
    ; 1..4 -> pick a scene by hand
    and.w   #$ff,d0
    sub.w   #'1',d0
    move.w  d0,scene
    clr.w   auto_cycle
    bsr     scene_enter
    rts
.setauto:
    move.w  #1,auto_cycle
    rts
.hit:
    move.w  #$ff,level
    clr.w   idle_ticks
.none:
    rts
.quit:
    move.w  #1,quit_flag
    rts

;----------------------------------------------------------------------
    section data
    even
scene_init_tbl:
    dc.l    cubes_init, field_init, moire_init, band_init, strobe_init
scene_frame_tbl:
    dc.l    cubes_frame, field_frame, moire_frame, band_frame, strobe_frame
; one stripe frequency per pad, spread wide enough to read as 8 different
; pictures rather than eight shades of the same one
pad_tbl:
    dc.w    128, 256, 512, 896, 1280, 1792, 2560, 3584
    even
; Velocity curve. MPK pads bunch their dynamics up at the bottom -- a real
; take gave 11,18,26,33,37,41,52,83,93,101 and then six hits pinned at 127 --
; so a linear map wastes the whole soft half and saturates the top. This is
; 255*(v/127)^0.65, which lifts a gentle tap into something visible.
vel_tbl:
    dc.b      0, 11, 17, 22, 27, 31, 35, 39, 42, 46, 49, 52, 55, 58, 61, 64
    dc.b     66, 69, 72, 74, 77, 79, 82, 84, 86, 89, 91, 93, 95, 98,100,102
    dc.b    104,106,108,110,112,114,116,118,120,122,124,126,128,130,132,134
    dc.b    135,137,139,141,143,144,146,148,150,151,153,155,157,158,160,162
    dc.b    163,165,167,168,170,172,173,175,176,178,180,181,183,184,186,187
    dc.b    189,190,192,193,195,196,198,199,201,202,204,205,207,208,210,211
    dc.b    213,214,215,217,218,220,221,223,224,225,227,228,230,231,232,234
    dc.b    235,236,238,239,240,242,243,244,246,247,248,250,251,252,254,255
    even
cube_data:
    incbin  "src/cubes.bin"
new_pal:
    dc.w    $000,$777,$111,$666,$222,$555,$333,$444
    dc.w    $700,$070,$007,$770,$707,$077,$444,$777

    section bss
    even
old_ssp:        ds.l 1
old_acia:       ds.l 1
old_tc:         ds.l 1
old_ta:         ds.l 1
old_phys:       ds.l 1
buf_base:       ds.l 1
cur_base:       ds.l 1
prev_ptr:       ds.l 1
rng_state:      ds.l 1
moire_idx:      ds.l 1
last_vbl:       ds.l 1
rez:            ds.w 1
row_bytes:      ds.w 1
scr_rows:       ds.w 1
half_rows:      ds.w 1
max_rows:       ds.w 1
level:          ds.w 1
prev_chunks:    ds.w 1
pool_off:       ds.w 1
quit_flag:      ds.w 1
midi_count:     ds.w 1
idle_ticks:     ds.w 1
demo_ctr:       ds.w 1
scene:          ds.w 1
auto_cycle:     ds.w 1
cycle_ctr:      ds.w 1
base_page:      ds.w 1
field_step:     ds.w 1
cubes_idle:     ds.w 1
shear_ctr:      ds.w 1
shear_cool:     ds.w 1
moire_half:     ds.w 1
moire_step:     ds.w 1
moire_phase:    ds.w 1
strobe_ctr:     ds.w 1
invert_flag:    ds.w 1
overrun_acc:    ds.w 1
midi_bytes:     ds.w 1
midi_disp:      ds.w 1
midi_head:      ds.w 1
midi_tail:      ds.w 1
acia_seen:      ds.w 1
acia_disp:      ds.w 1
tc_ticks:       ds.w 1
tc_disp:        ds.w 1
isr_hits:       ds.w 1
isr_disp:       ds.w 1
overrun_disp:   ds.w 1
window_ctr:     ds.w 1
midi_status:    ds.b 1
midi_d1:        ds.b 1
    even
midi_ring:      ds.b MIDI_RING
    even
cube_level:     ds.w 8
cube_angle:     ds.w 8
cube_glitch:    ds.w 8
    even
cube_org:       ds.l 8
    even
old_pal:        ds.w 16
stripe_tbl:     ds.w 256
    even
noise_pool:     ds.b POOL_SIZE
    even
screen_mem:     ds.b BUF_TOTAL+256
