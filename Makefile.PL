# -*-Perl-*-
#	%W%	%G%
use ExtUtils::MakeMaker qw(WriteMakefile $Verbose %att);
require 5.001;

require './config';

$sattr = &config;

$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

WriteMakefile(DISTNAME => "sybperl",
	      NAME => Sybase, 
	      VERSION => $$sattr{VERSION},
	      dist => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
	      LINKTYPE => $linktype,
	      'linkext' => {LINKTYPE => ''}
	      );


sub MY::libscan
{
    return '' if m:/SCCS/:;
    $_;
}

sub MY::staticmake
{
    my($self, %attribs) = @_;

    my(%searchdirs)=($att{PERL_ARCHLIB} => 1,  $att{INST_ARCHLIB} => 1);
    my(@searchdirs)=keys %searchdirs;
    my @static;
    
    my(@perlinc) = ($att{INST_ARCHLIB}, $att{INST_LIB}, $att{PERL_ARCHLIB}, $att{PERL_LIB});
    # Check the sybperl CONFIG status to see which extensions to add:
    push(@static, "$att{INST_ARCHLIB}/auto/$att{FULLEXT}/DBlib/DBlib.a") if $sattr{DBLIBVS} > 0; 
    push(@static, "$att{INST_ARCHLIB}/auto/$att{FULLEXT}/CTlib/CTlib.a") if $sattr{CTLIBVS} > 0;
    
    MY->makeaperl('MAKE' => $att{MAKEFILE}, 
			     'DIRS' => \@searchdirs, 
			     'STAT' => \@static, 
			     'INCL' => \@perlinc,
			     'TARGET' => $att{MAP_TARGET},
			     'TMP' => "",
			     'LIBPERL' => $att{LIBPERL_A}
			     );
}
    
