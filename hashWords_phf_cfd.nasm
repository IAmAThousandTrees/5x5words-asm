
global hashWords

;; perfect hashing algorithm using the perfect hashfunction
;; right aligned codes from before counting
;; 5 arrays: {codes, index, links} are aligned elements. hashtable is 65780 dwords with indexes into the arrays, to fit the perfect hashfunction.
;; hashtable is cleared to -1 to account for the zero indexes being valid. takes .93µs
;; input words is needed for hashtable lookup, codes are only used once for hashfunction. overwrite input codes with first-unique codes for count.
;; 5th array is for first-unique words for remaking the codes after the count and ranking.
;; start of memory areas assumed to be 64-byte aligned. hashtable needs to be writeable to 65792nd dword.

; total time for 10000 input words: 6.33µs expected, 12.2µs measured
; 				(again, presumably gather/scatter being slow, though this time hashtable is l2-sized)


; 4 inputs: rdi = codes, rsi = hashspace, rdx = linkspace, ecx = n_words

section .data
align 64

dwid:		dd		0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
bit1vals:	dw	0,0,0,0,0,0,10626,19481,26796,32781,37626,41502,44562,46942,48762,50127,51128,51843,52338,52668,52878,53004,53074,53109,53124,53129,53130,0,0,0,0,0
bit2vals:	dw		0,0,0,0,0,0,1771,3311,4641,5781,6750,7566,8246,8806,9261,9625,9911,10131,10296,10416,10500,10556,10591,10611,10621,10625,10626,0,0,0,0,0
bit3vals:	dw		0,0,0,0,0,0,231,441,631,802,955,1091,1211,1316,1407,1485,1551,1606,1651,1687,1715,1736,1751,1761,1767,1770,1771,0,0,0,0,0
bit4vals:	dw		0,0,0,0,0,0,21,41,60,78,95,111,126,140,153,165,176,186,195,203,210,216,221,225,228,230,231,0,0,0,0,0
bit5vals:	dw		0,0,0,0,0,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,0,0,0,0,0 ;; adjusted for A=1 (empty first bit means all pcnt(x-1) has 1 more)
evencomb:	dq		0x5555555555555555
one:		dd		1
thirtyone:	dd		31
sixteen:	dd		16

section .text
align 16

hashWords:
	lea				r10, [rdx + rcx * 4]			; linkspace in r10
	lea				rdi, [rdi + rcx * 4]			; adjust pointers for end-referencing negative indexes

	vmovdqa32		zmm21, [bit1vals]
	vmovdqa32		zmm22, [bit2vals]
	vmovdqa32		zmm23, [bit3vals]
	vmovdqa32		zmm24, [bit4vals]
	vmovdqa32		zmm25, [bit5vals]
	vmovdqa32		zmm10, [dwid]
	vpbroadcastd	zmm20, [one]
	vpbroadcastd	zmm31, [thirtyone]
	vpbroadcastd	zmm26, [sixteen]
	vpternlogd		zmm27, zmm27, zmm27, 0xff		; all1s

;; first clear(set) the hashmemory
	mov				edx, 65760						; covers top block and a bit more. make sure 65792 is writeable.
.clearloop:
	vmovdqa32		[rsi + rdx * 4 + 64], zmm27		; set hashspace to all1s
	vmovdqa32		[rsi + rdx * 4], zmm27			; set hashspace to all1s
	sub				edx, 32
	jns				.clearloop						; loop should manage 1 write/cycle

	kxorq			k0, k0, k0
	knotq			k0, k0							; k0 isn't all 1s until you set it. for the gather/scatter ops.
	kmovq			k7, [evencomb]					; the comb mask actually isn't required since upper-half of dwords will always be zero after vpopcntd
													; and selecting 0 from these tables will always give 0 in this specific case. but I left it in.

	neg				rcx								; negative read index
	mov				rdx, rcx						; duplicate for the also-negative write index to reference same pointer for codes

.loop:
	vmovdqu32		zmm5, [rdi + rcx * 4]			; get codes

	vplzcntd		zmm3, zmm5						; lzcnt gives different numbers but still useable
	vpermw			zmm4{k7z}, zmm3, zmm25			; bit 5 values from 27 to 6 (0,0,0,0),0,1,2,3,4,5,6,7....20,21,(0,0,0,0,0,0) (w)(r2l)

	vpsubd			zmm2, zmm5, zmm20				; zmm20 = 1s (dw)
	vpandd			zmm0, zmm5, zmm2				; unmodified codes remains in zmm5
	vpopcntd		zmm3, zmm2						; using without removing the extra bits just increases popcnt return by 4
	vpermw			zmm3{k7z}, zmm3, zmm21			; bit 1 values from 4 to 25 in zmm21, k7=0x55555555
	vpaddd			zmm4, zmm4, zmm3

	vpsubd			zmm2, zmm0, zmm20				; zmm20 = 1s
	vpandd			zmm0, zmm0, zmm2
	vpopcntd		zmm3, zmm2						; using without removing the extra bits just increases popcnt return by 3
	vpermw			zmm3{k7z}, zmm3, zmm22			; bit 2 values from 4 to 25
	vpaddd			zmm4, zmm4, zmm3

	vpsubd			zmm2, zmm0, zmm20				; zmm20 = 1s
	vpandd			zmm0, zmm0, zmm2
	vpopcntd		zmm3, zmm2						; using without removing the extra bits just increases popcnt return by 2
	vpermw			zmm3{k7z}, zmm3, zmm23			; bit 3 values from 4 to 25
	vpaddd			zmm4, zmm4, zmm3

	vpsubd			zmm2, zmm0, zmm20				; zmm20 = 1s
	vpopcntd		zmm3, zmm2						; using without removing the extra bits just increases popcnt return by 1
	vpermw			zmm3{k7z}, zmm3, zmm24			; bit 4 values from 4 to 25
	vpaddd			zmm4, zmm4, zmm3				; latency 14c 9p5 1p0 11p05, 21total µops

