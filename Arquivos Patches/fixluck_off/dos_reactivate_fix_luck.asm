.nds
.relativeinclude on
.erroronwarning on

.open "../../Extracted files Castlevania - Alvor da Tristeza (BR)/ftc/overlay9_0", 0x02000000

; Reactivate the original luck behavior, by reverting all byte values to the original.

.org 0x0202567C
.stringn 0x85,0x29

.org 0x02025688
.stringn 0x42,0x78
  
.org 0x0202568C
.stringn 0x07,0x09

.org 0x02025690
.stringn 0x40,0x78,0xA0,0x11

.org 0x0202569A
.stringn 0x67,0xE2
  
.org 0x020256BC
.stringn 0x06,0x63,0xA0,0xE1
  
.org 0x020257A0
.stringn 0x02,0x7A,0x67,0xE2
  
.org 0x020257C8
.stringn 0x07,0x00,0xA0,0xE1

.org 0x020257F0
.stringn 0x00,0x90,0xA0,0xE1

.org 0x02025800
.stringn 0x80,0x90,0xA0,0x01

.org 0x02025804
.stringn 0x07,0x00,0xA0,0xE1
  

.close