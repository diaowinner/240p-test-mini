;
; Controller reading for Game Boy and Super Game Boy
;
; Copyright 2018 Damian Yerrick
; 
; This software is provided 'as-is', without any express or implied
; warranty.  In no event will the authors be held liable for any damages
; arising from the use of this software.
; 
; Permission is granted to anyone to use this software for any purpose,
; including commercial applications, and to alter it and redistribute it
; freely, subject to the following restrictions:
; 
; 1. The origin of this software must not be misrepresented; you must not
;    claim that you wrote the original software. If you use this software
;    in a product, an acknowledgment in the product documentation would be
;    appreciated but is not required.
; 2. Altered source versions must be plainly marked as such, and must not be
;    misrepresented as being the original software.
; 3. This notice may not be removed or altered from any source distribution.
;
include "src/gb.inc"

DAS_DELAY = 15
DAS_SPEED = 3

SECTION "ram_pads", WRAM0
cur_keys:: ds 1
new_keys:: ds 1
das_keys:: ds 1
das_timer:: ds 1
is_sgb:: ds 1

SECTION "rom_pads", ROM0

; Controller reading ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This controller reading routine is optimized for size.
; It stores currently pressed keys in cur_keys (1=pressed) and
; keys newly pressed since last read in new_keys, with the same
; nibble ordering as the Game Boy Advance.
; 76543210
; |||||||+- A
; ||||||+-- B
; |||||+--- Select
; ||||+---- Start
; |||+----- Right
; ||+------ Left
; |+------- Up
; +-------- Down
;           R
;           L (just kidding)

read_pad::
  ; Poll half the controller
  ld a,P1F_BUTTONS
  call .onenibble
  ld b,a  ; B7-4 = 1; B3-0 = unpressed buttons

  ; Poll the other half
  ld a,P1F_DPAD
  call .onenibble
  swap a   ; A3-0 = unpressed directions; A7-4 = 1
  xor b    ; A = pressed buttons + directions
  ld b,a   ; B = pressed buttons + directions

  ; And release the controller
  ld a,P1F_NONE
  ld [rP1],a

  ; Combine with previous cur_keys to make new_keys
  ld a,[cur_keys]
  xor b    ; A = keys that changed state
  and b    ; A = keys that changed to pressed
  ld [new_keys],a
  ld a,b
  ld [cur_keys],a
  ret

.onenibble:
  ldh [rP1],a  ; switch the key matrix
  ldh a,[rP1]  ; ignore value while waiting for the key matrix to settle
  ldh a,[rP1]
  ldh a,[rP1]
  ldh a,[rP1]
  ldh a,[rP1]
  ldh a,[rP1]  ; the actual read
  or $F0   ; A7-4 = 1; A3-0 = unpressed keys
  ret

;;
; Adds held keys to new_keys, DAS_DELAY frames after press and
; every DAS_SPEED frames thereafter
; @param B which keys are eligible for autorepeat
autorepeat::
  ; If no eligible keys are held, skip all autorepeat processing
  ld a,[cur_keys]
  and b
  ret z
  ld c,a  ; C: Currently held

  ; If any keys were pressed, set the eligible keys among them
  ; as the autorepeating set
  ld a,[new_keys]
  ld d,a  ; D: new_keys
  or a
  jr z,.no_restart_das
  and b
  ld [das_keys],a
  ld a,DAS_DELAY
  jr .have_das_timer
.no_restart_das:

  ; If time has expired, merge in the autorepeating set
  ld a,[das_timer]
  dec a
  jr nz,.have_das_timer
  ld a,[das_keys]
  and c
  or d
  ld [new_keys],a
  ld a,DAS_SPEED
.have_das_timer:
  ld [das_timer],a
  ret

; Super Game Boy detection ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

detect_sgb::
  ; Try to set the SGB to 2-player mode
  di
  ld hl,sgb_packet_twoplayers
  call sgb_send
  call sgb_wait

  ; When the key matrix is released, SGB returns player number in
  ; bits 1-0 (active low).
  ld a,[rP1]
  and $03
  xor $03
  jr nz, .isSGB

  ; When the key matrix is asserted and released, such as when one
  ; controller is read, SGB advances to the next controller.
  call read_pad
  ld a,[rP1]
  and $03
  xor $03
  jr nz, .isSGB

  ; Not SGB
;  xor a  ; set by previous xor
.haveSGB:
  ld [is_sgb],a
  ld hl,sgb_packet_oneplayer
  jp sgb_send
.isSGB:
  ld a,1
  jr .haveSGB

SIZEOF_SGB_PACKET EQU 16
CHAR_BIT EQU 8

;;
; Sends a Super Game Boy packet starting at HL.
; Assumes no IRQ handler does any sort of controller autoreading.

sgb_send:

  ; B: Number of remaining bytes in this packet
  ; C: Number of remaining packets
  ; D: Remaining bit data
  ; E: Number of remaining bits in this byte
  ld a,$07
  and [hl]
  ret z
  ld c,a

.packetloop:
  ; Start transfer by asserting both halves of the key matrix
  ; momentarily.  (This is like strobing an NES controller.)
  xor a
  ldh [rP1],a
  ld a,$30
  ldh [rP1],a
  push bc
  ld b,SIZEOF_SGB_PACKET
.byteloop:
  ; Read a byte from the packet
  ld e,CHAR_BIT
  ld a,[hl+]
  ld d,a
.bitloop:
  ; Send a 1 as $10 then $30, or a 0 as $20 then $30
  ld a,$10
  bit 0,d
  jr nz,.bitIs0
  ld a,$20
.bitIs0:
  ldh [rP1],a
  ld a,$30
  ldh [rP1],a

  ; Advance D to next bit (this is like NES MMC1)
  rr d
  dec e
  jr nz,.bitloop
  dec b
  jr nz,.byteloop

  ; Send $20 $30 as end of packet
  ld a,$20
  ld [rP1],a
  ld a,$30
  ld [rP1],a

  call sgb_wait
  pop bc
  dec c
  jr nz,.packetloop
  ret

;;
; Waits about 4 frames for Super Game Boy to have processed a command
sgb_wait:
  ld de, 7000
.loop:
  nop
  nop
  nop
  dec de
  ld a, e
  or d
  jr nz, .loop
  ret

sgb_packet_twoplayers:
  db ($11 << 3) + 1
  db 1
  ds 14

sgb_packet_oneplayer:
  db ($11 << 3) + 1
  db 0
  ds 14