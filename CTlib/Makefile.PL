# -*-Perl-*-
# @(#)Makefile.PL	1.17	11/28/97


require 5.002;

use ExtUtils::MakeMaker;
use Config;

require '../config.pl';

$sattr = &config;

#####
### Configure
#####

$CTLIBVS = $$sattr{CTLIBVS};
$SYBASE = $$sattr{SYBASE};
$VERSION = $$sattr{VERSION};

$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

# Extra flags to pass to CPP
if($^O eq 'MSWin32') {
    $inc_string = "-I$SYBASE\\include";
    $def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER=\\\"$VERSION\\\" $$sattr{EXTRA_DEFS}";
    if($$sattr{BORLAND_LIBS}) {
	$lib_string = "-L$SYBASE\\blib -llibcs -llibct -llibcomn";
    } else {
	$lib_string = "-L$SYBASE\\lib -llibcs -llibct -llibcomn";
    }
} else {
    $inc_string = "-I$SYBASE/include";
    $def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER='\"\${VERSION}\"' $$sattr{EXTRA_DEFS}";
    $lib_string = "-L$SYBASE/lib -lct -lcs -ltcl -lcomn -lintl";
    $lib_string =~ s/-ltcl/-lsybtcl/ if $^O =~ /linux/i;
    $lib_string =~ s/-l/-lsyb_/g if $^O eq 'VMS';
    $lib_string .= " $$sattr{EXTRA_LIBS} -lm";
}

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
    my %opts = ('NAME'	=> 'Sybase::CTlib',
		  'VERSION'	=> $VERSION,
		  'LIBS'	=> [$lib_string],
		  'DEFINE'	=> $def_string,
		  'INC'	=> $inc_string,
		  'LINKTYPE' => $linktype,
		  'XSPROTOARG' => '-prototypes');
    if($^O ne VMS && $^O ne 'MSWin32') {
	$opts{'LDDLFLAGS'} = "-L$SYBASE/lib $Config{lddlflags}";
	$opts{'LDFLAGS'}   = "-L$SYBASE/lib $Config{lddlflags}";
    }
    WriteMakefile(%opts);
}
