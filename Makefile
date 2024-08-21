ifndef PREFIX
    PREFIX  = /usr/local
endif

VERSION = 1.0.0
INSTALLDIR=${PREFIX}/lib/tsession-dynamodb${VERSION}

install:
	mkdir -p ${INSTALLDIR}
	cp pkgIndex.tcl ${INSTALLDIR}
	cp -R tcl ${INSTALLDIR}