# -*-Perl-*-
#	$Id: Makefile.PL,v 1.6 2002/01/11 23:50:28 mpeppler Exp $
require 5.002;
use ExtUtils::MakeMaker;
use Config;

require './config.pl';

$sattr = &config;

configPwd();

$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

if($Config{lns}) {
    system("cd CTlib; $Config{lns} ../pod/sybperl.pod CTlib.pod") if(!-e 'CTlib/CTlib.pod');
    system("cd DBlib; $Config{lns} ../pod/sybperl.pod DBlib.pod") if(!-e 'DBlib/DBlib.pod');
}
    


foreach (@INC) {
    next if(/site_perl/);
    next if(/blib/);
    if(-d "$_/Sybase") {
	warn <<"MSG_EOF";
*** WARNING ***
An installed copy of the Sybase modules found in $_
This can cause a version conflict as this version installs in
    $Config{installprivlib}/site_perl
which comes later in Perl $]'s include directory list.

You may need to manually remove these older Sybase directories if
sybperl $sattr{VERSION} does not run correctly.

One way to do so would be to run the following command
    mv $_/Sybase $_/Sybase.old

MSG_EOF
#'	
    }
}

WriteMakefile('DISTNAME' => "sybperl",
	      'NAME' => Sybase, 
	      'VERSION' => $$sattr{VERSION},
	      'dist' => {'TARFLAGS' => "cvf", 'COMPRESS' => "gzip"},
	      'LINKTYPE' => $linktype,
	      'XSPROTOARG' => '-prototypes',
	      ($] >= 5.005 ?
	       (ABSTRACT   => 'Sybase API modules',
		AUTHOR     => 'Michael Peppler (mpeppler@peppler.org)') : ()),
	      ($] >= 5.005 && $^O eq 'MSWin32' && 
	       $Config{archname} =~ /-object\b/i ? (CAPI => 'TRUE') :()),
              'MAN3PODS' => { 'pod/sybperl.pod' => 'blib/man3/sybperl.3' }
	      );



sub MY::libscan
{
    my($self, $path) = @_;
    return '' if $path =~ m:/SCCS/:;
    $path;
}

sub configPwd {
    open(IN, "PWD") || die "Can't open PWD: $!";
    my %pwd;
    while(<IN>) {
	chomp;
	next if(/^\s*\#/);
	next if(/^\s*$/);
	my ($key, $val) = split(/=/, $_);
	$pwd{$key} = $val || "undef";
    }
    close(IN);
    select(STDOUT); $| = 1;

    print "The sybperl modules need access to a Sybase server to run the tests.\n";
    print "To clear an entry please enter 'undef'\n";
    print "Sybase server to use (default: $pwd{SRV}): ";
    $pwd{SRV} = getAns() || $pwd{SRV};
    print "User ID to log in to Sybase (default: $pwd{UID}): ";
    $pwd{UID} = getAns() || $pwd{UID};
    print "Password (default: $pwd{PWD}): ";
    $pwd{PWD} = getAns() || $pwd{PWD};

    open(OUT, ">PWD") || die "Can't open PWD: $!";
    print OUT <<EOF;
# This file contains optional login id, passwd and server info for the test
# programs:
# You probably don't want to have it lying around after you've made
# sure that everything works OK.

EOF
    foreach (keys %pwd) {
	$pwd{$_} = '' if $pwd{$_} eq 'undef';
	print OUT "$_=$pwd{$_}\n";
    }
    close(OUT);
}

sub getAns {
    my $ans = <STDIN>;
    chomp($ans);
    $ans;
}

    
