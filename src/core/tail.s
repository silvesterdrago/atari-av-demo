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
    ifd ACIABAR                 ; bar three is the probe INSIDE the 6850: lit
    move.w  acia_seen,acia_disp ; with bar two empty means the bytes arrive and
    clr.w   acia_seen           ; the program is not draining them; both empty
    clr.w   show_ctr            ; means nothing is reaching the machine at all
    else
    move.w  show_ctr,acia_disp  ; otherwise it is the show's own counter
    clr.w   show_ctr
    clr.w   acia_seen
    endif
.done:
    rts

;----------------------------------------------------------------------
; d0 = address -> ST screen base register (256-byte granularity)
;----------------------------------------------------------------------
set_screen_base:
    move.l  d0,cur_base
    move.w  fx_shift,d1         ; a held displacement: the base register steps
    beq.s   .noshift            ; 256 bytes, which is three rows down and 128
    ext.l   d1                  ; pixels across, so one page is a geometric
    lsl.l   #8,d1               ; fault and not a smear. It only moves where
    add.l   d1,d0               ; the beam READS, so nothing can be corrupted
.noshift:
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
    ifnd FOLLOW                 ; -DFOLLOW=<0..255> pins it, for measuring
    move.w  follow,d0           ; the follower sinks on its own: if Live stops
    beq.s   .nofall             ; sending, the picture must come back to rest
    subq.w  #1,d0               ; rather than hang at whatever came last
    move.w  d0,follow
.nofall:
    endif
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
    ifd HAS_SHOW_KEY            ; a show may claim a key of its own; Enter and
    cmp.w   #13,d1              ; p both reach it, because one wrong key on the
    beq.s   .showkey            ; night costs more than a second compare
    cmp.w   #'p',d1
    beq.s   .showkey
    cmp.w   #'P',d1
    beq.s   .showkey
    endif
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
    ifd HAS_SHOW_KEY
.showkey:
    bsr     show_key
    rts
    endif
.strobe:
    bsr     strobe_toggle
    rts

;----------------------------------------------------------------------
; The number keys, for driving a set with no MIDI at all. A build whose
; codes are not simply 0..8 -- ARC addresses positions in the storyboard --
; defines HAS_SCENE_KEY and maps them itself.
;----------------------------------------------------------------------
    ifnd HAS_SHOW_FX            ; a show with effects of its own defines these
show_fx:                        ; two; otherwise an unknown code does nothing
show_fx_off:
    rts
    endif

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
; not a build flag. Twelve frames is 5.93 inversions a second, which is 2.97
; FLASHES -- a flash being a pair of opposing changes -- against the three a
; second the show's own spec cites, WCAG 2.3.1. Eight frames, which this was,
; gives 4.45 and breaks it. A controller may stretch the period but never
; shorten it past this.
;
; FLASH_LOCK holds the single-frame flash to the same rule, so an
; arrangement cannot break it by sending the code faster than the eye can
; take: the machine refuses rather than trusting the sequence.
;
; The palette is written every frame while an effect is inverting rather
; than only on the turns: a show may write it too -- GRID and HYPER
; inverse-flash on a hard hit -- so this way the effect takes the register
; back on the next frame instead of the two fighting over it. When nothing
; is inverting, the register is left alone.
;----------------------------------------------------------------------
STROBE_HALF equ 12              ; frames an inversion holds, and the floor
FLASH_LOCK  equ 24              ; frames between one-frame flashes, so three
                                ; a second is a ceiling and not a target
STROBE_MAX  equ 40              ; and the other end of what a knob may set

fx_frame:
    tst.w   flash_lock
    beq.s   .nolock
    subq.w  #1,flash_lock
.nolock:
    move.w  fx_shift,d0         ; the displacement rides in the base register,
    or.w    sh_last,d0          ; so it only lands when somebody writes it --
    beq.s   .nobase             ; and a still writes it once, at load. So the
    move.w  fx_shift,sh_last    ; base is rewritten from cur_base while the
    move.l  cur_base,d0         ; shift lives, and once more when it dies
    bsr     set_screen_base
.nobase:
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
    tst.w   fx_invert           ; held inverted: no flashing at all, which is
    beq.s   .nohold             ; the one inversion with no rate to limit
    move.w  #$777,PALETTE_HW
    rts
