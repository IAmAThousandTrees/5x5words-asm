;; count, rank, reconvert, all in one. whole processs: 0.901µs expected, 0.936 measured (yaay! l1-data means works as expected)
global countRankConvert

section .data
align 64
idb:			db		0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
				db		16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
				db		32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
				db		48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
;awaygather:		dw		17,1,19,3,21,5,23,7,25,9,27,11,29,13,31,15
;				dw		16,0,18,2,20,4,22,6,24,8,26,10,28,12,30,14
;awayshift:		dd		1,3,5,7,9,11,13,15,0,2,4,6,8,10,12,14
awaygather:		dw		16,0,17,1,18,2,19,3,20,4,21,5,22,6,23,7
				dw		24,8,25,9,26,10,27,11,28,12,29,13,30,14,31,15
awayshift:		dd		0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

bmtdw.perm:		db		0,32,4,36,8,40,12,44,16,48,20,52,24,56,28,60
				db		1,33,5,37,9,41,13,45,17,49,21,53,25,57,29,61
				db		2,34,6,38,10,42,14,46,18,50,22,54,26,58,30,62
				db		3,35,7,39,11,43,15,47,19,51,23,55,27,59,31,63
bmtwd.perm:		db		0,16,32,48,2,18,34,50,4,20,36,52,6,22,38,54
				db		8,24,40,56,10,26,42,58,12,28,44,60,14,30,46,62
				db		1,17,33,49,3,19,35,51,5,21,37,53,7,23,39,55
				db		9,25,41,57,11,27,43,59,13,29,45,61,15,31,47,63
firstwords2t:	dw		0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30
				dw		32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,62

bmtwd.msh1:		dq		4,4,60,60
bmtwd.tlm1:		dq		0xf0f0f0f0f0f0f0f0, 0xf0f0f0f0f0f0f0f0
				dq		0x0f0f0f0f0f0f0f0f, 0x0f0f0f0f0f0f0f0f
bmtwd.msh2:		dq		2, 62
bmtwd.tlm2:		dq		0xcccccccccccccccc, 0x3333333333333333
bmtdw.msh1:		dq		4,60
bmtdw.tlm1:		dq		0xf0f0f0f0f0f0f0f0, 0x0f0f0f0f0f0f0f0f
bmtdw.msh2:		;dq		0x1a120a02362e261e
				db		30,38,46,54,2,10,18,26
bmtdw.tlm2:		dq		0x33333333cccccccc
bmtdw.msh3:		;dq		0x2921372f0901170f
				db		15,23,1,9,47,55,33,41
bmtdw.tlm3:		dq		0x5555aaaa5555aaaa
bmtwd.msh3:		dq		0x19110901372f271f
bmtwd.tlm3:		dq		0x55555555aaaaaaaa

ones:			dd		0x00010001			; word 1s
thirtysevens:	dd		0x00250025
fifteens:		dd		0x000f000f
one:			dd		1					; dword 1
sixteens:		dd		0x00100010			; bit filter

section .text

align 16

;; rdi = codes, rsi = letterRanks, rdx = nwords
countRankConvert:

;; first load the bmt constants:
	vmovdqa32		zmm23, [bmtdw.perm]
	vbroadcasti64x2	zmm24, [bmtdw.msh1]
	vbroadcasti64x2	zmm25, [bmtdw.tlm1]
	vpbroadcastq	zmm26, [bmtdw.msh2]
	vpbroadcastq	zmm27, [bmtdw.tlm2]
	vpbroadcastq	zmm28, [bmtdw.msh3]
	vpbroadcastq	zmm29, [bmtdw.tlm3]
	vpxord			zmm3, zmm3, zmm3				;; word counts
;; rdi is end of data, rax is non-duplicate count from hashing, negated
	mov				rax, rdx
	lea				rdi, [rdi + rax * 4]			;; rdi now endpointer for codes
	vmovdqu32		[rdi], zmm3						;; zeros above the codes now
	neg				rax

.countloop:											;; vector counting loop - ~3.2 codes/cycle
	vmovdqa32		zmm0, [rdi + rax * 4]			;; 5p5, 5p05, 5c/l, 6000 codes (375l) = 0.426µs

