;======================================================================
;  NOISE AV core -- the half that is the same in every show.
;
;  A show is a source file in src/shows/ that includes this, then supplies
;  three entry points, then includes core/tail.s:
;
;      show_init       once, after the screen is set up and cleared
;      show_frame      once per vertical blank
;      show_note_on    d0 = strength 0..255 (velocity through the curve)
;                      d1 = pad index * 2, ready for a word-indexed table
;
;  Everything else -- taking over the machine, the MIDI ACIA and its ring
;  buffer, the timers, the envelope, the diagnostics -- lives here
;  Atari ST (68000 @ 8MHz, plain 1040 STF, SM124 mono 640x400 @ 71Hz)
;
;  Keys:  ESC = quit, Z = the strobe on and off, any other key = a manual
;         hit, so a show can be driven with no MIDI plugged in. A
;         multi-scene build defines SCENES and takes 1-9 for itself.
;
;  MIDI:  notes anywhere but the control channel are hits. On CTRL_CH a
;         note is a COMMAND -- its number is the code and its velocity the
;         strength to enter with -- a controller is a parameter, and
;         transport start puts the show back to a known state.
;
;  Build with -DDIAG=1 for the frame-budget overrun bar, -DSTROBE=1 to
;  boot with the strobe already running, -DACIABAR=1 to point bar three at
;  the 6850 itself rather than at the show's own counter.
;======================================================================

    ifd CORE_HEAD_DONE          ; a multi-scene build includes this once and
    section text                ; each scene file's own include lands here
    else
CORE_HEAD_DONE  equ 1

    ifnd DIAG
DIAG        equ 0
    endif
    ; Lowest pad note. Akai MPK Mini mk3 bank A starts at 36, mk2 at 48.
    ; Any contiguous run of 8 notes still gives 8 distinct looks whatever
    ; this is set to -- a wrong base only rotates which pad is which.
    ifnd CTRL_CH                ; commands arrive on a channel of their own,
CTRL_CH     equ 16              ; which is one Live track, so muting them
    endif                       ; leaves the hits playing
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
GD_FOPEN    equ $3d
GD_FCLOSE   equ $3e
GD_FREAD    equ $3f

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
    ifnd RANGE_PAGES            ; a show with no scrolling can shrink this
RANGE_PAGES equ 128             ; how far the window may travel before wrapping
    endif
BUF_PAGES   equ SCR_PAGES+RANGE_PAGES
BUF_TOTAL   equ BUF_PAGES*256

NOISE_HIT   equ $e8             ; only the very top of the envelope punches noise

    ; A show that uses neither the noise pool nor the tall scroll buffer can
    ; shrink them and spend the memory on its own data instead.
    ifnd POOL_SIZE
POOL_SIZE   equ 32768
    endif
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

    pea     new_pal
    move.w  #XB_SETPAL,-(sp)
    trap    #14
    addq.l  #6,sp

    ; hand the machine to the show
    move.l  buf_base,d0
    bsr     set_screen_base
    move.w  #$000,PALETTE_HW    ; mono: colour 0 dark = black ground, white ink
    bsr     fx_reset
    move.w  #STROBE_HALF,strobe_per
    move.w  #12,nz_count
    ifd STROBE
    move.w  #1,strobe_on        ; boot strobing, for measuring without a key
    endif
    bsr     clear_visible
    bsr     show_init

;----------------------------------------------------------------------
mainloop:
    bsr     wait_vbl
    if FAKEMIDI
    addq.w  #1,midi_bytes
    endif
    bsr     measure_overrun

    tst.w   fx_freeze           ; a held freeze stops the show where it is
    bne.s   .frozen
    bsr     show_frame
.frozen:
    bsr     fx_frame            ; after the show, so it owns the palette

    ; The base register is latched per frame, so what is painted at the end
    ; of a pass is what the beam shows during the NEXT one. Undoing it at the
    ; top of that next pass therefore takes it off before it has ever been
    ; seen -- which is exactly what happened, and only the odd stripe
    ; survived. Both go at the end instead, undo first and paint after: the
    ; scene always draws into the buffer that is NOT on screen, so restoring
    ; the one that IS can never land on fresh drawing.
    bsr     fx_noise_restore
    bsr     fx_noise_paint

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

    endif
