# -*-Perl-*-
# @(#)Sybperl.pm	1.18	9/18/95
#
# Copyright (c) 1994-1995
#   Michael Peppler
#
#   You may copy this under the terms of the GNU General Public License,
#   or the Artistic License, copies of which should have accompanied
#   your Perl kit.

package Sybase::Sybperl::Attribs;

sub TIESCALAR {
    my($x);
    $x = $_[1];
    $att{$x} = $_[2];

    bless \$x;
}
sub FETCH {
    my($x) = shift;
    return $att{$$x};
}
sub STORE {
    my($x) = shift;
    my($val) = shift;
    my($key);

    $att{$$x} = $val;

    foreach (keys %Sybase::Sybperl::DBprocs) {
	$key = $Sybase::Sybperl::DBprocs{$_};
	$key->{$$x} = $val;
    }
}    
    

package Sybase::Sybperl;

use Carp;
require Exporter;
require AutoLoader;
use Sybase::DBlib;

@ISA = qw(Exporter AutoLoader);

$SUCCEED = Sybase::DBlib::SUCCEED;
$FAIL = Sybase::DBlib::FAIL;
$NO_MORE_RESULTS = Sybase::DBlib::NO_MORE_RESULTS;
$NO_MORE_ROWS = Sybase::DBlib::NO_MORE_ROWS;
$MORE_ROWS = Sybase::DBlib::MORE_ROWS;
$REG_ROW = Sybase::DBlib::REG_ROW;
$DBTRUE = Sybase::DBlib::TRUE;
$DBFALSE = Sybase::DBlib::FALSE;
$DB_IN = DB_IN;
$DB_OUT = DB_OUT;

# Set defaults.
tie $dbNullIsUndef, Sybase::Sybperl::Attribs, 'dbNullIsUndef', 1;
tie $dbKeepNumeric, Sybase::Sybperl::Attribs, 'dbKeepNumeric', 1;
tie $dbBin0x, Sybase::Sybperl::Attribs, 'dbBin0x', 0;

@AttKeys = qw(dbNullIsUndef dbKeepNumeric dbBin0x);

@EXPORT = qw(dblogin dbcmd dbsqlexec dbresults dbnextrow dbstrcpy
	     dbuse dbopen dbclose
	     $SUCCEED $FAIL $NO_MORE_RESULTS $NO_MORE_ROWS
	     $MORE_ROWS $REG_ROW $DBTRUE $DBFALSE
	     $dbNullIsUndef $dbKeepNumeric $dbBin0x
	     bcp_init bcp_meminit bcp_sendrow bcp_batch bcp_done
	     bcp_control bcp_columns bcp_colfmt bcp_collen bcp_exec
	     bcp_readfmt bcp_writefmt
	     dbcancel dbcanquery dbfreebuf
	     DBCURCMD DBMORECMDS DBCMDROW DBROWS DBCOUNT dbhasretstat
	     dbretstatus dbnumcols dbcoltype dbcollen dbcolname
	     dbretdata dbsafestr
	     dbmsghandle dberrhandle dbexit dbrecftos
	     BCP_SETL bcp_getl
	     dbsetlogintime dbsettime DBGETTIME
	     DBSETLNATLANG DBSETLCHARSET dbsetversion dbversion
	     dbsetifile
	     DBLIBVS FAIL IN OUT
	     INT_CANCEL INT_CONTINUE	INT_EXIT INT_TIMEOUT
	     MORE_ROWS NO_MORE_RESULTS NO_MORE_ROWS NULL REG_ROW
	     STDEXIT SUCCEED SYBESMSG 
	     BCPBATCH BCPERRFILE BCPFIRST BCPLAST BCPMAXERRS	BCPNAMELEN
	     DBBOTH DBSINGLE DB_IN DB_OUT
	     dbmnymaxpos dbmnymaxneg dbmnyndigit dbmnyscale dbmnyinit
	     dbmnydown dbmnyinc dbmnydec dbmnyzero dbmnycmp dbmnysub
	     dbmnymul dbmnyminus dbmnydivide dbmnyadd dbmny4zero
	     dbmny4cmp dbmny4sub dbmny4mul dbmny4minus dbmny4divide
	     dbmny4add sql);


