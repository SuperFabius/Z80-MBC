# Z80-MBC
Here are all the project files (SW & HW) of the Z80-MBC, a complete mini Z80 system with 64kB RAM, Basic and Forth interpreters, CP/M 2.2, QP/M 2.71, Assembler and C toolchains, Serial port, an User led and key.

The complete project with all the details is published here: https://hackaday.io/project/19000-a-4-4ics-z80-homemade-computer-on-breadboard

The PCB gerber files are here: https://github.com/WestfW/4chipZ80 (the PCB was designed by Bill Westfield).



** UPDATE February 2018 **

New version S221116_R100218_Z80.ino. Fix the "ghost RTC" bug: when there isn't any Virtual Disk (only Basic and Forth) the RTC clock was always incorrectly found.
