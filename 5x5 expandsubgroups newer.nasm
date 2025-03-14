; another way to do subgroup expansions:
; 1: count lettergroups and store totals in temp form
; 2: rearrange to make the per-group tables that will get created by the single-pass expansions
; 3: do each expansion group on whole codeset, ie 15 groups get created each has all letters with the pop2 ordering intact
; why? theres a lot of things that will cause latency-delays if they are done serially but can paralellize if they're done in separate loops
; or can be done more elegantly than in a single loop

; 0.32+0.66+2.61=3.59µs
global expandSubgroups

section .data align=64
merge2trearrange:
				db		1,0,5,4,9,8,13,12,17,16,21,20,25,24,29,28
				db		33,32,37,36,41,40,45,44,49,48,53,52,57,56,61,60
				db		65,64,69,68,73,72,77,76,81,80,85,84,89,88,93,92
				db		97,96,101,100,105,104,109,108,113,112,117,116,121,120,125,124
mergeevenwords:	dw		0,32,2,34,4,36,6,38,8,40,10,42,12,44,14,46
				dw		16,48,18,50,20,52,22,54,24,56,26,58,28,60,30,62
scatterpattern: dd		0,0x80,0x100,0x180,0x200,0x280,0x300,0x380
				dd		0x400,0x480,0x500,0x580,0x600,0x680,0x700,0x780
groupmemberships:
				dw		0xfffe,0x5554,0x3332,0x1110,0xf0e,0x504,0x302,0x100,0xfe,0x54,0x32,0x10,0xe,4,2,0
				dw		0xfffe,0x5554,0x3332,0x1110,0xf0e,0x504,0x302,0x100,0xfe,0x54,0x32,0x10,0xe,4,2,0
expandorder:	dd		1,3,7,2,4,8,5,9,6,10,11,12,13,14,15,0
bmtwd.perm:		db		0,16,32,48,2,18,34,50,4,20,36,52,6,22,38,54
				db		8,24,40,56,10,26,42,58,12,28,44,60,14,30,46,62
				db		1,17,33,49,3,19,35,51,5,21,37,53,7,23,39,55
				db		9,25,41,57,11,27,43,59,13,29,45,61,15,31,47,63
bmtwd.msh1:		dq		4,4,60,60
bmtwd.tlm1:		dq		0xf0f0f0f0f0f0f0f0, 0xf0f0f0f0f0f0f0f0
				dq		0x0f0f0f0f0f0f0f0f, 0x0f0f0f0f0f0f0f0f
bmtwd.msh2:		dq		2, 62
bmtwd.tlm2:		dq		0xcccccccccccccccc, 0x3333333333333333
bmtwd.msh3:		dq		0x19110901372f271f
bmtwd.tlm3:		dq		0x55555555aaaaaaaa
x8000s			dd		0x80008000
x4000s			dd		0x40004000
x100:			dd		0x100
x200:			dd		0x200
x400:			dd		0x400
x800:			dd		0x800
xFFFE			dd		0xfffe

section .text
; rdi = codes		rsi = index		 edx = nwords
expandSubgroups:
	push r12
	vpbroadcastd	zmm16, [x100]
	vpbroadcastd	zmm17, [x200]
	vpbroadcastd	zmm18, [x400]
	vpbroadcastd	zmm19, [x800]
	vmovdqa32		zmm20, [expandorder]
	vmovdqa32		zmm21, [bmtwd.perm]
	vbroadcasti64x4	zmm22, [bmtwd.msh1]
	vbroadcasti64x4	zmm23, [bmtwd.tlm1]
	vbroadcasti64x2	zmm24, [bmtwd.msh2]
	vbroadcasti64x2	zmm25, [bmtwd.tlm2]
	vpbroadcastq	zmm26, [bmtwd.msh3]
	vpbroadcastq	zmm27, [bmtwd.tlm3]
	vmovdqa32		zmm28, [merge2trearrange]
	vmovdqa32		zmm29, [groupmemberships]
	vpbroadcastd	zmm30, [x8000s]
	vpbroadcastd	zmm31, [x4000s]

	xor				r9, r9							; lettergroup to expand
	xor				r11, r11						; index for temp space writeout
	lea				r8, [rsp - (22 * 256)]			; temp space for the counts
	and				r8, -64							; aligned
	vpxord			zmm9, zmm9, zmm9				; overall group length accumulator
