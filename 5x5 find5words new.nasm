;; search file in memory for words of 5-letter length in 36.6µs expected, 76.7µs measured

global find5words

section .data align=64

start_indexes:	dd	0x20,0x40,0x60,0x80,0xa0,0xc0,0xe0,0x100
				dd	0x120,0x140,0x160,0x180,0x1a0,0x1c0,0x1e0,0x200
adwid:			dd	0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
thirtytwos:		dd	0x20202020
twentysixs:		dd	0x1a1a1a1a
AAAA:			db	"AAAA"
fivetwelve:		dd	512
intmax:			dd	0x7fffffff

section .text
;; rdi = words file		rsi = indexes memory	edx = length of file in bytes
;; words file and indexes memory should be 64-byte aligned		21.3+14.2+1.1µs 36.6µs

find5words:
; first find the letters:
; we want the read, write, and loop counter to all be the same value for a single increment, so it must be negative
; the start of the file is aligned, but the end is not. we want the start of the bitfield to be aligned too.
; easiest way is to generate the endpointer for bitfield is to generate the startpointer, align it, and return to end
		vpxord		zmm10, zmm10, zmm10
		vmovdqu32	[rdi+rdx], zmm10		; clear above file by one block
		add			rdx, 7
		sar			rdx, 3					; inclusive qword length
		lea			rdi, [rdi + rdx * 8]	; qw-aligned endpointer for file
		mov			rcx, rdx				; need to keep a copy
		neg			rdx
		lea			r8, [rsp + rdx - 72]	; startpointer for bitfield memory
		mov			rax, 0xffffffffffffffc0	; for 64-byte alignments
		and			r8, rax					; aligned
		lea			r9, [r8 + rdx - 64]		; startpointer for bitfield index
		and			r9, rax					; aligned
		add			r8, rcx					; endpointer for bitfield memory
		vmovdqu32	[r8], zmm10				; clear 1-block above bitfield
		vpbroadcastd	zmm20, [AAAA]
		vpbroadcastd	zmm21, [thirtytwos]
		vpbroadcastd	zmm22, [twentysixs]
		vpbroadcastd	zmm23, [fivetwelve]
		vpbroadcastd	zmm24, [intmax]
		vmovdqa32		zmm25, [adwid]
.charLoop:
		vmovdqa32	zmm0, [rdi + rdx * 8]	; aquire bytes
		vpsubb		zmm0, zmm0, zmm20		; A=0
		vpandnd		zmm0, zmm21, zmm0		; a=A=0
		vpcmpnltub	k1, zmm0, zmm22			; letter=false
		kmovq		[r8 + rdx], k1			; store results
		add			rdx, 8
		js			.charLoop				; 2p05,1p5,1r1w,1p06. 3p05t/loop, so 1.5c/loop. (15ex./2loop for 12i) 21.3µs

; bits from above file will be 1s. this is not a problem.
; now we start on finding 5-letter words within the bitfield
; to move from byte based to dword based addressing is another 2 bits reduction. convert to bottom adr, round up length, convert to top adr
		sub			r8, rcx					; back to startpointer
		add			rcx, 3					; round up to include last bytes
		sar			rcx, 2					; byte to dword index
		lea			r8, [r8 + rcx * 4]		; now dword indexed endpointer
		lea			r9, [r9 + rcx * 4]		; now dword indexed endpointer
		neg			rcx						; negative read index
		mov			rax, rcx				; and writeback index
		mov			rdi, rcx				; keep a copy, and we're done with the file for this function aswell
		vmovdqa32	zmm10, [start_indexes]	; start indexes are:32,64,96,128,...
.wordLoop:
		vmovdqa32	zmm0, [r8 + rcx * 4]	; using rcx as readpointer/loopcounter
		vmovdqu32	zmm9, [r8 + rcx * 4 + 4]; reading +4 bytes for right double-shift

		vpshrdd		zmm1, zmm0, zmm9, 1
		vpshrdd		zmm2, zmm0, zmm9, 2
		vpshrdd		zmm3, zmm0, zmm9, 3
		vpshrdd		zmm4, zmm0, zmm9, 4
		vpshrdd		zmm5, zmm0, zmm9, 5
		vpshrdd		zmm6, zmm0, zmm9, 6
		vpternlogd	zmm0, zmm1, zmm2, 0x10	; abc=100 only, z012=100
		vpternlogd	zmm0, zmm3, zmm4, 0x10	; abc=100 only, z01234=10000
		vpternlogd	zmm0, zmm5, zmm6, 0x20	; abc=101 only, z0123456=1000001

		vptestmd	k1, zmm0, zmm0			; keep nonzero only
