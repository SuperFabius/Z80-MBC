;==============================================================================
; Z80-MBC QP/M 2.7 BIOS - S080517
;
;             Z80-MBC - HW ref: A041116 
; Virtual Disk Module - HW ref: A110417
;  Generic DS3231 RTC - Generic ebay RTC DE3231 I2C module (optional)
;
; Required IOS S221116 R110517 or newer (until otherwise stated)
;
; CHANGELOG:
;
; S080517           First release
;
;==============================================================================

; "Legacy" CP/M addresses
CCP     = CBASE          ; CP/M System entry
BDOS    = CCP + $806     ; BDOS entry
BIOS    = CCP + $1600    ; BIOS entry
IOBYT   = $0003          ; IOBYTE address
CDISK   = $0004          ; Address of Current drive name and user number
CCPLEN  = CBASE + 7      ; Address of current number of chars into the CCP input buffer
CCPFIRS = CBASE + 8      ; Address of the first charater of the CCP input buffer

; BIOS equates
NDISKS  .equ 2          ; Number of Disk Drives

; Commons ASCII chars
eos     .equ   $00      ; End of string
cr      .equ   $0d      ; Carriage return
lf      .equ   $0a      ; Line feed

    .org BIOS

; =========================================================================== ;
;                                                                             ;
; BIOS jump table                                                             ;
;                                                                             ;
; =========================================================================== ;

BOOT
    jp BOOT_    ; COLD START
WBOOT
WBOOTE
    jp WBOOT_   ; WARM START
CONST
    jp CONST_   ; CONSOLE STATUS
CONIN
    jp CONIN_   ; CONSOLE CHARACTER IN
CONOUT
    jp CONOUT_  ; CONSOLE CHARACTER OUT
LIST
    jp LIST_    ; LIST CHARACTER OUT
PUNCH
    jp PUNCH_   ; PUNCH CHARACTER OUT
READER
    jp READER_  ; READER CHARACTER OUT
HOME
    jp HOME_    ; MOVE HEAD TO HOME POSITION
SELDSK
    jp SELDSK_  ; SELECT DISK
SETTRK
    jp SETTRK_  ; SET TRACK NUMBER
SETSEC
    jp SETSEC_  ; SET SECTOR NUMBER
SETDMA
    jp SETDMA_  ; SET DMA ADDRESS
READ
    jp READ_    ; READ DISK
WRITE
    jp WRITE_   ; WRITE DISK
PRSTAT
    jp LISTST_  ; RETURN LIST STATUS
SECTRN
    jp SECTRN_  ; SECTOR TRANSLATE

DPBASE
               ; DISK PARAMETER HEADER FOR DISK 00
    .dw TRANTAB; Sector translation.
    .dw $0000  ; Scratch
    .dw $0000  ; Scratch
    .dw $0000  ; Scratch
    .dw DIRBF  ; Address of a 128-byte scratch pad area. All DPHs address the same scratch pad area.
    .dw DPB0   ; Address of a disk parameter block. Identical drives address the same disk parameter block.
    .dw $0000  ; Address of a scratch pad area for check for changed disks. This address is different for each DPH.
    .dw ALL00  ; Address of a scratch pad area for disk storage allocation information. Different for each DPH.

               ; DISK PARAMETER HEADER FOR DISK 01
    .dw TRANTAB; Sector translation.
    .dw $0000  ; Scratch
    .dw $0000  ; Scratch
    .dw $0000  ; Scratch
    .dw DIRBF  ; Address of a 128-byte scratch pad area. All DPHs address the same scratch pad area.
    .dw DPB1   ; Address of a disk parameter block. Identical drives address the same disk parameter block.
    .dw $0000  ; Address of a scratch pad area for check for changed disks. This address is different for each DPH.
    .dw ALL01  ; Address of a scratch pad area for disk storage allocation information. Different for each DPH.
    
DPB0           ; DISK PARAMETER BLOCK DISK 0
    .DW 32     ; SECTORS PER TRACK
    .DB 3      ; BLOCK SHIFT FACTOR
    .DB 7      ; BLOCK MASK
    .DB 0      ; EXTNT MASK
    .DW 127    ; DISK SIZE-1
    .DW 63     ; DIRECTORY MAX
    .DB 192    ; ALLOC 0
    .DB 0      ; ALLOC 1
    .DW 0      ; CHECK SIZE (No check needed. So DPH address to scratch pad = $0000 too)
    .DW 2      ; TRACK OFFSET

