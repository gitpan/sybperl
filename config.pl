# -*-Perl-*-
#	$Id: config.pl,v 1.1 1999/05/14 17:16:50 mpeppler Exp $
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
	
	($left, $right) = split(/=/);
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
	chop;
	next if !/^#/;
	
	($dummy, $left, $right) = split(' ');
	$left =~ s/\s*//g;

	$patchlvl{$left} = $right;
    }
    close(CFG);
    $patchlvl{UNOFFICIAL} = '' if(!defined($patchlvl{UNOFFICIAL}));

    $sattr{VERSION} = "$patchlvl{VERSION}.$patchlvl{PATCHLEVEL}$patchlvl{UNOFFICIAL}";

    $sattr{LINKTYPE} = 'static' if(!defined($Config{'usedl'}));

    # Set Sybase directory to the SYBASE env variable if the one from
    # CONFIG appears invalid
    $sattr{SYBASE} = $ENV{SYBASE} if(!exists($sattr{SYBASE})
				     || !-d $sattr{SYBASE} 
				     || !-d "$sattr{SYBASE}/lib"
				     || !-d "$sattr{SYBASE}/include"
				    );

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

1;
