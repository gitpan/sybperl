# -*-Perl-*-
#	@(#)Makefile.PL	1.18	12/30/97

require 5.002;

use ExtUtils::MakeMaker;
use Config;

require '../config.pl';

$sattr = &config;

# DB-Library version
$DBLIBVS = $$sattr{DBLIBVS};
$SYBASE = $$sattr{SYBASE};
$VERSION = $$sattr{VERSION};
# Extra flags to pass to CPP
if($^O eq 'MSWin32') {
    $inc_string = "-I$SYBASE\\include";
    $def_string = "-DDBLIBVS=$DBLIBVS -DSYBPLVER=\\\"$VERSION\\\" $$sattr{EXTRA_DEFS}";
    if($$sattr{BORLAND_LIBS}) {
	$lib_string = "-L$SYBASE\\blib -llibcomn -llibsybdb";
    } else {
	$lib_string = "-L$SYBASE\\lib -llibcomn -llibsybdb";
    }
} else {
    $inc_string = "-I$SYBASE/include";
    $def_string = "-DDBLIBVS=$DBLIBVS -DSYBPLVER='\"\${VERSION}\"' $$sattr{EXTRA_DEFS}";
    $lib_string = "-L$SYBASE/lib -lsybdb $$sattr{EXTRA_LIBS} -lm";
    $lib_string =~ s/sybdb/syb_db/ if $^O eq 'VMS';
    $lib_string =~ s/-lsdna// if $^O eq 'dec_osf';
}
$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

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
}
else
{
    my %opts = ('LIBS' => [$lib_string],
		'NAME' => "Sybase::DBlib",
		'INC' => $inc_string,
		'VERSION' => "$VERSION",
		'DEFINE' => $def_string,
		'XSPROTOARG' => '-prototypes',
		'LINKTYPE' => $linktype,);
    if($^O ne 'VMS' && $^O ne 'MSWin32') {
	$opts{'LDDLFLAGS'} = "-L$SYBASE/lib $Config{lddlflags}";
	$opts{'LDFLAGS'}   = "-L$SYBASE/lib $Config{lddlflags}";
    }
    WriteMakefile( %opts );
}

