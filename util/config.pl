# -*-Perl-*-
#	$Id: config.pl,v 1.11 2003/12/27 01:33:13 mpeppler Exp $
#
# Extract relevant info from the CONFIG files.

use Config;
use ExtUtils::MakeMaker;

use strict;

my @dirs = ('.', '..', '../..', '../../..');

my $syb_version;
my $VERSION;

#use vars q($MM_VERSION);

#if(defined($ExtUtils::MakeMaker::VERSION)) {
#    $MM_VERSION = $ExtUtils::MakeMaker::VERSION;
#} else {
#    $MM_VERSION = $ExtUtils::MakeMaker::Version;
#}

sub config
{
    my(%sattr);
    my($left, $right, $dir, $dummy, $config);
    
    foreach $dir (@dirs)
    {
	$config = "$dir/CONFIG";
	last if(-f $config);
    }
    open(CFG, $config) || die "Can't open $config: $!";
    
    while(<CFG>)
    {
	chop;
	s/^\s*//;
	next if /^#|^\s*$/;
	s/#.*$//;
	
	($left, $right) = split(/=\s*/);
	$left =~ s/\s*//g;

	$sattr{$left} = $right;
    }
    close(CFG);

    if(!$VERSION) {
	foreach $dir (@dirs)
	{
	    $config = "$dir/patchlevel";
	    last if(-f $config);
	}
	do $config;
    }
    $sattr{VERSION} = $VERSION;

    $sattr{LINKTYPE} = 'static' if(!defined($Config{'usedl'}));

    # Set Sybase directory to the SYBASE env variable if the one from
    # CONFIG appears invalid
    my $sybase_dir = $ENV{SYBASE};

    if(!$sybase_dir) {
	$sybase_dir = (getpwnam('sybase'))[7];
    }

    $sattr{SYBASE} = $sybase_dir if(!exists($sattr{SYBASE})
				    || !-d $sattr{SYBASE} 
				    || !-d "$sattr{SYBASE}/lib"
				    || !-d "$sattr{SYBASE}/include"
				   );

    die "Can't find any Sybase libraries under $sattr{SYBASE}/lib.\nPlease set the SYBASE environment correctly, or edit CONFIG and set SYBASE\ncorrectly there." unless checkLib($sattr{SYBASE});

    if($^O ne 'MSWin32' && $^O ne 'VMS') {
	$sattr{EXTRA_LIBS} = getExtraLibs($sattr{SYBASE}, $sattr{EXTRA_LIBS});
    }

    \%sattr;
}

if($ExtUtils::MakeMaker::VERSION > 5) {
    eval <<'EOF_EVAL';

sub MY::const_config {
    my($self) = shift;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    my(@m,$m);
    push(@m,"\n# These definitions are from config.sh (via $INC{'Config.pm'})\n");
    push(@m,"\n# They may have been overridden via Makefile.PL or on the command line\n");
    my(%once_only);
    foreach $m (@{$self->{CONFIG}}){
	next if $once_only{$m};
	next if ($self->{LINKTYPE} eq 'static' && $m =~ /C+DLFLAGS/i);
	push @m, "\U$m\E = ".$self->{uc $m}."\n";
	$once_only{$m} = 1;
    }
    join('', @m);
}

EOF_EVAL
}

sub getExtraLibs {
    my $dir = shift;
    my $cfg = shift;

    my $lib = "$dir/lib";
    if($ENV{SYBASE_OCS}) {
	$lib = "$dir/$ENV{SYBASE_OCS}/lib";
    }
    if(!defined($syb_version)) {
	my $libct;

	foreach (qw(libct.a libct.so libct.sl libct64.a libct64.so libct64.sl)) {
	    $libct = "$lib/$_";
	    last if -e $libct;
	}

	my $version = `strings $libct`;
	if($version =~ /Sybase Client-Library\/([^\/]+)\//) {
	    $syb_version = $1;
	    print "Sybase OpenClient $syb_version found.\n";
	} else {
	    $syb_version = 0;
	    print "Unknown OpenClient version found - may be FreeTDS.\n";
	}
    }

    opendir(DIR, "$lib") || die "Can't access $lib: $!";
    my %files = map { $_ =~ s/lib([^\.]+)\..*/$1/; $_ => 1 } grep(/lib/, readdir(DIR));
    closedir(DIR);

    my %x = map {$_ => 1} split(' ', $cfg);
    my $f;
    foreach $f (keys(%x)) {
	my $file = $f;
	$file =~ s/-l//;
	next if($file =~ /^-/);
	delete($x{$f}) unless (exists($files{$file}) || $f =~ /dnet_stub/);
    }
    
    foreach $f (qw(insck tli sdna dnet_stub tds)) {
	$x{"-l$f"} = 1 if exists $files{$f};
    }
    if($syb_version gt '11') {
	delete($x{-linsck});
	delete($x{-ltli});
    }

    join(' ', keys(%x));
}
    
	
sub checkLib {
    my $dir = shift;

    if($ENV{SYBASE_OCS}) {
	$dir .= "/$ENV{SYBASE_OCS}";
    }

    opendir(DIR, "$dir/lib") || die "Can't access $dir/lib: $!";
    my @files = grep(/libct|libsybdb/i, readdir(DIR));
    closedir(DIR);

    scalar(@files);
}

sub putEnv {
    my $sattr = shift;
    my $data  = shift;

    my $replace = '';

    if($$sattr{EMBED_SYBASE}) {
	if($$sattr{EMBED_SYBASE_USE_HOME}) {
	    $replace = qq(
BEGIN {
    if(!\$ENV{'SYBASE'}) {
	if(\@_ = getpwnam("sybase")) {
	    \$ENV{'SYBASE'} = \$_[7];
	} else {
	    \$ENV{'SYBASE'} = '$$sattr{SYBASE}';
	}
    }
}
);
	} else {
	    $replace = qq(
BEGIN {
    if(!\$ENV{'SYBASE'}) {
	\$ENV{'SYBASE'} = '$$sattr{SYBASE}';
    }
}
);
	}
    }

    $data =~ s/\#__SYBASE_START.*\#__SYBASE_END/\#__SYBASE_START\n$replace\n\#__SYBASE_END/s;

    $data;
}
    


1;
