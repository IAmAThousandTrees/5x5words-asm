;; ***************** the Search 345µs expected for search space of 223000. actual search space is 54000, and actual time is 147.4µs
;; (this is both slower and quicker than expected, quicker because search-space is much smaller,
;; 		slower because in proportion to the expected search-space is equivalent to 665µs, or expected should be 83.5µs.
;;		this is in line with other results where random-access to a dataset > l1 size is about 2x slower)
;; (the difference in search-space size is due to my having taken a trace of an old scalar version of the algorithm at some point,
;;		which was fundamentally broken in some way {the reason for the trace} but then some time later I used the trace to tell me
;;		what the expected numbers of iterations and proportions/distribution of different lengths of search, without considering
;;		that the trace was of a broken version that had given garbage results)

global search

section .data align=64

pileindex:
		dd	218940,68940,18940,8940,4940,2940,1940,1440
		dd	1240,1140,1090,1050,1030,1010,1000,0	; top of pile0 258940
		dq	0,0,0,0,0,0,0,0
pileindexcopy:
		dd	218940,68940,18940,8940,4940,2940,1940,1440
		dd	1240,1140,1090,1050,1030,1010,1000,0	; top of pile0 258940
;64-byte loads
;z16:	dd	4,5,6,7,0,1,2,3, 12,13,14,15,8,9,10,11
;z18:	dd  16,24,17,25,18,26,19,27, 20,28,21,29,22,30,23,31
z19:	;dd	0,8,1,9,2,10,3,11, 4,12,5,13,6,14,7,15
		dd	0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
z24:	db	0,32,2,34,4,36,6,38,8,40,10,42,12,44,14,46
		db	16,48,18,50,20,52,22,54,24,56,26,58,28,60,30,62
		db	1,33,3,35,5,37,7,39,9,41,11,43,13,45,15,47,
		db	17,49,19,51,21,53,23,55,25,57,27,59,29,61,31,63
z25:	dq	4,4,-4,-4,4,4,-4,-4
z26:	dq	2,-2,2,-2,2,-2,2,-2
z28:	dq	0xf0f0f0f0f0f0f0f0,0xf0f0f0f0f0f0f0f0,0x0f0f0f0f0f0f0f0f,0x0f0f0f0f0f0f0f0f
		dq	0xf0f0f0f0f0f0f0f0,0xf0f0f0f0f0f0f0f0,0x0f0f0f0f0f0f0f0f,0x0f0f0f0f0f0f0f0f
z31:	dd	1,3,7,0xf,0x1f,0x3f,0x7f,0xff
		dd	0x1ff,0x3ff,0x7ff,0xfff,0x1fff,0x3fff,0x7fff, 0xffff
z15:	dd  0x1ffff,0x3ffff,0x7ffff,0xfffff,0x1fffff,0x3fffff,0x7fffff,0xffffff
		dd	0x1ffffff,0x3ffffff,0x7ffffff,0xfffffff,0x1fffffff,0x3fffffff,0x7fffffff,0xffffffff
		;; rightward relevence masks include the self bit in order to pre-increment as the
		;; scalar code does

;16-byte broadcasts
z17:	dq  0x0504070601000302,0x0d0c0f0e09080b0a
z29:	dq	0xcccccccccccccccc,0x3333333333333333

;qword broadcasts
z27:	dq	0x19110901372f271f
z30:	dq	0x55555555aaaaaaaa
xaaaaa:	dq	0xaaaaaaaaaaaaaaaa
xccccc:	dq	0xcccccccccccccccc
xfffff:	dq	0xffffffffffffffff

;dword broadcasts
z11:	dd	1
z13:	dd	0x80000000
z14:	dd	32
z18:	dd	16
z20:	dd	0xfc0
z21:	dd	0xffe00000
maskffff:	dd	0x0000ffff
xfffe	dd	0xfffe

;word broadcasts (keep 2 for broadcastd)
z12:	dw	14,14
z22:	dw	15,15
z23:	dw	1,1



section .text
;; rdi = ptr to sorted codes, rsi = ptr to index-length array,
;; rdx = ptr to mask space, rcx = pointer to index history space (HUGE malloc ... 4Gb?)
;; search array entry: 63:32=parent index 31:6=mask 5=skipped 2:0 = layer?

;; splitting history means 63:32 and 31:0 are now separate dword arrays

			; TODO: ensure all writepointers are now indexes