;; we now have a perfect hash of the codes, that will prevent the need for word-checking and trees on each hash entry

;; we need to build the chain directly. normally, the link elements would get the current hashtable entry, and replace it with their own index.
;; if there is a conflict, the rightmost entry gets the current hashtable contents, but the leftmost conflicting entry gets it's index in the hashtable.
;; so the link entry for each conflicting element needs to be the index of the conflicting element to it's right.

	mov				rax, rcx						; keep a copy first because we still need it for a write yet
	add				rcx, 16							; increment to see if there's overread before continuing
	jns				.lastfew

	kmovw			k1, k0							; k0=0xffffffffffffffff
	vpgatherdd		zmm0{k1}, [rsi + zmm4 * 4]		; read current hashtable contents
	kmovw			k1, k0							; k0=0xffffffffffffffff
	vpscatterdd		[rsi + zmm4 * 4]{k1}, zmm10		; write indexes of current 16 codes/words to hashtable, leaving the leftmost in case of conflicts

	vpconflictd		zmm1, zmm4						; detect identical hashes in table (=anagrams)
	vptestmd		k1, zmm1, zmm1					; indicates conflicting elements that need their link adjusted
	vplzcntd		zmm1, zmm1						; find leftmost bit (nearest conflict to right) in conflicted elements
	vpsubd			zmm1, zmm31, zmm1				; zmm31 has 31s (a 1-bit in the rightmost position gives 31 - we need that to select element 0)
	vpermd			zmm0{k1}, zmm1, zmm10			; replace links/blanks from hashtable with indexes of the conflicting elements from this table
	vmovdqa32		[r10 + rax * 4], zmm0			; write links to the link array, using the pre-increment copy of rcx in rax

	vpcmpeqd		k1, zmm0, zmm27					; zmm27=-1s (dw) mask of new entries. also excludes in-register conflicted elements.

	vpcompressd		zmm5{k1}, zmm5					; first-unique codes. this is actually what we're hashing *for*.
	vmovdqu32		[rdi + rdx * 4], zmm5			; split writes for zen4

	kmovw			eax, k1
	popcnt			eax, eax						; count how many first-uniques there were
	vpaddd			zmm10, zmm10, zmm26				; zmm26 has 16's: increment the indexes
	add				rdx, rax						; add the first-unique total to the first-unique write index
	jmp				.loop							; 17p5+(17p5) 6p0+(11p0) 14p05+(9p05)
													; 36p5 + 17p0 + 23p05. min loop is 38c. 10000 input words is 625 loops, so 5.40µs

													;zen4: conflictd is 2 µops  1fp01,1fp12
													;	permdi2d is				1fp12		x 5
													;	scatterdd is 89µops		2fp01,4fp12,8fp123,4fp23,34fp45 (52 + 37 write ops?)
													;	gatherdd is 81µops		1fp01,7fp0123,3fp12,9fp123,2fp23,18fp45 (40 + 41read ops?)
													;	vpadd,and,andn:			1fp0123		x 21
													;	vpopcntd:				1fp01		x 5
													;	vplzcntd:				1fp01		x 1
													;	compress:				1fp01,1fp12	x 1
													;	movdqa/u32:	(write)		1fp45+1memwr
													;	kmov:					1fp45 (k-k:1fp23)	1 of each
													;	testnm:					1fp01		x 2
													; assuming core can do all of 0,1,2,3,4,5 each cycle...
													; memory reads and writes don't go via the ports, but are still counted. fp45 is write address calc
													; zen4 compress is weird - more mem-ops than scatter if direct→mem...
													; 28p0123 17p123 7p23 13p01 7p12 57p45 72tp0123 ... p45 limits at 28.5c? 4.05µs?

.lastfew:
	mov				r11d, 0xffff
	shrx			r11d, r11d, ecx					; make mask of valid (non-overread) columns
	kmovw			k2, r11d

	kmovw			k1, k2
	vpgatherdd		zmm0{k1}, [rsi + zmm4 * 4]		; read current hashtable contents
	kmovw			k1, k2
	vpscatterdd		[rsi + zmm4 * 4]{k1}, zmm10		; write indexes to hashtable, leaving the leftmost in case of conflicts

	vpconflictd		zmm1{k2}, zmm4					; detect identical hashes in table
	vptestmd		k1{k2}, zmm1, zmm1				; indicates conflicting elements that need their link overwritten with the next right conflict
	vplzcntd		zmm1{k1}{z}, zmm1				; find leftmost bit in conflicted elements. the conflictd is still valid because the junk is leftward
	vpsubd			zmm1{k1}{z}, zmm26, zmm1		; zmm1 has 31s (a 1-bit in the rightmost position gives 31 - we need that to select element 0)
	vpermd			zmm0{k1}, zmm1, zmm10			; replace link with index of the next right conflicting element from this group
	vmovdqa32		[r10 + rax * 4]{k2}, zmm0		; write links to the link array

	vpcmpeqd		k1{k2}, zmm0, zmm27				; zmm27=-1s (dw) mask of new entries

	vpcompressd		zmm5{k1}, zmm5					; first-unique codes
	vmovdqu32		[rdi + rdx * 4], zmm5			; split writes for zen4

	kmovd			eax, k1
	popcnt			eax, eax

	add				rax, rdx						; return is the number that were expunged, still negative. caller add to previous nwords value to get new value

	;; no pops needed

	ret




