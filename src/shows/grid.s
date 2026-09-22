;======================================================================
;  GRID
;
;  A city on the horizon, perspective lines running to a vanishing
;  point, and horizontal lines flying at the viewer out of it.
;
;  The whole effect rests on one observation: everything that looks
;  expensive here never moves. The skyline and the converging lines are
;  baked into a finished screen by tools/gengrid.py and copied into both
;  buffers once, so they cost nothing ever again. What moves is whole
;  screen rows -- the cheapest thing this machine draws -- and the
;  background goes back underneath them out of the same baked image,
;  which is why the perspective lines survive being flown over.
;
;  About 14 rows put back and 14 drawn a frame: ~9k cycles of 112k. The
;  grid runs at the full 71 Hz with nine tenths of the frame unspent.
;======================================================================
POOL_SIZE   equ 1024            ; no noise here
RANGE_PAGES equ 131             ; 256 pages: two whole screens, 32768 apart
    include "src/core/head.s"

NLINES      equ 12
PHASES      equ 64
ROWB        equ 80              ; bytes in a screen row; mono only
BACK        equ 32768           ; the other screen
GR_ROWS     equ 32000           ; the row table, after the background
GR_STYLE    equ GR_ROWS+PHASES*NLINES*2

SPEED_BASE  equ 900             ; phase per frame at rest: ~18 frames a slot
SPEED_DECAY equ 70
SPEED_HIT   equ 14              ; times velocity
FLASH_AT    equ 200             ; a hard hit inverts the whole display
FLASH_LEN   equ 3

;----------------------------------------------------------------------
show_init:
    ; the baked screen into both buffers
    lea     grid_data,a0
    move.l  buf_base,a1
    move.l  a1,a2
    adda.l  #BACK,a2
    move.w  #SCR_SIZE/32-1,d7
.cp:
    movem.l (a0)+,d0-d6/a3
    movem.l d0-d6/a3,(a1)
    movem.l d0-d6/a3,(a2)
    lea     32(a1),a1
    lea     32(a2),a2
    dbra    d7,.cp

    move.w  #SPEED_BASE,gspeed
    clr.w   gphase
    clr.w   gflash
    move.w  #1,back_side        ; screen A is on show, so draw into B
    lea     prev_rows,a0        ; neither buffer has lines on it yet
    move.w  #NLINES*2-1,d0
.zap:
    move.w  #-1,(a0)+
    dbra    d0,.zap
    rts

;----------------------------------------------------------------------
show_frame:
    ; --- the floor slows back to its resting speed
    move.w  gspeed,d0
    cmp.w   #SPEED_BASE+SPEED_DECAY,d0
    bcs.s   .sk
    sub.w   #SPEED_DECAY,d0
    bra.s   .sp
.sk:
    move.w  #SPEED_BASE,d0
.sp:
    move.w  d0,gspeed
    add.w   d0,gphase

    ; --- the flash is a single write to the palette, so it costs nothing
    tst.w   gflash
    beq.s   .noflash
    subq.w  #1,gflash
    bne.s   .noflash
    move.w  #$000,PALETTE_HW    ; back to white ink on black
.noflash:

    ; --- which screen we draw into, and its own record of what is on it
    move.w  back_side,d0
    eori.w  #1,back_side
    move.l  buf_base,a6
    tst.w   d0
    beq.s   .b0
    adda.l  #BACK,a6
.b0:
    mulu    #NLINES*2,d0
    lea     prev_rows,a4
    adda.w  d0,a4

    ; --- put the background back under the lines this screen still shows
    lea     grid_data,a5
    lea     grid_data+GR_STYLE,a3
    move.w  #NLINES-1,gi
.rest:
    move.w  (a4)+,d0
    bmi     .nextr
    move.b  1(a3),gthick
    and.l   #$ffff,d0
    mulu    #ROWB,d0
    move.l  a5,a0
    add.l   d0,a0
    move.l  a6,a1
    add.l   d0,a1
    bsr     copy_row
    subq.b  #1,gthick
    beq.s   .nextr
    bsr     copy_row            ; two rows for the near lines
.nextr:
    addq.l  #2,a3
    subq.w  #1,gi
    bpl     .rest

    ; --- and draw this frame's lines, remembering where they went
    move.w  gphase,d0
    lsr.w   #8,d0
    and.w   #PHASES-1,d0
    mulu    #NLINES*2,d0
    lea     grid_data+GR_ROWS,a2
    adda.w  d0,a2
    lea     grid_data+GR_STYLE,a3
    lea     prev_rows,a4
    move.w  back_side,d0        ; already flipped, so this is the side we
    eori.w  #1,d0               ; are drawing
    mulu    #NLINES*2,d0
    adda.w  d0,a4
    move.w  #NLINES-1,gi
.draw:
    move.w  (a2)+,d0
    move.w  d0,(a4)+            ; what the next pass here has to undo
    move.b  1(a3),gthick
    and.l   #$ffff,d0
    mulu    #ROWB,d0
    move.l  a6,a1
    add.l   d0,a1
    moveq   #0,d0               ; the style byte, spread over a long
    move.b  (a3),d0
    move.w  d0,d1
    lsl.w   #8,d1
    or.w    d1,d0
    move.w  d0,d1
    swap    d0
    move.w  d1,d0
    move.l  d0,d1
    move.l  d0,d2
    move.l  d0,d3
    move.l  d0,d4
    move.l  d0,d5
    move.l  d0,d6
    move.l  d0,d7
    bsr     draw_row
    subq.b  #1,gthick
    beq.s   .nextd
    bsr     draw_row
.nextd:
    addq.l  #2,a3
    subq.w  #1,gi
    bpl     .draw

    move.l  a6,d0
    bsr     set_screen_base
    rts

;----------------------------------------------------------------------
; a0 = source row, a1 = destination row. Both left on the next row.
; 80 bytes is two movem.l of eight registers and one of four.
;----------------------------------------------------------------------
copy_row:
    movem.l (a0)+,d0-d7
    movem.l d0-d7,(a1)
    movem.l (a0)+,d0-d7
    movem.l d0-d7,32(a1)
    movem.l (a0)+,d0-d3
    movem.l d0-d3,64(a1)
    lea     ROWB(a1),a1
    rts

;----------------------------------------------------------------------
; d0-d7 all hold the row's pattern, a1 = destination row, left on the next.
;----------------------------------------------------------------------
draw_row:
    movem.l d0-d7,(a1)
    movem.l d0-d7,32(a1)
    movem.l d0-d3,64(a1)
    lea     ROWB(a1),a1
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d2,-(sp)
    move.w  d0,d2
    mulu    #SPEED_HIT,d2
    add.w   gspeed,d2
    cmp.w   #$7000,d2           ; the phase is a word; keep the step sane
    bcs.s   .ok
    move.w  #$7000,d2
.ok:
    move.w  d2,gspeed
    cmp.w   #FLASH_AT,d0
    bcs.s   .done
    move.w  #$777,PALETTE_HW    ; one word, and the whole display inverts
    move.w  #FLASH_LEN,gflash
.done:
    movem.l (sp)+,d0-d2
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
grid_data:
    incbin  "src/grid.bin"

;----------------------------------------------------------------------
    section bss
    even
prev_rows:      ds.w NLINES*2   ; one set of rows per screen
gspeed:         ds.w 1
gphase:         ds.w 1
gflash:         ds.w 1
back_side:      ds.w 1
gi:             ds.w 1
gthick:         ds.w 1
    even
