# @(#)ctutil.pl	1.1	10/18/95
#
# Copyright (c) 1995
#   Michael Peppler
#
#   You may copy this under the terms of the GNU General Public License,
#   or the Artistic License, copies of which should have accompanied
#   your Perl kit.

#
# Some utility stuff for Sybase::CTlib
#

sub msg_cb
{
    my($layer, $origin, $severity, $number, $msg, $osmsg) = @_;

    printf STDERR "\nOpen Client Message:\n";
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

    # Don't print informational or status messages
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
    

ct_callback(CS_CLIENTMSG_CB, \&msg_cb);
ct_callback(CS_SERVERMSG_CB, \&srv_cb);

1;
