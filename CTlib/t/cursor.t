#!./perl

#	@(#)cursor.t	1.3	03/15/96

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN {print "1..22\n";}
END {print "not ok 1\n" unless $loaded;}
use Sybase::CTlib;
$loaded = 1;
print "ok 1\n";

require 'ctutil.pl';

######################### End of black magic.

# Find the passwd file:
@dirs = ('./.', './..', './../..', './../../..');
foreach (@dirs)
{
    if(-f "$_/PWD")
    {
	open(PWD, "$_/PWD") || die "$_/PWD is not readable: $!\n";
	while(<PWD>)
	{
	    chop;
	    s/^\s*//;
	    next if(/^\#/ || /^\s*$/);
	    ($l, $r) = split(/=/);
	    $Uid = $r if($l eq UID);
	    $Pwd = $r if($l eq PWD);
	    $Srv = $r if($l eq SRV);
	}
	close(PWD);
	last;
    }
}

($d = new Sybase::CTlib $Uid, $Pwd, $Srv)
    and print "ok 2\n"
    or die "not ok 2
-- The user id/password combination may be invalid.\n";

# Cursors are not avialable on 4.x servers:
@version = $d->ct_sql("select \@\@version");
@in = split(/\//, ${$version[0]}[0]);
($ver, @in) = split(/\./, $in[1], 2);
if($ver < 10.0) {
    my $i;
    print STDERR "Cursors are not available on this SQL Server.\n";
    for($i = 3; $i <= 22; ++$i){
	print "ok $i\n";
    }
    exit(0);
}

($d2 = $d->ct_cmd_alloc)
    and print "ok 3\n"
    or print "not ok 3\n";

($d->ct_cursor(CS_CURSOR_DECLARE, 'first_cursor',
	       'select * from master.dbo.sysprocesses',
	       CS_READ_ONLY) == CS_SUCCEED)
    and print "ok 4\n"
    or print "not ok 4\n";
($d->ct_cursor(CS_CURSOR_ROWS, undef, undef, 5) == CS_SUCCEED)
    and print "ok 5\n"
    or print "not ok 5\n";
($d->ct_send == CS_SUCCEED)
    and print "ok 6\n"
    or print "not ok 6\n";
while($d->ct_results($restype) == CS_SUCCEED) {}
($d2->ct_cursor(CS_CURSOR_DECLARE, "second_cursor",
		'select * from sysusers',
		CS_READ_ONLY) == CS_SUCCEED)
    and print "ok 7\n"
    or print "not ok 7\n";
($d2->ct_cursor(CS_CURSOR_ROWS, undef, undef, 2) == CS_SUCCEED)
    and print "ok 8\n"
    or print "not ok 8\n";
($d2->ct_send == CS_SUCCEED)
    and print "ok 9\n"
    or print "not ok 9\n";
while($d2->ct_results($restype) == CS_SUCCEED) {}

($d->ct_cursor(CS_CURSOR_OPEN, undef, undef, CS_UNUSED) == CS_SUCCEED)
    and print "ok 10\n"
    or print "not ok 10\n";
($d->ct_send == CS_SUCCEED)
    and print "ok 11\n"
    or print "not ok 11\n";
($d->ct_results($restype) == CS_SUCCEED)
    and print "ok 12\n"
    or print "not ok 12\n";
($restype == CS_CURSOR_RESULT)
    and print "ok 13\n"
    or print "not ok 13\n";

($d2->ct_cursor(CS_CURSOR_OPEN, undef, undef, CS_UNUSED) == CS_SUCCEED)
    and print "ok 14\n"
    or print "not ok 14\n";
($d2->ct_send == CS_SUCCEED)
    and print "ok 15\n"
    or print "not ok 15\n";
($d2->ct_results($restype) == CS_SUCCEED)
    and print "ok 16\n"
    or print "not ok 16\n";
($restype == CS_CURSOR_RESULT)
    and print "ok 17\n"
    or print "not ok 17\n";

$last = 1;
while($d->ct_fetch(CS_TRUE)) {
    %dat2 = $d2->ct_fetch(CS_TRUE) if($last);
    $last = 0 unless(%dat2);
}
if($last) {
    while($d2->ct_fetch()) {}
}
print "ok 18\n";

while($d->ct_results($restype)==CS_SUCCEED){}
while($d2->ct_results($restype)==CS_SUCCEED){}

($d->ct_cursor(CS_CURSOR_CLOSE, undef, undef, CS_DEALLOC) == CS_SUCCEED)
    and print "ok 19\n"
    or print "not ok 19\n";
($d->ct_send == CS_SUCCEED)
    and print "ok 20\n"
    or print "not ok 20\n";
while($d->ct_results($restype) == CS_SUCCEED) {}

($d2->ct_cursor(CS_CURSOR_CLOSE, undef, undef, CS_DEALLOC) == CS_SUCCEED)
    and print "ok 21\n"
    or print "not ok 21\n";
($d2->ct_send == CS_SUCCEED)
    and print "ok 22\n"
    or print "not ok 22\n";
while($d2->ct_results($restype) == CS_SUCCEED) {}
