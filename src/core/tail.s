    ifnd CORE_TAIL_DONE         ; included once however many scenes ask
CORE_TAIL_DONE  equ 1

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
    move.w  d1,isr_disp         ; bar four: frames the last pass took. With
                                ; a show that draws N things a pass this is
                                ; the only readout finer than a whole frame
    cmp.l   #1,d1
    bls.s   .ok
    addq.w  #1,overrun_acc
.ok:
    add.w   d1,window_ctr       ; count FRAMES, not passes
    cmp.w   #64,window_ctr
    bcs.s   .done
    clr.w   window_ctr
    move.w  overrun_acc,overrun_disp
    clr.w   overrun_acc
    move.w  midi_bytes,midi_disp
    clr.w   midi_bytes
    move.w  acia_seen,acia_disp
    clr.w   acia_seen
    move.w  show_ctr,acia_disp  ; bar three is the show's own counter
    clr.w   show_ctr
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
    move.b  midi_status,d1      ; program change and channel pressure carry
    and.b   #$f0,d1             ; ONE data byte, so they are complete here.
    cmp.b   #$c0,d1             ; Leaving midi_count alone is the whole trick:
    beq     .prog               ; under running status every following byte is
    cmp.b   #$d0,d1             ; another message of the same kind, and a
    beq     .next               ; counter would pair them up and desynchronise
    move.w  midi_count,d1
    bne.s   .second
    move.b  d0,midi_d1
    move.w  #1,midi_count
    bra     .next
.second:
    clr.w   midi_count
    move.b  midi_status,d2      ; the CHANNEL is the surface, not a note range:
    move.b  d2,d1               ; one Live track per role, and muting the
    and.b   #$f0,d1             ; commands leaves the hits playing
    and.b   #$0f,d2
    cmp.b   #$b0,d1
    beq     .ctl
    cmp.b   #$80,d1
    beq     .off
    cmp.b   #$90,d1
    bne     .next
    tst.b   d0
    beq     .off                ; note-on at velocity 0 IS a note-off
    cmp.b   #CTRL_CH-1,d2
    beq     .cmd
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
    ; Pads, not pitch: fold the note onto one of 8 slots. Masking with 7
    ; means any run of 8 notes lands on 8 distinct slots, so this works
    ; whatever the controller's base note happens to be.
    moveq   #0,d1
    move.b  midi_d1,d1
    sub.w   #PAD_BASE,d1
    and.w   #7,d1
    add.w   d1,d1               ; d1 = pad index * 2
    bsr     show_note_on        ; d0 = strength, d1 = pad*2
    bra     .next

.cmd:                           ; a command carries a code AND a strength, so
    and.w   #$7f,d0             ; entering a scene can arrive already running
    lea     vel_tbl,a0
    move.b  (a0,d0.w),d0
    and.w   #$ff,d0
    moveq   #0,d1
    move.b  midi_d1,d1
    bsr     cmd_press
    bra     .next
.off:
    cmp.b   #CTRL_CH-1,d2
    bne     .next
    moveq   #0,d1
    move.b  midi_d1,d1
    bsr     cmd_release
    bra     .next
.ctl:
    cmp.b   #CTRL_CH-1,d2
    bne     .next
    moveq   #0,d1
    move.b  midi_d1,d1          ; controller number
    bsr     cmd_cc
    bra     .next
.prog:                          ; the payload is this one byte; no strength
    move.b  midi_status,d1
    and.b   #$0f,d1
    cmp.b   #CTRL_CH-1,d1
    bne     .next
    moveq   #0,d1
    move.b  d0,d1
    moveq   #0,d0
    bsr     cmd_press
    bra     .next

.realtime:
    cmp.b   #$fa,d0
    beq     .start
    cmp.b   #$fc,d0
    beq     .stop
    cmp.b   #$f8,d0
    bne     .next
    addq.w  #1,clk_tick         ; 24 ppqn: the beat is what a tempo-locked
    cmp.w   #24,clk_tick        ; effect counts, not the frame
    bcs.s   .notick
    clr.w   clk_tick
    addq.w  #1,clk_beat
    bsr     fx_beat
.notick:
    move.w  level,d1
    cmp.w   #$40,d1
    bcc     .next
    move.w  #$40,level
    clr.w   idle_ticks
    bra     .next
.start:                         ; the arrangement drives the scenes, so play
    clr.w   clk_tick            ; has to mean "back to a known state" -- without
    clr.w   clk_beat            ; it a stop leaves the tape and the screen
    bsr     fx_reset            ; disagreeing about what is on
    ifd SCENES
    moveq   #0,d0
    moveq   #0,d1
    bsr     scene_select
    endif
    bra     .next
