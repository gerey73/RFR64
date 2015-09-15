RFR64: rfr64.asm
	nasm -f elf64 -l rfr64.lst rfr64.asm
	gcc -o RFR64 rfr64.o -ldl

clean:
	rm -f *.lst *.o RFR64

sweep:
	rm -f *.lst *.o

