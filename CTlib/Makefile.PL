# -*-Perl-*-
# @(#)Makefile.PL	1.11	1/30/96


use ExtUtils::MakeMaker;

require '../config';

$sattr = &config;

#####
### Configure
#####

$CTLIBVS = $$sattr{CTLIBVS};
$SYBASE = $$sattr{SYBASE};
$VERSION = $$sattr{VERSION};

$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

# Extra flags to pass to CPP
$inc_string = "-I$SYBASE/include";
$def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER='\"\${VERSION}\"' $$sattr{EXTRA_DEFS}";
$lib_string = "-L$SYBASE/lib -lct -lcs -ltcl -lcomn -lintl -linsck $$sattr{EXTRA_LIBS} -lm";

#####
### Configure End
#####

if($MM_VERSION < 5) {
    eval <<'EOF_EVAL';
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

# Write a dummy makefile if CTLIBVS is 0 - this means that we don't have
# CTlibrary on this system...
if($CTLIBVS == 0)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
}
else
{
    if($MM_VERSION > 5) {
	WriteMakefile('NAME'	=> 'Sybase::CTlib',
		  'VERSION'	=> $VERSION,
		  'LIBS'	=> [$lib_string],
		  'DEFINE'	=> $def_string,
		  'INC'	=> $inc_string,
		  'LINKTYPE' => $linktype,
		  'XSPROTOARG' => '-prototypes'
		  );
    } else {
	WriteMakefile('NAME'	=> 'Sybase::CTlib',
		  'VERSION'	=> $VERSION,
		  'LIBS'	=> [$lib_string],
		  'DEFINE'	=> $def_string,
		  'INC'	=> $inc_string,
		  'LINKTYPE' => $linktype,
#		  'XSPROTOARG' => '-prototypes'
		  );
    }
}
