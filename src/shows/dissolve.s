;======================================================================
;  DISSOLVE -- a picture broken apart, live.
;
;  Their dissolve is not a fade: rectangular regions are lifted out,
;  blanked where they came from, and most of them pasted back displaced,
;  the break-up growing toward the edges. So this one is computed on the
;  machine rather than baked -- every hit eats further into the picture,
;  harder hits further, and 65 KB of buffers instead of 750 KB of frames.
;
;  tools/gendis.py guarantees the two things that make a block cheap:
;  every x, width and horizontal shift is a multiple of 4 bytes, so both
;  ends of a copy are long-aligned, and every block lies inside the
;  screen once displaced. The ST needs no clipping and no bit shifting --
;  a block is a blank and a copy of whole rows.
;
;  The tile is always read from the untouched source, as in the
;  reference, so blocks that overlap compose the same way.
;
;  DISSOLVE.DAT must sit beside the binary. When the table runs out the
;  next hit mends the picture instead, as a wipe down the screen.
;======================================================================
POOL_SIZE   equ 1024            ; no noise, no scrolling window
RANGE_PAGES equ 1
    include "src/core/head.s"

SCRSZ       equ 32000
NBLKMAX     equ 64
BLKSZ       equ 14              ; xb y wb h dxb dy keep, as words
DATSZ       equ SCRSZ+2+NBLKMAX*BLKSZ
PERFRAME    equ 8               ; blocks a frame: about 80 000 cycles
HEALCH      equ 8000            ; bytes of mending a frame, so four frames
HIT_MIN     equ 2               ; blocks even the softest hit takes
    ifnd AUTOHIT                    ; -DAUTOHIT=<frames> hits by itself, so the
AUTOHIT     equ 0                   ; scene can be checked with no MIDI and no
    endif                           ; keyboard, which is how it is captured

;----------------------------------------------------------------------
show_init:
    lea     work,a1             ; the base register has no low byte, so the
    move.l  a1,d0               ; screen has to start on a 256 boundary
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,work0

    clr.w   -(sp)               ; Fopen, read only
    pea     dis_name
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi     .nofile
    move.w  d0,d2               ; the handle

    pea     blob                ; Fread: the source screen, then the table
    move.l  #DATSZ,-(sp)
    move.w  d2,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,d1

    move.w  d2,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp

    cmp.l   #SCRSZ+2,d1         ; too short to hold a screen and a count
    blt     .nofile
    move.w  blob+SCRSZ,d0
    beq     .nofile
    cmp.w   #NBLKMAX,d0         ; a count we would walk off the end of
    bhi     .nofile
    move.w  d0,nblk
    move.w  #1,dis_ready
    move.w  #1,auto_ctr

    bsr     start_heal          ; the first picture is the source, intact
.fill:
    bsr     copy_chunk
    tst.l   heal_left
    bne.s   .fill
    move.l  work0,d0
    bsr     set_screen_base
.nofile:                        ; no file leaves the scene blank, but quiet
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
    move.w  #200,d0
    moveq   #0,d1
    bsr     show_note_on
    movem.l (sp)+,d0-d1
.noauto:
    endif
    tst.l   heal_left
    beq.s   .blocks
    bsr     copy_chunk          ; mending reads as a wipe down the screen
    bra.s   .out
.blocks:
    move.w  blk_todo,d7
    beq.s   .out
    cmp.w   #PERFRAME,d7
    bls.s   .batch
    move.w  #PERFRAME,d7
.batch:
    sub.w   d7,blk_todo
    subq.w  #1,d7
.lp:
    move.w  blk_next,d0
    cmp.w   nblk,d0
    bcc.s   .spent
    addq.w  #1,blk_next
    mulu    #BLKSZ,d0
    lea     blob+SCRSZ+2,a3
    add.l   d0,a3
    bsr     apply_block
    dbra    d7,.lp
.out:
    rts
.spent:
    clr.w   blk_todo
    rts

;----------------------------------------------------------------------
show_note_on:                   ; d0 = strength, d1 = pad*2
    movem.l d0-d1,-(sp)
    tst.w   dis_ready
    beq.s   .out
    tst.l   heal_left
    bne.s   .out                ; mid-mend: let it finish
    move.w  blk_next,d1
    cmp.w   nblk,d1
    bcs.s   .break
    bsr     start_heal          ; nothing left to break, so mend it instead
    bra.s   .out
.break:
    lsr.w   #5,d0               ; a harder hit takes more of the picture
    add.w   #HIT_MIN,d0
    add.w   d0,blk_todo
.out:
    movem.l (sp)+,d0-d1
    rts

;----------------------------------------------------------------------
start_heal:
    clr.l   heal_ptr
    move.l  #SCRSZ,heal_left
    clr.w   blk_next
    clr.w   blk_todo
    rts

;----------------------------------------------------------------------
copy_chunk:                     ; put back up to HEALCH bytes of the source
    movem.l d0-d2/a0-a1,-(sp)
    move.l  heal_left,d0
    beq.s   .out
    cmp.l   #HEALCH,d0
    bls.s   .last
    move.l  #HEALCH,d0
.last:
    move.l  heal_ptr,d1
    lea     blob,a1
    add.l   d1,a1
    move.l  work0,a0
    add.l   d1,a0
    move.l  d0,d2
    lsr.l   #2,d2               ; SCRSZ and HEALCH are both multiples of 4
    subq.l  #1,d2
.lp:
    move.l  (a1)+,(a0)+
    dbra    d2,.lp
    add.l   d0,heal_ptr
    sub.l   d0,heal_left
.out:
    movem.l (sp)+,d0-d2/a0-a1
    rts

;----------------------------------------------------------------------
; a3 -> block, advanced past it. Blank where the tile was, then lay it
; down from the SOURCE at its displaced place; a removed tile is only
; blanked.
;----------------------------------------------------------------------
apply_block:
    movem.l d0-d7/a0-a2,-(sp)
    movem.w (a3)+,d0-d6         ; xb y wb h dxb dy keep
    move.w  d6,d7
    move.l  d1,d6
    mulu    #80,d6
    move.l  work0,a0
    add.l   d6,a0
    add.w   d0,a0               ; where the tile was, on the screen
    lea     blob,a1
    add.l   d6,a1
    add.w   d0,a1               ; the same place in the source
    add.w   d5,d1
    add.w   d4,d0
    move.l  d1,d6
    mulu    #80,d6
    move.l  work0,a2
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
dis_name:
    dc.b    "DISSOLVE.DAT",0
    even

;----------------------------------------------------------------------
    section bss
    even
blob:           ds.b DATSZ
work:           ds.b SCRSZ+256
work0:          ds.l 1
heal_ptr:       ds.l 1
heal_left:      ds.l 1
nblk:           ds.w 1
blk_next:       ds.w 1
blk_todo:       ds.w 1
dis_ready:      ds.w 1
auto_ctr:       ds.w 1
    even