;;	vpbmtdw			zmm1, zmm0						; should be an instruction
													; but it isn't, so we do this:
	vpermb			zmm1, zmm23, zmm0				; collect first bytes in first lane, second bytes in second lane...
	vpalignr		zmm2, zmm1, zmm1, 8				; swap qwords
	vprolvq			zmm2, zmm2, zmm24				; alternating direction rotates of 4 bits. using this custom bmt reduces p5 ops by one...
	vpternlogd		zmm1, zmm25, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm26, zmm1
	vpternlogd		zmm1, zmm27, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm28, zmm1
	vpternlogd		zmm1, zmm29, zmm2, 0xb8			; B?C:A			...because there's no pshufb required at the end

	vmovdqa32		[rdi + rax * 4], zmm1			; store the bmt result back for post-ranking-use

	vpopcntw		zmm1, zmm1						; all 0 bits in first word, all 1 bits in second
	vpaddw			zmm3, zmm3, zmm1				; add them up

	add				rax, 16							; negative loopcounter
	js				.countloop						; null codes don't count: final cycle is valid


;; 32-way word value ranking

;; after counting the non-exlusive word memberships of the 26 letter groups, we need to regenerate the bit assignments of the letters in reverse popularity order.
;; the original did this by sorting, but that is an enefficient method since what we need is to generate an in-register lookup-table of bits for letters.
;; the letter A will always select element 0 of the table from a permute, but that element can be bit 6 or bit 9 whatever the correct bit is for the popularity of A.
;; so what is needed is actually a ranking of letter popularities in letter place, that can be easily converted to a table of 32 32-bit bitmasks.

;; ranking entails comparing each element to every other and counting the number of other elements it is not-less than.
;; for a table of 32 elements this requres 16*31 comparisons to get info on every relationship - except that only the static columns know what the results were,
;; so if you want to get all the comparisons for a column in that column then you have to do them all twice, once in each of the columns involved.
;; if only there was some way to get one bit of information from every colummn into every other column, all at once...

;; Oh yes, a bit matrix transpose should do it ;þ

;; but we have to be careful about the order we do the comparisons in. In order to keep the details of each comparison separate, rather than compare and add, we must
;; compare and shift. the only expedient way I see to do this is to subtract and then use a double-shift to transfer the sign bit from the subtraction into the first
;; bit of the results collection. arrange the subtraction so that a win (home column is greater than rotated column) is a negative result, and the bits gather with
;; the first comparison ending up in the MSB of the element, and the last one in the LSB. In order to return the "away" results to their home columns, we have to be
;; able to rotate the results to get them into the right bits that the BMT can return them home, which means they need to be in home-register order, which requires
;; that the shifts all go left. only right-shifts are available through alignd and alignr so we shift nearly all the way round instead. Subtracting one from the
;; initial unrotated values from which the rotations are generated, but rotating in unsubtracted values each time gives ordering in the case of identical values such
;; that the one that was originaly further left will take the left spot, due to it gaining a home win against the rotated value, but where two values meet the other
;; way round (home value is the rightward element of the pair) it will not be counted as a home win. This produces the same result both ways when the home win bits
;; are counted as away losses after they've been returned home.

;; once all the bits are gathered, after 16 compare and shift operations, every bit in each of the 32 word elements is filled. with 32 elements to have their away
;; wins and losses returned to them, we combine sets of 16 that are all different away elements from each other into dwords, rotate them so that their away-element
;; results are in the away-element-numbered bit of the dword, and then a vpbmtdw operation returns them all to their home columns. Inverting them all, we have a
;; slight issue: there are 16 repeat-comparisons that are produced by the last comparison. The home results can be kept, but the away results need to be masked off
;; to avoid double reporting. The easiest time to do this is just before the rotate for the bmt when they are all still in position 0.

	vpbroadcastd	zmm31, [ones]

	vmovdqu32		zmm0, zmm3						; move in the counted values
	vpsubw			zmm1, zmm0, zmm31			 	; prevent duplicate rankings
	valignd			zmm2, zmm1, zmm0, 12			; generate ¼ and ½ rotations
	valignd			zmm3, zmm1, zmm0, 8				; due to left-rotation and left-priority for stability/non duplication, most of the rotated values are V-1
	vpalignr		zmm4, zmm1, zmm2, 14			; then word (1/32) rotations from them
	vpsubw			zmm4, zmm4, zmm0
	vpsrlw			zmm5, zmm4, 15					; keep sign bit only
	vpalignr		zmm4, zmm1, zmm2, 12
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm1, zmm2, 10
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm1, zmm2, 8
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm1, zmm2, 6
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm1, zmm2, 4
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm1, zmm2, 2
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpsubw			zmm4, zmm2, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg

	vpalignr		zmm4, zmm2, zmm3, 14
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm2, zmm3, 12
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm2, zmm3, 10
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm2, zmm3, 8
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm2, zmm3, 6
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm2, zmm3, 4
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpalignr		zmm4, zmm2, zmm3, 2
	vpsubw			zmm4, zmm4, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg
	vpsubw			zmm4, zmm3, zmm0
	vpshldw			zmm5, zmm5, zmm4, 1				; shift sign bit into result reg

