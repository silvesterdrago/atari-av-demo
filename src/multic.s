;======================================================================
;  NOISE AV -- the whole set in one binary.
;
;  1 GRID   2 HALFTONE   3 SPARKS   4 GLYPHS      instant
;  5 CUBES  6 SOLIDS  7 MONOLITH  8 HYPER         reads the card first
;  any other key = a hit on a pad        ESC = quit
;
;  The four heavy scenes hold 855 KB of tables between them, which no
;  megabyte will carry at once, so they share one buffer and the entered
;  scene's file is read into it. Switching between 1-4 costs nothing;
;  switching into 5-8 costs a read, unless that scene's data is already
;  in the buffer.
;
;  CUBES.DAT, SOLIDS.DAT, BIG.DAT and HYPER.DAT must sit beside the
;  binary. A missing file leaves its key dead rather than drawing from
;  an empty buffer, which for the pose scenes would mean wild addresses.
;======================================================================
SCENES      equ 1               ; tells the core's key handler to dispatch
SHARED      equ 1               ; and the heavy scenes to read the card
POOL_SIZE   equ 1024
RANGE_PAGES equ 131             ; two whole screens: GRID and MONOLITH flip
                                ; between them, and the cubes' shear walks the
                                ; base a few pages inside the first
    include "src/core/head.s"

NSCENE      equ 8
SD_MAX      equ 384000          ; the largest file: HYPER's twelve screens

;----------------------------------------------------------------------
show_init:
    lea     sd_buf,a0           ; HYPER is shown straight out of this buffer
    move.l  a0,d0               ; and the base register has no low byte
    add.l   #255,d0
    and.l   #$ffffff00,d0
    move.l  d0,sd_base
    move.w  #-1,sd_scene
    ifd START
    move.w  #START,d0
    else
    moveq   #0,d0
    endif
    move.w  #-1,cur_scene       ; so the first select always takes
    ifd CYCLE
    clr.w   cyc_ctr
    endif
    bsr     scene_select
    tst.w   cur_scene           ; the opening scene's file may be missing;
    bpl.s   .running            ; scene 0 needs none, so fall back to it
    moveq   #0,d0
    bsr     scene_select
.running:
    rts

;----------------------------------------------------------------------
show_frame:
    ifd CYCLE
    addq.w  #1,cyc_ctr
    cmp.w   #CYCLE,cyc_ctr
    bcs.s   .noswap
    clr.w   cyc_ctr
    move.w  cur_scene,d0
    addq.w  #1,d0
    cmp.w   #NSCENE,d0
    bcs.s   .wrapped
    moveq   #0,d0
.wrapped:
    bsr     scene_select
.noswap:
    endif
    move.w  cur_scene,d0
    lsl.w   #2,d0
    lea     frame_tbl,a0
    move.l  0(a0,d0.w),a0
    jmp     (a0)                ; the scene's rts returns to the core

;----------------------------------------------------------------------
; d0 = strength, d1 = pad*2, and the caller still needs both afterwards.
show_note_on:
    movem.l d0-d2/a0,-(sp)
    move.w  cur_scene,d2
    lsl.w   #2,d2
    lea     note_tbl,a0
    move.l  0(a0,d2.w),a0
    jsr     (a0)
    movem.l (sp)+,d0-d2/a0
    rts

;----------------------------------------------------------------------
; d0 = 0..8 from the number keys. The data is fetched BEFORE the scene is
; committed to: a scene whose file will not read must not be entered at
; all, since the pose scenes would then walk an empty buffer.
scene_select:
    cmp.w   #NSCENE,d0
    bcc     .out
    cmp.w   cur_scene,d0
    beq     .out
    movem.l d0-d2/a0-a2,-(sp)
    bsr     sd_ensure
    tst.w   sd_ok
    beq.s   .keep
    move.w  d0,cur_scene
    bsr     scene_enter
.keep:
    movem.l (sp)+,d0-d2/a0-a2
.out:
    rts

