# -*-Perl-*-
# @(#)ctlib.t	1.4	0
#
# Small test script for Sybase::CTlib

print "1..8\n";

use Sybase::CTlib;

# Find the passwd file:
@dirs = ('./..', './../..', './../../..');
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

    if($severity > 0)
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
    
