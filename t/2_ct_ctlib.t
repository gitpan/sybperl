# -*-Perl-*-
# $Id: 2_ct_ctlib.t,v 1.1 2003/12/25 17:16:42 mpeppler Exp $
#
# From
# @(#)ctlib.t	1.17	03/05/98
#
# Small test script for Sybase::CTlib

BEGIN {print "1..30\n";}
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
$Sybase::CTlib::Att{UseDateTime} = CS_TRUE;
$Sybase::CTlib::Att{UseMoney} = CS_TRUE;

ct_callback(CS_CLIENTMSG_CB, \&msg_cb);
ct_callback(CS_SERVERMSG_CB, \&srv_cb);

( $X = Sybase::CTlib->ct_connect($Uid, $Pwd, $Srv, '', {LastError => 0}) )
    and print("ok 2\n")
    or print "not ok 2
-- The supplied login id/password combination may be invalid\n";


(($rc = $X->ct_execute("use master")) == CS_SUCCEED)
    and print "ok 3\n"
    or print "not ok 3\n";


$res_type = 0;
while(($rc = $X->ct_results($res_type)) == CS_SUCCEED)
{
    print "$res_type\n";
}

($X->{LastError} == 5701) or warn "Wrong last error ($X->{LastError})";

($X->ct_execute("select * from sysusers") == CS_SUCCEED)
    and print("ok 4\n")
    or print "not ok 4\n";
($X->ct_results($res_type) == CS_SUCCEED)
    and print("ok 5\n")
    or print "not ok 5\n";
($res_type == CS_ROW_RESULT)
    and print("ok 6\n")
    or print "not ok 6\n";
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
    and print("ok 7\n")
    or print "not ok 7\n";
($res_type == CS_CMD_DONE)
    and print("ok 8\n")
    or print "not ok 8\n";
($X->ct_results($res_type) == CS_END_RESULTS)
    and print("ok 9\n")
    or print "not ok 9\n";

# Test the DateTime routines:

$X->ct_execute("select getdate(), crdate from master.dbo.sysdatabases where name = 'master'\n");
while($X->ct_results($res_type) == CS_SUCCEED)
{
    next if(!$X->ct_fetchable($res_type));
    while(($date, $crdate) = $X->ct_fetch)
    {
	(ref($date) eq 'Sybase::CTlib::DateTime')
	    and print "ok 10\n"
		or print "not ok 10\n";
	(ref($crdate) eq 'Sybase::CTlib::DateTime')
	    and print "ok 11\n"
		or print "not ok 11\n";
	
	@data = $date->crack;
	(@data == 10)
	    and print "ok 12\n"
		or print "not ok 12\n";
	("$date" eq $date->str)
	    and print "ok 13\n"
		or print "not ok 13\n";
	(($date cmp $crdate) == 1)
	    and print "ok 14\n"
		or print "not ok 14\n";
    }
}

# Test the Money routines
$money1 = $X->newmoney(4.89);
$money2 = $X->newmoney(8.56);
$money3 = $X->newmoney;
($money3 == 0)
    and print "ok 15\n"
    or print "not ok 15\n";

$money3 += 0.0001;
$money3 += 0.0001;
$money3 += 0.0001;
$money3 += 0.0001;
($money3 == 0.0004)
    and print "ok 16\n"
    or print "not ok 16\n";
(ref($money3) eq 'Sybase::CTlib::Money')
    and print "ok 17\n"
    or print "not ok 17\n";

$money3 = $money1 + $money2;
($money3 == 13.45)
    and print "ok 18\n"
    or print "not ok 18\n";

$money3 = $money1 - $money2;
($money3 == -3.67)
    and print "ok 19\n"
    or print "not ok 19\n";

$money3 /= $money2;
($money3 == -0.4287)
    and print "ok 20\n"
    or print "not ok 20\n";

$money3 = 3.53 - $money3;
($money3 == 3.9587)
    and print "ok 21\n"
    or print "not ok 21\n";

@tbal = ( 4.89, 8.92, 7.77, 11.11, 0.01 );

if(ref($money3) eq 'Sybase::CTlib::Money') {
    $money3->set(0);
} else {
    $money3 = 0;
}

(ref($money3) eq 'Sybase::CTlib::Money')
    and print "ok 22\n"
    or print "not ok 2\n";

for ( $cntr = 0 ; $cntr <= $#tbal ; $cntr++ ) {
    $money3 += $tbal[ $cntr ];
}
($money3 == 32.70)
    and print "ok 23\n"
    or print "not ok 23\n";

$cntr = $#tbal + 1;

$money3 /= $cntr;
($money3 == 6.54)
    and print "ok 24\n"
    or print "not ok 24\n";

(($money3 <=> 6.55) == -1)
    and print "ok 25\n"
    or print "not ok 2\n";
((6.55 <=> $money3) == 1)
    and print "ok 26\n"
    or print "not ok 26\n";

$num = $X->newnumeric(4.3321);
(($money3 <=> $num) == 1)
    and print "ok 27\n"
    or print "not ok 27\n";
(($num <=> $money3) == -1)
    and print "ok 28\n"
    or print "not ok 28\n";

$money = $X->newmoney(11.11);
$num = $X->newnumeric(1.111);
($num < $money)
    and print "ok 29\n"
    or print "not ok 29\n";
($money > $num)
    and print "ok 30\n"
    or print "not ok 30\n";

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

#    warn ("srv_cb: @_");
    if(defined($cmd)) {
	$cmd->{LastError} = $number;
    }

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
    