.nohold:
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
; Stripes of noise over whatever is on the screen, held on a note.
;
; Nothing here redraws a whole screen: a flipbook only moves the base
; register, and the baked screens ARE the source, while the morph engine
; clears only the boxes its own slots covered. So noise written into the
; picture would stay there for good. Every row it dirties is saved first
; and put back at the top of the next frame, BEFORE the scene draws --
; after would overwrite fresh drawing with stale bytes.
;
; Position, thickness and length are all drawn fresh each frame, because a
; stripe that keeps its place reads as a pattern rather than as a fault.
; The bytes come out of the noise pool at a rolling offset, so there is no
; random number per byte.
;
; The cost is three passes over what it dirties -- save, paint, restore --
; so about 11 cycles a byte. At the default twelve stripes that is some
; 600 bytes and 7k cycles, under a tenth of a frame; CC 3 raises it, and
; the ceiling of NZ_BYTES is what stops a knob from eating the frame.
;----------------------------------------------------------------------
; Rows go back LAST FIRST. Two stripes in one frame can overlap, and the
; second then saved the first one's noise as its "original" -- undone in the
; order they were laid, the second hands that noise back and it stays. In
; reverse it is handed back and then overwritten by the true original, which
; is what undo has to mean. Forwards it leaked about a byte every three
; frames, which took an hour of run time to show up as a haze.
fx_noise_restore:
    move.w  nz_n,d0
    beq.s   .out
    movem.l d0-d2/a0-a2,-(sp)
    move.w  d0,d1
    mulu    #6,d1
    lea     nz_addr,a0
    add.l   d1,a0               ; one past the last entry
    lea     nz_save,a1
    add.w   nz_total,a1         ; and one past the last byte saved
    subq.w  #1,d0
.row:
    subq.l  #6,a0
    moveq   #0,d1
    move.w  4(a0),d1            ; its length, and the bytes just before a1
    sub.w   d1,a1
    move.l  (a0),a2
    move.l  a1,-(sp)
    move.w  d1,d2
    subq.w  #1,d2
.byte:
    move.b  (a1)+,(a2)+
    dbra    d2,.byte
    move.l  (sp)+,a1
    dbra    d0,.row
    movem.l (sp)+,d0-d2/a0-a2
    clr.w   nz_n
    clr.w   nz_total
.out:
    rts

fx_noise_paint:
    tst.w   nz_on
    beq     .out
    movem.l d0-d7/a0-a2,-(sp)
    lea     nz_addr,a1
    lea     nz_save,a2
    moveq   #0,d6                   ; bytes spent so far
    move.w  nz_count,d7
    subq.w  #1,d7
    bmi     .done
.stripe:
    bsr     next_rng                ; one draw carries the whole stripe
    move.l  d3,d0
    and.l   #$ffff,d0
    mulu    scr_rows,d0
    clr.w   d0
    swap    d0                      ; the row it starts on
    move.w  d0,d5
    move.l  d3,d0
    lsr.l   #8,d0
    move.w  d0,d1
    and.w   #3,d1
    addq.w  #1,d1                   ; one to four rows thick
    lsr.l   #8,d0
    move.w  d0,d2
    and.w   #15,d2
    add.w   #8,d2                   ; eight to twenty-three bytes long
    lsr.l   #8,d0
    and.w   #63,d0                  ; and where it starts across
    move.w  row_bytes,d4
    sub.w   d0,d4
    cmp.w   d4,d2
    bls.s   .fits
    move.w  d4,d2                   ; clipped to the row rather than wrapped
.fits:
    tst.w   d2
    beq.s   .next
.rows:
    cmp.w   #NZ_ROWS,nz_n
    bcc     .done
    move.w  d6,d4
    add.w   d2,d4
    cmp.w   #NZ_BYTES,d4
    bhi.s   .done                   ; the ceiling, so a knob cannot eat a frame
    cmp.w   scr_rows,d5
    bcc.s   .next
    move.w  d5,d4
    mulu    row_bytes,d4
    move.l  cur_base,a0
    add.l   d4,a0
    add.w   d0,a0
    move.l  a0,(a1)+                ; where, and how much, so the restore does
    move.w  d2,(a1)+                ; not care where the base has moved since
    addq.w  #1,nz_n
    add.w   d2,nz_total
    add.w   d2,d6
    lea     noise_pool,a3
    move.w  nz_roll,d4
    and.w   #POOL_SIZE-1,d4
    add.w   d2,d4
    and.w   #POOL_SIZE-1,d4
    move.w  d4,nz_roll
    add.w   d4,a3
    move.w  d2,d4
    subq.w  #1,d4
.byte:
    move.b  (a0),(a2)+              ; save, then paint over it
    move.b  (a3)+,(a0)+
    dbra    d4,.byte
    addq.w  #1,d5
    subq.w  #1,d1
    bne.s   .rows
