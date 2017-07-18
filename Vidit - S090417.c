// ****************************************************************************************
/*

ViDiT - Virtual Disk Test - S090417

Virtual Disks Module test program for the Z80-MBC 

NOTE: Required IOS S221116 R180217 or newer

HW ref: A041116, A110417

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

unsigned int    sectCount = 1, disk = 0, track = 0, sector = 1, maxSect, ii;
unsigned int    currTrack, currSect, j, fillNum;
unsigned char   readBuff[16], i, k, inChar, verifyFlag;

void selDisk (unsigned char diskNum)
{
    SELDISK = diskNum;
}

void selTrack(unsigned int trackNum)
{
    SELTRACK = (unsigned char) (trackNum & 0x00ff);
    SELTRACK = (unsigned char) ((trackNum >> 8) & 0x00ff);
}

void selSect(unsigned int sectNum)
{
    SELSECT = (unsigned char) (sectNum & 0x00ff);
    SELSECT = (unsigned char) ((sectNum >> 8) & 0x00ff);
}

unsigned char errDisk()
{
    return ERRDISK;
}

unsigned char readSect()
{
    return READSECT;
}

void writeSect(unsigned char byte)
{
    WRITESECT = byte;
}
    
char getOneDigit()
// Read one numeric char [0..9] or a CR or a BACKSPACE from the input stream. Ignore others chars.
// If only a CR is pressed, it is returned a flag value of 10000 meaning "no number".
{
    unsigned char   inChar;
    
    do inChar = getchar();
    while (((inChar < 48) || (inChar > 57)) && (inChar != 13) && (inChar != 8));
    return inChar;
}

unsigned int readNum()
// Read a decimal 1-4 digit number from the input stream ending with a CR, and echo it
{
    unsigned char   i, j, inChar;
    unsigned int    num;
    do
    {
        do inChar = getOneDigit();                                          // Read first numeric char [0..9]
        while (inChar == 8);
        if (inChar == 13) return 10000;
        putchar(inChar);
        num = inChar - 48;                                                  // Convert first num char into decimal
        for (i = 1; i <= 3; i++)
        {
            inChar = getOneDigit();                                         // Get a numeric char
            j = 0;
            if (inChar == 8)
            // Read a BACKSPACE, so delete input
            {
                do 
                {
                    putchar(8);
                    putchar(32);
                    putchar(8);
                    j++;
                }
                while (j < i);
                break;
            }
            else putchar(inChar);
            if (inChar == 13) return num;                                   // Read a CR, so return
            num = num * 10;
            num = num + (inChar - 48);                                      // Convert a numeric char
        }
        if (inChar != 8)
        // Read a char after the 4th digit
        {
            do inChar = getOneDigit();
            while ((inChar != 13) && (inChar != 8));
            if ((inChar == 8) ) for (j = 0; j < 4; j++) 
            // Is a BACKSPACE, so clear all previous input
            {
                putchar(8);
                putchar(32);
                putchar(8);
            }
        }
    }
    while (inChar == 8);
    putchar(inChar);
    return num;
}

char upperCase(unsigned char c)
// Change a charcter in upper case if it is in [a-z] range
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
        printf("\nDisk error %03u: ", errCode);
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

void main(void) 
{ 
    printf("\nViDiT - Virtual Disk Test - S090417");
    selTrack(0);
    selSect(1);
    if (errDisk() == 14)
    {
        printf("\n");
        printErr(14);
        printf("\n* Program aborted *\n");
        return;
    }
    printf("\n\n\n\n                             * * * WARNING! * * *\n\n\n");
    printf("* * Write command will overwrite all previous data on the selected sectors! * *\n");
    do
    {
        printf("\n\nCurrent setting:\ndisk -> %01u", disk);
        printf(" : track -> %02u", track);
        printf(" : sector -> %02u", sector);
        maxSect = 1024 - ((track * 32) + sector -1);
        if (sectCount > maxSect) sectCount = maxSect;
        printf(" : sectors to process -> %u", sectCount);
        printf("\n\nCommands list:\n\n");
        printf(" D: Set disk\n");
        printf(" T: Set starting track\n");
        printf(" S: Set starting sector\n");
        printf(" N: Set how many sectors read or write\n");
        printf(" R: Read sectors\n");
        printf(" W: Write sectors filling a value and verify\n");
        printf(" E: Exit\n\n");
        do
        {
            printf("\r                  ");
            printf("\rEnter a command [D,T,S,N,R,W,E] >");
            inChar = getchar();
            inChar = upperCase(inChar);
        }
        while ((inChar != 'D') && (inChar != 'T') && (inChar != 'S') && (inChar != 'N') && (inChar != 'R') && (inChar != 'W') && (inChar != 'E'));
        putchar(inChar);
        printf("\n");
        //i = inChar - 48;
        switch  (inChar)
        {
            case 'D':
                do
                {
                    printf("\r                              ");
                    printf("\rEnter disk number [0..1] >");
                    ii = readNum();
                    if (ii < 10000) disk = ii;
                }
                while (disk > 1);
            break;
        
            case 'T':
                do
                {
                    printf("\r                                ");
                    printf("\rEnter track number [0..31] >");
                    ii = readNum();
                    if (ii < 10000) track = ii;
                }
                while (track > 31);
            break;
            
            case 'S':
                do
                {
                    printf("\r                                 ");
                    printf("\rEnter sector number [1..32] >");
                    ii = readNum();
                    if (ii < 10000) sector = ii;
                }
                while ((sector - 1) > 31);
            break;
            
            case 'N':
                do
                {
                    maxSect = 1024 - ((track * 32) + sector -1);
                    printf("\r                                        ");
                    printf("\rEnter sectors to process [1..%u] >", maxSect);
                    ii = readNum();
                    if (ii < 10000) sectCount = ii;
                }
                while (sectCount > maxSect);
            break;
                
            case 'R':
                currTrack = track;
                currSect = sector;
                for (j = 1; j <= sectCount; j++)
                {
                    selDisk(disk);
                    selTrack(currTrack);
                    selSect(currSect);
                    printf("\n* disk -> %02u", disk);
                    printf(" : track -> %02u", currTrack);
                    printf(" : sector -> %02u *\n", currSect);
                    // Read and print a sector
                    for (i = 0; i < 8; i++)
                    {
                        for (k = 0; k < 16; k++)
                        {   
                            readBuff[k] = readSect();
                            printf("%02X ", readBuff[k]);
                        }
                        printf("    ");
                        for (k = 0; k < 16; k++)
                        {   
                            if ((readBuff[k] > 32) && (readBuff[k] < 127)) putchar(readBuff[k]);
                            else putchar('.');
                        }
                        printf("\n");
                    }
                    printErr(errDisk());
                    currSect++;
                    if (currSect > 32)
                    {
                        currSect = 1;
                        currTrack++;
                    }
                }
            break;
            
            case 'W':
                verifyFlag = 1;
                do
                {
                    printf("\r                                      ");
                    printf("\rEnter the value to fill [0..255] >");
                    fillNum = readNum();
                }
                while (fillNum > 255);
                printf("\n\Are you sure to proceed [Y/N]? >");
                do inChar = upperCase(getchar());
                while ((inChar != 'Y') && (inChar != 'N'));
                putchar(inChar);
                printf("\n");
                if (inChar != 'Y') break;
                printf("\n");
                currTrack = track;
                currSect = sector;
                for (j = 1; j <= sectCount; j++)
                {
                    printf("Writing  track -> %02u", currTrack);
                    printf(" : sector -> %02u\n", currSect);
                    selDisk(disk);
                    selTrack(currTrack);
                    selSect(currSect);
                    for (i = 0; i < 128; i++)
                    // Write a sector
                    {
                        writeSect((unsigned char) fillNum); 
                    }
                    printErr(errDisk());
                    printf("Verifing track -> %02u", currTrack);
                    printf(" : sector -> %02u\n", currSect);
                    selDisk(disk);
                    for (i = 0; i < 128; i++)
                    // Verify a sector
                    {
                        k = readSect();
                        if (k != (unsigned char) fillNum) verifyFlag = 0;
                    }
                    printErr(errDisk());
                    if (!verifyFlag)
                    {
                        printf("* * * * VERIFY FAILED!!!! * * * *\n");
                        break;
                    }
                    currSect++;
                    if (currSect > 32)
                    {
                        currSect = 1;
                        currTrack++;
                    }
                }
            break;
        
            case 'E':
                printf("\n\n* Program terminated *\n");
            break;
        }
    }
    while (inChar != 'E');
} 