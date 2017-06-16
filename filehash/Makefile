#
# Makefile for filehash
#

CFLAGS  = -I. -D_FILE_OFFSET_BITS=64
LDFLAGS = libfilehash.a -lpthread

OBJ = ffdb_db.o ffdb_hash.o ffdb_hash_func.o ffdb_page.o ffdb_pagepool.o
INCLUDES = ffdb_cq.h ffdb_db.h ffdb_hash.h ffdb_hash_func.h ffdb_page.h ffdb_pagepool.h

%.o: %.cc $(INCLUDES)
	$CC $CFLAGS -c $(firstword $^)

# Intermediate files
libfilehash.a: $(OBJ)
	echo "AR $@"
	ar rcsu $@ $?

libfilehash.a: $(OBJ)

.PHONY: libfilehash.a

clean: 
	rm -f *.o *~ libfilehash.a


