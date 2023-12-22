.nds
.relativeinclude on
.erroronwarning on

.open "ftc/overlay9_22", 02223E00h

; Makes Nikolai (event 67) appear without having completed Monastery (event flag 6).
.org 0x02233270
  nop
.org 0x02233280
  mov r1, 0h


; Fixes object 60 (various Ecclesia events) so that the events that happen after killing Albus take precedence over the ones that happen before it.
; To do this we simply switch around the order of branches taken.
.org 0x022376A8
  bne 02237784h
.org 0x022376B0
  beq 02237784h
.org 0x02237750
  bne 022377C4h
.org 0x02237758
  beq 022377C4h
.org 0x02237790
  beq 022376DCh

.close


; Set the var B of certain events to 0.
; Var B for events is the prerequisite event flag you need before this event will appear.
; Setting it to 0 allows these events to appear even if you don't have the prerequisite flag.
.open "ftc/overlay9_51", 022C1FE0h
.org 0x022CF55C+0Ah ; Event 69
  .halfword 0
.close
.open "ftc/overlay9_53", 022C1FE0h
.org 0x022CD85C+0Ah ; Event 6B
  .halfword 0
.close
.open "ftc/overlay9_64", 022C1FE0h
.org 0x022CDAB0+0Ah ; Event 6C
  .halfword 0
.close
.open "ftc/overlay9_59", 022C1FE0h
.org 0x022D3564+0Ah ; Event 6F
  .halfword 0
.close
.open "ftc/overlay9_62", 022C1FE0h
.org 0x022C5FC8+0Ah ; Event 71
  .halfword 0
.close
.open "ftc/overlay9_60", 022C1FE0h
.org 0x022D2DC4+0Ah ; Event 74
  .halfword 0
.close
.open "ftc/overlay9_67", 022C1FE0h
.org 0x022C994C+0Ah ; Event 7E
  .halfword 0
.close
.open "ftc/overlay9_75", 022C1FE0h
.org 0x022CEDB8+0Ah ; Event 85
  .halfword 0
.close
