; another way to do subgroup expansions:
; 1: count lettergroups and store totals in temp form
; 2: rearrange to make the per-group tables that will get created by the single-pass expansions
; 3: do each expansion group on whole codeset, ie 15 groups get created each has all letters with the pop2 ordering intact
; why? theres a lot of things that will cause latency-delays if they are done serially but can paralellize if they're done in separate loops
; or can be done more elegantly than in a single loop

; 0.32+0.66+2.61=3.59µs expected, 6.6µs measured (presumably data-size related, l2-able but too big for l1?)

global expandSubgroups

section .data align=64
;	vmovdqa32	zmm31, [merge2tdw]				; zmm31=0,2,4,6,8,10,12,...,56,58,60,62(w)(l2r)
;	vmovdqa32	zmm30, [gatherpattern]			; zmm30=0,0x100,0x200,0x300...(dw)(l2r)
;	vmovdqa32	zmm29, [mergel2twd]				; zmm29=31,63,0,32,1,33,2,34,3,35...(w)(l2r) rotated by one dw so the first dw column end up empty (skipped letter0)
;	vmovdqa32	zmm28, [mergeh2twd]				; zmm28=15,47,16,48,17,49,18,50,19,51...(w)(l2r)
merge2tdw:		dw		0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30
				dw		32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,62
gatherpattern:	dd		0,0x100,0x200,0x300,0x400,0x500,0x600,0x700,
				dd		0x800,0x900,0xa00,0xb00,0xc00,0xd00,0xe00,0xf00
mergel2twd		dw		31,63,0,32,1,33,2,34,3,35,4,36,5,37,6,38
				dw		7,39,8,40,9,41,10,42,11,43,12,44,13,45,14,46
mergeh2twd		dw		15,47,16,48,17,49,18,50,19,51,20,52,21,53,22,54
				dw		23,55,24,56,25,57,26,58,27,59,28,60,29,61,30,62
merge2trearrange:
				db		1,0,5,4,9,8,13,12,17,16,21,20,25,24,29,28
				db		33,32,37,36,41,40,45,44,49,48,53,52,57,56,61,60
				db		65,64,69,68,73,72,77,76,81,80,85,84,89,88,93,92
				db		97,96,101,100,105,104,109,108,113,112,117,116,121,120,125,124
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
one				dd		1

section .text align=16
; rdi = codes		rsi = index		 edx = nwords
expandSubgroups:
	push			r12
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
	vmovd		r9d, xmm2							; 			(↑ these numbers are the group end-index numbers. we use them as start-indexes for the next group)
	vpextrd		r10d, xmm2, 1
	vpextrd		r11d, xmm2, 2
	lea			r12, [rdi + rdx * 4]				; working endpointer for read
	movzx		ecx, word [rsi + 2]					; using end index of first g0 lettergroup as our increment to skip letter 0, the least popular...
	sub			rcx, rdx							; in this case nwords is still useful to generate our neglen loopcounter starting at letter 1.
													; the group count totals didn't include letter0 so everything is handled from here on
	call 		exp4.in

; ***********************

	valignd		zmm2, zmm2, zmm2, 3					; right rotate 3 dwords to og-2,4,8
	vmovd		r9d, xmm2
	vpextrd		r10d, xmm2, 1
	vpextrd		r11d, xmm2, 2
	vpextrd		ecx, xmm9, 1						; group1 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 1						; group1 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp3.in

; ***********************************************

	valignd		zmm2, zmm2, zmm2, 3					; right rotate 3 dwords to og-5,9,6,10
	vmovd		r10d, xmm2
	vpextrd		r11d, xmm2, 1
	vpextrd		ecx, xmm9, 2						; group2 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 2						; group2 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp2.in

; ***********************************************

	vpextrd		r10d, xmm2, 2
	vpextrd		r11d, xmm2, 3
	vpextrd		ecx, xmm9, 3						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 3						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp2.in

; ***********************************************

	valignd		zmm2, zmm2, zmm2, 4					; og-11,12,13,14
	valignd		zmm1, zmm1, zmm1, 4
	valignd		zmm9, zmm9, zmm9, 4					; rotate for last 4

	vmovd		r11d, xmm2
	vmovd		ecx, xmm9							; group3 length
	neg			rcx									; to neglen
	vmovd		r12d, xmm1							; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp1.in

; ************************************************

	vpextrd		r11d, xmm2, 1
	vpextrd		ecx, xmm9, 1						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 1						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp1.in

