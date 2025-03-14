;********** v16>4p sort by compression			3-stage total = 3.54µs expected, 4.05µs measured (close enough, even though scatter)
;********** and v16>32p sort by scatter

; rdi = codes	rsi = length	 rdx = index

global sortpop2lpop

section .data
align 64
z16:	dd	1,2,4,8,1,2,4,8,1,2,4,8,1,2,4,8
z15:	dd	0x10,0x20,0x40,0x80,0x100,0x200,0x400,0x800
		dd	0x1000,0x2000,0x4000,0x8000,0x10000,0x20000,0x40000,0x80000
z14:	dd	0x100000,0x200000,0x400000,0x800000,0x1000000,0x2000000,0x4000000,0x8000000
		dd	0x10000000,0x20000000,0,0,0,0,0,0
;z31:	db	16 dup (0), 16 dup (64), 16 dup (192), 16 dup (128)
z13:	dd	0,1,3,7,0xf,0x1f,0x3f,0x7f,0xff,0x1ff,0x3ff,0x7ff,0xfff,0x1fff,0x3fff,0x7fff
interleavelowwords:
		dw	0,32,1,33,2,34,3,35,4,36,5,37,6,38,7,39
		dw	8,40,9,41,10,42,11,43,12,44,13,45,14,46,15,47
interleavehighwords:
		dw	16,48,17,49,18,50,19,51,20,52,21,53,22,54,23,55
		dw	24,56,25,57,26,58,27,59,28,60,29,61,30,62,31,63
bmtdw.perm:		db		0,32,4,36,8,40,12,44,16,48,20,52,24,56,28,60
				db		1,33,5,37,9,41,13,45,17,49,21,53,25,57,29,61
				db		2,34,6,38,10,42,14,46,18,50,22,54,26,58,30,62
				db		3,35,7,39,11,43,15,47,19,51,23,55,27,59,31,63

z21:	dd	0x10000000,0x20000000,0x40000000,0x80000000
;z30:	db	0,4,8,12,16,20,24,28,32,36,40,44,48,52,56,60
bmtdw.msh1:		dq		4,60
bmtdw.tlm1:		dq		0xf0f0f0f0f0f0f0f0, 0x0f0f0f0f0f0f0f0f
bmtdw.msh2:		;dq		0x1a120a02362e261e
				db		30,38,46,54,2,10,18,26
bmtdw.tlm2:		dq		0x33333333cccccccc
bmtdw.msh3:		;dq		0x2921372f0901170f
				db		15,23,1,9,47,55,33,41
bmtdw.tlm3:		dq		0x5555aaaa5555aaaa

z22:	dd	1			;16 dup (1)
evencomb:	dd	0x55555555
blokgroups:	dd	0x0fffffff
z30:	dd	64
z31:	dd	128

z20:	dw	28,28			;32 dup (60)
z19:	dw	29,29			;32 dup (61)
z18:	dw	30,30			;32 dup (62)
z17:	dw	31,31			;32 dup (63)


section .text
align 16

sortpop2lpop:
;	TODO: pushes
	push			r12
	push			r13
	push			r14

	vmovdqa32		zmm13, [z13]		; preloading all used masks, perms and constants
	vmovdqa32		zmm14, [z14]
	vmovdqa32		zmm15, [z15]
	vmovdqa32		zmm16, [z16]
	vpbroadcastd	zmm17, [z17]
	vpbroadcastd	zmm18, [z18]
	vpbroadcastd	zmm19, [z19]
	vpbroadcastd	zmm20, [z20]
	vbroadcasti32x4	zmm21, [z21]
	vpbroadcastd	zmm22, [z22]
	vmovdqa32		zmm23, [bmtdw.perm]
	vbroadcasti64x2	zmm24, [bmtdw.msh1]
	vbroadcasti64x2	zmm25, [bmtdw.tlm1]
	vpbroadcastq	zmm26, [bmtdw.msh2]
	vpbroadcastq	zmm27, [bmtdw.tlm2]
	vpbroadcastq	zmm28, [bmtdw.msh3]
	vpbroadcastq	zmm29, [bmtdw.tlm3]

	vpbroadcastd	zmm30, [z30]
	vpbroadcastd	zmm31, [z31]
	kxorq			k0,k0,k0
	knotq			k0,k0				; 0xffffffffffffffff for scatter mask

