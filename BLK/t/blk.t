#!./perl
# $Id: blk.t,v 1.2 2001/12/13 00:06:09 mpeppler Exp $
#
# From:
#	@(#)bcp.t	1.2	03/22/96

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN {print "1..10\n";}
END {print "not ok 1\n" unless $loaded;}
use Sybase::BLK;
$loaded = 1;
print "ok 1\n";

#require 'sybutil.pl';

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

($X = new Sybase::BLK $Uid, $Pwd, $Srv)
    and print "ok 2\n"
    or print "not ok 2
-- The supplied login id/password combination may be invalid\n";

$lock = '';

($X->ct_sql("create table #bcp(f1 char(5), f2 int, f3 text, f4 varchar(10) null) $lock"))
    and print "ok 3\n"
    or print "not ok 3\n";
($X->config(INPUT => 't/blk.dat',
	    OUTPUT => '#bcp',
	    REORDER => {1 => 'f2',
			2 => 'f3',
			3 => 'f1',
		        4 => 'f4'}))
    and print "ok 4\n"
    or print "not ok 4\n";
($X->run)
    and print "ok 5\n"
    or print "not ok 5\n";

(@rows = $X->ct_sql("select * from #bcp"))
    and print "ok 6\n"
    or print "not ok 6\n";
(scalar(@rows) == 4)
    and print "ok 7\n"
    or print "not ok 7\n";
(${$rows[3]}[1] == 12)
    and print "ok 8\n"
    or print "not ok 8 (${$rows[3]}[1]\n";
(${$rows[2]}[2] =~ /\r/)
    and print "ok 9\n"
    or print "not ok 9 (${$rows[2]}[2]\n";
(!defined(${$rows[1]}[3]))
    and print "ok 10\n"
    or print "not ok 10 (${$rows[1]}[3]\n";

