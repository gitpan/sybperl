# -*-Perl-*-
# @(#)Makefile.PL	1.12	03/22/96


require 5.002;

use ExtUtils::MakeMaker;
use Config;

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
    WriteMakefile('NAME'	=> 'Sybase::CTlib',
		  'VERSION'	=> $VERSION,
		  'LIBS'	=> [$lib_string],
		  'DEFINE'	=> $def_string,
		  'INC'	=> $inc_string,
		  'LINKTYPE' => $linktype,
		  'XSPROTOARG' => '-prototypes',
		  'LDDLFLAGS' => "-L$SYBASE/lib $Config{lddlflags}",
		  'LDFLAGS' => "-L$SYBASE/lib $Config{ldflags}"
		  );
}