;	add			ecx, 15
;	and			ecx, -16				; round up to nearest whole block
	mov			r10, rdi				; keep for later
	lea			rdi, [rdi + rsi * 4]	; now points at top
	mov			rcx, rsi				; loopcounter
	neg			rsi
	lea			r8, [rsp + rsi * 4 - 8]	; r8 points at bottom
	and			r8, -64					; aligned
	lea			r9, [r8 + rcx * 4]		; r9 points at top
	neg			rcx

;*** first count up, might as well count for the second sort at the same time...
	vpxord		zmm10, zmm10, zmm10		; word count register

.countloop:
	vmovdqa32		zmm0, [rdi + rcx * 4]
	vpsrld			zmm1, zmm0, 6
	vpermd			zmm1, zmm1, zmm16		; z16=1,2,4,8,1,2,4,8,1,2,4,8,1,2,4,8

	vplzcntd		zmm2, zmm0
	vpermi2d		zmm2, zmm15, zmm14		; z15=0x10,20,40,80,100,200...
											; z14=0x100000,0x200000... only to column 10
	vpord			zmm1, zmm1, zmm2		; combined counts

;;	vpbmtdw			zmm1, zmm0						; should be an instruction
													; but it isn't, so we do this:
	vpermb			zmm1, zmm23, zmm1				; collect first bytes in first lane, second bytes in second lane...
	vpalignr		zmm2, zmm1, zmm1, 8				; swap qwords
	vprolvq			zmm2, zmm2, zmm24				; alternating direction rotates of 4 bits. using this custom bmt reduces p5 ops by one...
	vpternlogd		zmm1, zmm25, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm26, zmm1
	vpternlogd		zmm1, zmm27, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm28, zmm1
	vpternlogd		zmm1, zmm29, zmm2, 0xb8			; B?C:A			...because there's no pshufb required at the end

	add				rcx, 16
	jns				.clOut

	vpopcntw		zmm2, zmm1
	vpaddw			zmm10, zmm10, zmm2		; count up for sorts

	jmp				.countloop				; negative loopcounter
.clOut:
	movd			xmm0, ecx
	vpsllw			zmm1, zmm1, xmm0		; dump extra bits of last round
	vpopcntw		zmm2, zmm1
	vpaddw			zmm10, zmm10, zmm2		; count up for sorts
	vmovdqu32		[rsp - 72], zmm10				; for DEBUG

							; without subcounts: 6 op p5, 4 on p0, 5 on p05, 7.5c/l = 0.64µs
							; with subcounts: 10p5, 8p0, 13p05, 31p05t = 15.5c/l = 1.32µs
;*** now to sort into 4 groups by most popular 2 letters using compress to enable writing
;	an average of 4 codes per write
; we get 21 letter groups by lzcnt
; order matters: when searching the 2 bits directly select a group to search.
; m0: whole group, words with w0,w1,w2,w3
; m1: words with w0,w2 only
; m2: words with w0,w1 only
; m3: words with w0 only.
; this means that the w0 group is inside all m groups, and needs to be in the middle,
; the w3 group is only included in m0, needs to be at the edge.
; 4 possible orders:  w1w0w2w3, w2w0w1w3, w3w1w0w2, w3w2w0w1
; which will be read: m02m0123m01m0, m01m0123m02m0, m0m02m0123m01, m0m01m0123m02
; last one makes most sense.
; so:	write idx both(w3) = 0
;		write idx b7(w2) = l3
;		write idx niether(w0) = l3+l2
;		write idx b6(w1) = l3+l2+l0

	movq		r12, xmm10				; get the 4 group counts
	mov			r11, r12				;
	mov			r14, r12				;
	movzx		r12d, r12w				; l0
	shr			r11, 32
	movzx		r11d, r11w				; l2
	shr			r14, 48					; l3		r14 = idx b7 pile (w2)
	add			r11d, r14d				; l2+l3 	r11 = ptr neither pile (w0)
	add			r12d, r11d				; l0+l2+l3	r12 = idx b6 pile (w1)
	xor			r13d, r13d				; 0			r13 = idx both pile	(w3)

	mov			rcx, rsi				; rsi is already neg'd
	vpxord		zmm1, zmm1, zmm1		; for DEBUG