align 16
search:
	push	rbp
	push	rbx
	push	r12
	push	r13
	push	r14
	push	r15

	mov 	rbp, rcx				; history ptr now in rbp

	mov		word [rsi+(32*63+27)*4], 16	; puts winners in pile -1 (15 beyond the saturation of 14)

	movsx	rcx, word [rsi]			; negative length of first set (position is assumed 0)
	movzx	r8d, word [rsi + 2]		; working write index, but it is also positive length of first group
	lea		r9, [rdi + r8 * 4]		; read endpoint
	lea		r10, [rdx + r8 * 4]		; masks write endpoint
	lea		r11, [rbp + r8 * 4]		; history write endpoint
	vpxord	zmm0, zmm0, zmm0		; to erase the history

.initl1:
	vmovdqu32	zmm1, [r9 + rcx * 4]
	vmovdqu32	[r10 + rcx * 4], zmm1
	vmovdqu32	[r11 + rcx * 4], zmm0
	add		rcx, 16
	js		.initl1
	; we don't have to care about the junk at the end, r8d has right number
	; 2c/l, 600/16l, 17ns

;;; now we begin to search, using rdx + r9 * 8 as readpointer
	kmovq	k7, [xaaaaa]
	knotq	k6, k7						; 0x5555555555555555
	kmovq	k5, [xccccc]
	kmovq	k0, [xfffff]
	lea		r10, [pileindex]			; needed for PIE
	vmovdqa32	zmm10, [pileindexcopy]
	vmovdqa32	[r10], zmm10			; reset piles between speedtest runs

	lea					r15, [rsp - (258940 * 8)]	; space for piles
	vmovdqa32			ymm10, [r10 + 32]		; load initial pile indexes
	kmovw				k1, k0
	vpscatterdq			[r15 + ymm10 * 8]{k1}, zmm0	; write zeros to pile bottoms
	vmovdqa32			zmm10, [r10]			; load initial pile indexes
	kmovw				k1, k0
	vpscatterdq			[r15 + ymm10 * 8]{k1}, zmm0	; write zeros to pile bottoms
											; loading register constants
	vpbroadcastd		zmm11, [z11]		; 1s(dw)
	vpbroadcastd		zmm12, [z22]		; 15s(w)
	vpbroadcastd		zmm13, [z13]		; 0x80000000s(dw)
	vpbroadcastd		zmm14, [z14]		; 32s(dw)
	vmovdqa32			zmm15, [z15]
	vbroadcasti32x4		zmm17, [z17]
	vpbroadcastd		zmm18, [z18]		; dw 16s
	vmovdqa32			zmm19, [z19]		; dw ID
	vpbroadcastd		zmm20, [z20]
	vpbroadcastd		zmm21, [z21]
	vpbroadcastd		zmm22, [z22]
	vpbroadcastd		zmm23, [z23]
	vmovdqa32			zmm24, [z24]
	vmovdqa32			zmm25, [z25]
	vmovdqa32			zmm26, [z26]
	vpbroadcastq		zmm27, [z27]
	vmovdqa32			zmm28, [z28]
	vbroadcasti32x4		zmm29, [z29]
	vpbroadcastq		zmm30, [z30]
	vmovdqa32			zmm31, [z31]

	xor		r9d, r9d					; working read index
	call 	.sortwork		;5bits
	call 	.processpiles	;>10bits
	call 	.sortwork		;10bits
	call 	.processpiles	;>15bits
	call 	.sortwork		;15bits
	call 	.processpiles	;>20bits
	call 	.sortwork		;20bits
	call 	.processpiles	;>25bits (all noskip winners found)

	movsx	rcx, word [rsi + 4]		; negative length of first set (position is assumed 0)
	movzx	r9, word [rsi + 6]		; end index
	lea		r9, [rdi + r9 * 4]		; read endpointer
	sub		r8d, ecx				; maintain write index
	lea		rax, [rdx + r8 * 4]		; masks write endpoint
	lea		rbx, [rbp + r8 * 4]		; history write endpoint
	vpxord	zmm0, zmm0, zmm0		; to erase the history

