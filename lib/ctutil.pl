# @(#)ctutil.pl	1.2	1/30/96
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

use Carp;

sub msg_cb
{
    my($layer, $origin, $severity, $number, $msg, $osmsg) = @_;
    my($string);

    $string = "\nOpen Client Message:\n";
    $string .= sprintf("Message number: LAYER = (%ld) ORIGIN = (%ld) ",
		       $layer, $origin);
    $string .= sprintf("SEVERITY = (%ld) NUMBER = (%ld)\n",
		       $severity, $number);
    $string .= "Message String: $msg\n";
    if (defined($osmsg))
    {
	$string .= sprintf("Operating System Error: %s\n",
			   $osmsg);
    }
    carp($string) if $string;
    CS_SUCCEED;
}
    
sub srv_cb
{
    my($cmd, $number, $severity, $state, $line, $server, $proc, $msg)
	= @_;
    my($string);

    # Don't print informational or status messages
    if($severity > 10)
    {
        $string = sprintf("Message number: %ld, Severity %ld, ",
			  $number, $severity);
	$string .= sprintf("State %ld, Line %ld\n",
			   $state, $line);
	       
	if (defined($server))
	{
	    $string .= sprintf("Server '%s'\n", $server);
	}
    
	if (defined($proc))
	{
	    $string .= sprintf(" Procedure '%s'\n", $proc);
	}

	$string .= "Message String: $msg\n";
    }
    elsif ($number == 0)
    {
	$string = "$msg\n";
    }
    carp($string) if $string;

    CS_SUCCEED;
}
    

ct_callback(CS_CLIENTMSG_CB, \&msg_cb);
ct_callback(CS_SERVERMSG_CB, \&srv_cb);

1;
