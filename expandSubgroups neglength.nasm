; ********   subgroup scatter by compress
;	same principal as the scalar sort but 16 codes at a time with compress select
;	expected 2.35µs total time

global expandSubgroups

default rel

section .data
align 64
z14:	dd	0,0x80,0x100,0x180,0x200,0x280,0x300,0x380
		dd	0x400,0x480,0x500,0x580,0x600,0x680,0x700,0x780
z19:	db	1,0,5,4,9,8,13,12,17,16,21,20,25,24,29,28
		db	33,32,37,36,41,40,45,44,49,48,53,52,57,56,61,60
		db	65,64,69,68,73,72,77,76,81,80,85,84,89,88,93,92
		db	97,96,101,100,105,104,109,108,113,112,117,116,121,120,125,124
z29:	dw	0xfffe,0x5554,0x3332,0x1110,0xf0e,0x504,0x302,0x100,0xfe,0x54,0x32,0x10,0xe,4,2,0
		dw	0xfffe,0x5554,0x3332,0x1110,0xf0e,0x504,0x302,0x100,0xfe,0x54,0x32,0x10,0xe,4,2,0
extractable:	dd		1,2,4,8,3,5,9,6,10,7,11,12,13,14,15,0
mergeevenwords2t:
				dw		0,32,2,34,4,36,6,38,8,40,10,42,12,44,14,46
				dw		16,48,18,50,20,52,22,54,24,56,26,58,28,60,30,62
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
;upperw:	dq	0xcccccccccccccccc
z30:	dd	0x80008000
z31:	dd	0x40004000
x100:	dd	0x100
x200:	dd	0x200
x400:	dd	0x400
x800:	dd	0x800
comb:	dd	0xcccccccc



section .text
; rdi = codes		rsi = index		 edx = nwords
expEnd:
;; TODO: cleanup and pops

	ret

expandSubgroups:
;; TODO: pushes
;; first load masks and permutations
	vmovdqa32		zmm13, [extractable]
	vmovdqa32		zmm14, [z14]
	vpbroadcastd	zmm15, [x100]	; 0x100
	vpbroadcastd	zmm16, [x200]	; 0x200
	vpbroadcastd	zmm17, [x400]	; 0x400
	vpbroadcastd	zmm18, [x800]	; 0x800
	vmovdqa32		zmm19, [z19]
	mov				eax, 1
	vpbroadcastw	zmm20, eax
	vmovdqa32		zmm21, [bmtwd.perm]
	vbroadcasti64x4	zmm22, [bmtwd.msh1]
	vbroadcasti64x4	zmm23, [bmtwd.tlm1]
	vbroadcasti64x2	zmm24, [bmtwd.msh2]
	vbroadcasti64x2	zmm25, [bmtwd.tlm2]
	vpbroadcastq	zmm26, [bmtwd.msh3]
	vpbroadcastq	zmm27, [bmtwd.tlm3]
	vmovdqa32		zmm28, [mergeevenwords2t]
	vmovdqa32		zmm29, [z29]
	vpbroadcastd	zmm30, [z30]
	vpbroadcastd	zmm31, [z31]
	mov				eax, 0xfffe
	kmovw			k6, eax
; broadcast bitmasks to z10/11/12/13 just before expansion, not here

	xor		ebx, ebx
.letterloop:
	add		ebx, 1							; letter: skipping subgroup scatter for first letter as it will
											; 	not be used
	movsx	rcx, word [rsi + rbx * 4]		; whole length of the lettergroups is the first block
	test	rcx, rcx
	jz		expEnd							; no point continuing for letters with no words
	mov				r9, rcx					; keep for later
	movzx			r8, word [rsi + rbx * 4 + 2]	; end of letter group
	lea				r8, [rdi + r8 * 4]		; to working pointer
	vpxord			zmm2, zmm2, zmm2		; the count w0
	vpxord			zmm3, zmm3, zmm3		; the count w1
	vpxord			zmm4, zmm4, zmm4		; the count w2
	vpxord			zmm5, zmm5, zmm5		; the count w3
