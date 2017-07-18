// ****************************************************************************************
/*

iDisk - Intel-Hex Disk image Loader - S250317

Disk images loader for the Z80-MBC (HW ref: A041116)

NOTE 1: Required IOS S221116 R180217 (or following until otherwise stated)

NOTE 2: Required Virtual Disk Module (HW ref: A110417)

NOTE 3: When compiling with SDDC the option "--data-loc 0x6000" *MUST* be used.
        (e.g., sdcc -mz80 --data-loc 0x6000 <input_source.c> -o <output_file.hex>)

Compiled with SDDC 3.6.0

*/
// ****************************************************************************************

#include <stdio.h>

// Z80-MBC I/O ports definition
__sfr __at 0x09 SELDISK;                    // Disk emulation I/O (write)
__sfr __at 0x0A SELTRACK;
__sfr __at 0x0B SELSECT;
__sfr __at 0x0C WRITESECT;

__sfr __at 0x05 ERRDISK;                    // Disk emulation I/O (read)
__sfr __at 0x06 READSECT;

#define dataBuffSize 0x8000                 // Input data buffer size
#define diskSectors 1024                    // Sectors (128 byte) in a disk

unsigned char dataBuff[dataBuffSize];       // Input data buffer
unsigned int byteCount;                     // Data bytes counter
unsigned int dataBuffIdx;                   // Index used to write data from buffer to the virtual disk
unsigned int lowAddr;
unsigned int hiAddr, ii;
unsigned long addr;                         // Current data address
unsigned long startAddr;                    // Starting data address
unsigned char magic;                        // Just4Fun "magic" code :-)
unsigned char errFlag;
unsigned char writeFlag;
unsigned char writeDoneFlag;                // Current segment write status (0 = not done, 1 = done)
unsigned char writeErrorCode;               // Disc write error code (0 = no errors)
unsigned char boundFillFlag;
unsigned char i, targetDisk;
unsigned int sectors;
unsigned char segment;                      // Current EEPROM segment (one segment = 32kB) [0..3]
unsigned char   D0SegDone[4], D1SegDone[4]; // Status of disks segments ( 0 = untouched, 1 = written)
unsigned char firstTrack, lastTrack, track; // [0..31]
unsigned char sector, lastSector;           // [1..32]
char c;

char upperCase(unsigned char c)
// Change a charcter in upper case if in [a..z] range
{
    if ((c >96) && (c < 123)) c = c - 32;
    return c;
}

void printErr(unsigned char errCode)
// Print the meaning of an ERRDISK error code
//
//                     error code:    0: no errors
//                                    1: data too long to fit in transmit buffer (I2C)
//                                    2: received NACK on transmit of address (I2C)
//                                    3: received NACK on transmit of data (I2C)
//                                    4: other error (I2C)
//                                    8: WRITESECT error (I/O byte counter overrun)
//                                    9: READSECT error (I/O byte counter overrun)
//                                   10: data read error (I2C)
//                                   11: invalid disk number
//                                   12: invalid track number
//                                   13: invalid sector number
//                                   14: virtual disk module not found
{
    if (errCode != 0)
    {
        printf("\n\nDisk error %03u: ", errCode);
        switch (errCode)
        {
            case 1:     printf("data too long to fit in transmit buffer (I2C)"); break;
            case 2:     printf("received NACK on transmit of address (I2C)"); break;
            case 3:     printf("received NACK on transmit of data (I2C)"); break;
            case 4:     printf("other error (I2C)"); break;
            case 8:     printf("write error (I/O byte counter overrun)"); break;
            case 9:     printf("read error (I/O byte counter overrun)"); break;
            case 10:    printf("data read error (I2C)"); break;
            case 11:    printf("invalid disk number"); break;
            case 12:    printf("invalid track number"); break;
            case 13:    printf("invalid sector number"); break;
            case 14:    printf("virtual disk module not found"); break;
            default:    printf("unknown error"); break;
        }
        printf("\n");
    }
}

char getOneChar()
// Read one char from the input stream and return it. CR and LF are ignored, anyway CR is echoed with a LF.
{
    char inChar;
    
    do
    {
        inChar = getchar();
        if ((inChar != 13) || (inChar != 11)) putchar(inChar);
        else if (inChar != 13)
        {
            putchar(13);        // CR + LF
            putchar(11);
        }
    }
    while ((inChar == 13) || (inChar == 11));       // Loop until a valid char is read
    return inChar;
}