.pop2loop:
	vmovdqa32	zmm0, [rdi + rcx * 4]
	vmovdqa32	[rdi + rcx * 4], zmm1		; clearing codes array for DEBUG
	vptestmd	k1, zmm0, zmm30				; zmm30 = 64s (dw)
	vptestmd	k2, zmm0, zmm31				; zmm31 = 128s (dw)
	korw		k3, k2, k1
 	add			rcx, 16
	jns			.pop2Out
	knotw		k3, k3
	vpcompressd	[r8 + r11 * 4]{k3}, zmm0	;neithers
	kmovw		eax, k3
	popcnt		eax, eax
	add			r11, rax
	kandnw		k3, k2, k1
	vpcompressd	[r8 + r12 * 4]{k3}, zmm0	;b6s
	kmovw		eax, k3
	popcnt		eax, eax
	add			r12, rax
	kandw		k3, k2, k1
	vpcompressd	[r8 + r13 * 4]{k3}, zmm0	;both
	kmovw		eax, k3
	popcnt		eax, eax
	add			r13, rax
	kandnw		k3, k1, k2
	vpcompressd	[r8 + r14 * 4]{k3}, zmm0	;b7s
	kmovw		eax, k3
	popcnt		eax, eax
	add			r14, rax
 	jmp			.pop2loop			; 4 compress, 10 on p5 min 12c/l(compress) 9p0 4p1 1p06 4p0156
.pop2Out:								; total 28µop, 1read,4write. 375*13/4400=1.02µs
	mov			eax, 0xffff
	shrx		eax, eax, ecx		; mask write of final groups
	kmovw		k4, eax				; no need for final pointer increments
	kandnw		k3, k3, k4
	vpcompressd	[r8 + r11 * 4]{k3}, zmm0	;neithers
	kmovw		eax, k3
	popcnt		eax, eax
	add			r11, rax			; EXCEPT FOR debug
	kandnw		k3, k2, k1
	kandw		k3, k3, k4
	vpcompressd	[r8 + r12 * 4]{k3}, zmm0	;b6s
	kmovw		eax, k3
	popcnt		eax, eax
	add			r12, rax			; EXCEPT FOR debug
	kandw		k3, k2, k1
	kandw		k3, k3, k4
	vpcompressd	[r8 + r13 * 4]{k3}, zmm0	;both
	kmovw		eax, k3
	popcnt		eax, eax
	add			r13, rax			; EXCEPT FOR debug
	kandnw		k3, k1, k2
	kandw		k3, k3, k4
	vpcompressd	[r8 + r14 * 4]{k3}, zmm0	;b7s
	kmovw		eax, k3
	popcnt		eax, eax
	add			r14, rax			; EXCEPT FOR debug

				; can't split writes for zen4 since the final 3 rounds would overwrite the beginnings of the next section
				; unless... pre-read the memory (vmovdqu32) then merge-compress before write... only adds read ops, but
				; could mess with and block hoisting?

; *** now we must stabley sort by 32(22) piles with scatter
; accumulate left to provide write indexes
	vpxord		zmm0, zmm0, zmm0
	valignd		zmm10, zmm0, zmm10, 2		; shift right by 4 words (dump pop2 counts)
	valignd		zmm11, zmm10, zmm0, 8		; shift left 16 words
	vpaddw		zmm10, zmm11, zmm10
	valignd		zmm11, zmm10, zmm0, 12		; shift left 8 words
	vpaddw		zmm10, zmm11, zmm10
	valignd		zmm11, zmm10, zmm0, 14		; shift left 4 words
	vpaddw		zmm10, zmm11, zmm10
	valignd		zmm11, zmm10, zmm0, 15		; shift left 2 words
	vpaddw		zmm10, zmm11, zmm10
	valignd		zmm11, zmm10, zmm0, 12		; shift left 1 lane in order to
	vpalignr	zmm11, zmm10, zmm11, 14		; shift left 1 word
	vpaddw		zmm10, zmm11, zmm10
	valignd		zmm11, zmm10, zmm0, 12		; shift left 1 lane in order to
	vpalignr	zmm10, zmm10, zmm11, 14		; shift left 1 word

	kmovd		k7, [evencomb]
	kmovd		k6, [blokgroups]
	mov			rcx, rsi
	vpxord		zmm6, zmm6, zmm6
	vpxord		zmm7, zmm7, zmm7
	vpxord		zmm8, zmm8, zmm8
	vpxord		zmm9, zmm9, zmm9			; clear count registers (DUH!)

 .lpoploop:
 	vmovdqa32	zmm0, [r9 + rcx * 4]
 	vplzcntd	zmm3, zmm0				; it's impossible for this to produce result above 21

	vpsrld		zmm2, zmm0, 6			; which means we can squeeze the counting for the subgroups in the top 4 bits
	vpermd		zmm2, zmm2, zmm21		; z21=0x10000000,0x20000000,0x40000000,0x80000000 x4

	vpsllvd		zmm1, zmm22, zmm3		; z22 = 1s (dw)
	vpord		zmm1, zmm1, zmm2		; combine for counts

