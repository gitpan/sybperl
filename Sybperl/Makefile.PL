# -*-Perl-*-
#	@(#)Makefile.PL	1.10	1/5/96

use ExtUtils::MakeMaker;

require '../config';

$sattr = &config;

$DBLIBVS = $$sattr{DBLIBVS};

#####
### Configure End
#####

if($MM_VERSION < 5) {
    eval <<'EOF_EVAL';

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
EOF_EVAL
}    

# Write a dummy makefile if DBLIBVS is 0 - this means that we don't have
# DBlibrary on this system...
if($DBLIBVS == 0)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
}
else
{
    if($MM_VERSION > 5) {
	WriteMakefile('NAME' => "Sybase::Sybperl",
		  'VERSION' => "$$sattr{VERSION}",
		  'NEEDS_LINKING' => 1,
		  );
    } else {
	WriteMakefile("NAME" => "Sybase::Sybperl",
		  "VERSION" => "$$sattr{VERSION}",
		  "SKIP" => [qw(static dynamic)],
		  "MAP_TARGET" => '../perl'
		  );
    }

}

