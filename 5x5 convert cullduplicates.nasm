;; 2.45µs expected, 22.3µs measured (presumably the gather being slow? file is l3 cache at best, 3cc/line transfer, 15000 words to fetch should be 10.5µs so something else is in play as well...)

global preConvert

section .data

align 64

; the shiftbits determing what bits will be set for each mod32(char) that is supplied.
; A(a)=bit1, not 0. 0s indicate no bit will be set for that char.
; this determines which column it's count will end up in, so As will count in column 0.
shiftbits1:		dd	0,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768
shiftbits2:		dd	0x10000,0x20000,0x40000,0x80000,0x100000,0x200000,0x400000
				dd	0x800000,0x1000000,0x2000000,0,0,0,0,0,0
qdperm1:		dd	0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30
qdperm2:		dd	1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31
lettermask:		dd	0x0003e000
one:			dd	1
five:			dd	5
odds:			dd	0xaaaaaaaa

section .text
align 16

;; rdi = file, rsi = words, rdx = codes, rcx = nwords

preConvert:
	vpbroadcastd	zmm20, [one]				; puts A in column 1 so that the permi2d in the reconvert has the A bit where A's will select
	vmovdqa32		zmm21, [shiftbits1]
	vmovdqa32		zmm22, [shiftbits2]
	vpbroadcastd	zmm23, [lettermask]
	vpbroadcastd	zmm24, [five]				; number of bits in a valid code
	vmovdqa32		zmm25, [qdperm1]
	vmovdqa32		zmm26, [qdperm2]
	kmovd			k7, [odds]					; 0b1010101010101010 - filters the shift and swap
	knotd			k6, k7						; 0b0101010101010101 - filters the swap
	kord			k0, k6, k7					; 0b1111111111111111 - read mask for the gather

	lea				rdx, [rdx + rcx * 4]		; end of codes
	lea				rsi, [rsi + rcx * 4]		; end of words point for negative index loopcounter
	neg				rcx							; negative read index
	mov				r8, rcx						; writeback index starts same

.convertloop:
	vmovdqa32		zmm8, [rsi + rcx * 4]		; grab a group of 16 32-bit byte indexes, use for qword gather from file
	vmovdqa32		ymm0, [rsi + rcx * 4 + 32]	; second 8 again (quicker than align, no p05 op)
	kmovb			k1, k0
	vpgatherdq		zmm1{k1}, [rdi + ymm8]
	kmovb			k1, k0
	vpgatherdq		zmm3{k1}, [rdi + ymm0]

	vmovdqa32		zmm2, zmm1					; convert qwords to dword columns:
	vpermt2d		zmm1, zmm25, zmm3			; gets even dwords
	vpermt2d		zmm2, zmm26, zmm3			; gets odd dwords

	vprord			zmm3, zmm1, 8
	vprord			zmm4, zmm1, 16
	vprord			zmm5, zmm1, 24
	vpermi2d		zmm1, zmm21, zmm22			; load balancing p0-p5
	vpermi2d		zmm2, zmm21, zmm22
	vprolvd			zmm3, zmm20, zmm3
	vprolvd			zmm4, zmm20, zmm4			; A counts in column 1
	vprolvd			zmm5, zmm20, zmm5
	vpternlogd		zmm1, zmm2, zmm3, 0xfe		; orABC
	vpternlogd		zmm1, zmm4, zmm5, 0xfe		; orABC

	vpopcntd		zmm2, zmm1
	vpcmpeqd		k1, zmm2, zmm24				; 5 bits required in each. z24 has 5s

	vpcompressd		[rdx + r8 * 4]{k1}, zmm1	; only write codes that have 5 different letters
	vpcompressd		[rsi + r8 * 4]{k1}, zmm8	; overwrite culled index list

	kmovw			eax, k1
	popcnt			eax, eax
	add				r8, rax						; increment writeback index by <nvalid>

	add				rcx, 16						; loop until rcx goes non-negative
	js				.convertloop				; if 0 index points at zero's, or even 5 same chars, final cycle is valid
												; 8p5 9p0, 6p05, 23tp05 18r2w 11.5c/l 15000/16 l, 2.45µs

	vpxord			zmm1, zmm1, zmm1
	vmovdqu32		[rdx + r8 * 4], zmm1		; ensure at least 16 0's after last write
	vmovdqu32		[rsi + r8 * 4], zmm1		; ensure at least 16 0's after last write

	mov 			rax, r8						; return value is nwords change.
;	neg				rax							; negative, caller can add to previous value

	ret