# Internal routine to check that a parameter passed as $dbproc to one
# of the Sybase::Sybperl routines is indeed a valid reference.
sub isadb
{
    my($db) = @_;
    my($ret) = 1;
    if(ref($db) ne "Sybase::DBlib")
    {
	carp("\$dbproc parameter is not valid - using default") if($^W);
	$ret = 0;
    }
    $ret;
}

sub dblogin
{
    my($x);

    ($x = Sybase::DBlib->dblogin(@_)) or return -1;

    $default_db = $x if(!defined($default_db));

    $DBprocs{$x} = $x;
    foreach (@AttKeys) {
	$x->{$_} = $Sybase::Sybperl::Attribs::att{$_};
    }
	
    $x;
}

sub dbopen
{
    my($x);

    ($x = Sybase::DBlib->dbopen(@_)) or return -1;

    $default_db = $x if(!defined($default_db));
	
    $DBprocs{$x} = $x;
    foreach (@AttKeys) {
	$x->{$_} = $Sybase::Sybperl::Attribs::att{$_};
    }

    $x;
}

sub dbclose
{
    my($dbproc) = @_;
    my($count);

    croak "&dbclose() must be called with an argument!\n"
	if(!defined($dbproc) || !&isadb($dbproc));

    delete($DBprocs{$dbproc});
    $dbproc->dbclose;
    undef($dbproc);
}

sub dbuse
{
    my(@params) = @_;
    my($dbproc);

    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    $default_db = &dblogin();
	    $DBprocs{$default_db} = $default_db;
	    foreach (@AttKeys) {
		$default_db->{$_} = $Sybase::Sybperl::Attribs::att{$_};
	    }
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $dbproc->dbuse(@params);
}

sub dbcmd
{
    my(@params) = @_;
    my($dbproc);

    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    $default_db = &dblogin();
	    $DBprocs{$default_db} = $default_db;
	    foreach (@AttKeys) {
		$default_db->{$_} = $Sybase::Sybperl::Attribs::att{$_};
	    }
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $dbproc->dbcmd(@params);
}
    
sub dbsqlexec
{
    my($dbproc) = @_;
    my($ret);

    if(!defined($dbproc) || !$dbproc || !&isadb($dbproc))
    {
	croak("It doesn't make sense to call dbsqlexec with an undefined \$dbproc") if(!defined($default_db));
	$dbproc = $default_db;
    }
    $ret = $dbproc->dbsqlexec;
    $ret;
}

sub dbresults
{
    my($dbproc) = @_;
    my($ret);

    if(!defined($dbproc) || !$dbproc || !&isadb($dbproc))
    {
	croak("It doesn't make sense to call dbresults with an undefined \$dbproc") if(!defined($default_db));
	$dbproc = $default_db;
    }
    $ret = $dbproc->dbresults;
    $ret;
}

sub dbnextrow
{
    my(@params) = @_;
    my($dbproc);
    my(@row);

    $dbproc = shift(@params);
    if(!$dbproc)
    {
	croak("dbproc is undefined.") if (!defined($default_db));
	$dbproc = $default_db;
    }
    
    @row = $dbproc->dbnextrow(@params);
    
    $main::ComputeID = $dbproc->{'ComputeID'};
    $main::DBstatus = $dbproc->{'DBstatus'};

    @row;
}

sub dbstrcpy
{
    my($dbproc) = @_;
    my($ret);

    if(!defined($dbproc) || !$dbproc || !&isadb($dbproc))
    {
	croak("It doesn't make sense to call dbstrcpy with an undefined \$dbproc") if(!defined($default_db));
	$dbproc = $default_db;
    }
    $ret = $dbproc->dbstrcpy;
    $ret;
}