.stop:
    bsr     fx_reset            ; a held effect whose note-off never comes
    bra     .next               ; would otherwise stay on for good

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
    move.w  d0,d1
    and.w   #$ff,d1
    cmp.w   #'z',d1             ; the strobe, before the catch-all hit below
    beq.s   .strobe
    cmp.w   #'Z',d1
    beq.s   .strobe
    ifd SCENES
    move.w  d0,d1               ; 1..9 pick a scene; a standalone show has
    and.w   #$ff,d1             ; no scene table and falls through to a hit
    cmp.w   #'1',d1
    bcs.s   .hit
    cmp.w   #'9',d1
    bhi.s   .hit
    sub.w   #'1',d1
    move.w  d1,d0
    bsr     scene_key           ; 0..8; a set may map these to anything
    rts
.hit:
    endif
    ; any key is a full-strength hit on one of the eight pads, so the show
    ; can be driven with no MIDI plugged in at all
    move.w  d0,d1
    and.w   #7,d1
    add.w   d1,d1
    move.w  #$ff,level
    clr.w   idle_ticks
    move.w  #$ff,d0
    bsr     show_note_on
.none:
    rts
.quit:
    move.w  #1,quit_flag
    rts
.strobe:
    bsr     strobe_toggle
    rts

;----------------------------------------------------------------------
; The number keys, for driving a set with no MIDI at all. A build whose
; codes are not simply 0..8 -- ARC addresses positions in the storyboard --
; defines HAS_SCENE_KEY and maps them itself.
;----------------------------------------------------------------------
    ifnd HAS_SCENE_KEY
scene_key:
    ifd SCENES
    bra     scene_select
    else
    rts
    endif
    endif

;----------------------------------------------------------------------
; Effects. All of them live here rather than in a show, because the things
; they touch -- the palette register and whether show_frame runs at all --
; belong to the core, so every show on it gets them for nothing.
;
; Inverting the whole display is one word to the palette, which is why the
; strobe costs nothing and can sit over any scene.
;
; STROBE_HALF is the floor on the period, not just its default, and it is
; not a build flag: one inversion every 8 frames is 4.5 Hz on the glass,
; the register will flip every frame at 71 Hz if asked, and 15-25 Hz is
; where photosensitive seizure risk peaks. A controller may stretch the
; period but never shorten it past this.
;
; The palette is written every frame while an effect is inverting rather
; than only on the turns: a show may write it too -- GRID and HYPER
; inverse-flash on a hard hit -- so this way the effect takes the register
; back on the next frame instead of the two fighting over it. When nothing
; is inverting, the register is left alone.
;----------------------------------------------------------------------
STROBE_HALF equ 8               ; frames an inversion holds, and the floor
STROBE_MAX  equ 40              ; and the other end of what a knob may set

fx_frame:
    tst.w   fx_flash            ; one inverted frame, then hand the register
    beq.s   .nofl               ; back -- a flash that forgot to would stick
    subq.w  #1,fx_flash
    beq.s   .back
    move.w  #$777,PALETTE_HW
    rts
.back:
    move.w  #$000,PALETTE_HW
    rts
.nofl:
    tst.w   strobe_sync         ; locked to the beat, not to the frame
    beq.s   .free
    move.w  beat_ph,d0
    bra.s   .paint
.free:
    tst.w   strobe_on
    beq.s   .out
    move.w  strobe_ctr,d1       ; the period lives in memory and a 68000 has
    addq.w  #1,d1               ; no memory-to-memory compare
    cmp.w   strobe_per,d1
    bcs.s   .hold
    moveq   #0,d1
    eori.w  #1,strobe_ph
.hold:
    move.w  d1,strobe_ctr
    move.w  strobe_ph,d0
.paint:
    tst.w   d0
    beq.s   .norm
    move.w  #$777,PALETTE_HW
    rts
.norm:
    move.w  #$000,PALETTE_HW
.out:
    rts

;----------------------------------------------------------------------
; Everything off and the register handed back. Transport start and stop
; both come through here: a held effect whose note-off never arrives --
; because the tape stopped -- would otherwise stay on for good.
;----------------------------------------------------------------------
fx_reset:
    clr.w   strobe_on
    clr.w   strobe_held
    clr.w   strobe_sync
    clr.w   strobe_ctr
    clr.w   strobe_ph
    clr.w   beat_ph
    clr.w   fx_freeze
    clr.w   fx_flash
    move.w  #$000,PALETTE_HW
    rts

strobe_toggle:                  ; the Z key, and command FX_STROBE
    eori.w  #1,strobe_on
    clr.w   strobe_ctr
    clr.w   strobe_ph
    move.w  #$000,PALETTE_HW    ; switching off on an inverted frame would
    rts                         ; otherwise leave the scene inverted for good

;----------------------------------------------------------------------
; One beat of the Live clock, 24 ticks in.
;----------------------------------------------------------------------
fx_beat:
    eori.w  #1,beat_ph
    rts

;----------------------------------------------------------------------
; A command off the control channel. d1 = code, d0 = strength through the
; velocity curve -- zero for a program change, which carries no velocity.
;
; Codes below FX_BASE are the arrangement's own: they go to the show's
; scene_select unchanged, so the code space is the SHOW's to define. A
; build that carries the whole arc can make the code the frame number in
; their sequence, which is then stable however many scenes get added.
;----------------------------------------------------------------------
FX_BASE     equ 100
FX_STROBE   equ 100             ; toggle
FX_STROBEH  equ 101             ; while held
FX_SYNC     equ 102             ; locked to the beat, while held
FX_FREEZE   equ 103             ; while held
FX_FLASH    equ 104             ; one inverted frame