;;	vpbmtdw			zmm1, zmm0						; should be an instruction
													; but it isn't, so we do this:
	vpermb			zmm1, zmm23, zmm1				; collect first bytes in first lane, second bytes in second lane...
	vpalignr		zmm2, zmm1, zmm1, 8				; swap qwords
	vprolvq			zmm2, zmm2, zmm24				; alternating direction rotates of 4 bits. using this custom bmt reduces p5 ops by one...
	vpternlogd		zmm1, zmm25, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm26, zmm1
	vpternlogd		zmm1, zmm27, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm28, zmm1
	vpternlogd		zmm1, zmm29, zmm2, 0xb8			; B?C:A			...because there's no pshufb required at the end

	vpopcntw	zmm4{k6z}, zmm1			; column increments
	vpermw		zmm2{k7z}, zmm3, zmm1	; confict bits to columns
	vpandd		zmm2, zmm2, zmm13		; filter for right relevence z13=0,1,3,7,f,1f,3f..dw
	vpopcntd	zmm2, zmm2				; count right relevent conflicts
	vpermw		zmm5{k7z}, zmm3, zmm10	; indexes to columns
	vpaddw		zmm10, zmm10, zmm4		; minimum loop latency (~1c)
	vpaddd		zmm5, zmm5, zmm2		; avoid conflicts

 	add			rcx, 16					; negative loopcounter
	jns 		.lpopOut

	kmovw		k1, k0
 	vpscatterdd	[r10 + zmm5 * 4]{k1}, zmm0	; write out perfectly?

	vpermw		zmm11, zmm20, zmm1		; z20 = 28s (w) => broadcast "code is neither" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11		; k6: block counting of the pop2-subgroup bits
	vpaddw		zmm9, zmm9, zmm11		; z9 = per letter count of group w0
	vpermw		zmm11, zmm19, zmm1		; z19 = 29s (w) => broadcast "code has b6 only" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm8, zmm8, zmm11		; z8 = per letter count of group w1
	vpermw		zmm11, zmm18, zmm1		; z18 = 30s (w) => broadcast "code has b7 only" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm7, zmm7, zmm11		; z7 = per letter count of group w2
	vpermw		zmm11, zmm17, zmm1		; z17 = 31s (w) => broadcast "code has both" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm6, zmm6, zmm11		; z6 = per letter count of group w3


 	jmp			.lpoploop
.lpopOut: 								; without subcounts:
 										; 16 writes, 8p5, 5p0, 10p05, p05t23 +3
 										; 16c/l x375 = 1.36µs
 								; with subcounts:
 										; 16 writes, 13p5, 10p0, 19p05, p05t42 +3
 										; 21c/l x375 = 1.79µs
	mov			eax, 0xffff
	shrx		eax, eax, ecx		; mask write of final groups
	kmovw		k1, eax				; no need for final pointer increments
 	vpscatterdd	[r10 + zmm5 * 4]{k1}, zmm0	; write out perfectly?

	movd		xmm0, ecx
	vpslld		zmm1, xmm0				; shift overread results out of view
	vpermw		zmm11, zmm20, zmm1		; z20 = 28s (w) => broadcast "code is neither" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm9, zmm9, zmm11		; z9 = per letter count of group w0
	vpermw		zmm11, zmm19, zmm1		; z19 = 29s (w) => broadcast "code has b6 only" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm8, zmm8, zmm11		; z8 = per letter count of group w1
	vpermw		zmm11, zmm18, zmm1		; z18 = 30s (w) => broadcast "code has b7 only" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm7, zmm7, zmm11		; z7 = per letter count of group w2
	vpermw		zmm11, zmm17, zmm1		; z17 = 31s (w) => broadcast "code has both" bits
	vpandd		zmm11, zmm1
	vpopcntw	zmm11{k6z}, zmm11
	vpaddw		zmm6, zmm6, zmm11		; z6 = per letter count of group w3




;**************************************************************************************
; TODO:	now total up and write index/length pairs to index for first 128 search groups

; lines reading the tables will use (lzcnt(code)+(pop6)<<5) as dword index.
; and what they expect to find is[31:16]=end+1 index, [15:0]=-len(group)
; what we know here will be contiguous groups of interleaved length/endindex pairs for all letters.

