#include <stdint.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>

/// global memory spaces

uint32_t maskspace[327680] __attribute__((aligned(64))); // space for the flowsearch masks
uint32_t linespace[327680] __attribute__((aligned(64))); // space for the flowsearch lineage
										// having these separate saves time in the search
uint32_t words[16384] __attribute__((aligned(64)));		// the indexes into the file
uint32_t codes[65536] __attribute__((aligned(64)));		// space for words converted to codes, and the expanded groups
uint32_t links[16384] __attribute__((aligned(64)));		// to store anagram hashchain links for the word indexes
uint32_t hashmap[65792] __attribute__((aligned(64)));	// link indexes of words hashed by their code
uint32_t cindex[64*32] __attribute__((aligned(64)));		// index to the sorted code groups in codes
uint16_t letterRanks[32] __attribute__((aligned(64)));	// transfer store for the letter counts, replaced by

char* filename = "words_alpha.txt";

/// C linkage for assembler routines:

extern int find5words(char* file, uint32_t* words, int flen);
//extern int countStore(char* file, uint32_t* words, uint16_t* lettercounts, uint32_t* codes, int nwords);
extern int preConvert(char* file, uint32_t* words, uint32_t* codes, int nwords);		// returns nwords change
extern int hashWords(uint32_t* codes, uint32_t* hashmap, uint32_t* linkspace, int nwords);	// returns nwords change
extern void countRankConvert(uint32_t* codes, uint16_t* letterRanks, int nwords);
extern void sortpop2lpop(uint32_t* codes, int nwords, uint32_t* cindex);
extern void expandSubgroups(uint32_t* codes, uint32_t* cindex, int nwords);; // rdi = codes		rsi = index		 edx = nwords
extern uint32_t search(uint32_t* codes, uint32_t* cindex, uint32_t* maskspace, uint32_t* linespace);
						//;; rdi = ptr to sorted codes, rsi = ptr to index-length array,
						//;; rdx = ptr to mask space, rcx = pointer to index history space (HUGE malloc ... 4Gb?)
						//;; NOTE: skip bit is useful in reporting, and no benefit to removing it
void report(uint32_t* maskspace, uint32_t* linespace, int windex, uint16_t* letterBits, uint32_t* hashspace, uint32_t* linkspace, uint32_t* indexes, char* file);
/// main function

