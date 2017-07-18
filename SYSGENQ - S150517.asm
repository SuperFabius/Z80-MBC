;==============================================================================
; Z80-MBC - SYSGENQ - S150517
;
; SYSGEN-like program to install QP/M 2.71 using QINSTALL
;
;             Z80-MBC - HW ref: A041116
; Virtual Disk Module - HW ref: A110417
;  Generic DS3231 RTC - Generic ebay RTC DE3231 I2C module (optional)
;
; Required IOS S221116 R110517 or newer (until otherwise stated)
;
;==============================================================================

; CP/M addresses
CCP     .equ    $900            ; CP/M System load address
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
    .org    $100                ; CP/M programs starting address

; =========================================================================== ;

    ; Load or write CCP+BDOS+BIOS from/to the system area of disk 0 (track 0 and 1)
    ; to/from RAM. CCP+BDOS+BIOS are stored from sector 1 track 0. 
    ; (LDSECT is the total number of sectors to load/write)
    ld      (CPMSP),SP      ; Save CP/M SP
    ld      sp, (LOCSTK)    ; Set the local stack 
    ld      hl, LoaderMsg1  ; Print a message
    call    puts
    ld      hl, askCommMsg  ; Ask the operation (R/W)
    call    puts
waitComm
    call    getc            ; Wait the choice
    call    to_upper        ; Convert it to uppercase
    ld      (COMMAND), a    ; Save it
    out     (1), a          ; Send echo
    cp      'R'             ; READ?
    jr      z, SYSRDWR      ; Yes, jump to read/write function
    cp      'W'             ; WRITE?
    jr      nz, waitComm    ; No, wait for a valid char
SYSRDWR
    ld      a, (COMMAND)    ; A = 'R' or 'W'
    cp      'W'             ; A = 'W' ?
    jr      z, INITWR       ; Yes, jump
    ld      hl, ReadMsg     ; No, print a message
    call    puts
    jr      INIT            ; Jump to do the rerquested operation
INITWR
    ld      hl, WriteMsg    ; No, print a message
    call    puts
INIT        ; initialize the read or write operation
    ld      a, LDSECT       ; Initialize the sectors counter
    ld      d, 0            ; D = first track = 0
    ld      e, 1            ; E = fisrt sector = 1
    ld      hl, CCP         ; HL = DMA = CCP starting address
    ld      (SECTCNT), a    ; Save the sectors counter
    ld      (DMABUFF), hl   ; Save current DMA (Disk Memory Access) address
LDLOOP      ; Do the read or wrote operation
    ld      c, d            ; Select track
    call    SETTRK
    ld      c, e            ; Select sector
    call    SETSEC
    ld      bc, (DMABUFF)   ; BC = current DMA
    ld      hl, 128
    add     hl, bc          ; HL = DMA + 128
    ld      (DMABUFF), hl   ; Save next DMA
    ld      (DMAAD), bc     ; Set current DMA

    ld      a, (COMMAND)    ; A = 'R' or 'W'
    cp      'W'             ; A = 'W' ?
    jr      z, WRITESEC     ; Yes, jump to write a sector
    call    READ            ; No, Read one sector
    jr      CHECKFLG        ; Jump to check the result flag
WRITESEC
    call    WRITE           ; Write one sector
CHECKFLG
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
    ld      hl, DoneMsg     ; Print a message
    call    puts
    ld      sp, (CPMSP)     ; Restore the CP/M SP
    ret                     ; Return to CP/M
    
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

WRITE
    ; Data is written from the currently selected DMA address to the currently
    ; selected drive, track, and sector. The error codes given in the READ command 
    ; are returned in register A
    xor     a               ; A = 0
    out     ($09), a        ; Select Disk 0 (needed to enable write operation. See IOS SELDISK)
    ld      c, $0c          ; C = Disk Write I/O address
    ld      b, 128          ; B = bytes to move (128 bytes = 1 sector)
    ld      hl, (DMAAD)     ; HL = DMA address
    otir                    ; Write a sector
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

getc
    ; Wait for a single incoming character on the serial line
    ; and read it, result is in A:
    in      a, (1)          ; read a char from uart
    cp      $ff             ; is = $FF?
    jp      z, getc         ; if yes jump until a valid char is received
    ret

; =========================================================================== ;

to_upper
    ; Convert a single character contained in A to upper case:
    cp      'a'             ; Nothing to do if not lower case
    ret     c
    cp      'z' + 1         ; > 'z'?
    ret     nc              ; Nothing to do, either
    and     $5f             ; Convert to upper case
    ret

; =========================================================================== ;

    ; Print_byte prints a single byte in hexadecimal notation to the serial line.
    ; The byte to be printed is expected to be in A.
print_byte      
    push    af              ; Save the contents of the registers
    push    bc
    ld      b, a
    rrca
    rrca
    rrca
    rrca
    call    print_nibble    ; Print high nibble
    ld      a, b
    call    print_nibble    ; Print low nibble
    pop     bc              ; Restore original register contents
    pop     af
    ret
 
; =========================================================================== ; 

    ; Print_nibble prints a single hex nibble which is contained in the lower 
    ; four bits of A:
print_nibble    
    push    af              ; We won't destroy the contents of A
    and     $f              ; Just in case...
    add     a, '0'          ; If we have a digit we are done here.
    cp      '9' + 1         ; Is the result > 9?
    jr      c, print_nibble_1
    add     a, 'A' - '0' - $a ; Take care of A-F
print_nibble_1  
    out     (1), a          ; Print the nibble and
    pop     af              ; restore the original value of A
    ret

; =========================================================================== ;
;
; MESSAGES
;
FatalMsg    .db     cr, lf, "FATAL DISK ERROR - SYSTEM HALTED", eos
LoaderMsg1  .db     cr, lf, "SYSGENQ - S150517 - Z80-MBC", cr, lf
            .db     "CP/M 2.2 SYSGEN-like Utility", cr, lf, lf
            .db     "Use only to install QP/M 2.71 using QINSTALL.COM", cr, lf
            .db     "WARNING: W command will overwrite system tracks!", cr, lf, eos
ReadMsg     .db     cr, lf, "Reading...", eos
WriteMsg    .db     cr, lf, "Writing...", eos
DoneMsg     .db     " done", cr, lf, eos
askCommMsg  .db     cr, lf, "Read system tracks and load to RAM or write them back to disk? [R/W] >", eos
CRLF        .db     cr, lf, eos

; =========================================================================== ;
;
; DATA AREA
;
COMMAND     .block  1
SECTCNT     .block  1
DMABUFF     .block  2
DMAAD       .block  2
CPMSP       .block  2
STKAREA     .block  64
LOCSTK      .equ    $

            .end