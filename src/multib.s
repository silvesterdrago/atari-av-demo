;======================================================================
;  NOISE AV set B -- cubes, halftone and the hyperspace jump.
;
;  1 CUBES   2 HALFTONE   3 HYPER
;  any other key = a hit on a pad        ESC = quit
;
;  HYPER.DAT must sit beside this binary: the jump's frames are read off
;  the card at start-up, not carried in the program.
;======================================================================
SCENES      equ 1               ; tells the core's key handler to dispatch
POOL_SIZE   equ 1024
RANGE_PAGES equ 8               ; the cubes' shear walks the base a few pages
    include "src/core/head.s"

NSCENE      equ 3

;----------------------------------------------------------------------
show_init:
    bsr     hy_load             ; take the card read at boot, not mid-set
    ifd START
    move.w  #START,cur_scene
    else
    clr.w   cur_scene
    endif
    ifd CYCLE
    clr.w   cyc_ctr                 ; test build: walk the scenes on a timer,
    endif                           ; down the same path a key takes
    bra     scene_enter

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
; d0 = 0..8 from the number keys.
scene_select:
    cmp.w   #NSCENE,d0
    bcc.s   .out
    cmp.w   cur_scene,d0
    beq.s   .out                ; already there; do not restart it
    move.w  d0,cur_scene
    bra     scene_enter
.out:
    rts

;----------------------------------------------------------------------
; Hand the machine to the scene in a known state: ink the right way round,
; showing the first buffer, and the buffer blank -- HYPER shows its own
; frames and the other two draw into this one.
scene_enter:
    movem.l d0-d2/a0-a2,-(sp)
    move.w  #$000,PALETTE_HW
    move.l  buf_base,d0
    bsr     set_screen_base
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #SCR_SIZE+1024,a1   ; past the visible screen, for the shear
    bsr     clear_span
    move.w  cur_scene,d0
    lsl.w   #2,d0
    lea     init_tbl,a0
    move.l  0(a0,d0.w),a0
    jsr     (a0)
    movem.l (sp)+,d0-d2/a0-a2
    rts

;----------------------------------------------------------------------
    include "src/shows/cubes.s"
    include "src/shows/halftone.s"
    include "src/shows/hyper.s"

    section text
init_tbl:
    dc.l    cu_init, ht_init, hy_init
frame_tbl:
    dc.l    cu_frame, ht_frame, hy_frame
note_tbl:
    dc.l    cu_note_on, ht_note_on, hy_note_on

    include "src/core/tail.s"

    section bss
    even
cur_scene:      ds.w 1
    ifd CYCLE
cyc_ctr:        ds.w 1
    endif
    even