.letterloop:
	add				r9d, 1							; skip counting first letter's expansion since it'll never be used
	movsx			rcx, word [rsi + r9 * 4]		; whole length of the lettergroups is the first block

	test			rcx, rcx
	jz				.letterout						; no point continuing for letters with no words

	movzx			r10, word [rsi + r9 * 4 + 2]	; end of letter group
	lea				r10, [rdi + r10 * 4]			; to working pointer

	vpxord			zmm10, zmm10, zmm10				; per letter&subgroup group length accumulators
	vpxord			zmm11, zmm11, zmm11
	vpxord			zmm12, zmm12, zmm12
	vpxord			zmm13, zmm13, zmm13

.countloop:
	vmovdqu32		zmm0, [r10 + rcx * 4]
	vmovdqu32 		zmm1, [r10 + rcx * 4 + 64]
	vpermt2b		zmm0, zmm28, zmm1				; z28 = 1,0,5,4,9,8,13,12... (b)(l2r)
													; first words of 32 codes, reversed bytes
	vptestmw		k1, zmm0, zmm31					; z31 = 0x4000s(w) bit6 present as mask
	vptestmw		k2, zmm0, zmm30					; z30 = 0x8000s(w) bit7 present as mask
	vpermw			zmm0, zmm0, zmm29				; z29 = 0xfffe,0x5554,0x3332,0x1110,0x0f0e,0x0504,0x0302,0x0100,0xfe,....e,4,2,0 (x2)(w)(l2r)
													; 			 ↑ removing bit0 means we don't count group0 and it doesn't appear in the totals
;	vpbmtwd			zmm0, zmm0						; 4p5,2p0,3p05 - occupies zmm27 to zmm21
	vpermb			zmm1, zmm21, zmm0				; collect-first-bytes-ish
	vpermq			zmm2, zmm1, 0x4e				; swap lanes
	vprolvq			zmm2, zmm2, zmm22				; zmm24=4,4,-4,-4
	vpternlogq		zmm1, zmm23, zmm2, 0xb8			; B?C:A zmm25=0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0ff0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0 x2
	vpalignr		zmm2, zmm1, zmm1, 8				; swap qwords
	vprolvq			zmm2, zmm2, zmm24				; zmm26=2,-2
	vpternlogq		zmm1, zmm25, zmm2, 0xb8			; zmm27=0x3333333333333333cccccccccccccccc
	vpmultishiftqb	zmm0, zmm26, zmm1				; zmm28=0x19110901372f271f
	vpternlogq		zmm0, zmm27, zmm1, 0xe2			; B?A:C zmm29=0x55555555aaaaaaaa

	kmovd			eax, k1
	vpbroadcastd	zmm1, eax
	kmovd			eax, k2
	vpbroadcastd	zmm2, eax

	add				rcx, 32
	jns				.countOut

	vmovdqa32		zmm3, zmm0
	vpternlogd		zmm3, zmm1, zmm2, 0x10			;A&~(B|C) ie w0
	vpopcntd		zmm3, zmm3
	vpaddd			zmm10, zmm10, zmm3
	vmovdqa32		zmm3, zmm0
	vpternlogd		zmm3, zmm1, zmm2, 0x40			;A&(B&~C) ie w1
	vpopcntd		zmm3, zmm3
	vpaddd			zmm11, zmm11, zmm3
	vmovdqa32		zmm3, zmm0
	vpternlogd		zmm3, zmm1, zmm2, 0x20			;A&(~B&C) ie w2
	vpopcntd		zmm3, zmm3
	vpaddd			zmm12, zmm12, zmm3
	vpternlogd		zmm0, zmm1, zmm2, 0x80			;A&(B&C) ie w3
	vpopcntd		zmm0, zmm0
	vpaddd			zmm13, zmm13, zmm0

	jmp				.countloop						; 14p5 11p05 4p0 29tp05, 14.5c/l. 200l in 0.66µs