unsigned char readHexByte(unsigned char *byte)
// Read an hex byte from the input stream.
// Return values: 0 = ok, 1 = syntax error
{
    char inChar;
    signed char i;
    
    *byte = 0;
    for (i = 1; i >= 0; i--)
    {
        inChar = getOneChar();                                          // Get a char
        if ((inChar > 96) && (inChar < 103)) inChar = inChar - 32;      // a - f to upper case
        if ((inChar > 47) && (inChar < 58)) inChar = inChar - 48;       // 0 - 9
        else if ((inChar > 64) && (inChar < 71)) inChar = inChar - 55;  // A - F
            else return 1;                                              // Illegal char: syntax error
        *byte = *byte | (inChar << (i * 4));                            // Byte in binary
    }
    return 0;                                                           // No errors
}

unsigned char readOneLine()
// Read and parse one intel-hex ASCII record (one input line).
// Return values: 0 = data record, 1 = EOF record, 4 = extended linear address record, 9 = Just4Fun "magic" record :-),
//                10 = syntax error, 11 = illegal record type, 12 = expected "0000" address in type 04 record,
//                13 = checksum error, 14 = illegal starting address, 15 = data address not in sequence,
//                16 = data buffer full
{
    unsigned char retValue, byte, recLenght, recType, checksum, sum, i;
    char inChar;
    
    inChar = getOneChar();
    if (inChar != ':') return 10;               // Read first char = ':'
    if (readHexByte(&recLenght) > 0) return 10; // Read record lenght
    sum = recLenght;
    if (readHexByte(&byte) > 0) return 10;      // Read 16 bit address MSB
    sum = sum + byte;
    lowAddr = ((unsigned int) byte) << 8;
    if (readHexByte(&byte) > 0) return 10;      // Read 16 bit address LSB
    sum = sum + byte;
    lowAddr = lowAddr | byte;
    if (readHexByte(&recType) > 0) return 10;   // Read record type
    sum = sum + recType;
    switch (recType)
    {
        case 0:                                 // Data record
            addr = (((unsigned long) hiAddr) << 16 ) | lowAddr;
            if (byteCount == 0)
            // First address in the input stream
            {
                if ((addr != 0) && (addr != 0x8000) && (addr != 0x10000) && (addr != 0x18000)) return 14; // Verify starting address
                startAddr = addr;               // Save starting address
                segment = (unsigned char) (addr / 0x8000);  // Calculate the EEPROM segment to write
            }
            for (i = 0; i < recLenght; i++)
            // Read the data bytes inside the data record
            {
                if (readHexByte(&byte) > 0) return 10;      // Read a data byte
                sum = sum + byte;
                if ((addr + i) == (startAddr + byteCount))
                {
                    if (byteCount >= dataBuffSize) return 16;// Data buffer full
                    dataBuff[byteCount] = byte;
                    byteCount++;
                }
                else return 15;                 // Data address not in sequence
            }
            retValue = 0; 
        break;
        
        case 1:                                 // EOF record
            retValue = 1; 
        break;
        
        case 4:                                 // Extended linear address record
            if (lowAddr !=0) return 12;         // Expected "0000" address in type 04 record
            if (readHexByte(&byte) > 0) return 10;          // Read 16 bit extended address MSB
            sum = sum + byte;
            hiAddr = ((unsigned int) byte) << 8;
            if (readHexByte(&byte) > 0) return 10;          // Read 16 bit extended address LSB
            i = sum + byte;                     // Splitted to avoid a strange SDDC "liverange" warning
            sum = i;
            hiAddr = hiAddr | byte;
            retValue = 4;
        break;
        
        case 9:                                 // Just4Fun "magic" record :-)
            magic = (unsigned char) lowAddr;
            retValue = 9; 
        break;
        
        default:    // Illegal record type
            return 11;
    }
    if (readHexByte(&checksum) > 0) return 10;  // Read checksum byte
    sum = 1 + ~sum;                             // Calculate checksum
    if (sum != checksum) return 13;             // Validate checksum
    return retValue;
}

