# -*-Perl-*-
#	@(#)Makefile.PL	1.5	9/18/95

use ExtUtils::MakeMaker;

open(CFG, "../CONFIG") || die "Can't open ../CONFIG: $!";

while(<CFG>)
{
    chop;
    s/^\s*//;
    next if /^#|^\s*$/;
    
    ($left, $right) = split(/=/);
    $left =~ s/\s*//g;

    $sattr{$left} = $right;
}
close(CFG);
$DBLIBVS = $sattr{DBLIBVS};

#####
### Configure End
#####

# Write a dummy makefile if DBLIBVS is 0 - this means that we don't have
# DBlibrary on this system...
if(!$DBLIBVS)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
    exit(0);
}


WriteMakefile("NAME" => "Sybase::Sybperl",
	      "VERSION" => "$sattr{VERSION}",
	      "SKIP" => [qw(static dynamic)]
	      );

sub MY::postamble {
	'
dynamic :: $(INST_PM)
static :: $(INST_PM)
'
}

