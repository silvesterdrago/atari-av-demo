
;======================================================================
;  CUBES4 -- the same show with four cubes instead of eight.
;
;  Two across and two down, so a cell is twice as wide and the tile twice
;  as big both ways: 192 px against 96. The outline grows with it, a
;  solid 6x6 brush against the old 2x1, which is the only thing "thicker"
;  can mean where there is no grey to shade with.
;
;  It costs about twice the blit -- four tiles of 4608 bytes against eight
;  of 1152, so 18432 bytes a frame rather than 9216 -- and the sprite
;  table is 576 KB rather than 144. The table is still carried inside the
;  binary: the tiles need no alignment, so TOS loading the data segment IS
;  the buffer, unlike HYPER's screens which would have cost the memory
;  twice. Nothing has to sit beside this one.
;======================================================================
    ifnd SCENES
POOL_SIZE   equ 1024
RANGE_PAGES equ 8               ; the shear walks the base a few pages
    endif
    include "src/core/head.s"

C4_W_BYTES  equ 24              ; 192 px, must match tools/gencubes.py big
C4_H        equ 160               ; 192 px wide is square on an SM124
C4_SPRITE   equ C4_W_BYTES*C4_H

;----------------------------------------------------------------------
    ifnd SCENES
show_init:
    endif
cu_init:
    ; the grid: two cells across, two down
    move.w  row_bytes,d5
    lsr.w   #1,d5               ; cell width in bytes (40 in mono)
    move.w  scr_rows,d6
    lsr.w   #1,d6               ; cell height in rows (200 in mono)
    move.w  d5,d2
    sub.w   #C4_W_BYTES,d2
    lsr.w   #1,d2               ; box x offset inside the cell
    move.w  d6,d3
    sub.w   #C4_H,d3
    lsr.w   #1,d3               ; box y offset inside the cell

    lea     cube_org,a0
    moveq   #0,d4
.mk:
    move.w  d4,d0
    and.w   #1,d0
    mulu    d5,d0
    add.w   d2,d0
    and.l   #$ffff,d0           ; byte within the row
    move.w  d4,d1
    lsr.w   #1,d1
    mulu    d6,d1
    add.w   d3,d1
    and.l   #$ffff,d1
    mulu    row_bytes,d1        ; -> byte offset of the box top
    add.l   d0,d1
    move.l  buf_base,a1
    add.l   d1,a1
    move.l  a1,(a0)+
    addq.w  #1,d4
    cmp.w   #4,d4
    bcs.s   .mk

    ; clear a little past the visible screen so the shear glitch slides
    ; black into view rather than whatever the last scene left behind
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1
    bsr     clear_span

    lea     cube_level,a0
    moveq   #(4*3)-1,d0         ; level, angle and glitch, 4 words each
.zap:
    clr.w   (a0)+
    dbra    d0,.zap
    clr.w   cubes_idle
    rts

    ifnd SCENES
show_frame:
    endif
cu_frame:
    ; with nothing plugged in, punch cubes at random so the screen lives
    cmp.w   #150,idle_ticks
    bcs.s   .nofree
    addq.w  #1,cubes_idle
    cmp.w   #14,cubes_idle
    bcs.s   .nofree
    clr.w   cubes_idle
    bsr     next_rng
    move.w  d3,d0
    and.w   #3,d0
    add.w   d0,d0
    lea     cube_level,a0
    move.w  #$ff,(a0,d0.w)
.nofree:

    move.w  cu_tick,d0          ; which half of the cubes this frame redraws
    eor.w   #1,d0
    move.w  d0,cu_tick

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
    mulu    #C4_SPRITE,d5
    ifd SHARED
    move.l  sd_base,a1       ; the set's shared buffer, filled on entry
    else
    lea     cube_data,a1
    endif
    add.l   d5,a1

    ; Two cubes a frame, odds and evens in turn. Four of these tiles do
    ; not fit in one -- measured, three do -- and a tile is opaque, so a
    ; cube that is not redrawn simply holds. Each one then tumbles at 35
    ; Hz while the screen stays at 71.
    move.w  d7,d6
    and.w   #1,d6
    cmp.w   cu_tick,d6
    bne     .next

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
    cmp.w   #4,d7
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
    move.w  #C4_H-1,d0
.row:                           ; six longs is the row, and movem pays 20
    movem.l (a1)+,d2-d7         ; cycles a long where a displacement costs 24
    movem.l d2-d7,(a0)
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
    moveq   #(C4_H/8)-1,d0    ; twenty-four blocks of eight rows
.blk:
    bsr     next_rng            ; only touches d3/d4
    move.w  d3,d5
    and.w   #15,d5
    subq.w  #8,d5
    add.w   d5,d5               ; -16..+14 bytes, and EVEN: a move.l to an odd
                                ; address is an address error on a 68000
    ; Shift what we read, not where we write. Moving the destination would
    ; smear pixels outside the box, and nothing ever erases out there.
    move.l  a1,a2
    adda.w  d5,a2
    rept    8                   ; straight, because the row counter would
    movem.l (a2)+,d2-d7         ; have to live in a register movem wants
    movem.l d2-d7,(a3)
    adda.w  d1,a3
    endr
    lea     (C4_W_BYTES*8)(a1),a1
    dbra    d0,.blk
    movem.l (sp)+,d0-d7/a0-a3
    rts

;======================================================================
; SCENE 1 -- MOIRE FIELD   (the chosen scene)
;
;----------------------------------------------------------------------
    ifnd SCENES
show_note_on:
    endif                           ; d0 = strength, d1 = pad*2
cu_note_on:
    movem.l d0-d1/a0,-(sp)
    lea     cube_level,a0
    move.w  d0,(a0,d1.w)
    cmp.w   #GLITCH_VEL,d0
    bcs.s   .done
    lea     cube_glitch,a0      ; a hard hit tears that cube
    move.w  #GLITCH_FRAMES,(a0,d1.w)
.done:
    movem.l (sp)+,d0-d1/a0
    rts

    include "src/core/tail.s"

;----------------------------------------------------------------------
    section data
    even
    ifnd SHARED
cube_data:
    incbin  "src/cubes4.bin"
    endif

;----------------------------------------------------------------------
    section bss
    even
cube_level:     ds.w 4
cube_angle:     ds.w 4
cube_glitch:    ds.w 4
cube_org:       ds.l 4
cubes_idle:     ds.w 1
cu_tick:        ds.w 1
shear_ctr:      ds.w 1
shear_cool:     ds.w 1
    even