DPB1           ; DISK PARAMETER BLOCK DISK 1
    .DW 32     ; SECTORS PER TRACK
    .DB 3      ; BLOCK SHIFT FACTOR
    .DB 7      ; BLOCK MASK
    .DB 0      ; EXTNT MASK
    .DW 127    ; DISK SIZE-1
    .DW 63     ; DIRECTORY MAX
    .DB 192    ; ALLOC 0
    .DB 0      ; ALLOC 1
    .DW 0      ; CHECK SIZE (No check needed. So DPH address to scratch pad = $0000 too)
    .DW 0      ; TRACK OFFSET
    
; Sector translate vector
TRANTAB 
    .DB     1, 2, 3, 4      ; Sectors 1, 2, 3, 4
    .DB     5, 6, 7, 8      ; Sectors 5, 6, 7, 6
    .DB     9, 10, 11, 12   ; Sectors 9, 10, 11, 12
    .DB     13, 14, 15, 16  ; Sectors 13, 14, 15, 16
    .DB     17, 18, 19, 20  ; Sectors 17, 18, 19, 20
    .DB     21, 22, 23, 24  ; Sectors 21, 22, 23, 24
    .DB     25, 26, 27, 28  ; Sectors 25, 26, 27, 28
    .DB     29, 30, 31, 32  ; Sectors 29, 30, 31, 32

; =========================================================================== ;
; BOOT                                                                        ;
; =========================================================================== ;
; The BOOT entry point gets control from the cold start loader and is         ;
; responsible for basic system initialization, including sending a sign-on    ;
; message, which can be omitted in the first version.                         ;
; If the IOBYTE function is implemented, it must be set at this point.        ;
; The various system parameters that are set by the WBOOT entry point must be ;
; initialized, and control is transferred to the CCP at 3400 + b for further  ;
; processing. Note that register C must be set to zero to select drive A.     ;
; =========================================================================== ;
BOOT_
    xor a
    ld      (IOBYT),a       ; Clear IOBYTE
    ld      (CDISK),a       ; Select Disk 0 & User 0
    ld      hl,BiosMsg      ; Print a message
    call    puts
    ;
    ; Set up the execution of AUTOEXEC.SUB if required
    ;
    in      a, (7)          ; Check if AUTOEXEC execution is requierd
    and     $01             ; Isolate AUTOEXEC flag
    jr      z, GOCPM        ; Jump if flag = 0 (nothing to set up)
    ld      bc, CCPAuto     ; Flag = 1, BC = address of AUTOEXEC command string
    ld      hl, CCPFIRS     ; HL = address of the first char of CCP input string
bufCopy     ; Copy the AUTOEXEC command string into the CCP input buffer
    ld      a, (bc)         ; A = current command string char
    cp      eos             ; End of string reached?
    jr      z, bufCopyEnd   ; Yes, jump
    ld      (hl), a         ; No, load it the CCP input buffer
    inc     bc              ; Increment command string character pointer
    inc     hl              ; Increment CCP input buffer character pointer
    jr      bufCopy         ; Copy  next character
bufCopyEnd  ; Calculate command string lenght and store it to CCP input buffer lenght variable
    ld      bc, CCPFIRS     ; BC = address of the first char of CCP input string
    xor     a               ; C = 0
    sbc     hl, bc          ; L = command string lenght (H = 0 always)
    ld      a, l            ; A = command string lenght
    ld      (CCPLEN), a     ; Store it into CCP buffer lenght variable
    jr      GOCPM