# These two should really be auto-loaded, but the generated filenames
# aren't unique in the first 8 letters.'
sub dbmnymaxneg
{
    my($dbproc) = @_;
    my(@ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));

    @ret = $dbproc->dbmnymaxneg(@params);

    @ret;
}
sub dbmnymaxpos
{
    my($dbproc) = @_;
    my(@ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));

    @ret = $dbproc->dbmnymaxpos(@params);

    @ret;
}

__END__

sub dbcancel
{
    my($dbproc) = @_;
    my($ret);
    
    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));

    $ret = $dbproc->dbcancel;

    $ret;
}

sub dbcanquery
{
    my($dbproc) = @_;
    my($ret);
    
    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));

    $ret = $dbproc->dbcanquery;

    $ret;
}

sub dbfreebuf
{
    my($dbproc) = @_;
    
    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));

    $dbproc->dbfreebuf;
}

sub DBCURCMD
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->DBCURCMD;
}
sub DBMORECMDS
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->DBMORECMDS;
}
sub DBCMDROW
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->DBCMDROW;
}
sub DBROWS
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->DBROWS;
}
sub DBCOUNT
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->DBCOUNT;
}

sub dbhasretstat
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->dbhasretstat;
}
sub dbretstatus
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->dbretstatus;
}

sub dbnumcols
{
    my($dbproc) = @_;
    my($ret);

    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->dbnumcols;
}
sub dbprtype
{
    my(@params) = @_;
    my($dbproc);
    my($ret);

    $dbproc = shift(@params);
    if(!$dbproc)
    {
	croak("dbproc is undefined.") if (!defined($default_db));
	$dbproc = $default_db;
    }

    $ret = $dbproc->dbprtype(@params);
    $ret;
}
sub dbcoltype
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->dbcoltype(@params);
}
sub dbcollen
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->dbcollen(@params);
}
sub dbcolname
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->dbcolname(@params);
}

sub dbretdata
{
    my(@params) = @_;
    my($dbproc, @ret);
    
    if(@params >= 1)
    {
	$dbproc = shift(@params);
    }
    else
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    @ret = $dbproc->dbretdata(@params);
}
sub dbsafstr
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    $dbproc = shift(@params);
    $ret = $dbproc->dbsafestr(@params);
}



#####
# bcp routines
####

sub bcp_init
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 4)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->bcp_init(@params);

    $ret;
}

sub bcp_meminit
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->bcp_meminit(@params);

    $ret;
}

sub bcp_sendrow
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    $dbproc = shift(@params);

    $ret = $dbproc->bcp_sendrow(@params);

    $ret;
}

sub bcp_batch
{
    my($dbproc) = @_;
    my($ret);
    
    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->bcp_batch;
}

sub bcp_done
{
    my($dbproc) = @_;
    my($ret);
    
    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    $ret = $dbproc->bcp_done;
}

sub bcp_control
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 2)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->bcp_control(@params);

    $ret;
}

sub bcp_columns
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->bcp_columns(@params);

    $ret;
}

sub bcp_colfmt
{
    my(@params) = @_;
    my($dbproc, $ret);
    
    if(@params == 7)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	$dbproc = $default_db;
    }
    else
    {
	$dbproc = shift(@params);
    }
    $ret = $dbproc->bcp_collen(@params);

    $ret;
}

sub bcp_collen
{
    my(@params) = @_;
    my($ret);
    
    if(@params == 2)
    {
	if(!defined($default_db))
	{
	    croak("dbproc is undefined.");
	}
	unshift(@params, $default_db);
    }
    $params[0] = $default_db if(!$params[0]);
    $ret = $params[0]->bcp_collen($params[1], $params[2]);

    $ret;
}

