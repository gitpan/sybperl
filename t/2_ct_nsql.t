#!/usr/local/bin/perl
#
# $Id: 2_ct_nsql.t,v 1.1 2003/12/25 17:16:42 mpeppler Exp $

use vars qw($Pwd $Uid $Srv);

BEGIN {print "1..4\n";}
END {print "not ok 1\n" unless $loaded;}
use Sybase::CTlib;
$loaded = 1;
print "ok 1\n";

#DBI->trace(2);

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
#DBI->trace(3);
ct_callback(CS_SERVERMSG_CB, \&Sybase::CTlib::nsql_srv_cb);
my $dbh = Sybase::CTlib->new($Uid, $Pwd, $Srv);
#exit;
$dbh and print "ok 2\n"
    or print "not ok 2\n";

my @d = $dbh->nsql("select * from sysusers", 'ARRAY');
foreach (@d) {
    local $^W = 0;
    print "@$_\n";
}
print "ok 3\n";


sub cb {
    my @data = @_;
    local $^W = 0;
    print "@data\n";

    1;
}
@d = $dbh->nsql("select * from sysusers", 'ARRAY', \&cb);
foreach (@d) {
    print "@$_\n";
}
print "ok 4\n";
