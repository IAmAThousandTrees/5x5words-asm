#include <x86intrin.h>
#include <stdio.h>
#include <stdint.h>

static inline uint32_t unskip(uint32_t mask)
{	// to remove the leftmost set bit, conditional on the presence of a bit at bit5
	uint32_t temp1, temp2; // used uninitialised warning is fine - set as io to function to give flexible clobberable temp reg
	asm volatile (	"	mov		%0, %2	\n"	//copy
					"	bsr 	%2, %1	\n"	// find last bit
					"	btr		%1, %2	\n"	// reset that bit
					"	btr		$5, %2	\n"	// test and reset the skip indicator
					"	cmovc	%2, %0	\n"	// copy back only if the skip bit was set
				:	"+r" (mask), "+r" (temp1), "+r" (temp2)	: : "cc" );
	return mask;
}

/* can't get the lzcnt intrinsic to work so wrote asm instead
uint32_t unskip(uint32_t mask)
{
	uint32_t skb = (mask & 0x20);	// extract the skip bit
//	int	lmbn = mssb(mask) - 5;		// whatever intrinsic uses bsr
	int lmbn = 26 - _lzcnt_u32(mask);// lzcnt alternative
	return mask & ~(skb << lmbn);	// shift to the Most Significant Set Bit and remove it
									// IF the skip bit was actually set
}
*/

uint32_t unscramble(uint32_t in, uint16_t* letterBits)
{	// from a popularity-ordered code, returns a natural-ordered code for the hashtable
	uint32_t out = 0;
	for(int n = 0; n < 32; n++) { // this might be a bit wrong: A could be element 1, not element 0
		out |= !!(in & (1 << (int)letterBits[n])) << n;
	}
	return out;
}
/*
void printwords(uint64_t* words, int n)
{
	printf("{");
	for(--n; n >= 0; --n) printf(" %s ", (char*)(words + n));
	printf("}");
}

uint64_t hashmul = 0x99672d35;

int hashread(uint64_t* hashspace, uint32_t find, uint64_t* found)
{
	uint64_t hash = (uint64_t)find * hashmul;
	hash >>= 16;
	uint64_t athash;
	int n = 0;
	while((athash = hashspace[hash++]))
	{	// loop through the hashes until a zero is found, storing any words whos code
		// matches what we're looking for
		hash &= 0x3fff;
		found[n] = (athash >> 32);
		n += ((uint32_t)athash == find);
	}
	for(int o = 0; o < n; ++o)
	{ // unpack compressed letters back into ascii
		uint64_t t1 = found[n] & 0x1fff;
		uint64_t t2 = found[n] & 0xfffc0000;
		uint64_t t3 = found[n] & 0x0003e000;
		t1 |= (t2 >> 2) | (t3 << 19);
		t1 &= 0x1f1f1f1f1f;
		t1 |= 0x2020202020;
		found[n] = t1;
	}
	return n;
} **** old hash seeking routine for old hashing process
*/

/*
bit1vals:	dw	0,0,0,0,0,0,10626,19481,26796,32781,37626,41502,44562,46942,48762,50127,51128,51843,52338,52668,52878,53004,53074,53109,53124,53129,53130,0,0,0,0,0
bit2vals:	dw		0,0,0,0,0,0,1771,3311,4641,5781,6750,7566,8246,8806,9261,9625,9911,10131,10296,10416,10500,10556,10591,10611,10621,10625,10626,0,0,0,0,0
bit3vals:	dw		0,0,0,0,0,0,231,441,631,802,955,1091,1211,1316,1407,1485,1551,1606,1651,1687,1715,1736,1751,1761,1767,1770,1771,0,0,0,0,0
bit4vals:	dw		0,0,0,0,0,0,21,41,60,78,95,111,126,140,153,165,176,186,195,203,210,216,221,225,228,230,231,0,0,0,0,0
bit5vals:	dw		0,0,0,0,0,0,0,21,20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0,0,0,0 ;; adjusted for A=1 (empty first bit means all pcnt(x-1) has 1 more)
*/
uint32_t bit1tab[32] = {0,0,0,0,0,0,10626,19481,26796,32781,37626,41502,44562,46942,48762,50127,51128,51843,52338,52668,52878,53004,53074,53109,53124,53129,53130,0,0,0,0,0};
uint32_t bit2tab[32] = {0,0,0,0,0,0,1771,3311,4641,5781,6750,7566,8246,8806,9261,9625,9911,10131,10296,10416,10500,10556,10591,10611,10621,10625,10626,0,0,0,0,0};
uint32_t bit3tab[32] = {0,0,0,0,0,0,231,441,631,802,955,1091,1211,1316,1407,1485,1551,1606,1651,1687,1715,1736,1751,1761,1767,1770,1771,0,0,0,0,0};
uint32_t bit4tab[32] = {0,0,0,0,0,0,21,41,60,78,95,111,126,140,153,165,176,186,195,203,210,216,221,225,228,230,231,0,0,0,0,0};
uint32_t bit5tab[32] = {0,0,0,0,0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,0,0,0,0,0};

