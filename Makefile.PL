# -*-Perl-*-
#	@(#)Makefile.PL	1.22	03/20/98
require 5.002;
use ExtUtils::MakeMaker;
use Config;

require './config.pl';

$sattr = &config;

$linktype = defined($$sattr{LINKTYPE}) ? $$sattr{LINKTYPE} : 'dynamic';

sub MY::libscan
{
    my($self, $path) = @_;
    return '' if $path =~ m:/SCCS/:;
    $path;
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
	
    }
}

WriteMakefile('DISTNAME' => "sybperl",
	      'NAME' => Sybase, 
	      'VERSION' => $$sattr{VERSION},
	      'dist' => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
	      'LINKTYPE' => $linktype,
	      'XSPROTOARG' => '-prototypes',
              'MAN3PODS' => 'pod/sybperl.pod'
	      );