unsigned char verifyDiskSect(unsigned char disk, unsigned char track, unsigned char sector, unsigned int *buffIndex )
// verify a sector into on the given track of the selected virtual disk, comparing with data buffer content.
// The index to the first byte to write from data buffer is "dataBuffIdx".
// Returns error code (0 = no errors, 1 = do not match).
// NOTE: disk [0..1], track [0..31], sector [1..32]
{
unsigned int    ii;
unsigned char   notEqual = 0;

    SELDISK = disk;     // Disk number
    SELTRACK = track;   // Track LSB
    SELTRACK = 0;       // Track MSB
    SELSECT = sector;   // Sector LSB
    SELSECT = 0;        // Sector MSB
    for (ii =0; ii < 128;  ii++)
    // Write selected sector
    {
        if (READSECT != dataBuff[*buffIndex]) notEqual = 1;
        (*buffIndex)++;
    }
    return notEqual;
}

unsigned char writeDiskSect(unsigned char disk, unsigned char track, unsigned char sector, unsigned int *buffIndex )
// Write a sector into on the given track of the selected virtual disk.
// The index to the first byte to write from data buffer is "dataBuffIdx".
// Returns write error code (0 = no errors).
// NOTE: disk [0..1], track [0..31], sector [1..32]
{
unsigned int ii;

    SELDISK = disk;     // Disk number
    SELTRACK = track;   // Track LSB
    SELTRACK = 0;       // Track MSB
    SELSECT = sector;   // Sector LSB
    SELSECT = 0;        // Sector MSB
    for (ii =0; ii < 128;  ii++)
    // Write selected sector
    {
        WRITESECT = dataBuff[*buffIndex];
        (*buffIndex)++;
    }
    return ERRDISK;
}

