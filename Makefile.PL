# -*-Perl-*-
#	@(#)Makefile.PL	1.19	03/22/96
require 5.002;
use ExtUtils::MakeMaker;
use Config;

require './config';

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
    if(-d "$_/Sybase") {
	warn <<"MSG_EOF";
*** WARNING ***
An installed copy of the Sybase modules found in $_
This can cause a version conflict as this version installs in
    $Config{installprivlib}/site_perl
which comes later in Perl 5.002's include directory list.

You may need to manually remove these older Sybase directories if
sybperl 2.05 does not run correctly.

MSG_EOF
	
    }
}

WriteMakefile('DISTNAME' => "sybperl",
	      'NAME' => Sybase, 
	      'VERSION' => $$sattr{VERSION},
	      'dist' => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
	      'LINKTYPE' => $linktype,
	      'XSPROTOARG' => '-prototypes'
	      );