; data is gathered, now rearrange:

;	lea				rax, [awaygather]				; for DEBUG
	vmovdqu32		zmm20, [awaygather]
	vpternlogd		zmm1, zmm5, zmm31, 0x11			; invert away results unless masked, in which case zero.
	vpermw			zmm1, zmm20, zmm1				; zmm20 = 14,30,12,28,10,26,8,24,6,22,4,20,2,18,0,16,15,31,13,29,11,27,9,25,7,23,5,21,3,19,1,17 (w)(r2l)
	vprolvd			zmm1, zmm1, [awayshift]			; awayshift = 14,12,10,8,6,4,2,0,15,13,11,9,7,5,3,1 (dw)(r2l) :: get a-away results in bit0

;;	vpbmtdw			zmm1, zmm1						; should be an instruction
													; but it isn't, so we do this:
	vpermb			zmm1, zmm23, zmm1				; collect first bytes in first lane, second bytes in second lane...
	vpalignr		zmm2, zmm1, zmm1, 8				; swap qwords
	vprolvq			zmm2, zmm2, zmm24				; alternating direction qword rotates of 4 bits.
	vpternlogd		zmm1, zmm25, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm26, zmm1
	vpternlogd		zmm1, zmm27, zmm2, 0xb8			; B?C:A
	vpmultishiftqb	zmm2, zmm28, zmm1
	vpternlogd		zmm1, zmm29, zmm2, 0xb8			; B?C:A

	vpopcntw		zmm5, zmm5						; home match result total
	vpopcntw		zmm1, zmm1						; away match result total
	vpaddw			zmm1, zmm1, zmm5				; ranked

													; 24p5, 17p0, 22p05  63 µops total (incl. bmt expanded) l=47c = 11ns


; now just remains to generate the bitmasks in 2 dword registers:
; we wish for the letters to end up with the least popular letter having bit 31.
; the unused columns will have had zeros so they will be counted as the least popular 6, they will have rank 0,1,2,3,4,5.
; subtracting the computed ranks from 37 gives the correct result.

	vpbroadcastd	zmm20, [thirtysevens]			; :0x00250025
	vpsubw			zmm1, zmm20, zmm1				; also correct for reverse-permute
	vmovdqa32		[rsi], zmm1						; store the word permute for later de-ranking to get the original codes for reading the hashtable

;; 32-way reverse-permute requires transmission of more than words can hold :\ so we rotate into 2 words in 2 registers, do 2 bmtwd, then recombine the popcnts

;; reload bmt constants for bmtwd, that we will also use for the reverse-bmt for bit-sorting the codes

	vmovdqa32		zmm23, [bmtwd.perm]
	vbroadcasti64x4	zmm24, [bmtwd.msh1]
	vbroadcasti64x4	zmm25, [bmtwd.tlm1]
	vbroadcasti64x2	zmm26, [bmtwd.msh2]
	vbroadcasti64x2	zmm27, [bmtwd.tlm2]
	vpbroadcastq	zmm28, [bmtwd.msh3]
	vpbroadcastq	zmm29, [bmtwd.tlm3]

	vpbroadcastd	zmm3,  [sixteens]					; can't embed broadcast on word operations :o(
	vptestmw		k1, zmm1, zmm3						; top bit of 1-in-32 selections as k-mask
	vpandd			zmm1, zmm1, [fifteens]{1to16}		; no rolvw so have to remove the bits
	vpsllvw			zmm1, zmm31, zmm1					; other 4 bits make 1-in-16 selection bits