void main()
{
    printf("\n\niDisk - Intel-Hex Disk image Loader - S250317");
    for (i = 0; i < 4; i++) D0SegDone[i] = 0;                           // Initialize disk 0 segments status
    for (i = 0; i < 4; i++) D1SegDone[i] = 0;                           // Initialize disk 1 segments status
    if (ERRDISK == 14)
    {
        printf("\n");
        printErr(14);
        printf("\n* Program aborted *\n");
        return;
    }
    do
    {
        for (ii = 0; ii < dataBuffSize; ii++) dataBuff[ii] = 0xe5;      // Initialize data buffer
        byteCount = 0;                                                  // Initialize read bytes counter
        hiAddr = 0;
        startAddr = 0;
        magic = 0xff;
        dataBuffIdx = 0;
        errFlag = 0;
        writeFlag = 0;
        boundFillFlag = 0;
        writeErrorCode = 0;
        writeDoneFlag = 0;
        printf("\n\nDisk segments write status: D0[");
        for (i = 0; i < 4; i++) { if (D0SegDone[i] == 0) printf("."); else printf("%01u", i); }
        printf("] - D1[");
        for (i = 0; i < 4; i++) { if (D1SegDone[i] == 0) printf("."); else printf("%01u", i); }
        printf("]\n\nWaiting input stream...\n");
        do
        // Read the input intel-hex stream until EOF or an error
        {
            i =  readOneLine();
            printf("\n");
        }
        while ((i != 1) && (i < 10));
        if (i > 9)
        // Error detected reading hex stream
        {
            errFlag = 1;
            printf("\nERROR: ");
            switch (i)
            {
                case 10:
                    printf("syntax error");
                break;
                case 11:
                    printf("illegal record type");
                break;
                case 12:
                    printf("expected address 0000 in type 04 record");
                break;
                case 13:
                    printf("checksum error");
                break;
                case 14:
                    printf("illegal starting address");
                break;
                case 15:
                    printf("data address not in sequence");
                break;
                case 16:
                    printf("data buffer full");
                break;
            }
            printf("\nPress ESC to continue...");
            do c = getchar();
            while (c != 27);
        }
        else
        // No errors detected. Print a summary of the received data and ask the target virtual disk
        // if needed
        {
            printf("\nRead bytes count: %u", byteCount);
            printf("\nEEPROM first addr to write: 0x%05lX", startAddr);
            printf("\nEEPROM current 32kB segment: %01u", segment);
            firstTrack = (diskSectors / 128) * segment;         // Calculate first track to write
            printf("\nFirst Track/Sector to write: %02u/01", firstTrack);
            sectors = byteCount / 128;                          // Calculate how many contiguous sectors to write
            if ((byteCount % 128) != 0)                         // Check if sector filling is needed
            {
                sectors++;
                boundFillFlag = 1;
            }
            printf("\nContiguous sectors to write: %03u", sectors);
            if (sectors > 0) lastTrack = firstTrack + ((sectors - 1) / 32);
            else lastTrack = firstTrack;
            printf("\nLast Track/Sector to write: %02u", lastTrack);
            if (sectors < 2) lastSector = 1;
            else lastSector = ((sectors - 1) % 32) +1;
            printf("/%02u", lastSector);
            printf("\nLast sector boundary fill: ");            // Sector boudary fill
            if (!boundFillFlag) printf("not needed");
            else printf("yes");
            if (byteCount > 0)
            {
                if (magic < 2) targetDisk = magic;
                else
                // Ask the target virtual disk
                {
                    printf("\n\nEnter the target virtual disk [0/1] >");
                    do
                    {
                        c = getchar();
                        if ((c == '0') || (c == '1')) putchar(c);
                        targetDisk = c - 48;
                    }
                    while ((c != '0') && (c != '1'));
                }
                printf("\nTarget virtual disk: %u", targetDisk);
            }
            else printf("\nNothing to do...");
        }
        if ((byteCount > 0) && !errFlag)
        // Write the received data into the EEPROM
        {
            printf("\n\nPress W to write or A to abort [W/A] >");
            do c = upperCase(getchar());
            while ((c != 'W') && (c != 'A'));
            putchar(c);
            if (c == 'W')
            {
                printf("\n\n* WARNING * ALL PREVIOUS DATA IN THE TARGET SECTORS WILL BE OVERWRITTEN!");
                printf("\n\nAre you sure [Y/N]? >");
                do c = upperCase(getchar());
                while ((c != 'Y') && (c != 'N'));
                putchar(c);
                if (c == 'Y') writeFlag = 1;
            }
            if (!writeFlag) printf("\nWrite operation cancelled!");
            else
            {
                track = firstTrack;
                sector = 1;
                for (ii = 0; ii < sectors; ii++)
                // Write a sector to virtualdisk
                {
                    printf("\n#%03u: writing... ", ii+1);
                    printf(" Disk: %01u", targetDisk);
                    printf(" - Track: %02u", track);
                    printf(" - Sector: %02u", sector);
                    writeErrorCode = writeDiskSect(targetDisk, track, sector, &dataBuffIdx);
                    if (writeErrorCode > 0) break;              // Abort write operation if an error occurred
                    if (sector < 32) sector++;
                    else
                    {
                        sector = 1;
                        track++;
                    }
                }
                printErr(writeErrorCode);                       // Print write error (if any)
                if (writeErrorCode > 0) printf("\n* WRITE ABORTED! *");
            }
        }
        // Verify the written data if no write error occurred
        if ((writeErrorCode == 0) && writeFlag)
        {
            dataBuffIdx = 0;
            track = firstTrack;
            sector = 1;
            writeDoneFlag = 1;
            printf("\n");
            for (ii = 0; ii < sectors; ii++)
            // Verify a sector
            {
                    printf("\n#%03u: verifying...", ii+1);
                    printf(" Disk: %01u", targetDisk);
                    printf(" - Track: %02u", track);
                    printf(" - Sector: %02u", sector);
                    if (verifyDiskSect(targetDisk, track, sector, &dataBuffIdx))
                    // Abort verify on error and print a message
                    {
                        printf("\n\n* FOUND MISMATCH - VERIFY FAILED! *\n");
                        writeDoneFlag = 0;
                        break; 
                    }
                    else printf(" -> OK");
                    if (sector < 32) sector++;
                    else
                    {
                        sector = 1;
                        track++;
                    }
            }
            if (writeDoneFlag) {if (targetDisk == 0) D0SegDone[segment] = 1; else D1SegDone[segment] = 1;}
        }
    }
    while (1);
}