char* mmapFile(char* filename, uint32_t* flen)
{
	int fd;

	printf("%s\n", filename);
	if ((fd = open(filename, O_RDONLY)) < 0) {
		printf("open");
		exit(1);
	}

	struct stat statbuf[1];
	if (fstat(fd, statbuf) < 0) {
		printf("fstat");
		exit(2);
	}

	size_t len = (*flen = statbuf->st_size);
	char* addr = mmap(NULL, len + 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (addr == MAP_FAILED) {
		printf("mmap");
		exit(3);
	}
	addr = mmap(addr, len, PROT_READ|PROT_WRITE, MAP_PRIVATE | MAP_FIXED | MAP_POPULATE, fd, 0);

	// Safe to close file now.  mapping remains until munmap() is called
	close(fd);

	return addr;
}

int main()
{
	uint32_t flen;
	char* file = mmapFile(filename, &flen); // read only memory mapped file
	/// for timings we'll use CLOCK_MONOTONIC and run the whole process between the mmap and the report 1000 times
	/// gathering the times for each and calculating the differences at the end,
	/// reporting the minimum times for each and total at the end
	//	pinning and sched_fifo seems to help a little, though not so much:~10% - best time ~273µs, @4200MHz (icelake 11400)
	struct timespec t0, t1, t2, t3, t4, t5, t6, t7;
	uint64_t lo = 1000000000,l1 = 1000000000,l2 = 1000000000,l3 = 1000000000,l4 = 1000000000,l5 = 1000000000,l6 = 1000000000,l7 = 1000000000,temp;
	int windex;
	for(int r=10000; r>0; --r) {
		clock_gettime(CLOCK_MONOTONIC, &t0);
		int nwords = find5words(file, words, flen); // indexes all 5-letter words in file
		clock_gettime(CLOCK_MONOTONIC, &t1);
		nwords += preConvert(file, words, codes, nwords);
			// culls words with repeated letters and their indexes
		clock_gettime(CLOCK_MONOTONIC, &t2);
		nwords += hashWords(codes, hashmap, links, nwords);
			// make hashmap of words by their natural-order codes
			// culls codes that are duplicates (anagrams)
			// but still enters them in the hashtable so hashtable will report multiple entries
			// but search only has to find once.
			// it overwrites the codes, but the links are still aligned with their original positions
			// which means the link indexes are aligned with and index the words (word byte indexes in file)
			// even though words isn't passed to the hashfunction
		clock_gettime(CLOCK_MONOTONIC, &t3);
		countRankConvert(codes, letterRanks, nwords);
			// counts how many of each letter there are in the remaining data set
			// use the letter counts to convert the codes to letter-popularity-ordered bit-codes
		clock_gettime(CLOCK_MONOTONIC, &t4);
		sortpop2lpop(codes, nwords, cindex);
			// sort the codes by least popular letter and most popular 2 letters
			// leave info about where to find the groups in index
		clock_gettime(CLOCK_MONOTONIC, &t5);
		expandSubgroups(codes, cindex, nwords);
			// copy out search groups by prior sort and next most popular 4 letters
			// creating 15 ordered subgroups for each main (least-popular) letter group
			// leave info about where to find the groups in index
		clock_gettime(CLOCK_MONOTONIC, &t6);
		windex = search(codes, cindex, maskspace, linespace);
		clock_gettime(CLOCK_MONOTONIC, &t7);
			// search for combinations of 5 5-letter words where no letter is repeated
			// searchspace becomes a complete history of every partial and complete success
			//  with each one pointing at the step that led to it so that the solutions can be
			//   disentangled afterwards
			//	  (would be kinda pointless if all we got was a solid bitmask at the end)
			// returns an index to the collected complete successes
		if(t0.tv_nsec < t7.tv_nsec) {
			temp=t1.tv_nsec - t0.tv_nsec; if(temp<l1) l1=temp; //printf("%ld\t", temp);
			temp=t2.tv_nsec - t1.tv_nsec; if(temp<l2) l2=temp; //printf("%ld\t", temp);
			temp=t3.tv_nsec - t2.tv_nsec; if(temp<l3) l3=temp; //printf("%ld\t", temp);
			temp=t4.tv_nsec - t3.tv_nsec; if(temp<l4) l4=temp; //printf("%ld\t", temp);
			temp=t5.tv_nsec - t4.tv_nsec; if(temp<l5) l5=temp; //printf("%ld\t", temp);
			temp=t6.tv_nsec - t5.tv_nsec; if(temp<l6) l6=temp; //printf("%ld\t", temp);
			temp=t7.tv_nsec - t6.tv_nsec; if(temp<l7) l7=temp;// printf("%ld\t", temp);
			temp=t7.tv_nsec - t0.tv_nsec; if(temp<lo) lo=temp; //printf("%ld\t\n", temp);
		}
	}
	printf("minimum stage times:\nfind 5-letter-words: %ld ns\n", l1);
	printf("convert to bitcodes and cull words with repeated letters: %ld ns\n", l2);
	printf("insert all words into hashtable, culling anagrams: %ld ns\n", l3);
	printf("count letters and rearrange bitcodes in order of overall letter frequency: %ld ns\n", l4);
	printf("sort the codes into groups based on their least popular letter, and subdivided by their most popular 2 letters: %ld ns\n", l5);
	printf("expand into 16 supersets that each exclude some of the next most popular 4 letters: %ld ns\n", l6);
	printf("find sets of 5 5-letter words with no repeated letters: %ld ns\n", l7);
	printf("minimum overall process time: %ld ns\n", lo);
	report(maskspace, linespace, windex, letterRanks, hashmap, links, words, file);
		// print results to stdout
	return(0);
}