.subgroupcountloop:
	vmovdqu32		zmm0, [r8 + rcx * 4]
	vmovdqu32 		zmm1, [r8 + rcx * 4 + 64]
	vpermt2b		zmm0, zmm19, zmm1		; z19=1,0,5,4,9,8,13,12 (b)(l2r)
											; first words of 32 codes, reversed bytes
	vptestmw		k1, zmm0, zmm31			; z31 = 0x4000s(w) bit6 present as mask
	vptestmw		k2, zmm0, zmm30			; z30 = 0x8000s(w) bit7 present as mask
	vpermw			zmm0, zmm0, zmm29		; z29 = 0xfffe,0x5554,0x3332,0x1110,0x0f0e,0x0504,0x0302,0x0100,0xfe,....,0 (x2)(w)(l2r)
											; excluding bit0 means the count for the unfiltered group g0 will be ignored and excluded
	vpermb			zmm1, zmm21, zmm1		; collect-first-bytes-ish
	vpermq			zmm2, zmm1, 0x4e		; swap lanes
	vprolvq			zmm2, zmm2, zmm22		; zmm24=4,4,-4,-4
	vpternlogq		zmm1, zmm23, zmm2, 0xb8	; B?C:A zmm25=0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0ff0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0 x2
	vpalignr		zmm2, zmm1, zmm1, 8		; swap qwords
	vprolvq			zmm2, zmm2, zmm24		; zmm26=2,-2
	vpternlogq		zmm1, zmm25, zmm2, 0xb8	; zmm27=0x3333333333333333cccccccccccccccc
	vpmultishiftqb	zmm2, zmm26, zmm1		; zmm28=0x19110901372f271f
	vpternlogq		zmm1, zmm27, zmm2, 0xb8	; zmm29=0x55555555aaaaaaaa

	kmovd			eax, k1
	vpbroadcastd	zmm11, eax
	kmovd			eax, k2
	vpbroadcastd	zmm12, eax

	add				rcx, 32
	jns				.sgclOut

	vmovdqa32		zmm10, zmm0
	vpternlogd		zmm10, zmm11, zmm12, 0x10	;A&~(B|C) ie w0
	vpopcntd		zmm10, zmm10
	vpaddd			zmm2, zmm2, zmm10
	vmovdqa32		zmm10, zmm0
	vpternlogd		zmm10, zmm11, zmm12, 0x80	;A&(B&C) ie w3
	vpopcntd		zmm10, zmm10
	vpaddd			zmm5, zmm5, zmm10
	vmovdqa32		zmm10, zmm0
	vpternlogd		zmm10, zmm11, zmm12, 0x40	;A&(B&~C) ie w1
	vpopcntd		zmm10, zmm10
	vpaddd			zmm3, zmm3, zmm10
	vpternlogd		zmm0, zmm11, zmm12, 0x20	;A&(~B&C) ie w2
	vpopcntd		zmm0, zmm0
	vpaddd			zmm4, zmm4, zmm0

	jmp				.subgroupcountloop		; 14p5 11p05 4p0 29tp05, 14.5c/l
