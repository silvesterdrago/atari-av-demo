;======================================================================
;  BENCH
;
;  Not a show. It measures the one constant every "how big can the
;  figure be" question reduces to: what it costs to touch a byte of
;  screen on this machine, in mono, with the shifter competing for the
;  bus. Fills the visible screen FILLS times per pass with movem.l --
;  the fastest store the 68000 has, 32 bytes per instruction -- and
;  counts passes.
;
;  Read bar three (row 8): passes completed per 64 frames, then
;      cycles/byte = (64/passes) * 112000 / (FILLS * 30720)
;  The book answer for this loop is 88 cycles per 32 bytes = 2.75.
;======================================================================
    include "src/core/head.s"

    ifnd FILLS
FILLS       equ 4               ; fills per pass. wait_vbl rounds a pass up
    endif                       ; to whole frames, so the way to pin the
                                ; cost is to vary this and watch where the
                                ; frames-per-pass count steps up
; skip the top 16 rows: the diagnostic bars live there, and a fill that
; covers them leaves every captured frame with nothing to read
SKIP        equ 16*80
SCR_BYTES   equ SCR_PAGES*256-SKIP

show_init:
    rts

show_frame:
    movem.l d0-d7/a0-a1,-(sp)
    moveq   #0,d0
    moveq   #0,d1
    moveq   #0,d2
    moveq   #0,d3
    moveq   #0,d4
    moveq   #0,d5
    moveq   #0,d6
    moveq   #0,d7
    move.w  #FILLS,bench_left
.pass:
    move.l  cur_base,a1
    add.l   #SKIP,a1
    move.l  a1,a0
    add.l   #SCR_BYTES,a0       ; movem to memory only counts downwards
.fill:
    movem.l d0-d7,-(a0)
    cmpa.l  a1,a0               ; no dbra: d0-d7 all have to stay zero
    bne.s   .fill
    subq.w  #1,bench_left
    bne.s   .pass

    addq.w  #1,show_ctr
    movem.l (sp)+,d0-d7/a0-a1
    rts

show_note_on:
    rts

    include "src/core/tail.s"

    section bss
bench_left: ds.w 1