sub bcp_exec
{
    my($dbproc) = @_;
    my(@ret);
    
    $dbproc = $default_db if(!defined($dbproc) || !&isadb($dbproc));
    @ret = $dbproc->bcp_exec;
}


sub bcp_readfmt
{
    my(@params) = @_;
    my($ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    $default_db = &dblogin();
	    $DBprocs{$default_db} = $default_db;
	    foreach (@AttKeys) {
		$default_db->{$_} = $Sybase::Sybperl::Attribs::att{$_};
	    }
	}
	unshift(@params, $default_db);
    }
    $params[0] = $default_db if(!$params[0]);
    $ret = $params[0]->bcp_readfmt($params[1]);

    $ret;
}

sub bcp_writefmt
{
    my(@params) = @_;
    my($ret);
    
    if(@params == 1)
    {
	if(!defined($default_db))
	{
	    $default_db = &dblogin();
	    $DBprocs{$default_db} = $default_db;
	    foreach (@AttKeys) {
		$default_db->{$_} = $Sybase::Sybperl::Attribs::att{$_};
	    }
	}
	unshift(@params, $default_db);
    }
    $params[0] = $default_db if(!$params[0]);
    $ret = $params[0]->bcp_writefmt($params[1]);

    $ret;
}

###
# dbmny routines:
###

sub dbmny4add
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmny4add(@params);

    @ret;
}

sub dbmny4divide
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmny4divide(@params);

    @ret;
}
sub dbmny4minus
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmny4minus(@params);

    @ret;
}
sub dbmny4mul
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmny4mul(@params);

    @ret;
}
sub dbmny4sub
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmny4sub(@params);

    @ret;
}
sub dbmny4cmp
{
    my(@params) = @_;
    my($dbproc);
    my($ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    $ret = $dbproc->dbmny4cmp(@params);

    $ret;
}
sub dbmny4zero
{
    my($dbproc) = @_;
    my(@ret);

    $dbproc = $default_db if(!defined($dbproc));

    @ret = $dbproc->dbmny4zero(@params);

    @ret;
}


sub dbmnyadd
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnyadd(@params);

    @ret;
}

sub dbmnydivide
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnydivide(@params);

    @ret;
}
sub dbmnyminus
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnyminus(@params);

    @ret;
}
sub dbmnymul
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnymul(@params);

    @ret;
}
sub dbmnysub
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnysub(@params);

    @ret;
}
sub dbmnycmp
{
    my(@params) = @_;
    my($dbproc);
    my($ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    $ret = $dbproc->dbmnycmp(@params);

    $ret;
}
sub dbmnyzero
{
    my($dbproc) = @_;
    my(@ret);

    $dbproc = $default_db if(!defined($dbproc));

    @ret = $dbproc->dbmnyzero(@params);

    @ret;
}
sub dbmnydec
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 2)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnydec(@params);

    @ret;
}
sub dbmnyinc
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 2)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnyinc(@params);

    @ret;
}
sub dbmnydown
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnydown(@params);

    @ret;
}
sub dbmnyinit
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 3)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnyinit(@params);

    @ret;
}
sub dbmnyscale
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 4)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnyscale(@params);

    @ret;
}
sub dbmnyndigit
{
    my(@params) = @_;
    my($dbproc);
    my(@ret);

    if(@params == 2)
    {
	$dbproc = shift(@params);
    }
    else
    {
	$dbproc = $default_db;
    }

    @ret = $dbproc->dbmnyndigit(@params);

    @ret;
}

sub sql
{
    my($db,$sql,$sep)=@_;			# local copy parameters
    my(@res, @data);

    $sep = '~' unless $sep;			# provide default for sep

    @res = ();					# clear result array

    $db->dbcmd($sql);				# pass sql to server
    $db->dbsqlexec;				# execute sql

    while($db->dbresults != NO_MORE_RESULTS) {	# copy all results
	while (@data = $db->dbnextrow) {
	    push(@res,join($sep,@data));
	}
    }

    @res;					# return the result array
}


1;
