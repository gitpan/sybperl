# -*-Perl-*-
#	@(#)Makefile.PL	1.7	10/18/95

use ExtUtils::MakeMaker;

require '../config';

$sattr = &config;

$DBLIBVS = $$sattr{DBLIBVS};

#####
### Configure End
#####

# Write a dummy makefile if DBLIBVS is 0 - this means that we don't have
# DBlibrary on this system...
if($DBLIBVS == 0)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
    exit(0);
}


WriteMakefile("NAME" => "Sybase::Sybperl",
	      "VERSION" => "$$sattr{VERSION}",
	      "SKIP" => [qw(static dynamic)],
	      "MAP_TARGET" => '../perl'
	      );

sub MY::postamble {
	'
dynamic :: $(INST_PM)
static :: $(INST_PM)
'
}


sub MY::staticmake
{
    my($self, %attribs) = @_;

'
# --- MakeMaker makeaperl section ---
MAP_TARGET    = ../perl
';
}