; =========================================================================== ;
; WBOOT                                                                       ;
; =========================================================================== ;
; The WBOOT entry point gets control when a warm start occurs.                ;
; A warm start is performed whenever a user program branches to location      ;
; 0000H, or when the CPU is reset from the front panel. The CP/M system must  ;
; be loaded from the first two tracks of drive A up to, but not including,    ;
; the BIOS, or CBIOS, if the user has completed the patch. System parameters  ;
; must be initialized as follows:                                             ;
;                                                                             ;
; location 0,1,2                                                              ;
;     Set to JMP WBOOT for warm starts (000H: JMP 4A03H + b)                  ;
;                                                                             ;
; location 3                                                                  ;
;     Set initial value of IOBYTE, if implemented in the CBIOS                ;
;                                                                             ;
; location 4                                                                  ;
;     High nibble = current user number, low nibble = current drive           ;
;                                                                             ;
; location 5,6,7                                                              ;
;     Set to JMP BDOS, which is the primary entry point to CP/M for transient ;
;     programs. (0005H: JMP 3C06H + b)                                        ;
;                                                                             ;
; Refer to Section 6.9 for complete details of page zero use. Upon completion ;
; of the initialization, the WBOOT program must branch to the CCP at 3400H+b  ;
; to restart the system.                                                      ;
; Upon entry to the CCP, register C is set to the drive to select after system;
; initialization. The WBOOT routine should read location 4 in memory, verify  ;
; that is a legal drive, and pass it to the CCP in register C.                ;
; =========================================================================== ;

WBOOT_
    ; Load CCP+BDOS from the system area of disk 0 (track 0 and 1).
    ; CCP+BDOS are stored from sector 1 track 0 to sector 12 track 1 
    ; (total 44 sectors to load)
    
    ld      sp, $80         ; Use space below buffer for stack 
    ld      hl, WbootMSG    ; Print a message
    call    puts
    ld      c, 0            ; Select disk 0
    call    SELDSK_
    ld      a, 44           ; Initialize the sectors counter
    ld      d, 0            ; D = first track = 0
    ld      e, 1            ; E = fisrt sector = 1
    ld      hl, CCP         ; HL = DMA = CCP starting address
    ld      (SECTCNT), a    ; Save the sectors counter
    ld      (DMABUFF), hl   ; Save current DMA

WBTLOOP
    ld      c, d            ; Select track
    ld      b, 0
    call    SETTRK_
    ld      c, e            ; Select sector
    ld      b, 0
    call    SETSEC_
    ld      bc, (DMABUFF)   ; BC = current DMA
    ld      hl, 128
    add     hl, bc          ; HL = DMA + 128
    ld      (DMABUFF), hl   ; Save next DMA
    call    SETDMA_          ; Set current DMA
    call    READ_            ; Read one sector
    or      a               ; Set flags (A = error code)
    jr      nz, FATALERR    ; Jump on warm boot read error
    ld      a, (SECTCNT)    ; A = sectors counter
    dec     a               ; A = A - 1
    jr      z, WBTEND       ; Jump if A = 0 (all done)
    ld      (SECTCNT), a    ; Save updated sectors counter
    inc     e               ; E = next sector
    ld      a, 33
    cp      e               ; Next sector = 33?
    jr      nz, WBTLOOP     ; No, jump
    ld      e, 1            ; Set next sector = 1
    ld      d, e            ; Set next track = 1
    jr      WBTLOOP

FATALERR
    ld      hl, FatalMsg    ; Print a message
    call    puts
    halt

WBTEND
    ld      hl, CRLFLF      ; Print a CR with two LF
    call    puts

GOCPM
    ld      hl, CPMMsg      ; Print a message
    call    puts
    ld      a, $C3          ; C3 IS A JMP INSTRUCTION
    ld      ($0000), a      ; FOR JMP TO WBOOT
    ld      hl,WBOOTE       ; WBOOT ENTRY POINT
    ld      ($0001), hl     ; SET ADDRESS FIELD FOR JMP AT 0
    
    ld      ($0005), a      ; FOR JMP TO BDOS
    ld      hl, BDOS        ; BDOS ENTRY POINT
    ld      ($0006), hl     ; ADDRESS FIELD OF JUMP AT 5 TO BDOS

    ld      bc, $0080       ; DEFAULT DMA ADDRESS IS 80H
    call    SETDMA_

    ;ei                     ; DO NOT ENABLE THE INTERRUPT SYSTEM
    
    ld      a, (CDISK)      ; GET CURRENT USER/DISK NUMBER (UUUUDDDD)
    and     $0f             ; Isolate the disk number. A = drive number (0, 1)
    cp      NDISKS          ; Drive number ok?
    jr      c, WBTDSKOK     ; Jump if valid number (Carry set if A < NDISKS)
    ld      a, (CDISK)      ; No, set disk 0 (previous user)
    and     $f0
    
