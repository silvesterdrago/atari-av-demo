;======================================================================
;  GLYPHS
;
;  Lines of text marching up a hardware-scrolled field. The vertical axis
;  is time, as in the moire field -- what you see is the last twenty-five
;  lines of history drifting off the top.
;
;  The catch the moire field did not have: the screen base register steps
;  256 bytes, which is 3 rows plus 128 pixels of shear. Stripe patterns
;  repeat every 16 pixels so the shear cancelled; text would be sliced to
;  ribbons. But lcm(256, 80) = 1280 bytes = exactly 16 rows with no shear
;  at all -- so the font is 16 pixels tall and one base step advances
;  exactly one line of text.
;
;  The font is the ST's own 8x16 system font, fetched through Line-A, so
;  there is no font data in the binary.
;
;  Pads pick the line. Velocity shreds it: hard hits XOR noise through the
;  glyphs on their way into the field, and the damage scrolls away as part
;  of the record.
;======================================================================
    include "src/core/head.s"

GLYPH_H     equ 16
STEP        equ 1280            ; 16 rows * 80 bytes, the no-shear step
RANGE       equ 32000           ; 25 steps, exactly one screen
STEP_DIV    equ 48              ; scroll accumulator threshold
WRECK_AT    equ 150             ; strength above which glyphs get chewed.
                                ; It is a one-shot flag, consumed by the next
                                ; line printed: decaying it over frames left
                                ; the text permanently eaten, because hits
                                ; arrive far more often than lines are printed.

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
gl_init:
    ; --- the ST's own 8x16 font, via Line-A
    dc.w    $a000               ; a1 = array of 3 font header pointers
    move.l  a1,a3
    moveq   #2,d1
.findfont:
    move.l  (a3),a0
    cmp.w   #GLYPH_H,82(a0)     ; form_height
    beq.s   .gotfont
    addq.l  #4,a3
    dbra    d1,.findfont
.gotfont:
    move.l  76(a0),font_dat     ; dat_table
    move.w  80(a0),font_w       ; form_width, bytes per bitmap row
    move.w  36(a0),font_first   ; first_ade

    ; --- the field starts empty, both copies of it
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #RANGE*2,a1
    bsr     clear_span

    clr.l   base_off
    clr.w   scroll_acc
    clr.w   cur_line
    clr.w   wreck
    move.l  buf_base,d0
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
    ifnd SCENES
show_frame:
    endif
gl_frame:
    ; scroll speed follows how hard the set is being played; at rest it
    ; still creeps, because a frozen wall of text reads as a crash
    move.w  level,d0
    lsr.w   #4,d0
    addq.w  #1,d0
    add.w   scroll_acc,d0
    cmp.w   #STEP_DIV,d0
    bcc.s   .step
    move.w  d0,scroll_acc
    rts
.step:
    sub.w   #STEP_DIV,d0
    move.w  d0,scroll_acc

    ; --- advance the window one whole text line
    move.l  base_off,d0
    add.l   #STEP,d0
    cmp.l   #RANGE,d0
    bcs.s   .nowrap
    sub.l   #RANGE,d0
.nowrap:
    move.l  d0,base_off
    move.l  buf_base,d1
    add.l   d0,d1
    exg     d0,d1
    bsr     set_screen_base     ; d0 = address

    ; --- where the strip that just came into view lives
    move.l  base_off,d0
    add.l   #RANGE-STEP,d0
    move.l  d0,strip_off
    move.l  buf_base,a4
    add.l   d0,a4               ; a4 = strip

    ; blank it, then print into it
    move.l  a4,a0
    move.l  a4,a1
    add.l   #STEP,a1
    bsr     clear_span
    bsr     print_line
    clr.w   wreck               ; one hard hit chews exactly one line

    ; --- keep the mirror identical, so the wrap cannot be seen
    move.l  strip_off,d0
    cmp.l   #RANGE,d0
    bcs.s   .low
    sub.l   #RANGE,d0
    bra.s   .haveo
.low:
    add.l   #RANGE,d0
