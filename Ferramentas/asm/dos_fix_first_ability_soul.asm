.nds
.relativeinclude on
.erroronwarning on

.open "ftc/arm9.bin", 02000000h

; This fixes a bug in the original game that occurs when you get your first ability soul. It activates more ability souls than you actually possess.
;
; The bug works like this: The first time you get an ability soul, the same function that equips the first bullet/guardian/enchant souls you get in the tutorial tries to run on the ability soul you get too. But this is a problem, because while your equipped bullet/guardian/enchant souls are stored as an integer representing the ID of the soul you have equipped, the ability souls you have equipped is stored as a bit field.
; For example, Doppelganger is the 2nd ability soul (counting from 0, not from 1). 2 in binary is 00000010. When it tries to store this in the bitfield representing the ability souls you have activated, it activates the 1st ability soul, Malphas. In other words, if your first ability soul is Doppelganger you gain both Doppelganger and Malphas. (Though Malphas doesn't show up in the list of ability souls you own, so you can't deactivate it.)
; This bug isn't noticeable in a normal playthrough because the first ability soul you get is always Balore. Balore is the 0th ability soul, and 0 in binary is still 0, so no extra souls get activated.

.org 0x0202E258 ; Run the first time you get an ability soul. This branches to the bugged code.
  b 0202E300h ; Replace with a branch to after the bugged code is over.

.close
