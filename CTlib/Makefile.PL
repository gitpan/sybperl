# -*-Perl-*-
# @(#)Makefile.PL	1.5	9/20/95


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

#####
### Configure
#####

$CTLIBVS = $sattr{CTLIBVS};
$SYBASE = $sattr{SYBASE};
$VERSION = $sattr{VERSION};

# Extra flags to pass to CPP
$inc_string = "-I$SYBASE/include -g";
$def_string = "-DCTLIBVS=$CTLIBVS -DSYBPLVER='\"\${VERSION}\"' $sattr{EXTRA_DEFS}";
$lib_string = "-L$SYBASE/lib -lct -lcs -ltcl -lcomn -lintl -ltli -linsck $sattr{EXTRA_LIBS} -ldl -lm";

#####
### Configure End
#####

# Write a dummy makefile if CTLIBVS is 0 - this means that we don't have
# CTlibrary on this system...
if(!$CTLIBVS)
{
    open(MF, ">Makefile") || die "Can't open Makefile: $!";
    print MF "# Empty Makefile to keep make happy\n\nall:\n\nconfig:\n\ntest:\n\ninstall:\n\n";
    print MF "clean realclean:\n	mv Makefile Makefile.old\n";
    close(MF);
    exit(0);
}

WriteMakefile(
    'NAME'	=> 'Sybase::CTlib',
    'VERSION'	=> $VERSION,
    'LIBS'	=> [$lib_string],   # e.g., '-lm' 
    'DEFINE'	=> $def_string,     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> $inc_string,     # e.g., '-I/usr/include/other'
);

