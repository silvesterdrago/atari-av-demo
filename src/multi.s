;======================================================================
;  NOISE AV -- every scene in one binary, switched on the number keys.
;
;  1 GRID   2 HALFTONE   3 SOLIDS   4 MONOLITH   5 SPARKS
;  any other key = a hit on a pad        ESC = quit
;
;  HYPER cannot join: its twelve baked screens want 384 KB of data and the
;  same again of aligned buffer, three quarters of the machine. It stays
;  a binary of its own.
;======================================================================
SCENES      equ 1               ; tells the core's key handler to dispatch
POOL_SIZE   equ 1024            ; no scene here wants the noise pool
RANGE_PAGES equ 131             ; 256 pages: two whole screens, for the
                                ; scenes that flip between them
    include "src/core/head.s"

NSCENE      equ 5

;----------------------------------------------------------------------
show_init:
    ifd START                       ; which scene the binary opens on
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
; Hand the machine to the cur_scene in a known state: ink the right way round,
; showing the first buffer, and both buffers blank -- a cur_scene that flips
; would otherwise inherit the last one's picture in the buffer it is about
; to draw into.
scene_enter:
    movem.l d0-d2/a0-a2,-(sp)
    move.w  #$000,PALETTE_HW
    move.l  buf_base,d0
    bsr     set_screen_base
    move.l  buf_base,a0
    move.l  a0,a1
    add.l   #2*SCR_SIZE,a1
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
    include "src/shows/solids.s"
    include "src/shows/monolith.s"
    include "src/shows/sparks.s"

    section text
init_tbl:
    dc.l    gr_init, ht_init, so_init, mo_init, sp_init
frame_tbl:
    dc.l    gr_frame, ht_frame, so_frame, mo_frame, sp_frame
note_tbl:
    dc.l    gr_note_on, ht_note_on, so_note_on, mo_note_on, sp_note_on

    include "src/core/tail.s"

    section bss
    even
cur_scene:      ds.w 1
    ifd CYCLE
cyc_ctr:        ds.w 1
    endif
    even