WBTDSKOK    
    ld      (CDISK), a      ; Save current User/Disk
    ld      c, a            ; C = current User/Disk for CCP jump
    jp      CCP             ; GO TO CP/M FOR FURTHER PROCESSING

; =========================================================================== ;
; CONST                                                                       ;
; =========================================================================== ;
; You should sample the status of the currently assigned console device and   ;
; return 0FFH in register A if a character is ready to read and 00H in        ;
; register A if no console characters are ready.                              ;
; =========================================================================== ;
CONST_
    ld      a, (InChrBuf)   ; A = previous char read by CONST, if any
    cp      $ff             ; Is = $FF ($FF from UART = no char)?
    jr      nz, InChr       ; No, jump (char already read)
    in      a, (1)          ; Yes, Read a char from "virtual" UART
    ld      (InChrBuf), a   ; Store it
    cp      $ff             ; Is = $FF ($FF from UART = no char)?
    jr      z, NoInChr      ; Yes, jump
    
InChr
    ld      a, $ff          ; No, return CP/M char ready flag ($FF)
    ret
    
NoInChr
    xor     a               ; A = 0
    ret                     ; Return CP/M no char flag ($00)
    
InChrBuf                    ; Last read char by CONST ($FF = no char)
    .fill   1               ; Initialized as $FF

; =========================================================================== ;
; CONIN                                                                       ;
; =========================================================================== ;
; The next console character is read into register A, and the parity bit is   ;
; set, high-order bit, to zero. If no console character is ready, wait until  ;
; a character is typed before returning.                                      ;
; =========================================================================== ;
CONIN_
    ld      a, (InChrBuf)   ; A = previous char read by CONST, if any
ChkInChr    
    cp      $ff             ; Is = $FF (FF from UART = no char)?
    jr      z, GetChr       ; Yes, jump to read a char
    push    af              ; No, InChrBuf = $FF (clear buffer)
    ld      a, $ff
    ld      (InChrBuf), a
    pop     af
    jr      SetChrPar
GetChr
    in      a, (1)          ; Read a char from UART
    cp      $ff             ; Is = $FF (FF from UART = no char)?
    jp      z, GetChr       ; Yes jump until a valid char is received
SetChrPar                   ; Set parity bit to 0
    and     $7f
    ret

; =========================================================================== ;
; CONOUT                                                                      ;
; =========================================================================== ;
; The character is sent from register C to the console output device.         ;
; The character is in ASCII, with high-order parity bit set to zero. You      ;
; might want to include a time-out on a line-feed or carriage return, if the  ;
; console device requires some time interval at the end of the line (such as  ;
; a TI Silent 700 terminal). You can filter out control characters that cause ;
; the console device to react in a strange way (CTRL-Z causes the Lear-       ;
; Siegler terminal to clear the screen, for example).                         ;
; =========================================================================== ;
CONOUT_
    ld      a, c
    out     (1), a
    ret

; =========================================================================== ;
; LIST                                                                        ;
; =========================================================================== ;
; The character is sent from register C to the currently assigned listing     ;
; device. The character is in ASCII with zero parity bit.                     ;
; =========================================================================== ;
LIST_
    ret                     ; Not implemented

; =========================================================================== ;
; PUNCH                                                                       ;
; =========================================================================== ;
; The character is sent from register C to the currently assigned punch       ;
; device. The character is in ASCII with zero parity.                         ;
; =========================================================================== ;
PUNCH_
    ret                     ; Not implemented

; =========================================================================== ;
; READER                                                                      ;
; =========================================================================== ;
; The next character is read from the currently assigned reader device into   ;
; register A with zero parity (high-order bit must be zero); an end-of-file   ;
; condition is reported by returning an ASCII CTRL-Z(1AH).                    ;
; =========================================================================== ;
READER_
    ld      a, $1a          ; Enter an EOF for now (READER not implemented)
    ret

; =========================================================================== ;
; HOME                                                                        ;
; =========================================================================== ;
; The disk head of the currently selected disk (initially disk A) is moved to ;
; the track 00 position. If the controller allows access to the track 0 flag  ;
; from the drive, the head is stepped until the track 0 flag is detected. If  ;
; the controller does not support this feature, the HOME call is translated   ;
; into a call to SETTRK with a parameter of 0.                                ;
; =========================================================================== ;
HOME_
    ld      bc, 0
    jp      SETTRK_