;		vpcompressd	zmm0{k1z}, zmm0			; split write for zen4
;		vmovdqu32	[r8 + rax * 4], zmm0	; write nonzero bitfield dwords
;		vpcompressd	zmm0{k1z}, zmm10		; split write for zen4
;		vmovdqu32	[r9 + rax * 4], zmm0	; and their end-bit byte-indexes for lzcnt subtraction
		vpcompressd	[r8 + rax * 4]{k1}, zmm0; compress direct to memory for intel
		vpcompressd	[r9 + rax * 4]{k1}, zmm10; compress direct to memory for intel

		vpaddd		zmm10, zmm10, zmm23		; increment indexes by 512
		kmovw		edx, k1
		popcnt		edx, edx
		add			rax, rdx
		add			rcx, 16
		js			.wordLoop				; 7p0, 5p5, 4p05 (8c/l) 14.2µs


; now onto actual indexing. in each dword there is one or more bits to discover, we can either use lzcnt or -1;popcnt to turn bit positions into numbers
; we also have to remove the bit after indexing it, so popcnt isn't as bad as it first seems.
; -1; and; andn; popcnt;
; lzcnt;ror;and					lzcnt still slightly better
; this final process is better done with startpointers
		lea			r8, [r8 + rdi * 4]
		lea			r9, [r9 + rdi * 4]
		sub			rax, rdi				; convert current writeback write index to startpointer indexing
		xor			edx, edx				; reading and result writing from 0
.indexLoop:
		vmovdqa32	zmm0, [r8 + rdx * 4]	; read bitfield
		vmovdqa32	zmm1, [r9 + rdx * 4]	; and their end-indexes

		vplzcntd	zmm2, zmm0
		vpsubd		zmm3, zmm1, zmm2
		vmovdqa32	[rsi + rdx * 4], zmm3	; 16 indexed 5-letter words at a time. junk may be written at end, but should be OK if the count is correct.

		vprorvd		zmm2, zmm24, zmm2
		vpandd		zmm0, zmm0, zmm2		; remove found bit

		add			edx, 16
		cmp			edx, eax
		jns			.lastfew

		vptestmd	k1, zmm0, zmm0			; keep nonzero only
		vpcompressd	zmm5{k1z}, zmm25		; compress the ID table
		vpermd		zmm0, zmm5, zmm0		; to avoid compress throughput limit
		vmovdqu32	[r8 + rax * 4], zmm0	; write nonzero bitfield dwords
		vpermd		zmm0, zmm5, zmm1		;
		vmovdqu32	[r9 + rax * 4], zmm0	; and their end-bit-byte-indexes for lzcnt subtraction

		kmovw		ecx, k1
		popcnt		ecx, ecx
		add			eax, ecx
		jmp			.indexLoop				; 3p0 5p5 2p05 (10p05 total, 5c/loop) 2r3w 15000 indexed in 1.1µs

.lastfew:
		mov			ecx, 0xffff
		sub			edx, eax				; eax is actually what our correct found-so-far count should be
		shrx		ecx, ecx, edx			; so just use the overread/overwritten edx for making the mask
		kmovw		k1, ecx					; valid mask
.lastLoop:
		vptestmd	k1{k1}, zmm0, zmm0		; keep valid nonzero only
		ktestw		k1, k1					; all done?
		jz			.done

		vplzcntd	zmm2, zmm0
		vpsubd		zmm3, zmm1, zmm2
;		vpcompressd	zmm4{k1z}, zmm3			; split write for zen4
;		vmovdqu32	[rsi + rax * 4], zmm4	; [nValid] indexed 5-letter words at a time. junk may be written at end, but should be OK if the count is correct.
		vpcompressd	[rsi + rax * 4]{k1}, zmm3
		vprorvd		zmm2, zmm24, zmm2
		vpandd		zmm0, zmm0, zmm2		; remove found bit

		kmovw		edx, k1					; how many valid this cycle?
		popcnt		edx, edx
		add			eax, edx				; increment the found count/write index by nValid
		jmp			.lastLoop
.done:
		ret									; found count already in eax, nothing to pop.


