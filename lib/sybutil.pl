# @(#)sybutil.pl	1.4	5/3/95
#
# Copyright (c) 1994
#   Michael Peppler and ITF Management SA
#
#   You may copy this under the terms of the GNU General Public License,
#   or the Artistic License, copies of which should have accompanied
#   your Perl kit.

#
# A couple of utility stuff for both Sybase::DBlib and Sybase::Sybperl
#


sub message_handler
{
    my ($db, $message, $state, $severity, $text, $server, $procedure, $line)
	= @_;

    if ($severity > 0)
    {
	print STDERR ("Sybase message ", $message, ", Severity ", $severity,
	       ", state ", $state);
	print STDERR ("\nServer `", $server, "'") if defined ($server);
	print STDERR ("\nProcedure `", $procedure, "'") if defined ($procedure);
	print STDERR ("\nLine ", $line) if defined ($line);
	print STDERR ("\n    ", $text, "\n\n");

# &dbstrcpy returns the command buffer.

	if(defined($db))
	{
	    my ($lineno, $cmdbuff) = (1, undef);

	    $cmdbuff = &Sybase::DBlib::dbstrcpy($db);
	       
	    foreach $row (split (/\n/, $cmdbuff))
	    {
		print STDERR (sprintf ("%5d", $lineno ++), "> ", $row, "\n");
	    }
	}
    }
    elsif ($message == 0)
    {
	print STDERR ($text, "\n");
    }
    
    0;
}

sub error_handler {
    my ($db, $severity, $error, $os_error, $error_msg, $os_error_msg)
	= @_;
    # Check the error code to see if we should report this.
    if ($error != SYBESMSG) {
	print STDERR ("Sybase error: ", $error_msg, "\n");
	print STDERR ("OS Error: ", $os_error_msg, "\n") if defined ($os_error_msg);
    }

    INT_CANCEL;
}

&dbmsghandle ("message_handler");
&dberrhandle ("error_handler");

1;