; =========================================================================== ;
; SELDSK                                                                      ;
; =========================================================================== ;
; The disk drive given by register C is selected for further operations,      ;
; where register C contains 0 for drive A, 1 for drive B, and so on up to 15  ;
; for drive P (the standard CP/M distribution version supports four drives).  ;
; On each disk select, SELDSK must return in HL the base address of a 16-byte ;
; area, called the Disk Parameter Header, described in Section 6.10.          ;
; For standard floppy disk drives, the contents of the header and associated  ;
; tables do not change; thus, the program segment included in the sample      ;
; CBIOS performs this operation automatically.                                ;
;                                                                             ;
; If there is an attempt to select a nonexistent drive, SELDSK returns        ;
; HL = 0000H as an error indicator. Although SELDSK must return the header    ;
; address on each call, it is advisable to postpone the physical disk select  ;
; operation until an I/O function (seek, read, or write) is actually          ;
; performed, because disk selects often occur without ultimately performing   ;
; any disk I/O, and many controllers unload the head of the current disk      ;
; before selecting the new drive. This causes an excessive amount of noise    ;
; and disk wear. The least significant bit of register E is zero if this is   ;
; the first occurrence of the drive select since the last cold or warm start. ;
; =========================================================================== ;
SELDSK_
    ld      hl, $0000       ; HL = error code
    ld      a, c            ; A = drive number (0, 1)
    cp      NDISKS          ; Drive number ok?
    ret     nc              ; No, illegal number. Return with error code (No Carry if >= NDISKS)
    out     ($09), a        ; Yes, select it
    ld      (DSKNUM), a     ; Save it
    ld      l, c            ; L = drive number
    ld      h, $00          ; HL = drive number (16 bit)
    add     hl, hl          ; 2 * HL
    add     hl, hl          ; 4 * HL
    add     hl, hl          ; 8 * HL
    add     hl, hl          ; 16 * HL = DPH displacement
    ld      de, DPBASE      ; DE = DPBASE
    add     hl, de          ; HL = DPBASE + (drive_number * 16)
    ret

; =========================================================================== ;
; SETTRK                                                                      ;
; =========================================================================== ;
; Register BC contains the track number for subsequent disk accesses on the   ;
; currently selected drive. The sector number in BC is the same as the number ;
; returned from the SECTRN entry point. You can choose to seek the selected   ;
; track at this time or delay the seek until the next read or write actually  ;
; occurs. Register BC can take on values in the range 0-76 corresponding to   ;
; valid track numbers for standard floppy disk drives and 0-65535 for         ;
; nonstandard disk subsystems.                                                ;
; =========================================================================== ;
SETTRK_  
    ld      (TRACK), bc     ; Save Track Number
    ld      a, c
    out     ($0a), a        ; Select low byte of the Track number
    ld      a, b
    out     ($0a), a        ; Select hogh byte of the Track number
    ret

; =========================================================================== ;
; SETSEC                                                                      ;
; =========================================================================== ;
; Register BC contains the sector number, 1 through 26, for subsequent disk   ;
; accesses on the currently selected drive. The sector number in BC is the    ;
; same as the number returned from the SECTRAN entry point. You can choose to ;
; send this information to the controller at this point or delay sector       ;
; selection until a read or write operation occurs.                           ;
; =========================================================================== ;
SETSEC_
    ld      (SECTOR), bc    ; Save Sector Number
    ld      a, c
    out     ($0b), a        ; Select low byte of the Sector number
    ld      a, b
    out     ($0b), a        ; Select hogh byte of the Sector number
    ret

; =========================================================================== ;
; SETDMA                                                                      ;
; =========================================================================== ;
; Register BC contains the DMA (Disk Memory Access) address for subsequent    ;
; read or write operations. For example, if B = 00H and C = 80H when SETDMA   ;
; is called, all subsequent read operations read their data into 80H through  ;
; 0FFH and all subsequent write operations get their data from 80H through    ;
; 0FFH, until the next call to SETDMA occurs. The initial DMA address is      ;
; assumed to be 80H. The controller need not actually support Direct Memory   ;
; Access. If, for example, all data transfers are through I/O ports, the      ;
; CBIOS that is constructed uses the 128 byte area starting at the selected   ;
; DMA address for the memory buffer during the subsequent read or write       ;
; operations.                                                                 ;
; =========================================================================== ;
SETDMA_
    ld      (DMAAD), bc     ; Save the DMA (Disk Memory Access) address
    ret

