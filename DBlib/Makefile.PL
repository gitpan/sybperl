# -*-Perl-*-
#	@(#)Makefile.PL	1.9	10/18/95

use ExtUtils::MakeMaker;

require '../config';

$sattr = &config;

# DB-Library version
$DBLIBVS = $$sattr{DBLIBVS};
$SYBASE = $$sattr{SYBASE};
# Extra flags to pass to CPP
$inc_string = "-I$SYBASE/include";
$def_string = "-DDBLIBVS=$DBLIBVS -DSYBPLVER='\"\${VERSION}\"' $$sattr{EXTRA_DEFS}";
$lib_string = "-L$SYBASE/lib -lsybdb $$sattr{EXTRA_LIBS} -lm";

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

WriteMakefile("LIBS" => [$lib_string],
	      "NAME" => "Sybase::DBlib",
	      "INC" => $inc_string,
	      "VERSION" => "$$sattr{VERSION}",
	      "DEFINE" => $def_string,
	      "MAP_TARGET" => '../perl'
	      );

sub MY::staticmake
{
    my($self, %attribs) = @_;

'
# --- MakeMaker makeaperl section ---
MAP_TARGET    = ../perl
';
}
