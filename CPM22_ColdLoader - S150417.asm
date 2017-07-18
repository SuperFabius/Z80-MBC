;==============================================================================
; Z80-MBC CP/M 2.2 Cold Loader - S150417
;
; Embedded into IOS S221116 R130417 (and following until otherwise stated)
;
;             Z80-MBC - HW ref: A041116
; Virtual Disk Module - HW ref: A110417
;
;==============================================================================

; CP/M addresses
CCP     .equ    $E400           ; CBASE: (CP/M System)
BDOS    .equ    CCP + $806      ; BDOS entry
BIOS    .equ    CCP + $1600     ; BIOS entry (jumps to BOOT)

; Commons ASCII chars
eos     .equ   $00              ; End of string
cr      .equ   $0d              ; Carriage return
lf      .equ   $0a              ; Line feed

; Definitions
LDSECT  .equ    50              ; Number of total sectors to load (CCP+BDOS+BIOS).
                                ; Max 64 sectors (two tracks)

; Starting address
        .org    $80

; =========================================================================== ;

    ; Load CCP+BDOS+BIOS from the system area of disk 0 (track 0 and 1).
    ; CCP+BDOS+BIOS are stored from sector 1 track 0 
    ; (total LDSECT sectors to load)
    ld      sp, $80         ; Space for local stack 
    ld      hl, LoaderMsg1  ; Print a message
    call    puts
    ld      a, LDSECT       ; Initialize the sectors counter
    ld      d, 0            ; D = first track = 0
    ld      e, 1            ; E = fisrt sector = 1
    ld      hl, CCP         ; HL = DMA = CCP starting address
    ld      (SECTCNT), a    ; Save the sectors counter
    ld      (DMABUFF), hl   ; Save current DMA (Disk Memory Access) address

LDLOOP
    ld      c, d            ; Select track
    call    SETTRK
    ld      c, e            ; Select sector
    call    SETSEC
    ld      bc, (DMABUFF)   ; BC = current DMA
    ld      hl, 128
    add     hl, bc          ; HL = DMA + 128
    ld      (DMABUFF), hl   ; Save next DMA
    ld      (DMAAD), bc     ; Set current DMA
    call    READ            ; Read one sector
    or      a               ; Set flags (A = error code)
    jr      nz, FATALERR    ; Jump on CP/M load read error
    ld      a, (SECTCNT)    ; A = sectors counter
    dec     a               ; A = A - 1
    jr      z, LOADEND      ; Jump if A = 0 (all done)
    ld      (SECTCNT), a    ; Save updated sectors counter
    inc     e               ; E = next sector
    ld      a, 33
    cp      e               ; Next sector = 33?
    jr      nz, LDLOOP      ; No, jump
    ld      e, 1            ; Set next sector = 1
    ld      d, e            ; Set next track = 1
    jr      LDLOOP

FATALERR
    ld      hl, FatalMsg    ; Print a message
    call    puts
    halt

LOADEND
    ld      hl, LoaderMsg2  ; Print a message
    call    puts
    jp  BIOS                ; Jump to CP/M Cold Boot
    
; =========================================================================== ;

SETTRK  
    ; Register C contains the track number for subsequent Disk 0 accesses
    ld a, c
    out     ($0a), a        ; Select low byte of the Track number
    xor     a
    out     ($0a), a        ; Select hogh byte of the Track number
    ret
    
; =========================================================================== ;

SETSEC
    ; Register C contains the sector number for subsequent Disk 0 accesses
    ld a, c
    out     ($0b), a        ; Select low byte of the Sector number
    xor     a
    out     ($0b), a        ; Select hogh byte of the Sector number
    ret

; =========================================================================== ;

READ
    ; Assuming the track, the sector, the DMA address have been set, the READ 
    ; subroutine attempts to read one sector based upon these parameters and 
    ; returns the following error codes in register A:                                                                 ;
    ;
    ;     0 - no errors occurred
    ;     1 - non recoverable error condition occurred
    xor     a               ; A = 0
    out     ($09), a        ; Select Disk 0 (needed to enable read operation. See IOS SELDISK)
    ld      c, $06          ; C = Disk Read I/O address
    ld      b, 128          ; B = bytes to move (128 bytes = 1 sector)
    ld      hl, (DMAAD)     ; HL = DMA address
    inir                    ; Read a sector
    in      a, ($05)        ; Read error code (0 = no errors)
    or      a               ; Set flags
    ret     z               ; Return if no error (A = 0)
    ld      a, 1
    ret                     ; Return with error (A = 1)

; =========================================================================== ;
            
puts
    ; Send a string to the serial line, HL contains the pointer to the string
    ld      a, (hl)
    cp      eos             ; End of string reached?
    jr      z, puts_end     ; Yes, jump
    out     (1), a          ; No, print
    inc     hl              ; Increment character pointer
    jr      puts            ; Transmit next character
puts_end
    ret

; =========================================================================== ;

; MESSAGES

FatalMsg    .db     cr, lf, "FATAL DISK READ ERROR - SYSTEM HALTED", eos
LoaderMsg1  .db     cr, lf, lf, "Z80-MBC CP/M 2.2 Cold Loader - S150417"
            .db     cr, lf, "Loading...", eos
LoaderMsg2  .db     " done", cr, lf, eos

; =========================================================================== ;

; DATA AREA

SECTCNT     .block  1
DMABUFF     .block  2
DMAAD       .block  2

            .end