cmd_press:
    movem.l d0-d1/a0,-(sp)
    cmp.w   #FX_BASE,d1
    bcc.s   .fx
    ifd SCENES
    exg     d0,d1               ; scene_select takes the code in d0 and the
    bsr     scene_select        ; strength in d1, which a show may ignore
    endif
    bra.s   .out
.fx:
    cmp.w   #FX_STROBE,d1
    bne.s   .h
    bsr     strobe_toggle
    bra.s   .out
.h:
    cmp.w   #FX_STROBEH,d1
    bne.s   .s
    move.w  #1,strobe_on
    move.w  #1,strobe_held
    clr.w   strobe_ctr
    clr.w   strobe_ph
    bra.s   .out
.s:
    cmp.w   #FX_SYNC,d1
    bne.s   .f
    move.w  #1,strobe_sync
    bra.s   .out
.f:
    cmp.w   #FX_FREEZE,d1
    bne.s   .fl
    move.w  #1,fx_freeze
    bra.s   .out
.fl:
    cmp.w   #FX_FLASH,d1
    bne.s   .out
    move.w  #2,fx_flash         ; one inverted frame, then the frame that
.out:                           ; gives the register back
    movem.l (sp)+,d0-d1/a0
    rts

;----------------------------------------------------------------------
; The note-off of a held effect. A toggled strobe is not touched: letting
; go of a hold must not cancel a strobe somebody switched on deliberately.
;----------------------------------------------------------------------
cmd_release:
    cmp.w   #FX_STROBEH,d1
    bne.s   .s
    tst.w   strobe_held
    beq.s   .out
    clr.w   strobe_held
    clr.w   strobe_on
    move.w  #$000,PALETTE_HW
    rts
.s:
    cmp.w   #FX_SYNC,d1
    bne.s   .f
    clr.w   strobe_sync
    clr.w   beat_ph
    move.w  #$000,PALETTE_HW
    rts
.f:
    cmp.w   #FX_FREEZE,d1
    bne.s   .out
    clr.w   fx_freeze
.out:
    rts

;----------------------------------------------------------------------
; A controller on the control channel. d1 = number, d0 = value 0..127.
; The values are kept for any show that wants them; the one the core acts
; on itself is the strobe period, clamped so a knob cannot reach the band
; the strobe is rate-limited away from.
;----------------------------------------------------------------------
CC_STROBE   equ 1

cmd_cc:
    movem.l d0-d2/a0,-(sp)
    cmp.w   #8,d1
    bcc.s   .out                ; CC 0..7 are kept, the rest ignored
    lea     cc_val,a0
    move.b  d0,(a0,d1.w)
    cmp.w   #CC_STROBE,d1
    bne.s   .out
    move.w  d0,d2               ; 0..127 across STROBE_HALF..STROBE_MAX
    mulu    #STROBE_MAX-STROBE_HALF,d2
    divu    #127,d2
    and.l   #$ffff,d2
    add.w   #STROBE_HALF,d2
    move.w  d2,strobe_per
.out:
    movem.l (sp)+,d0-d2/a0
    rts

;----------------------------------------------------------------------
    section data
    even
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
rng_state:      ds.l 1
last_vbl:       ds.l 1
rez:            ds.w 1
row_bytes:      ds.w 1
scr_rows:       ds.w 1
half_rows:      ds.w 1
max_rows:       ds.w 1
level:          ds.w 1
quit_flag:      ds.w 1
midi_count:     ds.w 1
idle_ticks:     ds.w 1
demo_ctr:       ds.w 1
scene:          ds.w 1
overrun_acc:    ds.w 1
midi_bytes:     ds.w 1
midi_disp:      ds.w 1
midi_head:      ds.w 1
midi_tail:      ds.w 1
acia_seen:      ds.w 1
show_ctr:       ds.w 1          ; bar three; a show counts whatever it likes
acia_disp:      ds.w 1
tc_ticks:       ds.w 1
tc_disp:        ds.w 1
isr_hits:       ds.w 1
isr_disp:       ds.w 1
overrun_disp:   ds.w 1
window_ctr:     ds.w 1
strobe_on:      ds.w 1
strobe_held:    ds.w 1
strobe_sync:    ds.w 1
strobe_ctr:     ds.w 1
strobe_ph:      ds.w 1
strobe_per:     ds.w 1
beat_ph:        ds.w 1
clk_tick:       ds.w 1
clk_beat:       ds.w 1
fx_freeze:      ds.w 1
fx_flash:       ds.w 1
cc_val:         ds.b 8
    even
midi_status:    ds.b 1
midi_d1:        ds.b 1
    even
midi_ring:      ds.b MIDI_RING
    even
    even
    even
old_pal:        ds.w 16
    even
noise_pool:     ds.b POOL_SIZE
    even
screen_mem:     ds.b BUF_TOTAL+256

    endif