.countOut:
	vmovd			xmm3, ecx
	vpslld			zmm0, zmm0, xmm3				; dump bits from overread
	vpslld			zmm1, zmm1, xmm3
	vpslld			zmm2, zmm2, xmm3				; bits stay inline so rest is valid unmodified

	vmovdqa32		zmm3, zmm0
	vpternlogd		zmm3, zmm1, zmm2, 0x10			;A&~(B|C) ie w0
	vpopcntd		zmm3, zmm3
	vpaddd			zmm10, zmm10, zmm3
	vmovdqa32		zmm3, zmm0
	vpternlogd		zmm3, zmm1, zmm2, 0x40			;A&(B&~C) ie w1
	vpopcntd		zmm3, zmm3
	vpaddd			zmm11, zmm11, zmm3
	vmovdqa32		zmm3, zmm0
	vpternlogd		zmm3, zmm1, zmm2, 0x20			;A&(~B&C) ie w2
	vpopcntd		zmm3, zmm3
	vpaddd			zmm12, zmm12, zmm3
	vpternlogd		zmm0, zmm1, zmm2, 0x80			;A&(B&C) ie w3
	vpopcntd		zmm0, zmm0
	vpaddd			zmm13, zmm13, zmm0

	; write temp results
	vpaddd			zmm8, zmm10, zmm12
	vmovdqa32		[r8 + r11 * 4], zmm10			; w0
	vmovdqa32		[r8 + r11 * 4 + 64], zmm11		; w1
	vmovdqa32		[r8 + r11 * 4 + 128], zmm8		; w0+w2 (l1)
	vpaddd			zmm8, zmm8, zmm11
	vpaddd			zmm8, zmm8, zmm13				; we also want the overall totals for the expansion writeouts
	vmovdqa32		[r8 + r11 * 4 + 192], zmm8		; w0+w2+w1+w3
	vpaddd			zmm9, zmm9, zmm8				; overall accumulation
	add				r11, 64
	jmp				.letterloop

.letterout:											; next we do the actual expansions, for which we need to accumulate left:

	mov				[r8 - 4], r11d					; stored data end index stored before table

;	vmovdqu32		[rsp-72], zmm9
	vmovd			xmm1, edx						; nwords as g0 count
	vpord			zmm1, zmm1, zmm9
	vpxord			zmm0, zmm0, zmm0				; accumulate left (8 steps)
	valignd			zmm2, zmm1, zmm0, 8				; shift left 8 dwords
	vpaddd			zmm1, zmm1, zmm2
	valignd			zmm2, zmm1, zmm0, 12			; shift left 4 dwords
	vpaddd			zmm1, zmm1, zmm2
	valignd			zmm2, zmm1, zmm0, 14			; shift left 2 dwords
	vpaddd			zmm1, zmm1, zmm2
	valignd			zmm2, zmm1, zmm0, 15			; shift left 1 dwords
	vpaddd			zmm1, zmm1, zmm2
	vmovdqu32		[rsp-72], zmm1

; now end indexes for groups are in all columns, which can be considered start indexes for prior group. ie group0 end in zmm1[0] fro read is g1 start for write.
; lengths in zmm9 still need to be negated for loopcounter.

; expansion 1: from g0 to g1,g2,g4,g8
; expansion 2: from g1 to g3,g5,g9
; expansion 3: from g2 to g6,g10
; expansion 4: from g3 to g7,g11
; expansion 5,6,7,8: from g4,5,6,7 to g12,13,14,15
; where to put 4 indexes...		rdx,r9,r10,r11		; rdx already has right number for group1 write index. read rest from zmm1

	vpermd		zmm2, zmm20, zmm1					; zmm20 = 1,3,7,2,4,8,5,9,6,10,11,12,13,14,15,0
	vmovd		r9d, xmm2
	vpextrd		r10d, xmm2, 1
	vpextrd		r11d, xmm2, 2
	lea			r12, [rdi + rdx * 4]				; working endpointer for read
	movzx		ecx, word [rsi + 2]					; using end index of first g0 lettergroup as our increment to skip letter 0, the least popular...
	sub			rcx, rdx							; in this case nwords is still useful to generate our neglen loopcounter starting at letter 1.
													; the group count totals didn't include letter0 so everything is handled from here on