.haveo:
    move.l  buf_base,a0
    add.l   d0,a0
    move.l  a0,a1
    add.l   #STEP,a1
    move.l  a4,a2
    bsr     fill_span

    ; next line of the litany
    move.w  cur_line,d0
    addq.w  #1,d0
    cmp.w   #GL_LINES,d0
    bcs.s   .lineok
    moveq   #0,d0
.lineok:
    move.w  d0,cur_line
    rts

;----------------------------------------------------------------------
; Print the current line into the 16 rows at a4, centred.
;----------------------------------------------------------------------
print_line:
    movem.l d0-d7/a0-a5,-(sp)

    move.w  cur_line,d0
    lsl.w   #2,d0
    lea     lines,a0
    move.l  (a0,d0.w),a3        ; a3 = the text

    ; how long is it
    move.l  a3,a0
    moveq   #-1,d4
.len:
    addq.w  #1,d4
    tst.b   (a0)+
    bne.s   .len
    ; centre it: (columns - length) / 2
    move.w  row_bytes,d5
    sub.w   d4,d5
    lsr.w   #1,d5               ; d5 = starting byte column

    move.l  font_dat,a2
    move.w  font_w,d6
    bsr     next_rng            ; seed the erosion; d3/d4 die here, both spent
    move.w  d3,d7               ; d7 = rolling noise

    moveq   #0,d2               ; row counter
.row:
    ; source: this row of the font bitmap strip
    move.w  d2,d0
    mulu    d6,d0
    move.l  a2,a0
    add.l   d0,a0               ; a0 = font row base

    ; destination: this row of the strip, at the centring offset
    move.w  d2,d0
    mulu    row_bytes,d0
    move.l  a4,a1
    add.l   d0,a1
    add.w   d5,a1

    move.l  a3,a5               ; text cursor
.char:
    moveq   #0,d0
    move.b  (a5)+,d0
    beq.s   .eol
    sub.w   font_first,d0
    move.b  (a0,d0.w),d1        ; the glyph's byte for this row

    ; roll the noise on every character, cheaply and inline -- next_rng
    ; would cost a bsr per byte and clobbers registers we are using
    move.w  d7,d4
    lsl.w   #3,d4
    eor.w   d4,d7
    move.w  d7,d4
    lsr.w   #5,d4
    eor.w   d4,d7

    ; chewed, when hit hard: AND against noise eats bits out of the glyph,
    ; which still reads as a letter being destroyed. EOR just turns it into
    ; static and you lose the word entirely.
    tst.w   wreck
    beq.s   .clean
    and.b   d7,d1
.clean:
    move.b  d1,(a1)+
    bra.s   .char
.eol:
    addq.w  #1,d2
    cmp.w   #GLYPH_H,d2
    bcs     .row

    movem.l (sp)+,d0-d7/a0-a5
    rts

;----------------------------------------------------------------------
; d0 = strength 0..255, d1 = pad index * 2
;----------------------------------------------------------------------
    ifnd SCENES
show_note_on:
    endif
gl_note_on:
    movem.l d0-d1,-(sp)
    lsr.w   #1,d1
    cmp.w   #GL_LINES,d1
    bcs.s   .ok
    moveq   #0,d1
.ok:
    move.w  d1,cur_line
    cmp.w   #WRECK_AT,d0
    bcs.s   .done
    move.w  #1,wreck            ; chew the next line printed, and only that
.done:
    movem.l (sp)+,d0-d1
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
; One line per pad. Edit freely -- this is the copy for the show.
lines:
    dc.l    l0,l1,l2,l3,l4,l5,l6,l7
GL_LINES      equ 8
l0: dc.b "NOISE",0
l1: dc.b "SIGNAL LOST",0
l2: dc.b "1040 STF",0
l3: dc.b "NO CARRIER",0
l4: dc.b "DEAD CHANNEL",0
l5: dc.b "MONO 71 HZ",0
l6: dc.b "STATIC",0
l7: dc.b "END OF LINE",0
    even

    section bss
    even
font_dat:       ds.l 1
base_off:       ds.l 1
strip_off:      ds.l 1
font_w:         ds.w 1
font_first:     ds.w 1
scroll_acc:     ds.w 1
cur_line:       ds.w 1
wreck:          ds.w 1