;----------------------------------------------------------------------
; d0 = scene. Reads its file into the shared buffer unless the buffer
; already holds it. Leaves sd_ok set when the scene may be entered.
sd_ensure:
    move.w  #1,sd_ok
    move.w  d0,d2
    lsl.w   #2,d2
    lea     data_tbl,a0
    move.l  0(a0,d2.w),a1       ; its file name, or 0 for none
    move.l  a1,d1
    beq.s   .done
    cmp.w   sd_scene,d0
    beq.s   .done               ; already in the buffer
    move.w  #-1,sd_scene        ; whatever is in there is about to go

    clr.w   -(sp)               ; Fopen, read only
    move.l  a1,-(sp)
    move.w  #GD_FOPEN,-(sp)
    trap    #1
    lea     8(sp),sp
    tst.l   d0
    bmi.s   .fail
    move.w  d0,d1               ; the handle

    lea     size_tbl,a0
    move.l  0(a0,d2.w),a2       ; how long the file must be
    move.l  sd_base,-(sp)       ; Fread: buffer, length, handle
    move.l  a2,-(sp)
    move.w  d1,-(sp)
    move.w  #GD_FREAD,-(sp)
    trap    #1
    lea     12(sp),sp
    move.l  d0,-(sp)            ; bytes read, across the close

    move.w  d1,-(sp)
    move.w  #GD_FCLOSE,-(sp)
    trap    #1
    addq.l  #4,sp
    move.l  (sp)+,d0

    cmp.l   a2,d0
    bne.s   .fail               ; a short read is not our file
    move.w  d2,d0
    lsr.w   #2,d0
    move.w  d0,sd_scene
    bra.s   .done
.fail:
    clr.w   sd_ok
.done:
    move.w  d2,d0               ; the scene number back, for the caller
    lsr.w   #2,d0
    rts

;----------------------------------------------------------------------
; Hand the machine to the scene in a known state: ink the right way round,
; showing the first buffer, and the buffer blank past the visible screen,
; which is where the cubes' shear slides from.
scene_enter:
    movem.l d0-d2/a0-a2,-(sp)
    move.w  #$000,PALETTE_HW
    move.l  buf_base,d0
    bsr     set_screen_base
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1
    bsr     clear_span
    move.w  cur_scene,d0
    lsl.w   #2,d0
    lea     init_tbl,a0
    move.l  0(a0,d0.w),a0
    jsr     (a0)
    movem.l (sp)+,d0-d2/a0-a2
    rts

;----------------------------------------------------------------------
    include "src/shows/grid.s"
    include "src/shows/halftone.s"
    include "src/shows/sparks.s"
    include "src/shows/glyphs.s"
    include "src/shows/cubes.s"
    include "src/shows/solids.s"
    include "src/shows/monolith.s"
    include "src/shows/hyper.s"

    section text
init_tbl:
    dc.l    gr_init, ht_init, sp_init, gl_init
    dc.l    cu_init, so_init, mo_init, hy_init
frame_tbl:
    dc.l    gr_frame, ht_frame, sp_frame, gl_frame
    dc.l    cu_frame, so_frame, mo_frame, hy_frame
note_tbl:
    dc.l    gr_note_on, ht_note_on, sp_note_on, gl_note_on
    dc.l    cu_note_on, so_note_on, mo_note_on, hy_note_on
data_tbl:
    dc.l    0, 0, 0, 0
    dc.l    nm_cubes, nm_solids, nm_big, nm_hyper
size_tbl:
    dc.l    0, 0, 0, 0
    dc.l    147456, 147488, 196640, 384000

    section data
    even
nm_cubes:   dc.b "CUBES.DAT",0
    even
nm_solids:  dc.b "SOLIDS.DAT",0
    even
nm_big:     dc.b "BIG.DAT",0
    even
nm_hyper:   dc.b "HYPER.DAT",0
    even

    include "src/core/tail.s"

    section bss
    even
sd_buf:         ds.b SD_MAX+256
sd_base:        ds.l 1
sd_scene:       ds.w 1
sd_ok:          ds.w 1
cur_scene:      ds.w 1
    ifd CYCLE
cyc_ctr:        ds.w 1
    endif
    even