.next:
    dbra    d7,.stripe
.done:
    movem.l (sp)+,d0-d7/a0-a2
.out:
    rts

;----------------------------------------------------------------------
; How deep an effect goes. d0 = strength 0..255 off the note, d1 = which
; controller holds the ceiling, d2 = the ceiling's own ceiling. Returns the
; depth in d0, at least 1.
;
; The rule is the same one hits have always had: velocity picks INSIDE what
; the knob allows. A knob alone is not playable -- it has to be set before
; the note, and in Live the velocity is drawn on the note anyway. A note with
; no velocity at all, which is what a program change is, takes the knob's
; value whole, because the faintest shift would be no shift.
;----------------------------------------------------------------------
fx_depth:
    movem.l d1-d3/a0,-(sp)
    lea     cc_val,a0
    moveq   #0,d3
    move.b  (a0,d1.w),d3        ; 0..127 from the controller
    mulu    d2,d3
    divu    #127,d3
    and.l   #$ffff,d3
    tst.w   d3                  ; an untouched controller means the whole
    bne.s   .have               ; range is available to the velocity
    move.w  d2,d3
.have:
    tst.w   d0                  ; no velocity at all -- a program change --
    beq.s   .full               ; takes the ceiling whole
    mulu    d3,d0
    divu    #255,d0
    and.l   #$ffff,d0
    tst.w   d0                  ; and a soft note is the SHALLOW end, never
    bne.s   .out                ; the deep one: one, not the ceiling
    moveq   #1,d0
    bra.s   .out
.full:
    move.w  d3,d0
.out:
    movem.l (sp)+,d1-d3/a0
    rts

;----------------------------------------------------------------------
; What the follower does on its own, once a show says it may.
;
; A still is a single picture and nothing in it moves, so without this it
; sits dead while the room is loud. With fx_auto set, the follower drives
; the noise and the displacement by itself -- no note needed, the picture
; breathes with the sound. Below AUTO_FLOOR it is left completely alone, so
; quiet means clean rather than faintly dirty.
;
; A held effect always wins: while a note is down its velocity governs, and
; letting go hands the parameter back to the follower.
;----------------------------------------------------------------------
fx_auto_frame:
    tst.w   fx_auto
    beq.s   .out
    movem.l d0-d2,-(sp)
    move.w  follow,d2
    cmp.w   #AUTO_FLOOR,d2
    bcc.s   .loud
    moveq   #0,d2               ; quiet: clean picture, nothing held
.loud:
    tst.w   nz_held
    bne.s   .shift
    tst.w   d2
    beq.s   .quietnz
    move.w  d2,d0
    mulu    #NOISE_MAX-1,d0
    divu    #255,d0
    and.l   #$ffff,d0
    addq.w  #1,d0
    move.w  d0,nz_count
    move.w  #1,nz_on
    bra.s   .shift
.quietnz:
    clr.w   nz_on
.shift:
    tst.w   sh_held
    bne.s   .done
    move.w  d2,d0
    mulu    #AUTO_SHIFT,d0
    divu    #255,d0
    and.l   #$ffff,d0
    move.w  d0,fx_shift
.done:
    movem.l (sp)+,d0-d2
.out:
    rts

;----------------------------------------------------------------------
; Everything off and the register handed back. Transport start and stop
; both come through here: a held effect whose note-off never arrives --
; because the tape stopped -- would otherwise stay on for good.
;----------------------------------------------------------------------
fx_reset:
    clr.w   flash_lock
    clr.w   sh_last
    clr.w   nz_on
    clr.w   nz_held
    clr.w   sh_held
    clr.w   fx_invert
    clr.w   fx_shift
    bsr     show_fx_off
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
FX_INVERT   equ 105             ; held inverted, not flashing
FX_SHIFT    equ 106             ; held displaced by CC 2 pages
FX_NOISE    equ 109             ; held: stripes of noise over the picture
SHIFT_MAX   equ 8               ; pages, and stripes, that a knob may ask for
NOISE_MAX   equ 16
AUTO_SHIFT  equ 4               ; and what the follower may reach on its own
AUTO_FLOOR  equ 12              ; below this the picture is left alone
NZ_ROWS     equ 48              ; rows one frame may dirty, and the size of
NZ_BYTES    equ 1536            ; the backup that puts them back

