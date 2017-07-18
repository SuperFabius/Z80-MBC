;==============================================================================
; S091216 R230117 - uLoader
; Z80-MBC Bootloader (Phase 1 boot program) - HW ref: A041116 
;
; This bootloader is embedded into IOS - I/O Subsystem - S221116 R230117
;==============================================================================
;
; CHANGELOG:
;
; S091216				First release
; S091216 R230117		Changed starting address, little optimization, 
;						renamed as uLoader :-)
;						WARNING: this release * is not * compatible with
;						previous IOS release (before S221116 R230117)
;
;==============================================================================
;
;  Memory layout:
;
;  +-------+
;  ! $0000 !    uLoader at startup
;  !  ---  !
;  ! $0037 !
;  +-------+
;  ! $0038 !    not used
;  !  ---  !
;  ! $FF7F !
;  +-------+
;  ! $FF80 !    uLoader after relocation
;  !  ---  !
;  ! $FFB7 !
;  +-------+
;  ! $FFB8 !    not used
;  !  ---  !	(reserved for uLoader updates)
;  ! $FFFF !
;  +-------+
;
;
;==============================================================================

DstAdr			.equ	$ff80				; Address where to move the bootloader at run time
IOboot2			.equ	02h					; I/O port address for reading the stored 
											; phase 2 boot program, one byte each read access

;------------------------------------------------------------------------------

				.org	$0000
Reset:			jr		Start1
Boot2StrAdr:	.block	2					; starting address of the phase 2 boot program
											; (dinamically written by IOS during loading)
											; Boot2StrAdr -> LSB, Boot2StrAdr+1 -> MSB
Boot2Lenght:	.block	2					; lenght in bytes of the phase 2 boot program 
											; (dinamically written by IOS during loading)
											; Boot2Lenght -> LSB, Boot2Lenght+1 -> MSB
											
Start1:			; move to address DstAdr all the program starting from ToMove address, 
				; and jump to it
				ld		hl,ToMove			; HL = source address (ToMove)
				ld		de,DstAdr			; DE = destination address (DstAdr)
				ld		bc,LastByte-ToMove	; BC = bytes to be ToMove
				ldir						; move all the part starting from ToMove 
											; to LastByte at address DstAdr
				jp		ToMove+Delta		; and jump there	

;------------------------------------------------------------------------------
				
ToMove:			; load the phase 2 boot program and jump to it
				; NOTE: this address after the move correspond to DstAdr, so run time (after the move) 
				;		address are given adding Delta = (DstAdr - ToMove) to the address
				ld		de,(Boot2Lenght)	; DE = lenght in bytes of the phase 2 boot program
				ld		hl,(Boot2StrAdr)	; HL = starting address of the phase 2 boot program
				ld		ix,(Boot2StrAdr)	; IX = starting address of the phase 2 boot program
				ld		c,IOboot2			; C = I/O address of phase 2 boot program storage
				ld		b,0					; B = 0 (= 256 bytes to move)
				ld		a,d					; A = MSB of Boot2Lenght
				or		a					; set Z flag
LoopMSB:		jp		z,LoopLSB+Delta		; jump if A = 0 (< 256 bytes to load)
				inir						; load a 256 bytes lot of the phase 2 boot program
				dec		a					; A = A - 1
				jp		LoopMSB+Delta		; load next 256 bytes lot
								
LoopLSB:		
				ld		a,e					; A = LSB of Boot2Lenght
				or		a					; set flags
				jp		z,JmpPhase2+Delta	; jump if A = 0 (0 bytes to load, so all done)
				ld		b,e					; B = bytes to move (= LSB of Boot2Lenght < 256)
				inir						; load last (<256) bytes of the phase 2 boot program
JmpPhase2:		jp		(ix)				; all done, so jump to the phase 2 boot program
LastByte:

;------------------------------------------------------------------------------

Delta			.equ		DstAdr-ToMove	; Displacement to add to address 
											; for the run time moved part			
				.end