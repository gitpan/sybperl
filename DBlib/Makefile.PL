# -*-Perl-*-
# $Id: Makefile.PL,v 1.21 1999/09/21 21:09:18 mpeppler Exp $
#	@(#)Makefile.PL	1.19	03/26/99

require 5.002;

use ExtUtils::MakeMaker;
use Config;

require '../config.pl';

$sattr = &config;

# DB-Library version
$DBLIBVS = $$sattr{DBLIBVS};
$SYBASE = $$sattr{SYBASE};
$VERSION = $$sattr{VERSION};

open(IN, "DBlib.pm.in") || die "Can't open DBlib.pm.in: $!";
{
    local $/ = undef;
    my $data = <IN>;
    close(IN);
    open(OUT, ">DBlib.pm") || die "Can't open DBlib.pm: $!";
    print OUT "# This file is auto generated from DBlib.pm.in.\n# Please edit DBlib.pm.in to make any changes\n";
    $data = putEnv($sattr, $data);
    print OUT $data;
    close(OUT);
}

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
		($] >= 5.005 ?
		 (ABSTRACT   => 'Sybase DB-Library API module',
		  AUTHOR     => 'Michael Peppler (mpeppler@mbay.net)') : ()),
		($] >= 5.005 && $^O eq 'MSWin32' && 
		 $Config{archname} =~ /-object\b/i ? (CAPI => 'TRUE') :()),
		'LINKTYPE' => $linktype,);
    if($^O ne 'VMS' && $^O ne 'MSWin32') {
	$opts{'LDDLFLAGS'} = "-L$SYBASE/lib $Config{lddlflags}";
	$opts{'LDFLAGS'}   = "-L$SYBASE/lib $Config{lddlflags}";
    }
    WriteMakefile( %opts );
}

