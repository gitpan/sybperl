# -*-Perl-*-
# @(#)DBlib.pm	1.19	1/5/96

# Copyright (c) 1991-1995
#   Michael Peppler
#
#   You may copy this under the terms of the GNU General Public License,
#   or the Artistic License, copies of which should have accompanied
#   your Perl kit.


package Sybase::DBlib;

require 5.000;

require Exporter;
require AutoLoader;
require DynaLoader;
use Carp;

# This does not work with 5.001 (produces a lot of 'subroutine redefined'
# warnings...
if($] >= 5.002) {
    eval '
use subs qw(SUCCEED FAIL NO_MORE_RESULTS);
'
}

@ISA = qw(Exporter AutoLoader DynaLoader);

@EXPORT = qw( dbmsghandle dberrhandle dbrecftos dbexit
	     BCP_SETL bcp_getl
	     dbsetlogintime dbsettime DBGETTIME
	     DBSETLNATLANG DBSETLCHARSET dbsetversion dbversion
	     dbsetifile dbrpwclr dbrpwset
	     DBLIBVS  FAIL 
	     INT_CANCEL INT_CONTINUE INT_EXIT INT_TIMEOUT
	     MORE_ROWS NO_MORE_RESULTS NO_MORE_ROWS NULL REG_ROW
	     STDEXIT SUCCEED SYBESMSG 
	     BCPBATCH BCPERRFILE BCPFIRST BCPLAST BCPMAXERRS	BCPNAMELEN
	     DBBOTH DBSINGLE DB_IN DB_OUT
	     TRUE FALSE
	     DBARITHABORT DBARITHIGNORE DBBUFFER DBBUFSIZE DBDATEFORMAT
	     DBNATLANG DBNOAUTOFREE DBNOCOUNT DBNOEXEC DBNUMOPTIONS
	     DBOFFSET DBROWCOUNT DBSHOWPLAN DBSTAT DBSTORPROCID
	     DBTEXTLIMIT DBTEXTSIZE DBTXPLEN DBTXTSLEN
	     NOSUCHOPTION
	     SYBBINARY SYBBIT SYBCHAR SYBDATETIME SYBDATETIME4
	     SYBFLT8 SYBIMAGE SYBINT1 SYBINT2 SYBINT4 SYBMONEY
	     SYBMONEY4 SYBREAL SYBTEXT SYBVARBINARY SYBVARCHAR
	     DBRPCRETURN DBRPCNORETURN DBRPCRECOMPILE
	     );