; chosen order:  w3w2w0w1 (l2r memorder)
; which will be read: m0m01m0123m02 (l2r)

; so we do math to create endpointers
; will be read according to current mask bits, not code bits (opposite)
; so must write in mask order.
; l0 = w3+w2+w0+w1
; l1 = w2+w0
; l2 = w0+w1
; l3 = w0

; e0 = base + l0
; e1 = base + w3 + w2 + w0
; e2 = e0
; e3 = e1
; base = total of all from before

; so we need:
; w0
; w0+w1
; w0+w2
; w0+w2+w3
; w0+w2+w3+w1
; leftward summing of w0+w2+w3+w1

; z9=w0, z8=w1, z7=w2, z6=w3
										; w0 = 			:l3
	vpaddw		zmm5, zmm9, zmm8		; w0+w1			:l2
	vpaddw		zmm4, zmm9, zmm7		; w0+w2			:l1
	vpaddw		zmm3, zmm4, zmm6		; w0+w2+w3
	vpaddw		zmm2, zmm3, zmm8		; w0+w2+w3+w1	:l0

	vpxord		zmm0, zmm0, zmm0		; 0 for rotations
	valignd		zmm6, zmm2, zmm0, 8		; left half have right half added
	vpaddw		zmm1, zmm2, zmm6
	valignd		zmm6, zmm1, zmm0, 12	; left 3/4 have the rest added
	vpaddw		zmm1, zmm1, zmm6
	valignd		zmm6, zmm1, zmm0, 14	; left 7/8 have the rest added
	vpaddw		zmm1, zmm1, zmm6
	valignd		zmm6, zmm1, zmm0, 15	; left 15/16 have the rest added
	vpaddw		zmm1, zmm1, zmm6
	valignd		zmm6, zmm1, zmm0, 12	; shift left 1 lane in order to
	vpalignr	zmm6, zmm1, zmm6, 14	; shift left 1 word
	vpaddw		zmm1, zmm1, zmm6		; base + w0+w2+w3+w1	:e0,e2
	vpsubw		zmm8, zmm1, zmm8		; base + w0+w2+w3		:e1,e3

; so now we have e0,e2 in zmm1, e1,e3 in zmm8, l0 in zmm2, l1 in zmm4, l2 in zmm5, l3 in zmm9
; we need to negate lengths and assembl l0e0,l1e1,l2e2,l3e3 in dquads.
; easiest way is probably unpack ops
;	all preloaded constants are unneeded now so we do from z10 up
	vpsubw		zmm2, zmm0, zmm2		; -l0
	vpsubw		zmm4, zmm0, zmm4		; -l1
	vpsubw		zmm5, zmm0, zmm5		; -l2
	vpsubw		zmm9, zmm0, zmm9		; -l3

; interleave l0w0 pairs into dwords
; load 2 more permute tables for word interleave
	vmovdqa32	zmm10, [interleavelowwords]		; :: 0,32,1,33,2,34,3,35,4,36,5,37,6,38...(w)(l2r)
	vmovdqa32	zmm11, [interleavehighwords]	; :: 16,48,17,49,18,50...(w)(l2r)
	vmovdqa32	zmm0, zmm10
	vpermi2w	zmm0, zmm2, zmm1
	vmovdqa32	[rdx], zmm0
	vmovdqa32	zmm0, zmm11
	vpermi2w	zmm0, zmm2, zmm1
	vmovdqa32	[rdx+64], zmm0
	vmovdqa32	zmm0, zmm10
	vpermi2w	zmm0, zmm4, zmm8
	vmovdqa32	[rdx+128], zmm0
	vmovdqa32	zmm0, zmm11
	vpermi2w	zmm0, zmm4, zmm8
	vmovdqa32	[rdx+192], zmm0
	vmovdqa32	zmm0, zmm10
	vpermi2w	zmm0, zmm5, zmm1
	vmovdqa32	[rdx+256], zmm0
	vmovdqa32	zmm0, zmm11
	vpermi2w	zmm0, zmm5, zmm1
	vmovdqa32	[rdx+320], zmm0
	vmovdqa32	zmm0, zmm10
	vpermi2w	zmm0, zmm9, zmm8
	vmovdqa32	[rdx+384], zmm0
	vmovdqa32	zmm0, zmm11
	vpermi2w	zmm0, zmm9, zmm8
	vmovdqa32	[rdx+448], zmm0
; done.

	pop			r14
	pop			r13
	pop			r12
	ret