;;	vpbmtwd			zmm1, zmm1							; should be an instruction...
														; but it isn't, so we do this:
	vpermb			zmm1, zmm23, zmm1					; collect-first-bytes-but-weird-order
	vpermq			zmm2, zmm1, 0x4e					; swap lanes
	vprolvq			zmm2, zmm2, zmm24					; zmm24=4,4,-4,-4
	vpternlogq		zmm1, zmm25, zmm2, 0xb8				; B?C:A zmm25=0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0ff0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0 x2
	vpalignr		zmm2, zmm1, zmm1, 8					; swap odd/even qword pairs
	vprolvq			zmm2, zmm2, zmm26					; zmm26=2,-2
	vpternlogq		zmm1, zmm27, zmm2, 0xb8				; zmm27=0x3333333333333333cccccccccccccccc
	vpmultishiftqb	zmm2, zmm28, zmm1					; zmm28=0x19110901372f271f
	vpternlogq		zmm1, zmm29, zmm2, 0xb8				; zmm29=0x55555555aaaaaaaa

	kmovd			eax, k1
	vpbroadcastd	zmm2, eax							; not sure why broadcastm only broadcasts 16 bits of the mask to each dword...
	vpandd			zmm4, zmm2, zmm1					; filter result bits by >=16
	vpandnd			zmm3, zmm2, zmm1					; filter result bits by < 16
														; l=15

	vpsubd			zmm3, zmm3, [one]{1to16}			; turn position into bits that we can count
	vpsubd			zmm4, zmm4, [one]{1to16}			; turn position into bits that we can count
	vpopcntd		zmm3, zmm3							; count
	vpopcntd		zmm4, zmm4							; count
	vmovdqa32		zmm1, [firstwords2t]				; 0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,62(w)(l2r)
	vpermi2w		zmm1, zmm3, zmm4					; rearrange to word permute table
														; 20 p05 µops (84 total from count result to sort permute table)
														; l total is 73
;	vmovdqu32		[rsp - 72], zmm1				; for DEBUG
;	nop
	vpermw			zmm1, zmm1, [idb]					; that we use to load the byte id table turning it into a byte permute index
;	vmovdqu32		[rsp - 72], zmm1				; for DEBUG
	vpermb			zmm23, zmm23, zmm1					; and combine that with the collect-first-bytes of the bmtwd we'll use to reverse the bmt's codes
;	vmovdqu32		[rsp - 72], zmm23				; for DEBUG

;; ready for rearrangement of the codes. overwriting the originals used for culling and counting with ranked-bit-order verdions used for the search.

;; having the bitmask in popularity order gives some very useful properties...
;; 1: the most popular letter bits are the first 6, so finding search group is easy (shr)
;; 2: the least popular letter is the leftmost set bit, so is easy to tell where it goes
;;		in a sort (lzcnt)
;; 3: the search for the next letter group to search is no longer a loop, just find the next leftmost unset bit in the current search mask (lzcnt(~mask))
;; together these enable a continuous search process (adding candidates to a list while processing the list)
;; in just 64 bits all required information can be carried for each search:
;; 5 = skip (add the one bit that was skipped into the mask as well)(also optional: you can find the skip because when there's 6 bits added the left one is a skip)
;; 31:6 = currentmask
;; 52:32 = index of the parent search that generated this one, to find the words that fitted for final result reporting
;; 53:63 = temporary note of what search group to do on this mask

;; it is even possible to 99% vectorise the search... ... as we shall soon see.


	neg				rdx
.convertloop:
	vmovdqa32		zmm1, [rdi + rdx * 4]				; we did the bmt before and stored it. this only works because we recall the blocks aligned with the stores

	vpermb			zmm1, zmm23, zmm1					; combined sorting permute and collect-first-bytes
	vpermq			zmm2, zmm1, 0x4e					; swap lanes
	vprolvq			zmm2, zmm2, zmm24					; zmm24=4,4,-4,-4
	vpternlogq		zmm1, zmm25, zmm2, 0xb8				; B?C:A zmm25=0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0ff0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0 x2
	vpalignr		zmm2, zmm1, zmm1, 8					; swap qwords
	vprolvq			zmm2, zmm2, zmm26					; zmm26=2,-2
	vpternlogq		zmm1, zmm27, zmm2, 0xb8				; zmm27=0x3333333333333333cccccccccccccccc
	vpmultishiftqb	zmm2, zmm28, zmm1					; zmm28=0x19110901372f271f
	vpternlogq		zmm1, zmm29, zmm2, 0xb8				; zmm29=0x55555555aaaaaaaa

	vmovdqu32		[rdi + rdx * 4], zmm1				; write out. no trash at end because we zeroed above the top of codes before we started ;)

	add				rdx, 16								; negative loop counter
	js				.convertloop						; go until we're positive
														; 4p5, 2p0, 3p05. 4.5c/l

	;; cleanup and pops not required
	ret

;; alternate method: store the bmt during the count, create a reverse permute matrix from the ranking, permute the stored bmt and reverse-bmt to get ranked codes.
;; if a simmilar 4p5 4p0 incorperating the reverse permute can be created, could do the reencoding in 4c/16, and removes need for storing words during pre-convert
;; and hashing (shortened anagram-free list is codes only)

;;possible: 	first bytes→first half * rank bits positions
;;			swap lanes, rotate 4,4,-4,-4
;;			swap qwords, rotate 2,-2
;;			msh dwords
;;result: 9p05 total. 4p5, 2p0, 3p05 can work in 4.5c/l...
