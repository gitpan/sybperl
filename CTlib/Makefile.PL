# -*-Perl-*-
# $Id: Makefile.PL,v 1.25 2002/01/11 23:50:29 mpeppler Exp $
# @(#)Makefile.PL	1.19	03/26/99


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

if($ENV{SYBASE_OCS}) {
    $SYBASE .= "/$ENV{SYBASE_OCS}";
}

open(IN, "CTlib.pm.in") || die "Can't open CTlib.pm.in: $!";
{
    local $/ = undef;
    my $data = <IN>;
    close(IN);
    open(OUT, ">CTlib.pm") || die "Can't open CTlib.pm: $!";
    print OUT "# This file is auto generated from CTlib.pm.in.\n# Please edit CTlib.pm.in to make any changes\n";
    $data = putEnv($sattr, $data);
    print OUT $data;
    close(OUT);
}


$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

# Extra flags to pass to CPP
if($^O eq 'MSWin32') {
    $inc_string = "-I$SYBASE\\include";
    $def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER=\\\"$VERSION\\\" $$sattr{EXTRA_DEFS}";
    if($$sattr{BORLAND_LIBS}) {
	$lib_string = "-L$SYBASE\\blib -llibcs -llibct -llibcomn -llibblk";
    } else {
	$lib_string = "-L$SYBASE\\lib -llibcs -llibct -llibcomn -llibblk";
    }
} else {
    $inc_string = "-I$SYBASE/include";
    $def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER='\"\${VERSION}\"' $$sattr{EXTRA_DEFS}";
    $lib_string = "-L$SYBASE/lib -lct -lcs -ltcl -lcomn -lintl -lblk";

    # Linux uses libsybtcl instead of libtcl to avoid conflicts with tcl/tk
    if(-e "$SYBASE/lib/libsybtcl$Config{lib_ext}" || 
       -e "$SYBASE/lib/libsybtcl$Config{so}") {
	$lib_string =~ s/-ltcl/-lsybtcl/;
    }

    $lib_string =~ s/-l/-lsyb_/g if $^O eq 'VMS';
    $lib_string .= " $$sattr{EXTRA_LIBS} -lm";


    # Logic to replace normal libs with _r (re-entrant) libs if
    # usethreads is defined provided by W. Phillip Moore (wpm@ms.com)
    # I have no idea if this works on Win32 systems (probably not!)
    if ( $Config{usethreads} eq 'define' && $Config{osname} =~ /solaris|linux/ ) {
	print "Running in threaded mode - looking for _r libraries...\n";
	opendir(SYBLIB,"$SYBASE/lib")
	    or die "Unable to opendir $SYBASE/lib: $!\n";
	
	my %libname = ();
	
	foreach ( readdir(SYBLIB) ) {
	    next unless /^lib(\S+)\.(so|a)/;
	    next unless -f "$SYBASE/lib/$_";
	    $libname{$1} = 1;
	}
	
	closedir(SYBLIB);
	
	foreach ( split(/\s+/,$lib_string) ) {
	    next unless /^-l(\S+)/;
	    my $oldname = $1;
	    my $newname = $1 . "_r";
	    next unless exists $libname{$newname};
	    print "Found -l$newname for -l$oldname\n";
	    $lib_string =~ s/-l$oldname\b/-l$newname/;
	}
	
    }
    # If we are building for a 64 bit platform that also supports 32 bit
    # (i.e. Solaris 8, HP-UX11, etc) then we need to make some adjustments
    if($$sattr{BUILD_TYPE} == 64) {
	$def_string .= ' -DSYB_LP64';

	print "Running in 64bit mode - looking for '64' libraries...\n";
	opendir(SYBLIB,"$SYBASE/lib")
	    or die "Unable to opendir $SYBASE/lib: $!\n";
	
	my %libname = ();
	
	foreach ( readdir(SYBLIB) ) {
	    next unless -f "$SYBASE/lib/$_";
	    next unless /^lib(\S+)\.(so|a)/;
	    $libname{$1} = 1;
	}
	
	closedir(SYBLIB);
	
	foreach ( split(/\s+/,$lib_string) ) {
	    next unless /^-l(\S+)/;
	    my $oldname = $1;
	    my $newname = $1 . '64';
	    next unless exists $libname{$newname};
	    print "Found -l$newname for -l$oldname\n";
	    $lib_string =~ s/-l$oldname\b/-l$newname/;
	}
	
    }
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
		($] >= 5.005 ?
		 (ABSTRACT   => 'Sybase OpenClient API modules',
		  AUTHOR     => 'Michael Peppler (mpeppler@mbay.net)') : ()),
		($] >= 5.005 && $^O eq 'MSWin32' && 
		 $Config{archname} =~ /-object\b/i ? (CAPI => 'TRUE') :()),
		'XSPROTOARG' => '-prototypes');
    if($^O ne VMS && $^O ne 'MSWin32') {
	$opts{'LDDLFLAGS'} = "-L$SYBASE/lib $Config{lddlflags}";
#	$opts{'LDFLAGS'}   = "-L$SYBASE/lib $Config{lddlflags}";
    }
    WriteMakefile(%opts);
}