cmd_press:
    movem.l d0-d1/a0,-(sp)
    cmp.w   #FX_BASE,d1
    bcc.s   .fx
    ifd SCENES
    exg     d0,d1               ; scene_select takes the code in d0 and the
    bsr     scene_select        ; strength in d1, which a show may ignore
    endif
    bra     .out
.fx:
    cmp.w   #FX_STROBE,d1
    bne.s   .h
    bsr     strobe_toggle
    bra     .out
.h:
    cmp.w   #FX_STROBEH,d1
    bne.s   .s
    move.w  #1,strobe_on
    move.w  #1,strobe_held
    clr.w   strobe_ctr
    clr.w   strobe_ph
    bra     .out
.s:
    cmp.w   #FX_SYNC,d1
    bne.s   .f
    move.w  #1,strobe_sync
    bra     .out
.f:
    cmp.w   #FX_FREEZE,d1
    bne.s   .fl
    move.w  #1,fx_freeze
    bra     .out
.fl:
    cmp.w   #FX_FLASH,d1
    bne.s   .inv
    tst.w   flash_lock          ; too soon after the last: refused, not queued
    bne     .out
    move.w  #FLASH_LOCK,flash_lock
    move.w  #2,fx_flash         ; one inverted frame, then the frame that
    bra.s   .out                ; gives the register back
.inv:
    cmp.w   #FX_INVERT,d1
    bne.s   .sh
    move.w  #1,fx_invert
    bra     .out
.sh:
    cmp.w   #FX_SHIFT,d1
    bne.s   .nz
    moveq   #CC_SHIFT,d1
    moveq   #SHIFT_MAX,d2
    bsr     fx_depth            ; velocity picks inside what the knob allows
    move.w  d0,fx_shift
    move.w  #1,sh_held
    bra     .out
.nz:
    cmp.w   #FX_NOISE,d1
    bne.s   .own
    moveq   #CC_NOISE,d1
    moveq   #NOISE_MAX,d2
    bsr     fx_depth
    move.w  d0,nz_count
    move.w  #1,nz_on
    move.w  #1,nz_held
    bra     .out
.own:
    bsr     show_fx             ; any code the core does not know belongs to
                                ; the show, whatever its number -- otherwise
                                ; the two code spaces have to be kept in step
.out:
    movem.l (sp)+,d0-d1/a0
    rts

;----------------------------------------------------------------------
; The note-off of a held effect. A toggled strobe is not touched: letting
; go of a hold must not cancel a strobe somebody switched on deliberately.
;----------------------------------------------------------------------
cmd_release:
    cmp.w   #FX_INVERT,d1
    bne.s   .sh
    clr.w   fx_invert
    move.w  #$000,PALETTE_HW
    rts
.sh:
    cmp.w   #FX_SHIFT,d1
    bne.s   .nz
    clr.w   sh_held             ; letting go hands it back to the follower,
    clr.w   fx_shift            ; which may put it straight back
    rts
.nz:
    cmp.w   #FX_NOISE,d1
    bne.s   .own
    clr.w   nz_held
    clr.w   nz_on               ; the rows go back on the next frame, by the
    rts                         ; same path that puts them back every frame
.own:
    bsr     show_fx_off
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
CC_SHIFT    equ 2               ; read straight out of cc_val by FX_SHIFT
CC_NOISE    equ 3
CC_FOLLOW   equ 4               ; an envelope follower in Live, as a number

cmd_cc:
    movem.l d0-d2/a0,-(sp)
    cmp.w   #8,d1
    bcc.s   .out                ; CC 0..7 are kept, the rest ignored
    lea     cc_val,a0
    move.b  d0,(a0,d1.w)
    cmp.w   #CC_FOLLOW,d1       ; the follower is not a parameter but a LEVEL:
    bne.s   .nofollow           ; it arrives continuously and the show leans on
    add.w   d0,d0               ; it as a floor, so hits still punch above it
    move.w  d0,follow
    clr.w   idle_ticks          ; something is playing, so the idle generator
    bra.s   .out                ; must keep out of the way
.nofollow:
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
follow:         ds.w 1
fx_auto:        ds.w 1
nz_held:        ds.w 1
sh_held:        ds.w 1
sh_last:        ds.w 1
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
flash_lock:     ds.w 1
fx_invert:      ds.w 1
fx_shift:       ds.w 1
nz_on:          ds.w 1
nz_n:           ds.w 1
nz_total:       ds.w 1
nz_count:       ds.w 1
nz_roll:        ds.w 1
nz_addr:        ds.l NZ_ROWS
nz_len:         ds.w NZ_ROWS
    even
nz_save:        ds.b NZ_BYTES
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
