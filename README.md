# 5x5words-asm
An avx512 implementation of the "find 5 5-letter words with all different letters" puzzle. I upload purely for educational reading, and make no guarantee that it still works as it has been a while since I was working on it actively, as I may have left a change half-done somewhere, and I have made untested changes in the last few hours before uploading too, that may or may not have fixed the bug noted below.

These files are a code::blocks project for the 5x5words challenge largely made in nasm assembly, but to build it correctly code::blocks requires some considerable setup to know what to do with nasm files, so I'll breifly explain how to build without an IDE (see Build).

The assembly is written for 64-bit linux execution environment, (mostly) respecting the 64-bit linux C calling convention, although it takes a lot of liberties with the stack. The code itself is OS agnostic though, it just works with memory, so should be modifiable for use on windows pretty easily. The main difference will be that windows has different expectations about register assignments for parameters and what a called function must preserve, but there may be additional issues with the unrestrained use I make of stack space (freely growing worklists etc.)

# Build

To build the nasm files separately at the command line use:

nasm -p nasm_defaults.inc file.nasm

On each of the nasm files. this should produce file.o as a PIE elf64.
(the nasm_defaults.inc sets up some macros that let me type {k1z} instead of {k1}{z} for avx512 zeroing-mask predicates, and default the data references to PC-relative addressing for relocatable code.)

Then build the c main() file with gcc and link the nasm generated object files.

# Run
When run in a terminal it expects to find the words_alpha.txt file in the execution directory.
It should output the results, and timings for the various sections of the process.

There are still some flaws in the code: apart from a couple of sub-optimal memory locality optimisations yet to be done, for some reason although it works perfectly the first time, if the search is re-run in the same execution, then somewhere dirty memory causes it to miss-read things and fail to find all the solutions. I have yet to work out why, since everything is being re-sourced from the original file and overwritten each time. I can only think there's a memory corruption bug somewhere that I have yet to find.

# Comments and Notes in the code

When looking through the code you'll often find notes that simply say something like zmm13=... with some hex after it. this was a note to myself on a constant to be loaded into the register at the eginning of the function. The one thing that my not be obvious is that at the end there will e something like (w)(r2l) or (dw)(l2r). w (word) and dw (dword) should be self explanititory but r2l or l2r refer to the memory byte order. it is normal to only list data elements left to right since that is the direction our language flows across the page. But our numbers flow right to left, since the Arabic numerals our math is based on, like the Arabic language they came from, flows right to left. In many cases, especially where different element sizes are mixed in a series of operations I find it it much simpler to work with everything flowing right-to-left so that the order of digits remains the same whether they are to be interpreted as 64 bytes, 32 words, 16 dwords or 8 qwords.

In addition to the extensive line by line notes in the executable code there's also a few other notes files including a pseudocode version of the algorithm where I was trying to imagine how a high-level language might represent the processes written in assembly as a more general set of bulk data handling data types and functions. I guess it's kinda C++-like in its way of doing things but C++ is one language I can say for certain cannot stretch to handle it. Maybe rust's metaprogramming would make it possible to handle all the different methods data types and cases in the most appropriate way, but I wouldn't be confident of anything short of a fully new language designed around making this kind of thing more accessible being able to handle it optimally.