; ************************************************

	vpextrd		r11d, xmm2, 2
	vpextrd		ecx, xmm9, 2						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 2						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp1.in

; ************************************************

	vpextrd		r11d, xmm2, 3
	vpextrd		ecx, xmm9, 3						; group3 length
	neg			rcx									; to neglen
	vpextrd		r12d, xmm1, 3						; group3 end index
	lea			r12, [rdi + r12 * 4]				; to endpointer

	call 		exp1.in


; each expansion removes 33% of the codes. limiting factor is compress throughput of 3c.
;	expansion 1: 1,2,4,8, whole set processed = 375 loops @ 12c
;	expansion 2: 3,5,6,9,10,12 on .66 set = 250loops @18c
;	expansion 3: 7,11,13,14  on .44 set = 180loops @12c
;	expansion 4: 15 on .30 set = 108 loops @3c
;	total: 11484c, 2.61µs

; **************************************************

; now to populate the main searchgroup tables with index/neglen pairs for the expansion groups...

; total size of expansions: 5900*.66 = 3894	* 4 = 15576+
;							3894*.66 = 2570 * 6 = 15420+
;							2570*.66 = 1696 * 4 =  6784+
;							1696*.66 = 1119 * 1 =  1119=38899+6000=44899*4=180KB

; alt index generation
; each row of 32 dwords has the indexes for 32 letters of one group.subgroup. the subgroup legths are interdependent so reading all subgroup lengths for one group and processing together seems reasonable.
; the gather operation will want to load 16 at a time, from up to 22 letters that would be 16+6,
; we can use a half-length load with mask generated by the count abandon point.
; so 4x24-el reads at 64-byte offsets and 256-byte stride could get all data for one group into 4 reg pairs.
; merge down to 4 reg.s of words, accumlulate w0123 left to get offsets within the group for each letter end. =e0,e2.
; subtract w1, =e1,e3 etc. merge el pairs and write out same as for end of sort stage.
; stored counts geometry:
; B:g0w0,g1w0,g2w0,g3w0,g4w0,g5w0,g6w0,g7w0,g8w0,g9w0,g10w0,g11w0,g12w0,g13w0,g14w0,g15w0
; B:g0w1,g1w1,g2w1,g3w1,g4w1,g5w1,g6w1,g7w1,g8w1,g9w1,g10w1,g11w1,g12w1,g13w1,g14w1,g15w1
; B:g0w02,g1w02,g2w02,g3w02,g4w02,g5w02,g6w02,g7w02,g8w02,g9w02,g10w02,g11w02,g12w02,g13w02,g14w02,g15w02
; B:g0w0123,g1w0123,g2w0123,g3w0123,g4w0123,g5w0123,g6w0123,g7w0123,g8w0123,g9w0123,g10w0123,g11w0123,g12w0123,g13w0123,g14w0123,g15w0123
; C:g0w0,g1w0,g2w0,g3w0,g4w0,g5w0,g6w0,g7w0,g8w0,g9w0,g10w0,g11w0,g12w0,g13w0,g14w0,g15w0
; C:g0w1,g1w1,g2w1,g3w1,g4w1,g5w1,g6w1,g7w1,g8w1,g9w1,g10w1,g11w1,g12w1,g13w1,g14w1,g15w1
; C:g0w02,g1w02,g2w02,g3w02,g4w02,g5w02,g6w02,g7w02,g8w02,g9w02,g10w02,g11w02,g12w02,g13w02,g14w02,g15w02
; C:g0w0123,g1w0123,g2w0123,g3w0123,g4w0123,g5w0123,g6w0123,g7w0123,g8w0123,g9w0123,g10w0123,g11w0123,g12w0123,g13w0123,g14w0123,g15w0123
; D:g0w0,g1w0,g2w0,g3w0,g4w0,g5w0,g6w0,g7w0,g8w0,g9w0,g10w0,g11w0,g12w0,g13w0,g14w0,g15w0
; D:g0w1,g1w1,g2w1,g3w1,g4w1,g5w1,g6w1,g7w1,g8w1,g9w1,g10w1,g11w1,g12w1,g13w1,g14w1,g15w1
; D:g0w02,g1w02,g2w02,g3w02,g4w02,g5w02,g6w02,g7w02,g8w02,g9w02,g10w02,g11w02,g12w02,g13w02,g14w02,g15w02
; D:g0w0123,g1w0123,g2w0123,g3w0123,g4w0123,g5w0123,g6w0123,g7w0123,g8w0123,g9w0123,g10w0123,g11w0123,g12w0123,g13w0123,g14w0123,g15w0123

	vmovdqa32	zmm31, [merge2tdw]				; zmm31=0,2,4,6,8,10,12,...,56,58,60,62(w)(l2r)
	vmovdqa32	zmm30, [gatherpattern]			; zmm30=0,0x100,0x200,0x300...(dw)(l2r)
	vmovdqa32	zmm29, [mergel2twd]				; zmm29=31,63,0,32,1,33,2,34,3,35...(w)(l2r) rotated by one so the first dw column end up empty (skipped letter0)
	vmovdqa32	zmm28, [mergeh2twd]				; zmm28=15,47,16,48,17,49,18,50,19,51...(w)(l2r)
	mov			ecx, [r8 - 4]					; last known accruing of count data
	shr			ecx, 6							; back to count
	mov			eax, -1
	bzhi		eax, eax, ecx					; to 32-bit mask
	kmovw		k2, eax							; first 16 bits to a mask for gather
	shr			eax, 16
	kmovw		k3, eax							; second 16 bits to a mask for gather

	vpxord		zmm0, zmm0, zmm0				; a zero for subtractive negations and alignd shifts
	valignd		zmm1, zmm1, zmm1, 12		; restore group end-indexes to original columns but left 1 for use as group start-indexes
	mov			ecx, 15
	kmovd		k7, [one]


