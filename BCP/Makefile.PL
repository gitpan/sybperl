#	@(#)Makefile.PL	1.5	03/22/96

require 5.002;
use ExtUtils::MakeMaker;

$VERSION='0.03';
$DBLIBVS = 0;

if(-f '../config') {
    require '../config';

    $sattr = &config;

    $DBLIBVS = $$sattr{DBLIBVS};
}
else
{
    eval {
	require Sybase::DBlib;
	$DBLIBVS = &Sybase::DBlib::DBLIBVS;
    }
}
    

# Write a dummy makefile if DBLIBVS is 0 - this means that we don't have
# DBlibrary on this system...
if($DBLIBVS == 0)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
}
else
{
    WriteMakefile('NAME' => "Sybase::BCP",
		  'VERSION' => "$VERSION",
		  'NEEDS_LINKING' => 1,
		  'dist' => {'TARFLAGS' => "cvfF", 'COMPRESS' => "gzip"},
		  );
}