.initl2:
	vmovdqu32	zmm1, [r9 + rcx * 4]
	vmovdqu32	[rax + rcx * 4], zmm1
	vmovdqu32	[rbx + rcx * 4], zmm0
	add		rcx, 16
	js		.initl2
	; we don't have to care about the junk at the end, r8d has right number
	; 2c/l, 600/16l, 17ns

	xor		r9d, r9d				; start again reading from zero
	vpbroadcastd	zmm12, [z12]	; 14s(w) for saturate. pile 15 for winners from now on

	call 	.sortworkaddskip	;>6-26bits		we only need to add skips once since we
											;only add skips to unskipped searches and all
											;unskipped searches are already in the history
	call 	.processpiles	;>11-26bits
	call 	.sortwork		;11-26bits
	call 	.processpiles	;>16-26bits
	call 	.sortwork		;16-26bits
	call 	.processpiles	;>21-26bits
	call 	.sortwork		;21-26bits
	call 	.processpiles	;>26bits (all skip winners found)
	call 	.sortwork		;26bits - to get the last skip winners all in pile15


	;**************************** search is done ************************

	;; all winners end up in pile 15, we can just copy them to the top of the working space
	mov		r13d, [r10 + 60]			; starting from the top of pile 15
	mov		dword [rdx + r8 * 4], 0		; terminate the main masks pile with a null
	mov		dword [rbp + r8 * 4], 0		; terminate the main history pile with a null
.winnerloop:
	mov		eax, [r15 + r13 * 8]		; transferring the winner "masks" is a waste of time, they're all the same and never read
	mov		ebx, [r15 + r13 * 8 + 4]	; what's interesting is not the result but how we got there...
	test	eax, eax
	jz		.donewinners
	inc		r8d
	dec		r13d
	mov		[rdx + r8 * 4], eax
	mov		[rbp + r8 * 4], ebx
	jmp		.winnerloop
.donewinners:
	mov 	eax, r8d					; return value is end of winners list


	pop		r15
	pop		r14
	pop		r13
	pop		r12
	pop		rbx
	pop		rbp
	ret		;; returns index to top of solutions found
			;; (written to end of working space with a zero separating them from the rest)
			;; caller uses the indexes to trace back the solution and uses xor/andn to recover the codes
.sortworkaddskip:
	mov			r13d, 76543				; magic number
.sortwork:
	vmovdqa32	zmm10, [r10]			; (re)load pile indexes
	kmovw		k4, [xfffe]				; re-load mask for non-update of zero pile
.vsearchreadloop:
	vmovdqu32	zmm0, [rdx + r9 * 4]	; get 16 work items for sorting to piles (0-15)
	vmovdqu32 	zmm4, [rdx + r9 * 4 + 64] ; get 16 more (16-31)

	vpternlogd 	zmm3, zmm0, zmm0, 0x55	; a=!c
	vplzcntd 	zmm3, zmm3				; count leading 1s to find next search letter
	vpternlogd 	zmm7, zmm4, zmm4, 0x55	; a=!c
	vplzcntd 	zmm7, zmm7				; count leading 1s to find next search letter

	cmp			r13d, 76543				; r13d only becomes this number if set exactly
	jnz			.noaddskip				; to prevent bypass of the skip adding

	vpsrlvd		zmm3, zmm13, zmm3		; z13 is top bit only (0x80000000s (dw))
	vpternlogd	zmm2, zmm3, zmm14, 0xfe	; orABC z14 is just the skip bit (32s(dw))
	vpternlogd 	zmm3, zmm2, zmm2, 0x55	; a=!c
	vplzcntd 	zmm3, zmm3				; count leading 1s to find next search letter
	vpsrlvd		zmm7, zmm13, zmm7		; z13 is top bit only (0x80000000s (dw))
	vpternlogd	zmm4, zmm7, zmm14, 0xfe	; orABC z14 is just the skip bit (32s(dw))
	vpternlogd 	zmm7, zmm4, zmm4, 0x55	; a=!c
	vplzcntd 	zmm7, zmm7				; count leading 1s to find next search letter