int hashfunc(uint32_t find)
{	// new hashing process is based on the perfect hashfunction (combinational numbering) and a linked list of indexes into the file on each hash entry
	// the perfect hashfunction requires a set of position-value tables for each bit, and order is important in that numbering, so they must be unscrambled first.
	// in the end this is just the hashfunction, returning the index the hash points to and letting print print the values by scanning the list is easier
	uint32_t t, hash = bit1tab[__builtin_popcount(t = find - 1)]; find &= t;
	hash += bit2tab[__builtin_popcount(t = find - 1)]; find &= t;
	hash += bit3tab[__builtin_popcount(t = find - 1)]; find &= t;
	hash += bit4tab[__builtin_popcount(t = find - 1)]; find &= t;
	hash += bit5tab[__builtin_popcount(t = find - 1)]; find &= t;
	return hash;
}
void printwords(uint32_t link, uint32_t* linkspace, uint32_t* indexes, char* file)
{
	printf("{");
	for(; link != 0xffffffff; link = linkspace[link]) printf(" %.5s ", (file + indexes[link]));
	printf("}");
}

void report(uint32_t* maskspace, uint32_t* linespace, int windex, uint16_t* letterBits, uint32_t* hashspace, uint32_t* linkspace, uint32_t* indexes, char* file)
{	// maskspace and linespace are the history from the search, windex the index of the last winner
	// letterBits has the rankings of the bits for unscrambling them
	// hashspace, linkspace, indexes and file are for finding the lists of words that are anagrams of the extracted masks
	uint32_t parent;
	while((parent = linespace[windex--] & 0x1fffff))	// mask of winner isn't read
	{
		uint32_t mask5 = maskspace[parent];
		parent = linespace[parent] & 0x1fffff;			// history still has the search group bits in it, so need the top 11 bits filtered off
		uint32_t mask4 = maskspace[parent];
		parent = linespace[parent] & 0x1fffff;
		uint32_t mask3 = maskspace[parent];
		parent = linespace[parent] & 0x1fffff;
		uint32_t mask2 = maskspace[parent];
		parent = linespace[parent] & 0x1fffff;
		uint32_t mask1 = maskspace[parent];

		mask5 ^= mask4;	// separating the codes
		mask4 ^= mask3; // one will have 7 bits if there's a skip in the search sequence
		mask3 ^= mask2; // the others will have 5 bits each
		mask2 ^= mask1; // and can be used to find the words that generated them

		mask5 = unscramble(unskip(mask5), letterBits); // all 5 need to be unskipped though, since we don't know which has the skip
		mask4 = unscramble(unskip(mask4), letterBits); // but the unskip function only removes the MSSB if the skip bit is set
		mask3 = unscramble(unskip(mask3), letterBits);
		mask2 = unscramble(unskip(mask2), letterBits);
		mask1 = unscramble(unskip(mask1), letterBits);

		printwords(hashspace[hashfunc(mask1)], linkspace, indexes, file);
		printwords(hashspace[hashfunc(mask2)], linkspace, indexes, file);
		printwords(hashspace[hashfunc(mask3)], linkspace, indexes, file);
		printwords(hashspace[hashfunc(mask4)], linkspace, indexes, file);
		printwords(hashspace[hashfunc(mask5)], linkspace, indexes, file);
		printf("\n");
/*		uint64_t words[16]; // in case there's more than one word in the dataset with the
							// same 5 letters
		int n = hashread(hashspace, mask5, words); printwords(words, n);
		n = hashread(hashspace, mask4, words); printwords(words, n);
		n = hashread(hashspace, mask3, words); printwords(words, n);
		n = hashread(hashspace, mask2, words); printwords(words, n);
		n = hashread(hashspace, mask1, words); printwords(words, n); printf("\n");
*/
	}
}
