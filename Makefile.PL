# -*-Perl-*-
#	@(#)Makefile.PL	1.16	1/5/96
use ExtUtils::MakeMaker;
require 5.001;

require './config';

$sattr = &config;

$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

# Make sure we can handle both MakeMaker version 4.x and 5.x
#
# $MM_VERSION is set in the 'config' file.
if($MM_VERSION > 5) {
    eval <<'EOF_EVAL';
sub MY::libscan
{
    my($self, $path) = @_;
    return '' if $path =~ m:/SCCS/:;
    $path;
}
EOF_EVAL
} else {
    eval <<'EOF_EVAL';

sub MY::libscan
{
    return '' if m:/SCCS/:;
    $_;
}

sub MY::staticmake
{
    my($self, %attribs) = @_;
    my(%att) = %ExtUtils::MakeMaker::att;
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
    
EOF_EVAL
}


if($MM_VERSION > 5) {
    WriteMakefile('DISTNAME' => "sybperl",
		  'NAME' => Sybase, 
		  'VERSION' => $$sattr{VERSION},
		  'dist' => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
		  'LINKTYPE' => $linktype,
		  'XSPROTOARG' => '-prototypes'
		  );
} else {
    WriteMakefile(DISTNAME => "sybperl",
		  NAME => Sybase, 
		  VERSION => $$sattr{VERSION},
		  dist => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
		  LINKTYPE => $linktype,
		  'linkext' => {LINKTYPE => ''}
		  );
}