.noaddskip:

	vpslld		zmm3, zmm3, 1			; line up 5-bit lzcnt with bottom of pop6 bits
	vpternlogd 	zmm3, zmm0, zmm20, 0xd8	; c?b:a z20 has 0x00000fc0 to pull pop6 out
	kmovw		k1, k0
	vpgatherdd	zmm8{k1}, [rsi + zmm3 * 2]	; ** get group lengths for next step

	vpslld		zmm7, zmm7, 1			; line up with pop6 bits
	vpternlogd 	zmm7, zmm4, zmm20, 0xd8	; c?b:a z20 has 0x00000fc0 to pull pop6 out
	kmovw		k1, k0
	vpgatherdd	zmm9{k1}, [rsi + zmm7 * 2]	; ** get group lengths for next step

	vpslld		zmm1, zmm3, 20			; bits [11:1] to top of dword [31:21]
	vpbroadcastd zmm5, r9d				; new history tags from current read index
	vpaddd		zmm5, zmm5, zmm19		; z19 has 0,1,2,3,4,5,6...(dw)(l2r)
	vpternlogd	zmm1, zmm5, zmm21, 0xe4	; c?a:b z21 has 0xffe00000 to pull history in
	vmovdqa32	zmm2, zmm0
	vpshufd		zmm0{k7}, zmm1, 0xb1	; new history tags and search group merged with ;k7=aaaaaaaa
	vpshufd		zmm1{k6}, zmm2, 0xb1	; current mask ready for scatter to piles		;k6=55555555
	vmovdqu32		[rsp - 72], zmm0				; for DEBUG
	vmovdqu32		[rsp - 72], zmm1				; for DEBUG

	vpslld		zmm7, zmm7, 20			; to top of dword
	vpaddd		zmm5, zmm5, zmm18		; z18 has 16s(dw)(l2r)
	vpternlogd	zmm5, zmm7, zmm21, 0xd8	; c?b:a z21 has 0xffe00000 to pull group in
	vmovdqa32	zmm6, zmm4
	vpshufd		zmm4{k7}, zmm5, 0xb1	; new history tags and search group merged with
	vpshufd		zmm5{k6}, zmm6, 0xb1	; current mask ready for scatter to piles

	vpshufb		zmm8{k5}, zmm9, zmm17	; z17 has 0x0d0c0f0e09080b0a0504070601000302 x4
										; k5 = 0xcccccccccccccccc = swap words and merge
										; this merges the two to appear as alternating
										; bits in the rotation, but this can be fixed in
										; the initial permb of the bmt, or with the mrr bit order
	vpsubw		zmm8, zmm22, zmm8		; z22 has 15s (w) << adjusted for negative len
	vpsraw		zmm8, zmm8, 4			; floor((len+15)/16) = search cycle count
	vpminsw		zmm8, zmm8, zmm12		; saturate at 15/14: = pile number

;	vpshufb		zmm9, zmm8, zmm17		; z17 has 0x0d0c0f0e09080b0a0504070601000302 x4
	vprold		zmm9, zmm8, 16			; alternate method of word swap, not on p5 and not word filtering

;***it is possible to get this sorting to pull out the winners into a seperate pile
; eg: winners will have lzcnt>21(<4 letters left to fill) and <27, so if those (unused)
; search groups all have negative lengths (-16 is good), and minsw used to saturate to 14,
; they'll end up on their own in pile 15... but then we'll need to use a different shift
; that filters the bits (which is fine).
; and even if not found when doing the unskipped search due to one missing bit higher up,
; it will be "found" by the skipped version later on once it's filled in the missing bit.
; ... but will we still find the word? yes, because the skipped bit is the only thing added
; and the pile has the original as it's history. possible there will be double-reports due
; to this. if negative lengths are only in groups for lzcnt >26 (skip-len gap) ie 27-28
; then all will be reported only on the skip pass, and will be in zero pile on unskip pass.
; Indeed, the layer count will be obsolete.
; only one positive length is needed: lzcnt=27, g15.3
;***
	vmovdqa32	zmm6, zmm23					; z23=1s(w)
	vpshldvw	zmm6, zmm23, zmm8			; filter needed because -1 must be wrapped to 15

