# -*-Perl-*-
# @(#)DBlib.pm	1.26	02/04/97

# Copyright (c) 1991-1997
#   Michael Peppler
#
#   You may copy this under the terms of the GNU General Public License,
#   or the Artistic License, copies of which should have accompanied
#   your Perl kit.

require 5.002;

package Sybase::DBlib::_attribs;

use Carp;


sub FETCH {
    return $_[0]->{$_[1]} if (exists $_[0]->{$_[1]});
    carp("'$_[1]' is not a valid Sybase::DBlib attribute") if(!defined($_[0]->{$_[1]}));
    return undef;
}
 
sub FIRSTKEY {
    each %{$_[0]};
}

sub NEXTKEY {
    each %{$_[0]};
}

sub EXISTS{ 
    exists($_[0]->{$_[1]});
}

sub STORE {
    if(!exists($_[0]->{$_[1]})) {
	carp("'$_[1]' is not a valid Sybase::DBlib attribute");
	return undef;
    }
    $_[0]->{$_[1]} = $_[2];
}

sub readonly {
    carp "Can't delete or clear attributes from a Sybase::DBlib handle.\n";
}

sub DELETE{ &readonly }
sub CLEAR { &readonly }


package Sybase::DBlib::Att;

use Carp;

sub TIEHASH {
    bless {
	UseDateTime => 0,
	UseMoney => 0,
#	   UseNumeric => 0,      # I don't think this can work with DBlib
	MaxRows => 0,
	dbKeepNumeric => 1,
	dbNullIsUndef => 1,
	dbBin0x => 0,
       }
}
sub FETCH { 
    return $_[0]->{$_[1]} if (exists $_[0]->{$_[1]});
    return undef;
}
 
sub FIRSTKEY {
    each %{$_[0]};
}

sub NEXTKEY {
    each %{$_[0]};
}

sub EXISTS{ 
     exists($_[0]->{$_[1]});
}

sub STORE {
    croak("'$_[1]' is not a valid Sybase::DBlib attribute") if(!exists($_[0]->{$_[1]}));
    $_[0]->{$_[1]} = $_[2];
}

sub readonly { croak "\%Sybase::DBlib::Att is read-only\n" }

sub DELETE{ &readonly }
sub CLEAR { &readonly }

package Sybase::DBlib::DateTime;

# Sybase DATETIME handling.

# For converting to Unix time:

require Time::Local;


# Here we set up overloading operators
# for certain operations.

use overload ("\"\"" => \&d_str,		# convert to string
	      "cmp" => \&d_cmp,		# compare two dates
	     "<=>" => \&d_cmp);		# same thing

sub d_str {
    my $self = shift;

    $self->str;
}

sub d_cmp {
    my ($left, $right, $order) = @_;

    $left->cmp($right, $order);
}

sub mktime {
    my $self = shift;
    my (@data, $ret);

    # Wrapped in an eval() in case POSIX is not compiled in this
    # copy of Perl.
    eval {
    require POSIX;		# This isn't very clean, but it speeds
				# up loading for something that is rarely
				# used...
    
    @data = $self->crack;

    $ret = POSIX::mktime($data[7], $data[6], $data[5], $data[2],
			 $data[1], $data[0]-1900);
    };
    $ret;
}

sub timelocal {
    my $self = shift;
    my (@data, $ret);

    @data = $self->crack;

    $ret = Time::Local::timelocal($data[7], $data[6], $data[5], $data[2],
				  $data[1], $data[0]-1900);
}

sub timegm {
    my $self = shift;
    my (@data, $ret);

    @data = $self->crack;

    $ret = Time::Local::timegm($data[7], $data[6], $data[5], $data[2],
			       $data[1], $data[0]-1900);
}

package Sybase::DBlib::Money;

# Sybase MONEY handling. Again, we set up overloading for
# certain operators (in particular the arithmetic ops.)

use overload ("\"\"" => \&m_str,		# Convert to string
	     "0+" => \&m_num,		# Convert to floating point
	     "<=>" => \&m_cmp,		# Compare two money items
	     "+" => \&m_add,		# These you can guess...
	     "-" => \&m_sub,
	     "*" => \&m_mul,
	     "/" => \&m_div);

    
sub m_str {
    my $self = shift;

    $self->str;
}

sub m_num {
    my $self = shift;

    $self->num;
}

sub m_cmp {
    my ($left, $right, $order) = @_;
    my $ret;

    $ret = $left->cmp($right, $order);
}

sub m_add {
    my ($left, $right) = @_;

    $left->calc($right, '+');
}
sub m_sub {
    my ($left, $right, $order) = @_;

    $left->calc($right, '-', $order);
}
sub m_mul {
    my ($left, $right) = @_;

    $left->calc($right, '*');
}
sub m_div {
    my ($left, $right, $order) = @_;

    $left->calc($right, '/', $order);
}

package Sybase::DBlib;

require Exporter;
require AutoLoader;
require DynaLoader;
use Carp;

use subs qw(sql SUCCEED FAIL NO_MORE_RESULTS SYBESMSG INT_CANCEL);

use vars qw(%Att);

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

tie %Att, Sybase::DBlib::Att;

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
    
    if(($ret = $self->dbsqlexec) == &SUCCEED)
    {
	$ret = $self->dbresults;
    }

    croak "dbsucceed failed\n" if($abort && $ret == &FAIL);

    $ret;
}

sub dbclose
{
    undef($_[0]);
}


sub sql				# Submitted by Gisle Aas
{
    my($db, $cmd, $sub, $flag) = @_;
    my @res;
    my @data;

    if($db->{'MaxRows'}) {
	$db->dbsetopt(&DBROWCOUNT, "$db->{'MaxRows'}");
    }

    $db->dbcmd($cmd);
    $db->dbsqlexec || return undef; # The SQL command failed

    $flag = 0 unless $flag;
    
    while($db->dbresults != &NO_MORE_RESULTS) {
        while (@data = $db->dbnextrow($flag)) {
            if (defined $sub) {
                &$sub(@data);
            } else {
		if($flag) {
		    push(@res, {@data});
		} else {
		    push(@res, [@data]);
		}
            }
        }
    }
    
    if($db->{'MaxRows'}) {
	$db->dbsetopt(&DBROWCOUNT, "0");
    }
    
    wantarray ? @res : \@res;  # return the result array
}

sub r_sql {
    my($db, $cmd, $sub) = @_;

    $db->dbcmd($cmd);
    $db->dbsqlexec || return undef; # The SQL command failed

    my @res;
    my @data;
    while($db->dbresults != &NO_MORE_RESULTS) {
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

