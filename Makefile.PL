# -*-Perl-*-
#	@(#)Makefile.PL	1.11	9/20/95
use ExtUtils::MakeMaker;
require 5.001;

open(CFG, "./CONFIG") || die "Can't open ./CONFIG: $!";

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

$linktype = defined($sattr{LINKTYPE}) ? $sattr{LINKTYPE} : 'dynamic';

WriteMakefile(DISTNAME => "sybperl",
	      NAME => Sybase, 
	      VERSION => $sattr{VERSION},
	      dist => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
	      LINKTYPE => $linktype,
	      'linkext' => {LINKTYPE => ''}
	      );


sub MY::libscan
{
    return '' if m:/SCCS/:;
    $_;
}
