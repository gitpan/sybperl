# -*-Perl-*-
# @(#)Makefile.PL	1.7	10/24/95


use ExtUtils::MakeMaker;

require '../config';

$sattr = &config;

#####
### Configure
#####

$CTLIBVS = $$sattr{CTLIBVS};
$SYBASE = $$sattr{SYBASE};
$VERSION = $$sattr{VERSION};

# Extra flags to pass to CPP
$inc_string = "-I$SYBASE/include";
$def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER='\"\${VERSION}\"' $$sattr{EXTRA_DEFS}";
$lib_string = "-L$SYBASE/lib -lct -lcs -ltcl -lcomn -lintl -ltli -linsck $$sattr{EXTRA_LIBS} -ldl -lm";

#####
### Configure End
#####

# Write a dummy makefile if CTLIBVS is 0 - this means that we don't have
# CTlibrary on this system...
if($CTLIBVS == 0)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
    exit(0);
}

WriteMakefile(
    'NAME'	=> 'Sybase::CTlib',
    'VERSION'	=> $VERSION,
    'LIBS'	=> [$lib_string],   # e.g., '-lm' 
    'DEFINE'	=> $def_string,     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> $inc_string,     # e.g., '-I/usr/include/other'
);

sub MY::staticmake
{
    my($self, %attribs) = @_;

'
# --- MakeMaker makeaperl section ---
MAP_TARGET    = ../perl
';
}