.sgclOut:
	movd			xmm1, ecx
	vpslld			zmm0, zmm0, xmm1		; dump bits from overread
	vpslld			zmm11, zmm11, xmm1
	vpslld			zmm12, zmm12, xmm1		; bits stay inline so rest is valid unmodified

	vmovdqa32		zmm10, zmm0
	vpternlogd		zmm10, zmm11, zmm12, 0x10	;A&~(B|C) ie w0
	vpopcntd		zmm10, zmm10
	vpaddd			zmm2, zmm2, zmm10
	vmovdqa32		zmm10, zmm0
	vpternlogd		zmm10, zmm11, zmm12, 0x80	;A&(B&C) ie w3
	vpopcntd		zmm10, zmm10
	vpaddd			zmm5, zmm5, zmm10
	vmovdqa32		zmm10, zmm0
	vpternlogd		zmm10, zmm11, zmm12, 0x40	;A&(B&~C) ie w1
	vpopcntd		zmm10, zmm10
	vpaddd			zmm3, zmm3, zmm10
	vpternlogd		zmm0, zmm11, zmm12, 0x20	;A&(~B&C) ie w2
	vpopcntd		zmm0, zmm0
	vpaddd			zmm4, zmm4, zmm0

	; group0l is all 4 combined - indexes based on sum of prior g0 lengths
	vpaddd		zmm10, zmm2, zmm4			; w0 + w2
	vpaddd		zmm8, zmm10, zmm5			; w0 + w2 + w3
	vpaddd		zmm10, zmm8, zmm3			; whole group lengths, will be g0l

	vpxord		zmm0, zmm0, zmm0			; accumulate left (8 steps)
	valignd		zmm12, zmm10, zmm0, 8		; shift left 8 dwords
	vpaddd		zmm11, zmm10, zmm12
	valignd		zmm12, zmm11, zmm0, 12		; shift left 4 dwords
	vpaddd		zmm11, zmm11, zmm12
	valignd		zmm12, zmm11, zmm0, 14		; shift left 2 dwords
	vpaddd		zmm11, zmm11, zmm12
	valignd		zmm12, zmm11, zmm0, 15		; shift left 1 dword
	vpaddd		zmm11, zmm11, zmm12

	valignd		zmm11, zmm11, zmm11, 15 	; rotate left one dword
	movd		r13d, xmm11					; extract the grand total...
	vpord		zmm11{k6z}, zmm11, zmm11	; k6=0xfffe ...then erase it
											; indexes relative to start of letters groups
	vpbroadcastd	zmm12, edx
	vpaddd		zmm6, zmm11, zmm12			; g0i:: base for the rest
	add			edx, r13d					; where the end of this set of subgroups will be

; order is imprtant: see also comment in sortPop2-Lpop.nasm
; we are using in-memory order: w3w2w0w1
; so the overlapping search groups are: m0m01m0123m02
; we are also using end indexes and negative lengths to save a few ops in the search loop
; m0: idx=w3+w2+w0+w1, l=w3+w2+w0+w1
; m1: idx=w3+w2+w0, l=w2+w0
; m2: idx=w3+w2+w0+w1, l=w0+w1
; m3: idx=w3+w2+w0, l=w0
; w0-3 are the counts from above: w0=zmm2, w1=zmm3, w2=zmm4, w3=zmm5.
; these have been totalled into zmm10, and an accumulate-left done into zmm6 to provide the
; base index for each subgroup

	vpaddd		zmm7, zmm6, zmm10		; end idx for m0,m2 = base + all4
	vpaddd		zmm8, zmm8, zmm6		; end idx for m1,m3 = base + w0w2w3
	vpsubd		zmm2, zmm0, zmm2		; l3 = -w0
	vpsubd		zmm3, zmm2, zmm3		; l2 = -w0-w1
	vpsubd		zmm4, zmm2, zmm4		; l1 = -w0-w2
	vpsubd		zmm5, zmm0, zmm10		; l0 = -all

	; 64 groups, 32dw(128b) apart. best to scatter with fixed index, increment the base

	lea			rax, [rsi + rbx * 4]			; group m0
	kmovw		k1, k6							; scatter needs a mask, leaving out g0 which is already written
	vmovdqa32	zmm0, zmm28
	vpermi2w	zmm0, zmm5, zmm7			; even/odd blending of low words from 2 tables
	vpscatterdd	[rax + zmm14 * 4]{k1}, zmm0	; z14=0,128,256,384,512...(dw)(l2r)
	add			rax, 32							; group m1
	kmovw		k1, k6							; scatter needs a mask, leaving out g0 which is already written
	vmovdqa32	zmm0, zmm28
	vpermi2w	zmm0, zmm4, zmm8			; even/odd blending of low words from 2 tables
	vpscatterdd	[rax + zmm14 * 4]{k1}, zmm0	; z14=0,128,256,384,512...(dw)(l2r)
	add			rax, 32							; group m2
	kmovw		k1, k6							; scatter needs a mask, leaving out g0 which is already written
	vmovdqa32	zmm0, zmm28
	vpermi2w	zmm0, zmm3, zmm7			; even/odd blending of low words from 2 tables
	vpscatterdd	[rax + zmm14 * 4]{k1}, zmm3	; z14=0,128,256,384,512...(dw)(l2r)
	add			rax, 32							; group m3
	kmovw		k1, k6							; scatter needs a mask, leaving out g0 which is already written
	vmovdqa32	zmm0, zmm28
	vpermi2w	zmm0, zmm2, zmm8			; even/odd blending of low words from 2 tables
	vpscatterdd	[rax + zmm14 * 4]{k1}, zmm2	; z14=0,128,256,384,512...(dw)(l2r)

