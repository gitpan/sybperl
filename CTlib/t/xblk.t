# -*-Perl-*-
# $Id: xblk.t,v 1.2 2001/10/29 19:24:50 mpeppler Exp $
#
# From
# @(#)ctlib.t	1.17	03/05/98
#
# Small test script for Sybase::CTlib

BEGIN {print "1..14\n";}
END {print "not ok 1\n" unless $loaded;}
use Sybase::CTlib qw(2.01);
$loaded = 1;
print "ok 1\n";

$Version = $Sybase::CTlib::Version;

print "Sybperl Version $Version\n";

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

#ct_callback(CS_SERVERMSG_CB, \&srv_cb);
#ct_callback(CS_CLIENTMSG_CB, \&clt_cb);

( $X = Sybase::CTlib->ct_connect($Uid, $Pwd, $Srv, '', {CON_PROPS => {CS_BULK_LOGIN => CS_TRUE}}) )
    and print("ok 2\n")
    or print "not ok 2
-- The supplied login id/password combination may be invalid\n";

$X->ct_sql("create table #tmp(x numeric(9,0) identity, a1 varchar(10), i int null, n numeric(6,2), d datetime, s smalldatetime, mn money, mn1 smallmoney, img image null)");

($X->blk_init("#tmp", 9, 0, 1) == CS_SUCCEED)
    and print "ok 3\n"
    or print "not ok 3\n";

@data = ([undef, "one", 123, 123.4, 'Oct 11 2001 11:00', 'Oct 11 2001', 23.45, 44.23, 'x' x 1000],
	 [undef, "two", -1, 123.456, 'Oct 12 2001 11:23', 'Oct 11 2001', 44444444444.34, 44353.44, 'a' x 100],
	 [undef, "three", undef, 123, 'Oct 11 2001 11:00', 'Oct 11 2001', 343434.3333, 34.23, 'z' x 100]);

$i = 4;

foreach (@data) {
    ($X->blk_rowxfer($_) == CS_SUCCEED)
	and print "ok $i\n"
	    or print "not ok $i\n";
    ++$i;
}

($X->blk_done(&Sybase::CTlib::CS_BLK_ALL, $rows) == CS_SUCCEED)
    and print "ok $i\n"
    or print "not ok $i\n";

++$i;
($rows == 3) and print "ok $i\n" or print "not ok $i\n";

$X->blk_drop;

++$i;
($X->blk_init("#tmp", 9, 1, 0) == CS_SUCCEED)
    and print "ok $i\n"
    or print "not ok $i\n";

@data = ([10, "one", 123, 123.4, 'Nov 1 2001 12:00', 'Nov 1 2001', 343434.3333, 34.23, 'z' x 100],
	 [11, "two", -1, 123.456, '11/1/2001 12:00', '11/1/2001 11:21', 343434.3333, 34.23, 'z' x 100],
	 [12, "three", undef, 123, 'Nov 1 2001 12:00', 'Nov 1 2001', 343434.3333, 34.23, 'z' x 100]);

++$i;

foreach (@data) {
    ($X->blk_rowxfer($_) == CS_SUCCEED)
	and print "ok $i\n"
	    or print "not ok $i\n";
    ++$i;
}

($X->blk_done(&Sybase::CTlib::CS_BLK_ALL, $rows) == CS_SUCCEED)
    and print "ok $i\n"
    or print "not ok $i\n";

++$i;
($rows == 3) and print "ok $i\n" or print "not ok $i\n";

$X->blk_drop;

$X->ct_sql("select * from #tmp", sub { local $^W = 0; print "@_\n"; });




sub srv_cb {
    print "@_\n";

    CS_SUCCEED;
}

sub clt_cb {
    print "@_\n";

    CS_SUCCEED;
}