; =========================================================================== ;
; READ                                                                        ;
; =========================================================================== ;
; Assuming the drive has been selected, the track has been set, and the DMA   ;
; address has been specified, the READ subroutine attempts to read one sector ;
; based upon these parameters and returns the following error codes in        ;
; register A:                                                                 ;
;                                                                             ;
;     0 - no errors occurred                                                  ;
;     1 - non recoverable error condition occurred                            ;
;                                                                             ;
; Currently, CP/M responds only to a zero or nonzero value as the return      ;
; code. That is, if the value in register A is 0, CP/M assumes that the disk  ;
; operation was completed properly. If an error occurs the CBIOS should       ;
; attempt at least 10 retries to see if the error is recoverable. When an     ;
; error is reported the BDOS prints the message BDOS ERR ON x: BAD SECTOR.    ;
; The operator then has the option of pressing a carriage return to ignore    ;
; the error, or CTRL-C to abort.                                              ;
; =========================================================================== ;
READ_
    push    hl
    push    bc
    ld      a, (DSKNUM)     ; A = Disk Number
    out     ($09), a        ; Select Disk (needed to enable read operation. See IOS SELDISK)
    ld      c, $06          ; C = Disk Read I/O address
    ld      b, 128          ; B = bytes to move (128 bytes = 1 sector)
    ld      hl, (DMAAD)     ; HL = DMA address
    inir                    ; Read a sector
    pop     bc
    pop     hl
    in      a, ($05)        ; Read error code (0 = no errors)
    or      a               ; Set flags
    ret     z               ; Return if no error (A = 0)
    ld      a, 1
    ret                     ; Return with error (A = 1)

; =========================================================================== ;
; WRITE                                                                       ;
; =========================================================================== ;
; Data is written from the currently selected DMA address to the currently    ;
; selected drive, track, and sector. For floppy disks, the data should be     ;
; marked as nondeleted data to maintain compatibility with other CP/M         ;
; systems. The error codes given in the READ command are returned in register ;
; A, with error recovery attempts as described above.                         ;
; =========================================================================== ;
WRITE_
    push    hl
    push    bc
    ld      a, (DSKNUM)     ; A = Disk Number
    out     ($09), a        ; Select Disk ù(needed to enable write operation. See IOS SELDISK)
    ld      c, $0c          ; C = Disk Write I/O address
    ld      b, 128          ; B = bytes to move (128 bytes = 1 sector)
    ld      hl, (DMAAD)     ; HL = DMA address
    otir                    ; Write a sector
    pop     bc
    pop     hl
    in      a, ($05)        ; Read error code (0 = no errors)
    or      a               ; Set flags
    ret     z               ; Return if no error (A = 0)
    ld      a, 1
    ret                     ; Return with error (A = 1)

; =========================================================================== ;
; LISTST                                                                      ;
; =========================================================================== ;
; You return the ready status of the list device used by the DESPOOL program  ;
; to improve console response during its operation. The value 00 is returned  ;
; in A if the list device is not ready to accept a character and 0FFH if a    ;
; character can be sent to the printer. A 00 value should be returned if LIST ;
; status is not implemented.                                                  ;
; =========================================================================== ;
LISTST_
    xor     a               ; A = 0 (not implemented)
    ret

; =========================================================================== ;
; SECTRAN                                                                     ;
; =========================================================================== ;
; Logical-to-physical sector translation is performed to improve the overall  ;
; response of CP/M. Standard CP/M systems are shipped with a skew factor of   ;
; 6, where six physical sectors are skipped between each logical read         ;
; operation. This skew factor allows enough time between sectors for most     ;
; programs to load their buffers without missing the next sector. In          ;
; particular computer systems that use fast processors, memory, and disk      ;
; subsystems, the skew factor might be changed to improve overall response.   ;
; However, the user should maintain a single-density IBM-compatible version   ;
; of CP/M for information transfer into and out of the computer system, using ;
; a skew factor of 6.                                                         ;
;                                                                             ;
; In general, SECTRAN receives a logical sector number relative to zero in BC ;
; and a translate table address in DE. The sector number is used as an index  ;
; into the translate table, with the resulting physical sector number in HL.  ;
; For standard systems, the table and indexing code is provided in the CBIOS  ;
; and need not be changed.                                                    ;
; =========================================================================== ;
SECTRN_
    EX      DE, HL          ; HL = translate table
    ADD     HL, BC          ; HL = translate table (sector)
    LD      l, (hl)         ; L = translate table (sector)
    LD      h, 0            ; HL = translate table (translated sector)
    ret                     ; Return with value in HL

