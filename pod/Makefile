#	@(#)Makefile	1.2	8/7/95
#  The stuff below shoudl be OK if you've unpacked the extension in the
# correct place (ie $(PERLSRC)/ext).
#

POD2MAN = pod2man
POD2HTML = pod2html
PERL = perl

all: man

POD = \
	sybperl.pod

MAN = \
	sybperl.man

HTML = \
	sybperl.html

man: $(MAN)

html: $(HTML)

.SUFFIXES: .pod .man

.pod.man:
	$(POD2MAN) $*.pod >$*.man

.SUFFIXES: .pod .html

.pod.html:
	$(POD2HTML) $*.pod >$*.html

clean:
	rm -f $(MAN) $(HTML) *~ *.ps

