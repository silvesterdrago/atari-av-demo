;======================================================================
;  FLOOR -- the perspective floor, its transverse lines flying.
;
;  Frame 13 of their sequence; frame 14 is the same picture plus one
;  block standing on the horizon, which is another entry in genflip's
;  table rather than another scene.
;
;  Only the transverse lines move -- the depths ride step**(-phase)
;  while the longitudinal lines stand -- so one turn of phase maps the
;  set onto itself and the 24 baked frames loop seamlessly.
;
;  Three corrections to their generator ride in tools/sysload.py, not
;  here: the step is the depth set's own ratio, the depths are exactly
;  geometric, and the vertical is scaled to our 400 rows. SEQUENCE.md
;  carries why, and the one defect left -- the far line appearing out
;  of nothing partway through the turn.
;======================================================================
    ifd POINT
FB_STAMP    equ 1               ; frame 14 is frame 13 plus the block
    endif
    include "src/shows/flipbook.inc"

    ifd POINT
;----------------------------------------------------------------------
; Frame 14: a block 16 px wide standing ON the horizon, which is their
; frame 13 with one mark added. It is stamped into the loaded frames once
; rather than baked into a second file: the rows it covers are black in
; every frame of the floor -- checked, the horizon bar starts below them --
; so FIELD.TOS is five kilobytes beside FLOOR.DAT instead of another 750.
;
; The block is 16 px on a byte boundary, so a row needs no masking; their
; 18 px would cost two partial bytes a row to land two pixels nobody can
; see at this size. It is written as two BYTES rather than a word: 16 px
; centred on 320 start at byte 39, and a word write to an odd address is
; an address error on a 68000.
;----------------------------------------------------------------------
PT_Y0       equ 100             ; the horizon bar runs 118..126
PT_ROWS     equ 18
PT_BYTE     equ 39              ; x 312..327, centred on 320

    section text
fb_stamp:
    movem.l d0-d3/a0-a1,-(sp)
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
    move.b  #-1,(a1)
    move.b  #-1,1(a1)
    adda.w  row_bytes,a1
    dbra    d2,.row
    add.l   #FRAMESZ,a0
    dbra    d3,.frame
    movem.l (sp)+,d0-d3/a0-a1
    rts
    endif

;----------------------------------------------------------------------
    section data
    even
fb_name:
    dc.b    "FLOOR.DAT",0
    even