; =========================================================================== ;
; TIMDAT                                                                      ;
; =========================================================================== ;
; This ia a QP/M specific routine for the QP/M-to-real-time-clock interface   ;
; to fully utilize the time/date stamping features of QP/M.                   ;
; The address of TIMDAT must be specified during QINSTALL via option <2> of   ;
; the QDOS installation menu (see pages 26-27 of the QP/M Installation Guide) ; 
;                                                                             ;
; NOTE: If the RTC is not present, IOS will give all 0s bytes. Unintentionally;
;       I discovered that this is "interpreted" by QP/M as a "NO CLOCK"!!!    ;                                         ;
; =========================================================================== ;
TIMDAT
    jp      USERCLK
USERCLK
    in      a, (7)          ; Reset IOS DATETIME I/O counter
    in      a, (8)          ; Read RTC seconds
    ld      (USERDT +5 ), a ; Store it into the date/time vector
    in      a, (8)          ; Read RTC minutes
    ld      (USERDT + 4), a ; Store it into the date/time vector
    in      a, (8)          ; Read RTC hours
    ld      (USERDT + 3), a ; Store it into the date/time vector
    in      a, (8)          ; Read RTC day
    ld      (USERDT), a     ; Store it into the date/time vector
    in      a, (8)          ; Read RTC month
    ld      (USERDT + 1), a ; Store it into the date/time vector
    in      a, (8)          ; Read RTC year
    ld      (USERDT + 2), a ; Store it into the date/time vector
    ld      hl, USERDT      ; HL = date/time vector address
    ret

; =========================================================================== ;
;
; Send a string to the serial line, HL contains the pointer to the string
;
; =========================================================================== ;
puts
    ld      a, (hl)
    cp      eos             ; End of string reached?
    jr      z, puts_end     ; Yes, jump
    out     (1), a          ; No, print
    inc     hl              ; Increment character pointer
    jr      puts            ; Transmit next character
puts_end
    ret

; MESSAGES

BiosMsg     .db     cr, lf, lf, "Z80-MBC QP/M 2.71 BIOS - S080517", cr, lf, eos
CRLFLF      .db     cr, lf, lf, eos
CPMMsg      .db     "QP/M 2.71 Copyright 1985 (c) by MICROCode Consulting", cr, lf, eos
FatalMsg    .db     cr, lf, "FATAL DISK READ ERROR - SYSTEM HALTED", eos
WbootMSG    .db     cr, lf, "QP/M WARM BOOT...", cr, lf, eos
CCPAuto     .db     "QSUB AUTOEXEC", eos

; =========================================================================== ;
; THE REMAINDER OF THE CBIOS IS RESERVED UNINITIALIZED DATA AREA, AND DOES    ;
; NOT NEED TO BE A PART OF THE SYSTEM MEMORY IMAGE (THE SPACE MUST BE         ;
; AVAILABLE, HOWEVER).                                                        ;
; =========================================================================== ;

DIRBF
    .block  128

ALL00
    .block  31
    
ALL01
    .block  31

DSKNUM                      ; Selected Disk Number (8 bit)
    .block  1
    
TRACK                       ; Selected Track Number (16 bit)
    .block  2
    
SECTOR                      ; Selected Sector Number (16 bit)
    .block  2
    
DMAAD                       ; Selected DMA (Disk Memory Access) address (16 bit)
    .block  2               

DMABUFF
    .block  2               ; DMA buffer for WBOOT
    
SECTCNT
    .block  1               ; Sectors counter for WBOOT
    
USERDT                      ; QP/M 6 bytes date/time vector:
    .block  6               ;  day
                            ;  month
                            ;  year
                            ;  hours
                            ;  minutes
                            ;  seconds

    .end