exp1loop:											; expansion 1: from g0 to g1,g2,g4,g8
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm16						; zmm16 = 0x100s(dw)
	vpcompressd	[rdi + rdx * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			edx, eax
	vptestnmd	k1, zmm0, zmm17						; zmm17 = 0x200s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r9d, eax
	vptestnmd	k1, zmm0, zmm18						; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp1loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm16					; zmm16 = 0x100s(dw)
	vpcompressd	[rdi + rdx * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm17					; zmm17 = 0x200s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18					; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ***********************

	valignd		zmm2, zmm2, zmm2, 3					; right rotate 3 dwords
	vmovd		r9d, xmm2
	vpextrd		r10d, xmm2, 1
	vpextrd		r11d, xmm2, 2
	vpextrd		ecx, xmm9, 1						; group1 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 1						; group1 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp2loop:											; expansion 2: from g1 to g3,g5,g9
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm17						; zmm17 = 0x200s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r9d, eax
	vptestnmd	k1, zmm0, zmm18						; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp2loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm17					; zmm17 = 0x200s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18					; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ***********************************************

	valignd		zmm2, zmm2, zmm2, 3					; right rotate 3 dwords
	vmovd		r10d, xmm2
	vpextrd		r11d, xmm2, 1
	vpextrd		ecx, xmm9, 2						; group2 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 2						; group2 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp3loop:											; expansion 3: from g2 to g6,g10
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm18						; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp3loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18					; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ***********************************************

	vpextrd		r10d, xmm2, 2
	vpextrd		r11d, xmm2, 3
	vpextrd		ecx, xmm9, 3						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 3						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp4loop:											; expansion 4: from g3 to g7,g11
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm18						; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp4loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18					; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ***********************************************

	valignd		zmm2, zmm2, zmm2, 4
	valignd		zmm1, zmm1, zmm1, 4
	valignd		zmm9, zmm9, zmm9, 4					; rotate for last 4

	vmovd		r11d, xmm2
	vmovd		ecx, xmm9							; group3 length
	neg			rcx									; to neglen
	vmovd		r12d, xmm1							; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp5loop:											; expansion 5: from g4 to g12
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp4loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ************************************************

	vpextrd		r11d, xmm2, 1
	vpextrd		ecx, xmm9, 1						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 1						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp6loop:											; expansion 6: from g5 to g13
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp6loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ************************************************

	vpextrd		r11d, xmm2, 2
	vpextrd		ecx, xmm9, 2						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 2						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp7loop:											; expansion 7: from g6 to g14
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp7loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

; ************************************************

	vpextrd		r11d, xmm2, 3
	vpextrd		ecx, xmm9, 3						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 3						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

exp8loop:											; expansion 8: from g7 to g15
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	jns			.out
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			exp8loop
.out:
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0


; each expansion removes 33% of the codes. limiting factor is compress throughput of 3c.
;	expansion 1: 1,2,4,8, whole set processed = 375 loops @ 12c
;	expansion 2: 3,5,6,9,10,12 on .66 set = 250loops @18c
;	expansion 3: 7,11,13,14  on .44 set = 180loops @12c
;	expansion 4: 15 on .30 set = 108 loops @3c
;	total: 11484c, 2.61µs

; **************************************************

; now to populate the main searchgroup tables with index/neglen pairs for the expansion groups...


; we have horizontal rows of exp.group populations separated by pop2.subgroup and letter
; we need horizontal rows of letters separated by pop2/exp.group.
; subgroups are contiguous, letters are sequential within exp.groups.
; end index of subgroup is start of exp.group + summed counts of whole of prior letters within exp.group + subgroup offsets
; we need whole of each letter group as a sum for easy summing. we can use the exp.group starts calculated before
; then subtract w1 from end of letter group to get e1e3 and e0e2
; l0 is whole group length
; l1 is w0+w2
; l2 is w0+w1
; l3 is w0

;   so storing w0, w1, w0+w2, w0+w2+w1+w3 makes most sense
;	simplest write-out is by scatter, but might be slow... time could easily be 22*64c = 0.32µs. not too bad really.
;					might be better in the countloop? not possible,	since we need the group totals to begin the calc.
;	perhaps gathering for each group would work better, then calc all letters together for each group and its subgroups?
;					maybe 2*speedup on memory ops?
	vmovdqa32	zmm31, [mergeevenwords]			; 0,32,2,34,4,36,6,38...(w)(l2r)
	vmovdqa32	zmm30, [scatterpattern]			; 0, 128,256,384,512...(dw)(l2r)
	kmovw		k6, [xFFFE]						; to clear column 0 and prevent scatter of g0 values
	mov			ecx, [r8 - 4]					; last known accruing of count data
	mov			edx, 1							; letter group to scatter to
	lea			r8, [r8 + rcx * 4]				; to endpointer
	neg			rcx
	vpxord		zmm0, zmm0, zmm0				; a zero for subtractive negations
	valignd		zmm1{k6z}, zmm1, zmm1, 11		; restore group end-indexes to original columns but left 1 for use as start-index accumulator
indexloop:
	vmovdqa32	zmm2, [r8 + rcx * 4]			; w0			(l3)
	vmovdqa32	zmm3, [r8 + rcx * 4 + 64]		; w1
	vmovdqa32	zmm4, [r8 + rcx * 4 + 128]		; w0+w2			(l1)
	vmovdqa32	zmm5, [r8 + rcx * 4 + 192]		; w0+w1+w2+w3	(l0)
	vpaddd		zmm1, zmm1, zmm5				; base+w0123	(e0,e2)
	vpsubd		zmm6, zmm1, zmm1				; base+w023		(e1,e3)
	vpsubd		zmm3, zmm0, zmm3
	vpsubd		zmm2, zmm0, zmm2
	vpaddd		zmm3, zmm3, zmm2				; w0+w1			(l2)
	vpsubd		zmm4, zmm0, zmm4
	vpsubd		zmm5, zmm0, zmm5				; lengths negative now

	lea			rax, [rsi + rdx * 4]
	kmovw		k1, k6
	vmovdqa32	zmm7, zmm31
	vpermi2w	zmm7, zmm5, zmm1
	vpscatterdd	[rax + zmm30 * 4]{k1}, zmm7
	add			rax, 128						; 32 dwords over is the next subgroup
	kmovw		k1, k6
	vmovdqa32	zmm7, zmm31
	vpermi2w	zmm7, zmm4, zmm6
	vpscatterdd	[rax + zmm30 * 4]{k1}, zmm7
	add			rax, 128						; 32 dwords over is the next subgroup
	kmovw		k1, k6
	vmovdqa32	zmm7, zmm31
	vpermi2w	zmm7, zmm3, zmm1
	vpscatterdd	[rax + zmm30 * 4]{k1}, zmm7
	add			rax, 128						; 32 dwords over is the next subgroup
	kmovw		k1, k6
	vmovdqa32	zmm7, zmm31
	vpermi2w	zmm7, zmm2, zmm6
	vpscatterdd	[rax + zmm30 * 4]{k1}, zmm7


	add			edx, 1
	add			rcx, 64
	js			indexloop

	pop			r12
	ret
; total size of expansions: 5900*.66 = 3894	* 4 = 15576+
;							3894*.66 = 2570 * 6 = 15420+
;							2570*.66 = 1696 * 4 =  6784+
;							1696*.66 = 1119 * 1 =  1119=38899+6000=44899*4=180KB

