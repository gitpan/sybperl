# -*-Perl-*-
# @(#)ctlib.t	1.11	10/31/95
#
# Small test script for Sybase::CTlib

print "1..29\n";

use Sybase::CTlib;

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

ct_callback(CS_CLIENTMSG_CB, \&msg_cb);
ct_callback(CS_SERVERMSG_CB, "srv_cb");

( $X = Sybase::CTlib->ct_connect($Uid, $Pwd, $Srv) )
    and print("ok 1\n")
    or die "not ok 1
-- The supplied login id/password combination may be invalid\n";

(($rc = $X->ct_execute("use master")) == CS_SUCCEED)
    and print "ok 2\n"
    or warn "not ok 2 ($rc)\n";
while(($rc = $X->ct_results($res_type)) == CS_SUCCEED)
{
    print "$res_type\n";
}


($X->ct_execute("select * from sysusers") == CS_SUCCEED)
    and print("ok 3\n")
    or die "not ok 3\n";
($X->ct_results($res_type) == CS_SUCCEED)
    and print("ok 4\n")
    or die "not ok 4\n";
($res_type == CS_ROW_RESULT)
    and print("ok 5\n")
    or die "not ok 5\n";
while(@dat = $X->ct_fetch) {
    foreach (@dat) {
	if(defined($_))	{
	    print ;
	} else {
	    print "NULL";
	}
	print " ";
    }
    print "\n";
}
($X->ct_results($res_type) == CS_SUCCEED)
    and print("ok 6\n")
    or die "not ok 6\n";
($res_type == CS_CMD_DONE)
    and print("ok 7\n")
    or die "not ok 7\n";
($X->ct_results($res_type) == CS_END_RESULTS)
    and print("ok 8\n")
    or die "not ok 8\n";

# Test the DateTime routines:

$X->ct_execute("select getdate(), crdate from master.dbo.sysdatabases where name = 'master'\n");
while($X->ct_results($restype) == CS_SUCCEED)
{
    next if(!$X->ct_fetchable($restype));
    while(($date, $crdate) = $X->ct_fetch)
    {
	(ref($date) eq 'Sybase::CTlib::DateTime')
	    and print "ok 9\n"
		or die "not ok 9\n";
	(ref($crdate) eq 'Sybase::CTlib::DateTime')
	    and print "ok 10\n"
		or die "not ok 10\n";
	
	@data = $date->crack;
	(@data == 10)
	    and print "ok 11\n"
		or die "not ok 11\n";
	("$date" eq $date->str)
	    and print "ok 12\n"
		or die "not ok 12\n";
	(($date cmp $crdate) == 1)
	    and print "ok 13\n"
		or die "not ok 13\n";
    }
}

# Test the Money routines
$money1 = $X->newmoney(4.89);
$money2 = $X->newmoney(8.56);
$money3 = $X->newmoney;
($money3 == 0)
    and print "ok 14\n"
    or print "not ok 14\n";

$money3 += 0.0001;
$money3 += 0.0001;
$money3 += 0.0001;
$money3 += 0.0001;
($money3 == 0.0004)
    and print "ok 15\n"
    or print "not ok 15\n";
(ref($money3) eq 'Sybase::CTlib::Money')
    and print "ok 16\n"
    or print "not ok 16\n";

$money3 = $money1 + $money2;
($money3 == 13.45)
    and print "ok 17\n"
    or print "not ok 17\n";

$money3 = $money1 - $money2;
($money3 == -3.67)
    and print "ok 18\n"
    or print "not ok 18\n";

$money3 /= $money2;
($money3 == -0.4287)
    and print "ok 19\n"
    or print "not ok 19\n";

$money3 = 3.53 - $money3;
($money3 == 3.9587)
    and print "ok 20\n"
    or print "not ok 20\n";

@tbal = ( 4.89, 8.92, 7.77, 11.11, 0.01 );

$money3->set(0);

(ref($money3) eq 'Sybase::CTlib::Money')
    and print "ok 21\n"
    or print "not ok 21\n";

for ( $cntr = 0 ; $cntr <= $#tbal ; $cntr++ ) {
    $money3 += $tbal[ $cntr ];
}
($money3 == 32.70)
    and print "ok 22\n"
    or print "not ok 22\n";

$cntr = $#tbal + 1;

$money3 /= $cntr;
($money3 == 6.54)
    and print "ok 23\n"
    or print "not ok 23\n";

(($money3 <=> 6.55) == -1)
    and print "ok 24\n"
    or print "not ok 24\n";
((6.55 <=> $money3) == 1)
    and print "ok 25\n"
    or print "not ok 25\n";

$num = $X->newnumeric(4.3321);
(($money3 <=> $num) == 1)
    and print "ok 26\n"
    or print "not ok 26\n";
(($num <=> $money3) == -1)
    and print "ok 27\n"
    or print "not ok 27\n";

$money = $X->newmoney(11.11);
$num = $X->newnumeric(1.111);
($num < $money)
    and print "ok 28\n"
    or print "not ok 28\n";
($money > $num)
    and print "ok 29\n"
    or print "not ok 29\n";

sub msg_cb
{
    my($layer, $origin, $severity, $number, $msg, $osmsg) = @_;

    printf STDERR "\nOpen Client Message: (In msg_cb)\n";
    printf STDERR "Message number: LAYER = (%ld) ORIGIN = (%ld) ",
	    $layer, $origin;
    printf STDERR "SEVERITY = (%ld) NUMBER = (%ld)\n",
	    $severity, $number;
    printf STDERR "Message String: %s\n", $msg;
    if (defined($osmsg))
    {
	printf STDERR "Operating System Error: %s\n",
		$osmsg;
    }
    CS_SUCCEED;
}
    
sub srv_cb
{
    my($cmd, $number, $severity, $state, $line, $server, $proc, $msg)
	= @_;

    if($severity > 10)
    {
        printf STDERR "Message number: %ld, Severity %ld, ",
	$number, $severity;
	printf STDERR "State %ld, Line %ld\n",
               $state, $line;
	       
	if (defined($server))
	{
	    printf STDERR "Server '%s'\n", $server;
	}
    
	if (defined($proc))
	{
	    printf STDERR " Procedure '%s'\n", $proc;
	}

	printf STDERR "Message String: %s\n", $msg;
    }
    elsif ($number == 0)
    {
	print STDERR $msg, "\n";
    }

    CS_SUCCEED;
}
    