@EXPORT_OK = qw(ERREXIT EXCEPTION EXCLIPBOARD EXCOMM EXCONSISTENCY EXCONVERSION
	EXDBLIB EXECDONE EXFATAL EXFORMS EXINFO EXLOOKUP EXNONFATAL EXPROGRAM
	EXRESOURCE EXSCREENIO EXSERVER EXSIGNAL	EXTIME EXUSER
	SYBEAAMT SYBEABMT SYBEABNC SYBEABNP SYBEABNV SYBEACNV SYBEADST SYBEAICF
	SYBEALTT SYBEAOLF SYBEAPCT SYBEAPUT SYBEARDI SYBEARDL SYBEASEC SYBEASNL
	SYBEASTF SYBEASTL SYBEASUL SYBEAUTN SYBEBADPK SYBEBBCI SYBEBCBC
	SYBEBCFO SYBEBCIS SYBEBCIT SYBEBCNL SYBEBCNN SYBEBCNT SYBEBCOR SYBEBCPB
	SYBEBCPI SYBEBCPN SYBEBCRE SYBEBCRO SYBEBCSA SYBEBCSI SYBEBCUC SYBEBCUO
	SYBEBCVH SYBEBCWE SYBEBDIO SYBEBEOF SYBEBIHC SYBEBIVI SYBEBNCR SYBEBPKS
	SYBEBRFF SYBEBTMT SYBEBTOK SYBEBTYP SYBEBUCE SYBEBUCF SYBEBUDF SYBEBUFF
	SYBEBUFL SYBEBUOE SYBEBUOF SYBEBWEF SYBEBWFF SYBECDNS SYBECLOS
	SYBECLOSEIN SYBECLPR SYBECNOR SYBECNOV SYBECOFL SYBECONN SYBECRNC
	SYBECSYN SYBECUFL SYBECWLL SYBEDBPS SYBEDDNE SYBEDIVZ SYBEDNTI SYBEDPOR
	SYBEDVOR SYBEECAN SYBEECRT SYBEEINI SYBEEQVA SYBEESSL SYBEETD SYBEEUNR
	SYBEEVOP SYBEEVST SYBEFCON SYBEFGTL SYBEFMODE SYBEFSHD SYBEGENOS
	SYBEICN SYBEIDCL SYBEIFCL SYBEIFNB SYBEIICL SYBEIMCL SYBEINLN SYBEINTF
	SYBEIPV SYBEISOI SYBEITIM SYBEKBCI SYBEKBCO SYBEMEM SYBEMOV SYBEMPLL
	SYBEMVOR SYBENBUF SYBENBVP SYBENDC SYBENDTP SYBENEHA SYBENHAN SYBENLNL
	SYBENMOB SYBENOEV SYBENOTI SYBENPRM SYBENSIP SYBENTLL SYBENTST SYBENTTN
	SYBENULL SYBENULP SYBENUM SYBENXID SYBEOOB SYBEOPIN SYBEOPNA SYBEOPTNO
	SYBEOREN SYBEORPF SYBEOSSL SYBEPAGE SYBEPOLL SYBEPRTF SYBEPWD SYBERDCN
	SYBERDNR SYBEREAD SYBERFILE SYBERPCS SYBERPIL SYBERPNA SYBERPND
	SYBERPUL SYBERTCC SYBERTSC SYBERTYPE SYBERXID SYBESEFA SYBESEOF
	SYBESFOV SYBESLCT SYBESOCK SYBESPID SYBESYNC SYBETEXS
	SYBETIME SYBETMCF SYBETMTD SYBETPAR SYBETPTN SYBETRAC SYBETRAN
	SYBETRAS SYBETRSN SYBETSIT SYBETTS SYBETYPE SYBEUACS SYBEUAVE SYBEUCPT
	SYBEUCRR SYBEUDTY SYBEUFDS SYBEUFDT SYBEUHST SYBEUNAM SYBEUNOP SYBEUNT
	SYBEURCI SYBEUREI SYBEUREM SYBEURES SYBEURMI SYBEUSCT SYBEUTDS SYBEUVBF
	SYBEUVDT SYBEVDPT SYBEVMS SYBEVOIDRET SYBEWAID SYBEWRIT SYBEXOCI
	SYBEXTDN SYBEXTN SYBEXTSN SYBEZTXT
);

sub AUTOLOAD {
    local($constname);
    ($constname = $AUTOLOAD) =~ s/.*:://;
    $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($! =~ /Invalid/) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
	    ($pack,$file,$line) = caller;
	    die "Your vendor has not defined Sybase::DBlib macro $constname, used at $file line $line ($pack).
";
	}
    }
    eval "sub $AUTOLOAD { $val }";
    goto &$AUTOLOAD;
}

bootstrap Sybase::DBlib;

# Preloaded methods go here.  Autoload methods go after __END__, and are
# processed by the autosplit program.

# Alias dblogin to new:
*new = \&dblogin;


1;
__END__

sub dbsucceed
{
    my($self) = shift;
    my($abort) = shift;
    my($ret);
    
    if(($ret = $self->dbsqlexec) == SUCCEED)
    {
	$ret = $self->dbresults;
    }

    croak "dbsucceed failed\n" if($abort && $ret == FAIL);

    $ret;
}

sub dbclose
{
    undef($_[0]);
}


sub sql				# Submitted by Gisle Aas
{
    my($db, $cmd, $sub) = @_;

    $db->dbcmd($cmd);
    $db->dbsqlexec || return undef; # The SQL command failed

    my @res;
    my @data;
    while($db->dbresults != NO_MORE_RESULTS) {
        while (@data = $db->dbnextrow) {
            if (defined $sub) {
                &$sub(@data);
            } else {
                push(@res, [@data]);
            }
        }
    }
    wantarray ? @res : \@res;  # return the result array
}

sub r_sql {
    my($db, $cmd, $sub) = @_;

    $db->dbcmd($cmd);
    $db->dbsqlexec || return undef; # The SQL command failed

    my @res;
    my @data;
    while($db->dbresults != NO_MORE_RESULTS) {
        while (@data = $db->dbnextrow) {
            if (defined $sub) {
                &$sub(@data);
            } else {
                push(@res, [@data]);
            }
        }
    }
    @res;  # return the result array
}