;************************************************************************************

	; get main group index in again
	; re-reading is bad - has to wait for scatters to complete and probably triggers the watchdog.
	; we can use negative indexing throughout
	; and extract the group ends from the m0l0 tables we already have in zmm5/zmm7
	; we are writing groups 1,2,4,8 on this first cycle
	; then 3,5,9
	; then 6,10; 7,11; 12; 13; 14; 15;
	; so permute with 1,2,4,8,3,5,9,6,10,7,11,12,13,14,15,0 then use alignd to bring each 4 into view of extract
	; but we need start indexes not ends so...

;	vpermd		zmm5, zmm13, zmm5
	mov			rcx, r9				; kept from before - whole group neg.length
	vpaddd		zmm6, zmm7, zmm5	; start-indexes of exp.groups. lengths are negative, so add them
	vpermd		zmm6, zmm13, zmm6	; only permuting start-indexes since read order for source groups is 1,2,3,4,5,6,7
	movd		r9d, xmm6
	vpextrd		r10d, xmm6, 1
	vpextrd		r11d, xmm6, 2
	vpextrd		r12d, xmm6, 3
									; four write indexes in r9,r10,r11,r12 (rdi base)
.subgroupcopyloop1:					; first filter by one letter each to 4 groups
	vmovdqu32		zmm0, [r8 + rcx * 4]
	add			rcx, 16
	jns			.vsgclout1			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm15		; z10 has 0x100s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r9d, eax
	vptestnmd	k1, zmm0, zmm16		; z11 has 0x200s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm17		; z10 has 0x400s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	vptestnmd	k1, zmm0, zmm18		; z10 has 0x800s(dw)
	vpcompressd	[rdi + r12 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r12d, eax
	jmp			.subgroupcopyloop1	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout1:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm15		; z10 has 0x100s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm16		; z11 has 0x200s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm17		; z10 has 0x400s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18		; z10 has 0x800s(dw)
	vpcompressd	[rdi + r12 * 4]{k1}, zmm0

; repeat adding one bit each time like for scalar expander

	vpextrd		r9d, xmm7, 1		; end of g1
	lea			r9, [rdi + r9 * 4]	; to pointer
	vpextrd		ecx, xmm5, 1		; negl of g1
	movsx		rcx, ecx
	valignd		zmm1, zmm6, zmm6, 4 ; 4dw right rotation of startindexes
	movd		r10d, xmm1			; g3 si
	vpextrd		r11d, xmm1, 1		; g5 si
	vpextrd		r12d, xmm1, 2		; g5 si

.subgroupcopyloop2:		; filter out each of other 3 bits from group 1 (3,5,9)
	vmovdqu32		zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout2			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm16		; z11 has 0x200s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm17		; z12 has 0x400s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	vptestnmd	k1, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r12 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r12d, eax
	jmp			.subgroupcopyloop1	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout2:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm16		; z10 has 0x100s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm17		; z11 has 0x200s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18		; z12 has 0x400s(dw)
	vpcompressd	[rdi + r12 * 4]{k1}, zmm0

;*****
	vpextrd		r9d, xmm7, 2		; end of g2
	lea			r9, [rdi + r9 * 4]	; to pointer
	vpextrd		ecx, xmm5, 2		; negl of g2
	movsx		rcx, ecx
	valignd		zmm1, zmm6, zmm6, 7 ; 7dw right rotation of startindexes
	movd		r10d, xmm1			; g6 si
	vpextrd		r11d, xmm1, 1		; g10 si

.subgroupcopyloop3:		; filter out each of other 2 bits from group 2 (6,10)
	vmovdqu32		zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout3			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm17		; z11 has 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm18		; z12 has 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			.subgroupcopyloop3	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout3:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm17		; z12 has 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

	vpextrd		r9d, xmm7, 3		; end of g3
	lea			r9, [rdi + r9 * 4]	; to pointer
	vpextrd		ecx, xmm5, 3		; negl of g3
	movsx		rcx, ecx			; to 64 bit
;	valignd		zmm1, zmm6, zmm6, 7 ; 7dw right rotation of startindexes
	vpextrd		r10d, xmm1, 2		; g6 si
	vpextrd		r11d, xmm1, 3		; g10 si

.subgroupcopyloop4:		; filter out each of other 2 bits from group 3 (7,11)
	vmovdqu32		zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout4			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm17		; z11 has 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	vptestnmd	k1, zmm0, zmm18		; z12 has 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
	jmp			.subgroupcopyloop4	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout4:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm17		; z12 has 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0

;****

	valignd		zmm5, zmm5, zmm5, 4
	valignd		zmm7, zmm7, zmm7, 4
	valignd		zmm1, zmm6, zmm6, 11	; rotations for the last 4 groups
	movd		r9d, xmm7
	lea			r9, [rdi + r9 * 4]	; to pointer
	movd		ecx, xmm5
	movsx		rcx, ecx			; to 64 bit
	movd		r10d, xmm6

.subgroupcopyloop5:		; filter out the other 1 bit from group 4 (12)
	vmovdqu32	zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout5			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	jmp			.subgroupcopyloop5	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout5:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0

	vpextrd		r9d, xmm7, 1
	lea			r9, [rdi + r9 * 4]	; to pointer
	vpextrd		ecx, xmm5, 1
	movsx		rcx, ecx			; to 64 bit
	vpextrd		r10d, xmm6, 1

.subgroupcopyloop6:		; filter out the other 1 bit from group 5 (13)
	vmovdqu32		zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout6			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	jmp			.subgroupcopyloop6	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout6:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0

	vpextrd		r9d, xmm7, 2
	lea			r9, [rdi + r9 * 4]	; to pointer
	vpextrd		ecx, xmm5, 2
	movsx		rcx, ecx			; to 64 bit
	vpextrd		r10d, xmm6, 2

.subgroupcopyloop7:		; filter out the other 1 bit from group 6 (14)
	vmovdqu32		zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout7			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	jmp			.subgroupcopyloop7	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout7:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0

	vpextrd		r9d, xmm7, 3
	lea			r9, [rdi + r9 * 4]	; to pointer
	vpextrd		ecx, xmm5, 3
	movsx		rcx, ecx			; to 64 bit
	vpextrd		r10d, xmm6, 3

.subgroupcopyloop8:		; filter out the other 1 bit from group 7 (15)
	vmovdqu32		zmm0, [r9 + rcx * 4]
	add			ecx, 16
	jns			.vsgclout8			; leave to do masked final round
	vptestnmd	k1, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r10d, eax
	jmp			.subgroupcopyloop8	; 12p5 4p0 4p1 4p0156 2p06 12c/l, 375l in
.vsgclout8:
	mov		eax, 0xffff
	shrx	eax, eax, ecx
	kmovw	k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18		; z13 has 0x800s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0

; if each bit average removes 50% of prior list, loop1 goes 375x	12c/l
;												 loop2,6,8, go 188x	9c,6c,3c/l 18c/l total
;												 loop3,5,7 go 94x	6c,3c,3c/l 12c/l
;												 loop4	goes 47x	3c/l	   3c/l
;																total= 2.08µs

;												total size of codes 30375 dwords
;	cmp		ebx, 22			; going till letter 21 - or check for zero length?
;	jnz		letterloop
	jmp		.letterloop