;	vpbmtwd		zmm6, zmm6					; instruction not found... so...
	vpermb		zmm6, zmm24, zmm6			; 0,32,2,34..30,62;1,33,3,35,5..31,63(b)(l2r)
	vpermq		zmm7, zmm6, 0x4e			; swap lanes
	vprolvq		zmm7, zmm7, zmm25			; 4,4,-4,-4,4,4,-4,-4(qw)(l2r) alternate rotate
	vpternlogd	zmm6, zmm7, zmm28, 0xd8		; c?b:a 0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f,f(r2l)
	vpalignr	zmm7, zmm6, zmm6, 8			; swap qwords
	vprolvq		zmm7, zmm7, zmm26			; 2,-2,2,-2,2,-2,2,-2(qw)(l2r)
	vpternlogd	zmm6, zmm7, zmm29, 0xd8		; c?b:a 3333333333333333cccccccccccccccc x4
	vpmultishiftqb zmm7, zmm27, zmm6		; 0x19110901372f271f
	vpternlogd	zmm6, zmm7, zmm30, 0xd8		; c?b:a 55555555aaaaaaaa55555555aaaaaaaa x4
											; result is all 32 word bit0's in dword 0
											; in order
	add 		r9d, 32
	cmp			r9d, r8d					; is ok to always run, should never have no work
	jl			.vsearchdone				; and even if it did it would do no harm

	vpermd		zmm2, zmm8, zmm6			; 1st half conflicts->scatter columns
	vpermd		zmm3, zmm9, zmm6			; 2nd half conflicts->scatter columns
	vpopcntd	zmm6, zmm6					; source increments
	vpandd		zmm2, zmm2, zmm31			; 1st half filter for rightward relevence
											; 1,3,7,f,1f...ffff(l2r)
	vpandd		zmm3, zmm3, zmm15			; 2nd half filter for rightward relevence
											; 1ffff,3ffff,7ffff...ffffffff(l2r)
	vpopcntd	zmm2, zmm2					; 1st half scatter preincrements
	vpopcntd	zmm3, zmm3					; 2nd half scatter preincrements

	vpermd		zmm8, zmm8, zmm10			; select 16 dword indexes from z10
	vpermd		zmm9, zmm9, zmm10			; select 16 dword indexes from z10
	vpaddd		zmm10{k4}, zmm10, zmm6		; increment used indexes, except zero pile <<possible bug? dirty end data might cause unintended increments
	vpaddd		zmm8, zmm8, zmm2			; avoid conflicts							<< also here
	vpaddd		zmm9, zmm9, zmm3			; avoid conflicts



	vmovdqa32	zmm6{k6z}, zmm8				; just 8	(0,2,4,6,8,10,12,14)
	kmovw		k1, k0
	vpscatterqq [r15 + zmm6 * 8]{k1}, zmm0	; at a time
	vpshufd		zmm6{k6z}, zmm8, 0xb1		; but each	(1,3,5,7,9,11,13,15)
	kmovw		k1, k0
	vpscatterqq [r15 + zmm6 * 8]{k1}, zmm1	; in right place
	vmovdqa32	zmm6{k6z}, zmm9				; just 8	(16,18,20,22,24,26,28,30)
	kmovw		k1, k0
	vpscatterqq [r15 + zmm6 * 8]{k1}, zmm4	; at a time
	vpshufd		zmm6{k6z}, zmm9, 0xb1		; but each	(17,19,21,23,25,27,29,31)
	kmovw		k1, k0
	vpscatterqq [r15 + zmm6 * 8]{k1}, zmm5	; in right place

	jmp			.vsearchreadloop			; recount: scatterqq(z,z) has 2p0,1p0156,8p49,8p78.gatherdd has 1p0,1p5,16p23
											; loop: 28p0,20p5,20p05 68 on p05, 96 memops, 8 others (p15,p06,p0156 ops) 172µop total
											; (write min 32c)(vec alu min 34c)(aloc. min 34.4c) so 7082l in 55.4µs
.vsearchdone:
	sub			r9d, r8d					; how many extras were read
	mov			eax, 0xffffffff
	shrx		eax, eax, r9d				; full-width valid element mask
	vpbroadcastd zmm16, eax					; to filter increments by
	mov			ebx, 0x55555555				; evens
	pext		ebx, eax, ebx
	kmovb		k1, ebx
	shr			ebx, 8
	kmovb		k3, ebx
	mov			ebx, 0xaaaaaaaa				; odds
	pext		ebx, eax, ebx
	kmovb		k2, ebx
	shr			ebx, 8