indexloop:
	add			r8, 4							; skip g0
	add			rsi, 512						; index write point increment, skips overwriting g0

	lea			r10, [r8+192]					; w0123's first so that accum-left can happen during gathers
	lea			r9, [r10 + 0x1000]				; second half pointer
	kmovw		k1, k2
	vpxord		zmm5, zmm5, zmm5
	vpgatherdd	zmm5{k1}, [r10 + zmm30]			; all w0123's for group
	vmovdqu32		[rsp-72], zmm5
	kmovw		k1, k3
	vpxord		zmm6, zmm6, zmm6
	vpgatherdd	ymm6{k1}, [r9 + ymm30]			; in 2 registers
	vmovdqu32		[rsp-72], zmm6
	vpermt2w	zmm5, zmm31, zmm6				; now in one
	vmovdqu32		[rsp-72], zmm5

	lea			r9, [r8 + 0x1000]				; second half pointer
	kmovw		k1, k2
	vpxord		zmm2, zmm2, zmm2
	vpgatherdd	zmm2{k1}, [r8 + zmm30]			; all w0's for group
	kmovw		k1, k3
	vpxord		zmm3, zmm3, zmm3
	vpgatherdd	ymm3{k1}, [r9 + ymm30]			; in 2 registers
	vpermt2w	zmm2, zmm31, zmm3				; now in one

	lea			r10, [r8+64]					; w1's
	lea			r9, [r10 + 0x1000]				; second half pointer
	kmovw		k1, k2
	vpxord		zmm3, zmm3, zmm3
	vpgatherdd	zmm3{k1}, [r10 + zmm30]		; all w1's for group
	kmovw		k1, k3
	vpxord		zmm4, zmm4, zmm4
	vpgatherdd	ymm4{k1}, [r9 + ymm30]			; in 2 registers
	vpermt2w	zmm3, zmm31, zmm4				; now in one
	vmovdqu32		[rsp-72], zmm3

	lea			r10, [r8+128]					; w02's
	lea			r9, [r10 + 0x1000]				; second half pointer
	kmovw		k1, k2
	vpxord		zmm4, zmm4, zmm4
	vpgatherdd	zmm4{k1}, [r10 + zmm30]		; all w02's for group
	kmovw		k1, k3
	vpxord		zmm7, zmm7, zmm7
	vpgatherdd	ymm7{k1}, [r9 + ymm30]			; in 2 registers
	vpermt2w	zmm4, zmm31, zmm7				; now in one

	; add the group index to letter1's length, makes the result actual end indexes
	vmovdqa32	zmm6, zmm5
	vpaddw		zmm6{k7}, zmm5, zmm1			; k7 = 1, first column only
	vmovdqu32		[rsp-72], zmm1
	valignd		zmm1, zmm1, zmm1, 1				; rotate group start indexes for next time
	vmovdqu32		[rsp-72], zmm6

	; word accum-left on the w0123s
	valignd		zmm7, zmm6, zmm0, 8
	vmovdqu32		[rsp-72], zmm7
	vpaddw		zmm6, zmm6, zmm7
	vmovdqu32		[rsp-72], zmm6
	valignd		zmm7, zmm6, zmm0, 12
	vmovdqu32		[rsp-72], zmm7
	vpaddw		zmm6, zmm6, zmm7
	vmovdqu32		[rsp-72], zmm6
	valignd		zmm7, zmm6, zmm0, 14
	vmovdqu32		[rsp-72], zmm7
	vpaddw		zmm6, zmm6, zmm7
	vmovdqu32		[rsp-72], zmm6
	valignd		zmm7, zmm6, zmm0, 15
	vmovdqu32		[rsp-72], zmm7
	vpaddw		zmm6, zmm6, zmm7
	vmovdqu32		[rsp-72], zmm6
	valignd		zmm7, zmm6, zmm0, 12
	vmovdqu32		[rsp-72], zmm7
	vpalignr	zmm7, zmm6, zmm7, 14
	vmovdqu32		[rsp-72], zmm7
	vpaddw		zmm6, zmm6, zmm7				; because letter 1 length is in column 0, these are automatically end-indexes, e0,e2
	vmovdqu32		[rsp-72], zmm6

	vpsubw		zmm7, zmm6, zmm3				; subtract w1 for e1,e3
	vmovdqu32		[rsp-72], zmm7

	vpsubw		zmm2, zmm0, zmm2				; -w0=l3
	vpsubw		zmm3, zmm2, zmm3				; -w01=l2
	vpsubw		zmm4, zmm0, zmm4				; -w02=l1
	vpsubw		zmm5, zmm0, zmm5				; -w0123=l0

	vmovdqa32	zmm8, zmm29
	vpermi2w	zmm8, zmm5, zmm6
	vmovdqa32	[rsi], zmm8
	vpermt2w	zmm5, zmm28, zmm6
	vmovdqa32	[rsi + 64], zmm5				; e0l0

	vmovdqa32	zmm8, zmm29
	vpermi2w	zmm8, zmm4, zmm7
	vmovdqa32	[rsi + 128], zmm8
	vpermt2w	zmm4, zmm28, zmm7
	vmovdqa32	[rsi + 192], zmm4				; e1l1

	vmovdqa32	zmm8, zmm29
	vpermi2w	zmm8, zmm3, zmm6
	vmovdqa32	[rsi + 256], zmm8
	vpermt2w	zmm3, zmm28, zmm6
	vmovdqa32	[rsi + 320], zmm3				; e2l2

	vmovdqa32	zmm8, zmm29
	vpermi2w	zmm8, zmm2, zmm7
	vmovdqa32	[rsi + 384], zmm8
	vpermt2w	zmm2, zmm28, zmm7
	vmovdqa32	[rsi + 448], zmm2				; e3l3

	sub			ecx, 1
	jnz			indexloop						; loop has 96 read ops and 8 writes, goes 15 times. 48cx15=0.163µs
												; theres also 19p5, 35p05 ops, but that's not enough to slow down the gathers at all.

	pop			r12
	ret

	; ***********************************************************
	; separated expand loop subroutines
	; setup as before, no change. call expN.in
	; all expect bit masks in zmm16-19
	; all rely on starting write indexes supplied in first N of r11,r10,r9,rdx
	; rdi+r11*4 will be written with all codes that do NOT contain mask in zmm19. r10:zmm18, r9:zmm17, rdx:zmm16 simmilarly.
	; rdi has codespace base pointer, r12 has endpointer of read, rcx is neglen of source, rax used internally

exp4:
.loop:
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
.in:
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	js			.loop
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
	ret

exp3:
.loop:
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
.in:
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	js			.loop
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm17					; zmm17 = 0x200s(dw)
	vpcompressd	[rdi + r9 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm18					; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	ret

exp2:
.loop:
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
.in:
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	js			.loop
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm18					; zmm18 = 0x400s(dw)
	vpcompressd	[rdi + r10 * 4]{k1}, zmm0
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	ret

exp1:
.loop:
	vptestnmd	k1, zmm0, zmm19						; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	kmovw		eax, k1
	popcnt		eax, eax
	add			r11d, eax
.in:
	vmovdqu32	zmm0, [r12 + rcx * 4]
	add			rcx, 16
	js			.loop
	mov			eax, 0xffff
	shrx		eax, eax, ecx
	kmovw		k2, eax
	vptestnmd	k1{k2}, zmm0, zmm19					; zmm19 = 0x800s(dw)
	vpcompressd	[rdi + r11 * 4]{k1}, zmm0
	ret

