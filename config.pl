# -*-Perl-*-
#	$Id: config.pl,v 1.7 2001/09/06 21:13:46 mpeppler Exp $
#
# Extract relevant info from the CONFIG and patchlevel.h files.

use Config;

my @dirs = ('.', '..', '../..', '../../..');

if(defined($ExtUtils::MakeMaker::VERSION)) {
    $MM_VERSION = $ExtUtils::MakeMaker::VERSION;
} else {
    $MM_VERSION = $ExtUtils::MakeMaker::Version;
}

sub config
{
    my(%attr, %patchlvl);
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

    foreach $dir (@dirs)
    {
	$config = "$dir/patchlevel.h";
	last if(-f $config);
    }
    open(CFG, $config) || die "Can't open $config: $!";

    while(<CFG>)
    {
	chomp;
	next if !/^#/;
	
	($dummy, $left, $right) = split(' ');
	$left =~ s/\s*//g;
	$right =~ s/^\s*//g;

	$patchlvl{$left} = $right;
    }
    close(CFG);
    $patchlvl{UNOFFICIAL} = '' if(!defined($patchlvl{UNOFFICIAL}));

    $sattr{VERSION} = "$patchlvl{VERSION}.$patchlvl{PATCHLEVEL}$patchlvl{UNOFFICIAL}";

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

    if($^O ne MSWin32 && $^O ne 'VMS') {
	$sattr{EXTRA_LIBS} = getExtraLibs($sattr{SYBASE}, $sattr{EXTRA_LIBS});
    }

    \%sattr;
}

if($MM_VERSION > 5) {
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

    my $version = `strings $lib/libct.a`;
    $version =~ /Sybase Client-Library\/([^\/]+)\//;
    $version = $1;
    print "Sybase OpenClient $version found.\n";

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
    if($version gt '11') {
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
    my @files = grep(/libct/i, readdir(DIR));
    closedir(DIR);

    scalar(@files);
}

sub putEnv {
    my $sattr = shift;
    my $data  = shift;

    my $replace = '';

    if($$sattr{EMBED_SYBASE}) {
	if($$satter{EMBED_SYBASE_USE_HOME}) {
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

    $data =~ s/__SYBASE__/$replace/;

    $data;
}
    


1;