;	kmovb		k4, ebx						; moved below final use of k4=0xfffe

	vpandd		zmm6, zmm6, zmm16			; remove bits from overread columns
	vpermd		zmm2, zmm8, zmm6			; 1st half conflicts->scatter columns
	vpermd		zmm3, zmm9, zmm6			; 2nd half conflicts->scatter columns
	vpopcntd	zmm6, zmm6					; source increments
	vpandd		zmm2, zmm2, zmm31			; 1st half filter for rightward relevence
											; 1,3,7,f,1f...ffff(l2r)
	vpandd		zmm3, zmm3, zmm15			; 2nd half filter for rightward relevence
											; 1ffff,3ffff,7ffff...ffffffff(l2r)
	vpopcntd	zmm2, zmm2					; 1st half scatter preincrements
	vpopcntd	zmm3, zmm3					; 2nd half scatter preincrements

	vpermd		zmm8, zmm8, zmm10			; select 16 dword indexes from z10
	vpermd		zmm9, zmm9, zmm10			; select 16 dword indexes from z10
	vpaddd		zmm10{k4}, zmm10, zmm6		; increment used indexes, except zero pile
	vpaddd		zmm8, zmm8, zmm2			; avoid conflicts
	vpaddd		zmm9, zmm9, zmm3			; avoid conflicts

	kmovb		k4, ebx

	vmovdqa32	zmm6{k6z}, zmm8				; just 8
	vpscatterqq [r15 + zmm6 * 8]{k1}, zmm0	; at a time
	vpshufd		zmm6{k6z}, zmm8, 0xb1		; but each
	vpscatterqq [r15 + zmm6 * 8]{k2}, zmm1	; in right place
	vmovdqa32	zmm6{k6z}, zmm9				; just 8
	vpscatterqq [r15 + zmm6 * 8]{k3}, zmm4	; at a time
	vpshufd		zmm6{k6z}, zmm9, 0xb1		; but each
	vpscatterqq [r15 + zmm6 * 8]{k4}, zmm5	; in right place
	mov			r9d, r8d					; r9 (readpoint) went too far, set it right

	vmovdqa32	[r10], zmm10				; store back pile indexes

	xor			r13d, r13d					; clear the addskip magic number so we don't do it again next time

	ret			; return from call to sortwork/sortworkaddskip


.pilesfinished:
	ret			; return from call to processpiles
.processpiles:
	mov		r14d, 0xffff			; for maskmaking
	vmovd	r12d, xmm12				; start with last pile as used by last sortwork
	and		r12d, 15				; zmm has top-pile as words for word saturation. get rid of the second word.
	jmp		.pileloopstart			;	(z12 still holds the saturation limit on write pile)
.pileloop:
	mov		[r10 + r12 * 4], r11d	; reset pile index to starting place after finishing
	sub		r12d, 1					; working down through the piles
	jz		.pilesfinished			; don't process pile zero
.pileloopstart:
	mov		r11d, [r10 + r12 * 4]	; get a pile index
.pileouterloop:
	mov		rax, [r15 + r11 * 8]	; get the work from the pile
	test	rax, rax				; null = pile finished
	jz		.pileloop				; so get the next pile

	shr		rax, 53					; 11-bit search group
	movsx	rcx, word [rsi + rax * 4]; negative length of search
	movzx	ebx, word [rsi + rax * 4 + 2]; end index of search
	lea		rbx, [rdi + rbx * 4]	; index -> read endpointer

	vpbroadcastd	zmm1, [r15 + r11 * 8]		; mask to test
	vpbroadcastd	zmm3, [r15 + r11 * 8 + 4]	; history for merge
						; outer loop: 3c/l (1p5, 15µop, 5 reads) 192621 in 131µs
						; pre-neg,enddex: 13µop, 5 read, 2.6c/l: 192621 in 113µs
.writeinnerloop:
	vmovdqu32	zmm0, [rbx + rcx * 4]		; get candidates
	vptestnmd	k1, zmm0, zmm1				; test candidates (0==success)
	kmovw		eax, k1						; retrieve for count
	vpord		zmm0, zmm0, zmm1			; merge candidates
	add			rcx, 16						; increment readpointer
	jnl			.plastfew					; +ve==read too many. 1s pile will always exit
	popcnt		eax, eax					; count successes
	vpcompressd	zmm0{k1z}, zmm0				; discard failures
	vmovdqu32	[rbp + r8 * 4], zmm3		; write out history
	vmovdqu32	[rdx + r8 * 4], zmm0		; write out masks
	add			r8d, eax					; increment writepointer by number written
	jmp			.writeinnerloop				; 14ops, 3p5, 3c/l 281000l in 192µs
											; can eat 1op/il from outerloop: -12.8µs
											; can eat 1op/ol from outerloop: -8.7µs
											; 113+192+55-21.5=339µs
.plastfew:
	shrx		r13d, r14d, ecx				; maskmaking
	and			eax, r13d					; apply to test result mask
	kmovw		k1, eax						; return modified mask
;****
	popcnt		eax, eax					; count successes
	vpcompressd	zmm0{k1z}, zmm0				; discard failures
	vmovdqu32	[rbp + r8 * 4], zmm3		; write out history
	vmovdqu32	[rdx + r8 * 4], zmm0		; write out masks
	add			r8d, eax					; increment writepointer by number written
;**** between stars should be counted as innerloop final iteration

	sub			r11d, 1				; scan down through the pile
	jmp			.pileouterloop		; break test is at start of loop so always go back

