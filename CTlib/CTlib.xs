/* -*-C-*-
 *	@(#)CTlib.xs	1.10	9/21/95
 */

/* Copyright (c) 1995
   Michael Peppler

   Parts of this file are
   Copyright (c) 1995 Sybase, Inc.

   You may copy this under the terms of the GNU General Public License,
   or the Artistic License, copies of which should have accompanied
   your Perl kit. */

   
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ctpublic.h>

#define CTLIB_VERSION	CS_VERSION_100
#ifndef MAX
#define MAX(X,Y)	(((X) > (Y)) ? (X) : (Y))
#endif

#ifndef MIN
#define MIN(X,Y)	(((X) < (Y)) ? (X) : (Y))
#endif

/*
** Maximum character buffer for displaying a column
*/
#define MAX_CHAR_BUF	1024


typedef struct column_data
{
    CS_SMALLINT	indicator;
    CS_INT	type;
    union {
	CS_CHAR	*c;
	CS_INT i;
	CS_FLOAT f;
    } value;
    CS_INT	valuelen;
} ColData;

typedef enum
{
    CON_CONNECTION,
    CON_CMD,
    CON_EED_CMD,
} ConType;

#if 0
struct ParamInfo
{
    int type;
    union {
	CS_INT i;
	CS_FLOAT f;
	CS_CHAR *c;
    } u;
    int size;
    void *value;
    struct ParamInfo *next;
};
#endif
    
typedef struct conInfo
{
    ConType type;
    int numCols;
    
    ColData *coldata;
    CS_DATAFMT *datafmt;
    CS_CONNECTION *connection;
    CS_COMMAND *cmd;
    CS_INT lastResult;
#if 0
    struct ParamInfo *paramHead;
#endif
} ConInfo;

typedef struct
{
    SV *	sub ;
} CallBackInfo ;

static CallBackInfo server_cb 	= { 0 } ;
static CallBackInfo client_cb 	= { 0 } ;

typedef enum hash_key_id
{
    HV_coninfo,
    HV_compute_id,
} hash_key_id;

static char *hash_keys[] =
{ "__coninfo__", "ComputeId",};

static CS_CONTEXT *context;


static SV
**my_hv_fetch(hv, id, flag)
    HV *hv;
    hash_key_id id;
    int flag;
{
    return hv_fetch(hv, hash_keys[id], strlen(hash_keys[id]), flag);
}

static SV
**my_hv_store(hv, id, sv, flag)
    HV *hv;
    hash_key_id id;
    SV *sv;
    int flag;
{
    return hv_store(hv, hash_keys[id], strlen(hash_keys[id]), sv, flag);
}

static ConInfo
*get_ConInfo(dbp)
    SV *dbp;
{
    HV *hv;
    SV **svp;
    ConInfo *info;
    
    if(!SvROK(dbp))
	croak("connection parameter is not a reference");
    hv = (HV *)SvRV(dbp);
    if(!(svp = my_hv_fetch(hv, HV_coninfo, FALSE)))
	croak("no connection key in hash");
    info = (void *)SvIV(*svp);

    return info;
}

    
static CS_CONNECTION
*get_con(dbp)
    SV *dbp;
{
    ConInfo *info = get_ConInfo(dbp);

    return info->connection;
}

static CS_COMMAND
*get_cmd(dbp)
    SV *dbp;
{
    ConInfo *info = get_ConInfo(dbp);

    return info->cmd;
}

static void
cleanUp(info)
    ConInfo *info;
{
    int i;
    for(i = 0; i < info->numCols; ++i)
	if(info->coldata[i].type == CS_CHAR_TYPE)
	    Safefree(info->coldata[i].value.c);
    
    if(info->datafmt)
	Safefree(info->datafmt);
    if(info->coldata)
	Safefree(info->coldata);
#if 0
    if(info->paramHead)
    {
	struct ParamInfo *ptr, *next;
	for(ptr = info->paramHead; ptr; ptr = next)
	{
	    next = ptr;
	    if(ptr->type == CS_CHAR_TYPE)
		Safefree(ptr->u.c);
	    Safefree(ptr);
	}
	info->paramHead = NULL;
    }
#endif
    info->numCols = 0;
    info->coldata = NULL;
    info->datafmt = NULL;
}

static CS_CHAR * 
GetAggOp(op)
CS_INT op;
{
    CS_CHAR *name;

    switch ((int)op)
    {
      case CS_OP_SUM:
	name = "sum";
	break;
      case CS_OP_AVG:
	name = "avg";
	break;
      case CS_OP_COUNT:
	name = "count";
	break;
      case CS_OP_MIN:
	name = "min";
	break;
      case CS_OP_MAX:
	name = "max";
	break;
      default:
	name = "unknown";
	break;
    }
    return name;
}

static CS_INT
display_dlen(column)
CS_DATAFMT *column;
{
    CS_INT		len;

    switch ((int) column->datatype)
    {
      case CS_CHAR_TYPE:
      case CS_VARCHAR_TYPE:
      case CS_TEXT_TYPE:
      case CS_IMAGE_TYPE:
	len = MIN(column->maxlength, MAX_CHAR_BUF);
	break;

      case CS_BINARY_TYPE:
      case CS_VARBINARY_TYPE:
	len = MIN((2 * column->maxlength) + 2, MAX_CHAR_BUF);
	break;
	
      case CS_BIT_TYPE:
      case CS_TINYINT_TYPE:
	len = 3;
	break;
	
      case CS_SMALLINT_TYPE:
	len = 6;
	break;
	
      case CS_INT_TYPE:
	len = 11;
	break;
	
      case CS_REAL_TYPE:
      case CS_FLOAT_TYPE:
	len = 20;
	break;
	
      case CS_MONEY_TYPE:
      case CS_MONEY4_TYPE:
	len = 24;
	break;
	
      case CS_DATETIME_TYPE:
      case CS_DATETIME4_TYPE:
	len = 30;
	break;
	
      case CS_NUMERIC_TYPE:
      case CS_DECIMAL_TYPE:
	len = (CS_MAX_PREC + 2);
	break;
	
      default:
	len = column->maxlength;
	break;
    }
    
    return MAX(strlen(column->name) + 1, len);
}

static CS_RETCODE
display_header(numcols, columns)
CS_INT		numcols;
CS_DATAFMT	columns[];
{
    CS_INT		i;
    CS_INT		l;
    CS_INT		j;
    CS_INT		disp_len;

    fputc('\n', stdout);
    for (i = 0; i < numcols; i++)
    {
	disp_len = display_dlen(&columns[i]);
	fprintf(stdout, "%s", columns[i].name);
	fflush(stdout);
	l = disp_len - strlen(columns[i].name);
	for (j = 0; j < l; j++)
	{
	    fputc(' ', stdout);
	    fflush(stdout);
	}
    }
    fputc('\n', stdout);
    fflush(stdout);
    for (i = 0; i < numcols; i++)
    {
	disp_len = display_dlen(&columns[i]);
	l = disp_len - 1;
	for (j = 0; j < l; j++)
	{
	    fputc('-', stdout);
	}
	fputc(' ', stdout);
    }
    fputc('\n', stdout);
    
    return CS_SUCCEED;
}
#if 0
static CS_RETCODE
display_column(context, colfmt, data, datalength, indicator)
CS_CONTEXT	*context;
CS_DATAFMT	*colfmt;
CS_VOID 	*data;
CS_INT		datalength;
CS_SMALLINT	indicator;
{
    char		*null = "NULL";
    char		*nc   = "NO CONVERT";
    char		*cf   = "CONVERT FAILED";
    CS_DATAFMT	srcfmt;
    CS_DATAFMT	destfmt;
    CS_INT		olen;
    CS_CHAR		wbuf[MAX_CHAR_BUF];
    CS_BOOL		res;
    CS_INT		i;
    CS_INT		disp_len;

    if (indicator == CS_NULLDATA)
    {
	olen = strlen(null);
	strcpy(wbuf, null);
    }
    else
    {
	cs_will_convert(context, colfmt->datatype, CS_CHAR_TYPE, &res);
	if (res != CS_TRUE)
	{
	    olen = strlen(nc);
	    strcpy(wbuf, nc);
	}
	else
	{
	    srcfmt.datatype  = colfmt->datatype;
	    srcfmt.format    = colfmt->format;
	    srcfmt.locale    = colfmt->locale;
	    srcfmt.maxlength = datalength;
	    
	    memset(&destfmt, 0, sizeof(destfmt));
	    
	    destfmt.maxlength = MAX_CHAR_BUF;
	    destfmt.datatype  = CS_CHAR_TYPE;
	    destfmt.format    = CS_FMT_NULLTERM;
	    destfmt.locale    = NULL;
	    
	    if (cs_convert(context, &srcfmt, data, &destfmt,
			   wbuf, &olen) != CS_SUCCEED)
	    {
		olen = strlen(cf);
		strcpy(wbuf, cf);
	    }
	    else
	    {
		/*
		 ** output length include null
		 ** termination
		 */
		olen -= 1;
	    }
	}
    }
    fprintf(stdout, "%s", wbuf);
    fflush(stdout);
    
    disp_len = display_dlen(colfmt);
    for (i = 0; i < (disp_len - olen); i++)
    {
	fputc(' ', stdout);
    }
    fflush(stdout);
	
    return CS_SUCCEED;
}
#endif

static CS_RETCODE
describe(info, dbp, restype)
    ConInfo *info;
    SV *dbp;
    int restype;
{
    CS_RETCODE retcode;
    int i;
    
    if((retcode = ct_res_info(info->cmd, CS_NUMDATA,
			      &info->numCols, CS_UNUSED, NULL)) != CS_SUCCEED)
    {
	warn("ct_res_info() failed");
	goto GoodBye;
    }
    if(info->numCols <= 0)
    {
	warn("ct_res_info() returned 0 columns");
	info->numCols = 0;
	goto GoodBye;
    }
    New(902, info->coldata, info->numCols, ColData);
    New(902, info->datafmt, info->numCols, CS_DATAFMT);
    
    /* this routine may be called without the connection reference */
    if(dbp)
    {
	HV *hv;
	if(!SvROK(dbp))
	    croak("connection parameter is not a reference");
	hv = (HV *)SvRV(dbp);
	if(restype == CS_COMPUTE_RESULT)
	{
	    CS_INT comp_id, outlen;
    
	    if((retcode = ct_compute_info(info->cmd, CS_COMP_ID, CS_UNUSED,
					  &comp_id, CS_UNUSED, &outlen)) != CS_SUCCEED)
	    {
		warn("ct_compute_info failed");
		goto GoodBye;
	    }
	    my_hv_store(hv, HV_compute_id, (SV*)newSViv(comp_id), 0);
	}
	else
	    my_hv_store(hv, HV_compute_id, (SV*)newSViv(0), 0);
    }

    for(i = 0; i < info->numCols; ++i)
    {
	if((retcode = ct_describe(info->cmd, (i + 1),
				  &info->datafmt[i])) != CS_SUCCEED)
	{
	    warn("ct_describe() failed");
	    cleanUp(info);
	    goto GoodBye;
	}
	/* Make sure we have at least some sort of column name: */
	if(info->datafmt[i].namelen == 0)
	    sprintf(info->datafmt[i].name, "COL(%d)", i+1);
	if(restype == CS_COMPUTE_RESULT)
	{
	    CS_INT agg_op, outlen;
	    CS_CHAR *agg_op_name;
	    
	    if((retcode = ct_compute_info(info->cmd, CS_COMP_OP, (i + 1),
					  &agg_op, CS_UNUSED, &outlen)) != CS_SUCCEED)
	    {
		warn("ct_compute_info failed");
		goto GoodBye;
	    }
	    agg_op_name = GetAggOp(agg_op);
	    if((retcode = ct_compute_info(info->cmd, CS_COMP_COLID, (i + 1),
					  &agg_op, CS_UNUSED, &outlen)) != CS_SUCCEED)
	    {
		warn("ct_compute_info failed");
		goto GoodBye;
	    }
	    sprintf(info->datafmt[i].name, "%s(%d)", agg_op_name, agg_op);
	}

	switch(info->datafmt[i].datatype)
	{
	  case CS_BIT_TYPE:
	  case CS_TINYINT_TYPE:
	  case CS_SMALLINT_TYPE:
	  case CS_INT_TYPE:
	    info->datafmt[i].maxlength = sizeof(CS_INT);
	    info->datafmt[i].datatype = CS_INT_TYPE;
	    info->datafmt[i].format   = CS_FMT_UNUSED;
	    info->coldata[i].type = CS_INT_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      &info->coldata[i].value.i,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
	    
	  case CS_REAL_TYPE:
	  case CS_FLOAT_TYPE:
	  case CS_MONEY_TYPE:
	  case CS_MONEY4_TYPE:
	  case CS_NUMERIC_TYPE:
	  case CS_DECIMAL_TYPE:
	    info->datafmt[i].maxlength = sizeof(CS_FLOAT);
	    info->datafmt[i].datatype = CS_FLOAT_TYPE;
	    info->datafmt[i].format   = CS_FMT_UNUSED;
	    info->coldata[i].type = CS_FLOAT_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      &info->coldata[i].value.f,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
	    
	  case CS_TEXT_TYPE:
	  case CS_IMAGE_TYPE:
	    info->datafmt[i].datatype = CS_TEXT_TYPE;
	    info->datafmt[i].format   = CS_FMT_NULLTERM;
	    New(902, info->coldata[i].value.c, info->datafmt[i].maxlength, char);
	    info->coldata[i].type = CS_TEXT_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      info->coldata[i].value.c,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
		
	  case CS_CHAR_TYPE:
	  case CS_VARCHAR_TYPE:
	  case CS_BINARY_TYPE:
	  case CS_VARBINARY_TYPE:
	  case CS_DATETIME_TYPE:
	  case CS_DATETIME4_TYPE:
	  default:
	    info->datafmt[i].maxlength =
		display_dlen(&info->datafmt[i]) + 1;
	    info->datafmt[i].datatype = CS_CHAR_TYPE;
	    info->datafmt[i].format   = CS_FMT_NULLTERM;
	    New(902, info->coldata[i].value.c, info->datafmt[i].maxlength, char);
	    info->coldata[i].type = CS_CHAR_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      info->coldata[i].value.c,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
	}	
	/* check the return code of the call to ct_bind in the
	   switch above: */
	if (retcode != CS_SUCCEED) 
	{
	    warn("ct_bind() failed");
	    cleanUp(info);
	    break;
	}
    }
  GoodBye:;
    return retcode;
}


static CS_RETCODE
fetch_data(cmd)
CS_COMMAND	*cmd;
{
    CS_RETCODE	retcode;
    CS_INT	num_cols;
    CS_INT	i;
    CS_INT	j;
    CS_INT	row_count = 0;
    CS_INT	rows_read;
    CS_INT	disp_len;
    CS_DATAFMT	*datafmt;
    ColData	*coldata;

    /*
     ** Find out how many columns there are in this result set.
     */
    if((retcode = ct_res_info(cmd, CS_NUMDATA, &num_cols, CS_UNUSED, NULL))
       != CS_SUCCEED)
    {
	warn("fetch_data: ct_res_info() failed");
	return retcode;
    }

    /*
     ** Make sure we have at least one column
     */
    if (num_cols <= 0)
    {
	warn("fetch_data: ct_res_info() returned zero columns");
	return CS_FAIL;
    }

    New(902, coldata, num_cols, ColData);
    New(902, datafmt, num_cols, CS_DATAFMT);

    for (i = 0; i < num_cols; i++)
    {
	if((retcode = ct_describe(cmd, (i + 1), &datafmt[i])) != CS_SUCCEED)
	{
	    warn("fetch_data: ct_describe() failed");
	    break;
	}
	datafmt[i].maxlength = display_dlen(&datafmt[i]) + 1;
	datafmt[i].datatype = CS_CHAR_TYPE;
	datafmt[i].format   = CS_FMT_NULLTERM;

	New(902, coldata[i].value.c, datafmt[i].maxlength, char);
	if((retcode = ct_bind(cmd, (i + 1), &datafmt[i],
			      &coldata[i].value, &coldata[i].valuelen,
			      &coldata[i].indicator)) != CS_SUCCEED)
	{
	    warn("fetch_data: ct_bind() failed");
	    break;
	}
    }
    if (retcode != CS_SUCCEED)
    {
	for (j = 0; j < i; j++)
	{
	    Safefree(coldata[j].value.c);
	}
	Safefree(coldata);
	Safefree(datafmt);
	return retcode;
    }

    display_header(num_cols, datafmt);

    while (((retcode = ct_fetch(cmd, CS_UNUSED, CS_UNUSED, CS_UNUSED,
				&rows_read)) == CS_SUCCEED)
	   || (retcode == CS_ROW_FAIL))
    {
	row_count = row_count + rows_read;

		/*
		** Check if we hit a recoverable error.
		*/
	if (retcode == CS_ROW_FAIL)
	{
	    fprintf(stdout, "Error on row %ld.\n", row_count);
	    fflush(stdout);
	}

	/*
	 ** We have a row.  Loop through the columns displaying the
	 ** column values.
	 */
	for (i = 0; i < num_cols; i++)
	{	  
	    /*
	     ** Display the column value
	     */
	    fprintf(stdout, "%s", coldata[i].value.c);
	    fflush(stdout);

	    /*
	     ** If not last column, Print out spaces between this
	     ** column and next one. 
	     */
	    if (i != num_cols - 1)
	    {
		disp_len = display_dlen(&datafmt[i]);
		disp_len -= coldata[i].valuelen - 1;
		for (j = 0; j < disp_len; j++)
		{
		    fputc(' ', stdout);
		}
	    }
	} 
	fprintf(stdout, "\n");
	fflush(stdout);
    }

    /*
     ** Free allocated space.
     */
    for (i = 0; i < num_cols; i++)
    {
	Safefree(coldata[i].value.c);
    }
    Safefree(coldata);
    Safefree(datafmt);
    
    /*
     ** We're done processing rows.  Let's check the final return
     ** value of ct_fetch().
     */
    switch ((int)retcode)
    {
      case CS_END_DATA:
	retcode = CS_SUCCEED;
	break;

      case CS_FAIL:
	warn("fetch_data: ct_fetch() failed");
	return retcode;
	break;

      default:			/* unexpected return value! */
	warn("fetch_data: ct_fetch() returned an expected retcode");
	return retcode;
	break;
    }
    return retcode;
}


static CS_RETCODE
clientmsg_cb(context, connection, errmsg)
CS_CONTEXT	*context;
CS_CONNECTION	*connection;	
CS_CLIENTMSG	*errmsg;
{
    if(client_cb.sub)
    {
	dSP;
	int retval, count;

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);

	XPUSHs(sv_2mortal(newSViv(CS_LAYER(errmsg->msgnumber))));
	XPUSHs(sv_2mortal(newSViv(CS_ORIGIN(errmsg->msgnumber))));
	XPUSHs(sv_2mortal(newSViv(CS_SEVERITY(errmsg->msgnumber))));
	XPUSHs(sv_2mortal(newSViv(CS_NUMBER(errmsg->msgnumber))));
	XPUSHs(sv_2mortal(newSVpv(errmsg->msgstring, 0)));
	if (errmsg->osstringlen > 0)
	    XPUSHs(sv_2mortal(newSVpv(errmsg->osstring, 0)));
	else
	    XPUSHs(&sv_undef);
	PUTBACK;
	if((count = perl_call_sv(client_cb.sub, G_SCALAR)) != 1)
	    croak("A msg handler cannot return a LIST");
	SPAGAIN;
	retval = POPi;
	
	PUTBACK;
	FREETMPS;
	LEAVE;
	
	return retval;
    }
	
    fprintf(stderr, "\nOpen Client Message:\n");
    fprintf(stderr, "Message number: LAYER = (%ld) ORIGIN = (%ld) ",
	    CS_LAYER(errmsg->msgnumber), CS_ORIGIN(errmsg->msgnumber));
    fprintf(stderr, "SEVERITY = (%ld) NUMBER = (%ld)\n",
	    CS_SEVERITY(errmsg->msgnumber), CS_NUMBER(errmsg->msgnumber));
    fprintf(stderr, "Message String: %s\n", errmsg->msgstring);
    if (errmsg->osstringlen > 0)
    {
	fprintf(stderr, "Operating System Error: %s\n",
		errmsg->osstring);
    }
    fflush(stderr);

    return CS_SUCCEED;
}

static CS_RETCODE
servermsg_cb(context, connection, srvmsg)
CS_CONTEXT	*context;
CS_CONNECTION	*connection;
CS_SERVERMSG	*srvmsg;
{
    CS_COMMAND	*cmd;
    CS_RETCODE	retcode;
    
    if(server_cb.sub)	/* a perl error handler has been installed */
    {
	dSP;
	SV *rv;
	SV *sv;
	HV *hv;
	int retval, count;
	ConInfo *info;

	ENTER;
	SAVETMPS;
	PUSHMARK(sp);
	    
	if (srvmsg->status & CS_HASEED)
	{
	    if (ct_con_props(connection, CS_GET, CS_EED_CMD,
			     &cmd, CS_UNUSED, NULL) != CS_SUCCEED)
	    {
		warn("servermsg_cb: ct_con_props(CS_EED_CMD) failed");
		return CS_FAIL;
	    }
#if 0
	    hv = SvSTASH(SvRV(dbp));
	    package = HvNAME(hv);
#endif
	    New(902, info, 1, ConInfo);
	    info->connection = connection;
	    info->cmd = cmd;
	    info->numCols = 0;
	    info->coldata = NULL;
	    info->datafmt = NULL;
	    info->type = CON_EED_CMD;

	    describe(info, NULL, 0);
	
	    hv = (HV*)sv_2mortal((SV*)newHV());
	    sv = newSViv((IV)info);
	    my_hv_store(hv, HV_coninfo, sv, 0);
	    rv = newRV((SV*)hv);
#if 0
	    stash = gv_stashpv(package, TRUE);
	    ST(0) = sv_2mortal(sv_bless(rv, stash));
#else
	    XPUSHs(sv_2mortal(rv));
#endif	    
	}
	else
	    XPUSHs(&sv_undef);
	
	XPUSHs(sv_2mortal(newSViv(srvmsg->msgnumber)));
	XPUSHs(sv_2mortal(newSViv(srvmsg->severity)));
	XPUSHs(sv_2mortal(newSViv(srvmsg->state)));
	XPUSHs(sv_2mortal(newSViv(srvmsg->line)));
	if(srvmsg->svrnlen > 0)
	    XPUSHs(sv_2mortal(newSVpv(srvmsg->svrname, 0)));
	else
	    XPUSHs(&sv_undef);
	if(srvmsg->proclen > 0)
	    XPUSHs(sv_2mortal(newSVpv(srvmsg->proc, 0)));
	else
	    XPUSHs(&sv_undef);
	XPUSHs(sv_2mortal(newSVpv(srvmsg->text, 0)));

	
	PUTBACK;
	if((count = perl_call_sv(server_cb.sub, G_SCALAR)) != 1)
	    croak("An error handler can't return a LIST.");
	SPAGAIN;
	retval = POPi;
	
	PUTBACK;
	FREETMPS;
	LEAVE;
	
	return retval;
    }
    else
    {
	fprintf(stderr, "\nServer message:\n");
	fprintf(stderr, "Message number: %ld, Severity %ld, ",
		srvmsg->msgnumber, srvmsg->severity);
	fprintf(stderr, "State %ld, Line %ld\n",
		srvmsg->state, srvmsg->line);
	
	if (srvmsg->svrnlen > 0)
	    fprintf(stderr, "Server '%s'\n", srvmsg->svrname);
	
	if (srvmsg->proclen > 0)
	    fprintf(stderr, " Procedure '%s'\n", srvmsg->proc);
	
	fprintf(stderr, "Message String: %s\n", srvmsg->text);
	
	if (srvmsg->status & CS_HASEED)
	{
	    fprintf(stderr, "\n[Start Extended Error]\n");
	    if (ct_con_props(connection, CS_GET, CS_EED_CMD,
			     &cmd, CS_UNUSED, NULL) != CS_SUCCEED)
	    {
		warn("servermsg_cb: ct_con_props(CS_EED_CMD) failed");
		return CS_FAIL;
	    }
	    retcode = fetch_data(cmd);
	    fprintf(stderr, "\n[End Extended Error]\n\n");
	}
	else
	    retcode = CS_SUCCEED;
	fflush(stderr);

	return retcode;
    }
    return CS_SUCCEED;
}

static CS_RETCODE
notification_cb(connection, procname, pnamelen)
CS_CONNECTION	*connection;
CS_CHAR		*procname;
CS_INT		pnamelen;
{
    CS_RETCODE	retcode;
    CS_COMMAND	*cmd;

    fprintf(stderr,
	    "\n-- Notification received --\nprocedure name = '%s'\n\n",
	    procname);
    fflush(stderr);
    
    if (ct_con_props(connection, CS_GET, CS_EED_CMD,
		     &cmd, CS_UNUSED, NULL) != CS_SUCCEED)
    {
	warn("notification_cb: ct_con_props(CS_EED_CMD) failed");
	return CS_FAIL;
    }
    retcode = fetch_data(cmd);
    fprintf(stdout, "\n[End Notification]\n\n");
    
    return retcode;
}

static void
initialize()
{
    SV 		*sv;
    CS_RETCODE	retcode;
    CS_INT	netio_type = CS_SYNC_IO;

    if((retcode = cs_ctx_alloc(CTLIB_VERSION, &context)) != CS_SUCCEED)
	croak("Sybase::CTlib initialize: cs_ctx_alloc() failed");

    if((retcode = ct_init(context, CTLIB_VERSION)) != CS_SUCCEED)
    {
	cs_ctx_drop(context);
	context = NULL;
	croak("Sybase::CTlib initialize: ct_init() failed");
    }

    if((retcode = ct_callback(context, NULL, CS_SET, CS_CLIENTMSG_CB,
			  (CS_VOID *)clientmsg_cb)) != CS_SUCCEED)
	croak("Sybase::CTlib initialize: ct_callback(clientmsg) failed");
    if((retcode = ct_callback(context, NULL, CS_SET, CS_SERVERMSG_CB,
			      (CS_VOID *)servermsg_cb)) != CS_SUCCEED)
	croak("Sybase::CTlib initialize: ct_callback(servermsg) failed");

    if((retcode = ct_callback(context, NULL, CS_SET, CS_NOTIF_CB,
			      (CS_VOID *)notification_cb)) != CS_SUCCEED)
	croak("Sybase::CTlib initialize: ct_callback(notification) failed");

    if((retcode = ct_config(context, CS_SET, CS_NETIO, &netio_type, 
			    CS_UNUSED, NULL)) != CS_SUCCEED)
	croak("Sybase::CTlib initialize: ct_config(netio) failed");

    /* FIXME:
       We probably want to store both the version, and the
       more verbose copyright string here. See man perlguts to
       check how this can be done. */
    if((sv = perl_get_sv("Sybase::CTlib::Version", TRUE)))
	sv_setpv(sv, SYBPLVER);

}

static int
not_here(s)
char *s;
{
    croak("%s not implemented on this architecture", s);
    return -1;
}

static double
constant(name, arg)
char *name;
int arg;
{
    errno = 0;
    switch (*name) {
    case 'A':
	break;
    case 'B':
	break;
    case 'C':
	switch(name[1])
	{
	  case 'S':
	    switch(name[3])
	    {
	      case '1':
		if (strEQ(name, "CS_12HOUR"))
#ifdef CS_12HOUR
		    return CS_12HOUR;
#else
		goto not_there;
#endif
		break;
	      case 'A':
		if (strEQ(name, "CS_ABSOLUTE"))
#ifdef CS_ABSOLUTE
		    return CS_ABSOLUTE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ACK"))
#ifdef CS_ACK
		    return CS_ACK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ADD"))
#ifdef CS_ADD
		    return CS_ADD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ALLMSG_TYPE"))
#ifdef CS_ALLMSG_TYPE
		    return CS_ALLMSG_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ALLOC"))
#ifdef CS_ALLOC
		    return CS_ALLOC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ALL_CAPS"))
#ifdef CS_ALL_CAPS
		    return CS_ALL_CAPS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ANSI_BINDS"))
#ifdef CS_ANSI_BINDS
		    return CS_ANSI_BINDS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_APPNAME"))
#ifdef CS_APPNAME
		    return CS_APPNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ASYNC_IO"))
#ifdef CS_ASYNC_IO
		    return CS_ASYNC_IO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ASYNC_NOTIFS"))
#ifdef CS_ASYNC_NOTIFS
		    return CS_ASYNC_NOTIFS;
#else
		goto not_there;
#endif
		break;
	      case 'B':
		if (strEQ(name, "CS_BINARY_TYPE"))
#ifdef CS_BINARY_TYPE
		    return CS_BINARY_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BIT_TYPE"))
#ifdef CS_BIT_TYPE
		    return CS_BIT_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BLKDESC"))
#ifdef CS_BLKDESC
		    return CS_BLKDESC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BLK_HAS_TEXT"))
#ifdef CS_BLK_HAS_TEXT
		    return CS_BLK_HAS_TEXT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BLK_ROW"))
#ifdef CS_BLK_ROW
		    return CS_BLK_ROW;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BOUNDARY_TYPE"))
#ifdef CS_BOUNDARY_TYPE
		    return CS_BOUNDARY_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BROWSE_INFO"))
#ifdef CS_BROWSE_INFO
		    return CS_BROWSE_INFO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BULK_CONT"))
#ifdef CS_BULK_CONT
		    return CS_BULK_CONT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BULK_DATA"))
#ifdef CS_BULK_DATA
		    return CS_BULK_DATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BULK_INIT"))
#ifdef CS_BULK_INIT
		    return CS_BULK_INIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BULK_LOGIN"))
#ifdef CS_BULK_LOGIN
		    return CS_BULK_LOGIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BUSY"))
#ifdef CS_BUSY
		    return CS_BUSY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_BYLIST_LEN"))
#ifdef CS_BYLIST_LEN
		    return CS_BYLIST_LEN;
#else
		goto not_there;
#endif
		break;
	      case 'C':
		if (strEQ(name, "CS_CANBENULL"))
#ifdef CS_CANBENULL
		    return CS_CANBENULL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CANCELED"))
#ifdef CS_CANCELED
		    return CS_CANCELED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CANCEL_ALL"))
#ifdef CS_CANCEL_ALL
		    return CS_CANCEL_ALL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CANCEL_ATTN"))
#ifdef CS_CANCEL_ATTN
		    return CS_CANCEL_ATTN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CANCEL_CURRENT"))
#ifdef CS_CANCEL_CURRENT
		    return CS_CANCEL_CURRENT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CAP_ARRAYLEN"))
#ifdef CS_CAP_ARRAYLEN
		    return CS_CAP_ARRAYLEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CAP_REQUEST"))
#ifdef CS_CAP_REQUEST
		    return CS_CAP_REQUEST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CAP_RESPONSE"))
#ifdef CS_CAP_RESPONSE
		    return CS_CAP_RESPONSE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CHALLENGE_CB"))
#ifdef CS_CHALLENGE_CB
		    return CS_CHALLENGE_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CHARSETCNV"))
#ifdef CS_CHARSETCNV
		    return CS_CHARSETCNV;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CHAR_TYPE"))
#ifdef CS_CHAR_TYPE
		    return CS_CHAR_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CLEAR"))
#ifdef CS_CLEAR
		    return CS_CLEAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CLEAR_FLAG"))
#ifdef CS_CLEAR_FLAG
		    return CS_CLEAR_FLAG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CLIENTMSG_CB"))
#ifdef CS_CLIENTMSG_CB
		    return CS_CLIENTMSG_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CLIENTMSG_TYPE"))
#ifdef CS_CLIENTMSG_TYPE
		    return CS_CLIENTMSG_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CMD_DONE"))
#ifdef CS_CMD_DONE
		    return CS_CMD_DONE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CMD_FAIL"))
#ifdef CS_CMD_FAIL
		    return CS_CMD_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CMD_NUMBER"))
#ifdef CS_CMD_NUMBER
		    return CS_CMD_NUMBER;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CMD_SUCCEED"))
#ifdef CS_CMD_SUCCEED
		    return CS_CMD_SUCCEED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COLUMN_DATA"))
#ifdef CS_COLUMN_DATA
		    return CS_COLUMN_DATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMMAND"))
#ifdef CS_COMMAND
		    return CS_COMMAND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMMBLOCK"))
#ifdef CS_COMMBLOCK
		    return CS_COMMBLOCK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMPARE"))
#ifdef CS_COMPARE
		    return CS_COMPARE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMPLETION_CB"))
#ifdef CS_COMPLETION_CB
		    return CS_COMPLETION_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMPUTEFMT_RESULT"))
#ifdef CS_COMPUTEFMT_RESULT
		    return CS_COMPUTEFMT_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMPUTE_RESULT"))
#ifdef CS_COMPUTE_RESULT
		    return CS_COMPUTE_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMP_BYLIST"))
#ifdef CS_COMP_BYLIST
		    return CS_COMP_BYLIST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMP_COLID"))
#ifdef CS_COMP_COLID
		    return CS_COMP_COLID;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMP_ID"))
#ifdef CS_COMP_ID
		    return CS_COMP_ID;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_COMP_OP"))
#ifdef CS_COMP_OP
		    return CS_COMP_OP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONNECTION"))
#ifdef CS_CONNECTION
		    return CS_CONNECTION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONNECTNAME"))
#ifdef CS_CONNECTNAME
		    return CS_CONNECTNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONSTAT_CONNECTED"))
#ifdef CS_CONSTAT_CONNECTED
		    return CS_CONSTAT_CONNECTED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONSTAT_DEAD"))
#ifdef CS_CONSTAT_DEAD
		    return CS_CONSTAT_DEAD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONTEXT"))
#ifdef CS_CONTEXT
		    return CS_CONTEXT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONTINUE"))
#ifdef CS_CONTINUE
		    return CS_CONTINUE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CONV_ERR"))
#ifdef CS_CONV_ERR
		    return CS_CONV_ERR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CON_INBAND"))
#ifdef CS_CON_INBAND
		    return CS_CON_INBAND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CON_LOGICAL"))
#ifdef CS_CON_LOGICAL
		    return CS_CON_LOGICAL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CON_NOINBAND"))
#ifdef CS_CON_NOINBAND
		    return CS_CON_NOINBAND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CON_NOOOB"))
#ifdef CS_CON_NOOOB
		    return CS_CON_NOOOB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CON_OOB"))
#ifdef CS_CON_OOB
		    return CS_CON_OOB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CON_STATUS"))
#ifdef CS_CON_STATUS
		    return CS_CON_STATUS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CSR_ABS"))
#ifdef CS_CSR_ABS
		    return CS_CSR_ABS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CSR_FIRST"))
#ifdef CS_CSR_FIRST
		    return CS_CSR_FIRST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CSR_LAST"))
#ifdef CS_CSR_LAST
		    return CS_CSR_LAST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CSR_MULTI"))
#ifdef CS_CSR_MULTI
		    return CS_CSR_MULTI;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CSR_PREV"))
#ifdef CS_CSR_PREV
		    return CS_CSR_PREV;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CSR_REL"))
#ifdef CS_CSR_REL
		    return CS_CSR_REL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURRENT_CONNECTION"))
#ifdef CS_CURRENT_CONNECTION
		    return CS_CURRENT_CONNECTION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSORNAME"))
#ifdef CS_CURSORNAME
		    return CS_CURSORNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_CLOSE"))
#ifdef CS_CURSOR_CLOSE
		    return CS_CURSOR_CLOSE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_DEALLOC"))
#ifdef CS_CURSOR_DEALLOC
		    return CS_CURSOR_DEALLOC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_DECLARE"))
#ifdef CS_CURSOR_DECLARE
		    return CS_CURSOR_DECLARE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_DELETE"))
#ifdef CS_CURSOR_DELETE
		    return CS_CURSOR_DELETE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_FETCH"))
#ifdef CS_CURSOR_FETCH
		    return CS_CURSOR_FETCH;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_INFO"))
#ifdef CS_CURSOR_INFO
		    return CS_CURSOR_INFO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_OPEN"))
#ifdef CS_CURSOR_OPEN
		    return CS_CURSOR_OPEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_OPTION"))
#ifdef CS_CURSOR_OPTION
		    return CS_CURSOR_OPTION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_RESULT"))
#ifdef CS_CURSOR_RESULT
		    return CS_CURSOR_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_ROWS"))
#ifdef CS_CURSOR_ROWS
		    return CS_CURSOR_ROWS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSOR_UPDATE"))
#ifdef CS_CURSOR_UPDATE
		    return CS_CURSOR_UPDATE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_CLOSED"))
#ifdef CS_CURSTAT_CLOSED
		    return CS_CURSTAT_CLOSED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_DEALLOC"))
#ifdef CS_CURSTAT_DEALLOC
		    return CS_CURSTAT_DEALLOC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_DECLARED"))
#ifdef CS_CURSTAT_DECLARED
		    return CS_CURSTAT_DECLARED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_NONE"))
#ifdef CS_CURSTAT_NONE
		    return CS_CURSTAT_NONE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_OPEN"))
#ifdef CS_CURSTAT_OPEN
		    return CS_CURSTAT_OPEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_RDONLY"))
#ifdef CS_CURSTAT_RDONLY
		    return CS_CURSTAT_RDONLY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_ROWCOUNT"))
#ifdef CS_CURSTAT_ROWCOUNT
		    return CS_CURSTAT_ROWCOUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CURSTAT_UPDATABLE"))
#ifdef CS_CURSTAT_UPDATABLE
		    return CS_CURSTAT_UPDATABLE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CUR_ID"))
#ifdef CS_CUR_ID
		    return CS_CUR_ID;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CUR_NAME"))
#ifdef CS_CUR_NAME
		    return CS_CUR_NAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CUR_ROWCOUNT"))
#ifdef CS_CUR_ROWCOUNT
		    return CS_CUR_ROWCOUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_CUR_STATUS"))
#ifdef CS_CUR_STATUS
		    return CS_CUR_STATUS;
#else
		goto not_there;
#endif
		break;
	      case 'D':
		if (strEQ(name, "CS_DATA_BIN"))
#ifdef CS_DATA_BIN
		    return CS_DATA_BIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_BIT"))
#ifdef CS_DATA_BIT
		    return CS_DATA_BIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_BITN"))
#ifdef CS_DATA_BITN
		    return CS_DATA_BITN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_BOUNDARY"))
#ifdef CS_DATA_BOUNDARY
		    return CS_DATA_BOUNDARY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_CHAR"))
#ifdef CS_DATA_CHAR
		    return CS_DATA_CHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_DATE4"))
#ifdef CS_DATA_DATE4
		    return CS_DATA_DATE4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_DATE8"))
#ifdef CS_DATA_DATE8
		    return CS_DATA_DATE8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_DATETIMEN"))
#ifdef CS_DATA_DATETIMEN
		    return CS_DATA_DATETIMEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_DEC"))
#ifdef CS_DATA_DEC
		    return CS_DATA_DEC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_FLT4"))
#ifdef CS_DATA_FLT4
		    return CS_DATA_FLT4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_FLT8"))
#ifdef CS_DATA_FLT8
		    return CS_DATA_FLT8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_FLTN"))
#ifdef CS_DATA_FLTN
		    return CS_DATA_FLTN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_IMAGE"))
#ifdef CS_DATA_IMAGE
		    return CS_DATA_IMAGE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_INT1"))
#ifdef CS_DATA_INT1
		    return CS_DATA_INT1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_INT2"))
#ifdef CS_DATA_INT2
		    return CS_DATA_INT2;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_INT4"))
#ifdef CS_DATA_INT4
		    return CS_DATA_INT4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_INT8"))
#ifdef CS_DATA_INT8
		    return CS_DATA_INT8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_INTN"))
#ifdef CS_DATA_INTN
		    return CS_DATA_INTN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_LBIN"))
#ifdef CS_DATA_LBIN
		    return CS_DATA_LBIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_LCHAR"))
#ifdef CS_DATA_LCHAR
		    return CS_DATA_LCHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_MNY4"))
#ifdef CS_DATA_MNY4
		    return CS_DATA_MNY4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_MNY8"))
#ifdef CS_DATA_MNY8
		    return CS_DATA_MNY8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_MONEYN"))
#ifdef CS_DATA_MONEYN
		    return CS_DATA_MONEYN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOBIN"))
#ifdef CS_DATA_NOBIN
		    return CS_DATA_NOBIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOBIT"))
#ifdef CS_DATA_NOBIT
		    return CS_DATA_NOBIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOBOUNDARY"))
#ifdef CS_DATA_NOBOUNDARY
		    return CS_DATA_NOBOUNDARY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOCHAR"))
#ifdef CS_DATA_NOCHAR
		    return CS_DATA_NOCHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NODATE4"))
#ifdef CS_DATA_NODATE4
		    return CS_DATA_NODATE4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NODATE8"))
#ifdef CS_DATA_NODATE8
		    return CS_DATA_NODATE8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NODATETIMEN"))
#ifdef CS_DATA_NODATETIMEN
		    return CS_DATA_NODATETIMEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NODEC"))
#ifdef CS_DATA_NODEC
		    return CS_DATA_NODEC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOFLT4"))
#ifdef CS_DATA_NOFLT4
		    return CS_DATA_NOFLT4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOFLT8"))
#ifdef CS_DATA_NOFLT8
		    return CS_DATA_NOFLT8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOIMAGE"))
#ifdef CS_DATA_NOIMAGE
		    return CS_DATA_NOIMAGE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOINT1"))
#ifdef CS_DATA_NOINT1
		    return CS_DATA_NOINT1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOINT2"))
#ifdef CS_DATA_NOINT2
		    return CS_DATA_NOINT2;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOINT4"))
#ifdef CS_DATA_NOINT4
		    return CS_DATA_NOINT4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOINT8"))
#ifdef CS_DATA_NOINT8
		    return CS_DATA_NOINT8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOINTN"))
#ifdef CS_DATA_NOINTN
		    return CS_DATA_NOINTN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOLBIN"))
#ifdef CS_DATA_NOLBIN
		    return CS_DATA_NOLBIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOLCHAR"))
#ifdef CS_DATA_NOLCHAR
		    return CS_DATA_NOLCHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOMNY4"))
#ifdef CS_DATA_NOMNY4
		    return CS_DATA_NOMNY4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOMNY8"))
#ifdef CS_DATA_NOMNY8
		    return CS_DATA_NOMNY8;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOMONEYN"))
#ifdef CS_DATA_NOMONEYN
		    return CS_DATA_NOMONEYN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NONUM"))
#ifdef CS_DATA_NONUM
		    return CS_DATA_NONUM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOSENSITIVITY"))
#ifdef CS_DATA_NOSENSITIVITY
		    return CS_DATA_NOSENSITIVITY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOTEXT"))
#ifdef CS_DATA_NOTEXT
		    return CS_DATA_NOTEXT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOVBIN"))
#ifdef CS_DATA_NOVBIN
		    return CS_DATA_NOVBIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NOVCHAR"))
#ifdef CS_DATA_NOVCHAR
		    return CS_DATA_NOVCHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_NUM"))
#ifdef CS_DATA_NUM
		    return CS_DATA_NUM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_SENSITIVITY"))
#ifdef CS_DATA_SENSITIVITY
		    return CS_DATA_SENSITIVITY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_TEXT"))
#ifdef CS_DATA_TEXT
		    return CS_DATA_TEXT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_VBIN"))
#ifdef CS_DATA_VBIN
		    return CS_DATA_VBIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATA_VCHAR"))
#ifdef CS_DATA_VCHAR
		    return CS_DATA_VCHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATEORDER"))
#ifdef CS_DATEORDER
		    return CS_DATEORDER;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY1"))
#ifdef CS_DATES_DMY1
		    return CS_DATES_DMY1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY1_YYYY"))
#ifdef CS_DATES_DMY1_YYYY
		    return CS_DATES_DMY1_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY2"))
#ifdef CS_DATES_DMY2
		    return CS_DATES_DMY2;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY2_YYYY"))
#ifdef CS_DATES_DMY2_YYYY
		    return CS_DATES_DMY2_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY3"))
#ifdef CS_DATES_DMY3
		    return CS_DATES_DMY3;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY3_YYYY"))
#ifdef CS_DATES_DMY3_YYYY
		    return CS_DATES_DMY3_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY4"))
#ifdef CS_DATES_DMY4
		    return CS_DATES_DMY4;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DMY4_YYYY"))
#ifdef CS_DATES_DMY4_YYYY
		    return CS_DATES_DMY4_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_DYM1"))
#ifdef CS_DATES_DYM1
		    return CS_DATES_DYM1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_HMS"))
#ifdef CS_DATES_HMS
		    return CS_DATES_HMS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_HMS_ALT"))
#ifdef CS_DATES_HMS_ALT
		    return CS_DATES_HMS_ALT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_LONG"))
#ifdef CS_DATES_LONG
		    return CS_DATES_LONG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_LONG_ALT"))
#ifdef CS_DATES_LONG_ALT
		    return CS_DATES_LONG_ALT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MDY1"))
#ifdef CS_DATES_MDY1
		    return CS_DATES_MDY1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MDY1_YYYY"))
#ifdef CS_DATES_MDY1_YYYY
		    return CS_DATES_MDY1_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MDY2"))
#ifdef CS_DATES_MDY2
		    return CS_DATES_MDY2;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MDY2_YYYY"))
#ifdef CS_DATES_MDY2_YYYY
		    return CS_DATES_MDY2_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MDY3"))
#ifdef CS_DATES_MDY3
		    return CS_DATES_MDY3;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MDY3_YYYY"))
#ifdef CS_DATES_MDY3_YYYY
		    return CS_DATES_MDY3_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_MYD1"))
#ifdef CS_DATES_MYD1
		    return CS_DATES_MYD1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_SHORT"))
#ifdef CS_DATES_SHORT
		    return CS_DATES_SHORT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_SHORT_ALT"))
#ifdef CS_DATES_SHORT_ALT
		    return CS_DATES_SHORT_ALT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YDM1"))
#ifdef CS_DATES_YDM1
		    return CS_DATES_YDM1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YMD1"))
#ifdef CS_DATES_YMD1
		    return CS_DATES_YMD1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YMD1_YYYY"))
#ifdef CS_DATES_YMD1_YYYY
		    return CS_DATES_YMD1_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YMD2"))
#ifdef CS_DATES_YMD2
		    return CS_DATES_YMD2;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YMD2_YYYY"))
#ifdef CS_DATES_YMD2_YYYY
		    return CS_DATES_YMD2_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YMD3"))
#ifdef CS_DATES_YMD3
		    return CS_DATES_YMD3;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATES_YMD3_YYYY"))
#ifdef CS_DATES_YMD3_YYYY
		    return CS_DATES_YMD3_YYYY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATETIME4_TYPE"))
#ifdef CS_DATETIME4_TYPE
		    return CS_DATETIME4_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DATETIME_TYPE"))
#ifdef CS_DATETIME_TYPE
		    return CS_DATETIME_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DAYNAME"))
#ifdef CS_DAYNAME
		    return CS_DAYNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_ALL"))
#ifdef CS_DBG_ALL
		    return CS_DBG_ALL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_API_LOGCALL"))
#ifdef CS_DBG_API_LOGCALL
		    return CS_DBG_API_LOGCALL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_API_STATES"))
#ifdef CS_DBG_API_STATES
		    return CS_DBG_API_STATES;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_ASYNC"))
#ifdef CS_DBG_ASYNC
		    return CS_DBG_ASYNC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_DIAG"))
#ifdef CS_DBG_DIAG
		    return CS_DBG_DIAG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_ERROR"))
#ifdef CS_DBG_ERROR
		    return CS_DBG_ERROR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_MEM"))
#ifdef CS_DBG_MEM
		    return CS_DBG_MEM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_NETWORK"))
#ifdef CS_DBG_NETWORK
		    return CS_DBG_NETWORK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_PROTOCOL"))
#ifdef CS_DBG_PROTOCOL
		    return CS_DBG_PROTOCOL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DBG_PROTOCOL_STATES"))
#ifdef CS_DBG_PROTOCOL_STATES
		    return CS_DBG_PROTOCOL_STATES;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DEALLOC"))
#ifdef CS_DEALLOC
		    return CS_DEALLOC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DECIMAL_TYPE"))
#ifdef CS_DECIMAL_TYPE
		    return CS_DECIMAL_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DEFER_IO"))
#ifdef CS_DEFER_IO
		    return CS_DEFER_IO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DEF_PREC"))
#ifdef CS_DEF_PREC
		    return CS_DEF_PREC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DEF_SCALE"))
#ifdef CS_DEF_SCALE
		    return CS_DEF_SCALE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DESCIN"))
#ifdef CS_DESCIN
		    return CS_DESCIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DESCOUT"))
#ifdef CS_DESCOUT
		    return CS_DESCOUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DESCRIBE_INPUT"))
#ifdef CS_DESCRIBE_INPUT
		    return CS_DESCRIBE_INPUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DESCRIBE_OUTPUT"))
#ifdef CS_DESCRIBE_OUTPUT
		    return CS_DESCRIBE_OUTPUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DESCRIBE_RESULT"))
#ifdef CS_DESCRIBE_RESULT
		    return CS_DESCRIBE_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DIAG_TIMEOUT"))
#ifdef CS_DIAG_TIMEOUT
		    return CS_DIAG_TIMEOUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DISABLE_POLL"))
#ifdef CS_DISABLE_POLL
		    return CS_DISABLE_POLL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DIV"))
#ifdef CS_DIV
		    return CS_DIV;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DT_CONVFMT"))
#ifdef CS_DT_CONVFMT
		    return CS_DT_CONVFMT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DYNAMIC"))
#ifdef CS_DYNAMIC
		    return CS_DYNAMIC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_DYN_CURSOR_DECLARE"))
#ifdef CS_DYN_CURSOR_DECLARE
		    return CS_DYN_CURSOR_DECLARE;
#else
		goto not_there;
#endif
		break;
	      case 'E':
		if (strEQ(name, "CS_EBADLEN"))
#ifdef CS_EBADLEN
		    return CS_EBADLEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EBADPARAM"))
#ifdef CS_EBADPARAM
		    return CS_EBADPARAM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EBADXLT"))
#ifdef CS_EBADXLT
		    return CS_EBADXLT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EDIVZERO"))
#ifdef CS_EDIVZERO
		    return CS_EDIVZERO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EDOMAIN"))
#ifdef CS_EDOMAIN
		    return CS_EDOMAIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EED_CMD"))
#ifdef CS_EED_CMD
		    return CS_EED_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EFORMAT"))
#ifdef CS_EFORMAT
		    return CS_EFORMAT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ENCRYPT_CB"))
#ifdef CS_ENCRYPT_CB
		    return CS_ENCRYPT_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ENDPOINT"))
#ifdef CS_ENDPOINT
		    return CS_ENDPOINT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_END_DATA"))
#ifdef CS_END_DATA
		    return CS_END_DATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_END_ITEM"))
#ifdef CS_END_ITEM
		    return CS_END_ITEM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_END_RESULTS"))
#ifdef CS_END_RESULTS
		    return CS_END_RESULTS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ENOBIND"))
#ifdef CS_ENOBIND
		    return CS_ENOBIND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ENOCNVRT"))
#ifdef CS_ENOCNVRT
		    return CS_ENOCNVRT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ENOXLT"))
#ifdef CS_ENOXLT
		    return CS_ENOXLT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ENULLNOIND"))
#ifdef CS_ENULLNOIND
		    return CS_ENULLNOIND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EOVERFLOW"))
#ifdef CS_EOVERFLOW
		    return CS_EOVERFLOW;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EPRECISION"))
#ifdef CS_EPRECISION
		    return CS_EPRECISION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ERESOURCE"))
#ifdef CS_ERESOURCE
		    return CS_ERESOURCE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ESCALE"))
#ifdef CS_ESCALE
		    return CS_ESCALE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ESTYLE"))
#ifdef CS_ESTYLE
		    return CS_ESTYLE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ESYNTAX"))
#ifdef CS_ESYNTAX
		    return CS_ESYNTAX;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ETRUNCNOIND"))
#ifdef CS_ETRUNCNOIND
		    return CS_ETRUNCNOIND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EUNDERFLOW"))
#ifdef CS_EUNDERFLOW
		    return CS_EUNDERFLOW;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EXECUTE"))
#ifdef CS_EXECUTE
		    return CS_EXECUTE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EXEC_IMMEDIATE"))
#ifdef CS_EXEC_IMMEDIATE
		    return CS_EXEC_IMMEDIATE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EXPOSE_FMTS"))
#ifdef CS_EXPOSE_FMTS
		    return CS_EXPOSE_FMTS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EXPRESSION"))
#ifdef CS_EXPRESSION
		    return CS_EXPRESSION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EXTERNAL_ERR"))
#ifdef CS_EXTERNAL_ERR
		    return CS_EXTERNAL_ERR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_EXTRA_INF"))
#ifdef CS_EXTRA_INF
		    return CS_EXTRA_INF;
#else
		goto not_there;
#endif
		break;
	      case 'F':
		if (strEQ(name, "CS_FAIL"))
#ifdef CS_FAIL
		    return CS_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FALSE"))
#ifdef CS_FALSE
		    return CS_FALSE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FIRST"))
#ifdef CS_FIRST
		    return CS_FIRST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FIRST_CHUNK"))
#ifdef CS_FIRST_CHUNK
		    return CS_FIRST_CHUNK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FLOAT_TYPE"))
#ifdef CS_FLOAT_TYPE
		    return CS_FLOAT_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FMT_JUSTIFY_RT"))
#ifdef CS_FMT_JUSTIFY_RT
		    return CS_FMT_JUSTIFY_RT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FMT_NULLTERM"))
#ifdef CS_FMT_NULLTERM
		    return CS_FMT_NULLTERM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FMT_PADBLANK"))
#ifdef CS_FMT_PADBLANK
		    return CS_FMT_PADBLANK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FMT_PADNULL"))
#ifdef CS_FMT_PADNULL
		    return CS_FMT_PADNULL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FMT_UNUSED"))
#ifdef CS_FMT_UNUSED
		    return CS_FMT_UNUSED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FORCE_CLOSE"))
#ifdef CS_FORCE_CLOSE
		    return CS_FORCE_CLOSE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FORCE_EXIT"))
#ifdef CS_FORCE_EXIT
		    return CS_FORCE_EXIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_FOR_UPDATE"))
#ifdef CS_FOR_UPDATE
		    return CS_FOR_UPDATE;
#else
		goto not_there;
#endif
		break;
	      case 'G':
		if (strEQ(name, "CS_GET"))
#ifdef CS_GET
		    return CS_GET;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_GETATTR"))
#ifdef CS_GETATTR
		    return CS_GETATTR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_GETCNT"))
#ifdef CS_GETCNT
		    return CS_GETCNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_GOODDATA"))
#ifdef CS_GOODDATA
		    return CS_GOODDATA;
#else
		goto not_there;
#endif
		break;
	      case 'H':
		if (strEQ(name, "CS_HASEED"))
#ifdef CS_HASEED
		    return CS_HASEED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_HIDDEN"))
#ifdef CS_HIDDEN
		    return CS_HIDDEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_HIDDEN_KEYS"))
#ifdef CS_HIDDEN_KEYS
		    return CS_HIDDEN_KEYS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_HOSTNAME"))
#ifdef CS_HOSTNAME
		    return CS_HOSTNAME;
#else
		goto not_there;
#endif
		break;
	      case 'I':
		if (strEQ(name, "CS_IDENTITY"))
#ifdef CS_IDENTITY
		    return CS_IDENTITY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_IFILE"))
#ifdef CS_IFILE
		    return CS_IFILE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ILLEGAL_TYPE"))
#ifdef CS_ILLEGAL_TYPE
		    return CS_ILLEGAL_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_IMAGE_TYPE"))
#ifdef CS_IMAGE_TYPE
		    return CS_IMAGE_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_INIT"))
#ifdef CS_INIT
		    return CS_INIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_INPUTVALUE"))
#ifdef CS_INPUTVALUE
		    return CS_INPUTVALUE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_INTERNAL_ERR"))
#ifdef CS_INTERNAL_ERR
		    return CS_INTERNAL_ERR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_INTERRUPT"))
#ifdef CS_INTERRUPT
		    return CS_INTERRUPT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_INT_TYPE"))
#ifdef CS_INT_TYPE
		    return CS_INT_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_IODATA"))
#ifdef CS_IODATA
		    return CS_IODATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ISBROWSE"))
#ifdef CS_ISBROWSE
		    return CS_ISBROWSE;
#else
		goto not_there;
#endif
		break;
	      case 'K':
		if (strEQ(name, "CS_KEY"))
#ifdef CS_KEY
		    return CS_KEY;
#else
		goto not_there;
#endif
		break;
	      case 'L':
		if (strEQ(name, "CS_LANG_CMD"))
#ifdef CS_LANG_CMD
		    return CS_LANG_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LAST"))
#ifdef CS_LAST
		    return CS_LAST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LAST_CHUNK"))
#ifdef CS_LAST_CHUNK
		    return CS_LAST_CHUNK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_ALL"))
#ifdef CS_LC_ALL
		    return CS_LC_ALL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_COLLATE"))
#ifdef CS_LC_COLLATE
		    return CS_LC_COLLATE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_CTYPE"))
#ifdef CS_LC_CTYPE
		    return CS_LC_CTYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_MESSAGE"))
#ifdef CS_LC_MESSAGE
		    return CS_LC_MESSAGE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_MONETARY"))
#ifdef CS_LC_MONETARY
		    return CS_LC_MONETARY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_NUMERIC"))
#ifdef CS_LC_NUMERIC
		    return CS_LC_NUMERIC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LC_TIME"))
#ifdef CS_LC_TIME
		    return CS_LC_TIME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LOCALE"))
#ifdef CS_LOCALE
		    return CS_LOCALE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LOC_PROP"))
#ifdef CS_LOC_PROP
		    return CS_LOC_PROP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LOGINFO"))
#ifdef CS_LOGINFO
		    return CS_LOGINFO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LOGIN_STATUS"))
#ifdef CS_LOGIN_STATUS
		    return CS_LOGIN_STATUS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LOGIN_TIMEOUT"))
#ifdef CS_LOGIN_TIMEOUT
		    return CS_LOGIN_TIMEOUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LONGBINARY_TYPE"))
#ifdef CS_LONGBINARY_TYPE
		    return CS_LONGBINARY_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LONGCHAR_TYPE"))
#ifdef CS_LONGCHAR_TYPE
		    return CS_LONGCHAR_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_LONG_TYPE"))
#ifdef CS_LONG_TYPE
		    return CS_LONG_TYPE;
#else
		goto not_there;
#endif
		break;
	      case 'M':
		if (strEQ(name, "CS_MAXSYB_TYPE"))
#ifdef CS_MAXSYB_TYPE
		    return CS_MAXSYB_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_CAPVALUE"))
#ifdef CS_MAX_CAPVALUE
		    return CS_MAX_CAPVALUE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_CHAR"))
#ifdef CS_MAX_CHAR
		    return CS_MAX_CHAR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_CONNECT"))
#ifdef CS_MAX_CONNECT
		    return CS_MAX_CONNECT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_LOCALE"))
#ifdef CS_MAX_LOCALE
		    return CS_MAX_LOCALE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_MSG"))
#ifdef CS_MAX_MSG
		    return CS_MAX_MSG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_NAME"))
#ifdef CS_MAX_NAME
		    return CS_MAX_NAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_NUMLEN"))
#ifdef CS_MAX_NUMLEN
		    return CS_MAX_NUMLEN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_OPTION"))
#ifdef CS_MAX_OPTION
		    return CS_MAX_OPTION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_PREC"))
#ifdef CS_MAX_PREC
		    return CS_MAX_PREC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_REQ_CAP"))
#ifdef CS_MAX_REQ_CAP
		    return CS_MAX_REQ_CAP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_RES_CAP"))
#ifdef CS_MAX_RES_CAP
		    return CS_MAX_RES_CAP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_SCALE"))
#ifdef CS_MAX_SCALE
		    return CS_MAX_SCALE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MAX_SYBTYPE"))
#ifdef CS_MAX_SYBTYPE
		    return CS_MAX_SYBTYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MEM_ERROR"))
#ifdef CS_MEM_ERROR
		    return CS_MEM_ERROR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MEM_POOL"))
#ifdef CS_MEM_POOL
		    return CS_MEM_POOL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MESSAGE_CB"))
#ifdef CS_MESSAGE_CB
		    return CS_MESSAGE_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_CAPVALUE"))
#ifdef CS_MIN_CAPVALUE
		    return CS_MIN_CAPVALUE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_OPTION"))
#ifdef CS_MIN_OPTION
		    return CS_MIN_OPTION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_PREC"))
#ifdef CS_MIN_PREC
		    return CS_MIN_PREC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_REQ_CAP"))
#ifdef CS_MIN_REQ_CAP
		    return CS_MIN_REQ_CAP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_RES_CAP"))
#ifdef CS_MIN_RES_CAP
		    return CS_MIN_RES_CAP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_SCALE"))
#ifdef CS_MIN_SCALE
		    return CS_MIN_SCALE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_SYBTYPE"))
#ifdef CS_MIN_SYBTYPE
		    return CS_MIN_SYBTYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MIN_USERDATA"))
#ifdef CS_MIN_USERDATA
		    return CS_MIN_USERDATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MONEY4_TYPE"))
#ifdef CS_MONEY4_TYPE
		    return CS_MONEY4_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MONEY_TYPE"))
#ifdef CS_MONEY_TYPE
		    return CS_MONEY_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MONTH"))
#ifdef CS_MONTH
		    return CS_MONTH;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSGLIMIT"))
#ifdef CS_MSGLIMIT
		    return CS_MSGLIMIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSGTYPE"))
#ifdef CS_MSGTYPE
		    return CS_MSGTYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSG_CMD"))
#ifdef CS_MSG_CMD
		    return CS_MSG_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSG_GETLABELS"))
#ifdef CS_MSG_GETLABELS
		    return CS_MSG_GETLABELS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSG_LABELS"))
#ifdef CS_MSG_LABELS
		    return CS_MSG_LABELS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSG_RESULT"))
#ifdef CS_MSG_RESULT
		    return CS_MSG_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MSG_TABLENAME"))
#ifdef CS_MSG_TABLENAME
		    return CS_MSG_TABLENAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_MULT"))
#ifdef CS_MULT
		    return CS_MULT;
#else
		goto not_there;
#endif
		break;
	      case 'N':
		if (strEQ(name, "CS_NETIO"))
#ifdef CS_NETIO
		    return CS_NETIO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NEXT"))
#ifdef CS_NEXT
		    return CS_NEXT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOAPI_CHK"))
#ifdef CS_NOAPI_CHK
		    return CS_NOAPI_CHK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NODATA"))
#ifdef CS_NODATA
		    return CS_NODATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NODEFAULT"))
#ifdef CS_NODEFAULT
		    return CS_NODEFAULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOINTERRUPT"))
#ifdef CS_NOINTERRUPT
		    return CS_NOINTERRUPT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOMSG"))
#ifdef CS_NOMSG
		    return CS_NOMSG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOTIFY_ALWAYS"))
#ifdef CS_NOTIFY_ALWAYS
		    return CS_NOTIFY_ALWAYS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOTIFY_NOWAIT"))
#ifdef CS_NOTIFY_NOWAIT
		    return CS_NOTIFY_NOWAIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOTIFY_ONCE"))
#ifdef CS_NOTIFY_ONCE
		    return CS_NOTIFY_ONCE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOTIFY_WAIT"))
#ifdef CS_NOTIFY_WAIT
		    return CS_NOTIFY_WAIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOTIF_CB"))
#ifdef CS_NOTIF_CB
		    return CS_NOTIF_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NOTIF_CMD"))
#ifdef CS_NOTIF_CMD
		    return CS_NOTIF_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NO_COUNT"))
#ifdef CS_NO_COUNT
		    return CS_NO_COUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NO_LIMIT"))
#ifdef CS_NO_LIMIT
		    return CS_NO_LIMIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NO_RECOMPILE"))
#ifdef CS_NO_RECOMPILE
		    return CS_NO_RECOMPILE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NO_TRUNCATE"))
#ifdef CS_NO_TRUNCATE
		    return CS_NO_TRUNCATE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NULLDATA"))
#ifdef CS_NULLDATA
		    return CS_NULLDATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NULLTERM"))
#ifdef CS_NULLTERM
		    return CS_NULLTERM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NUMDATA"))
#ifdef CS_NUMDATA
		    return CS_NUMDATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NUMERIC_TYPE"))
#ifdef CS_NUMERIC_TYPE
		    return CS_NUMERIC_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NUMORDERCOLS"))
#ifdef CS_NUMORDERCOLS
		    return CS_NUMORDERCOLS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_NUM_COMPUTES"))
#ifdef CS_NUM_COMPUTES
		    return CS_NUM_COMPUTES;
#else
		goto not_there;
#endif
		break;
	      case 'O':
		if (strEQ(name, "CS_OBJ_NAME"))
#ifdef CS_OBJ_NAME
		    return CS_OBJ_NAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPTION_GET"))
#ifdef CS_OPTION_GET
		    return CS_OPTION_GET;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_ANSINULL"))
#ifdef CS_OPT_ANSINULL
		    return CS_OPT_ANSINULL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_ANSIPERM"))
#ifdef CS_OPT_ANSIPERM
		    return CS_OPT_ANSIPERM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_ARITHABORT"))
#ifdef CS_OPT_ARITHABORT
		    return CS_OPT_ARITHABORT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_ARITHIGNORE"))
#ifdef CS_OPT_ARITHIGNORE
		    return CS_OPT_ARITHIGNORE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_AUTHOFF"))
#ifdef CS_OPT_AUTHOFF
		    return CS_OPT_AUTHOFF;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_AUTHON"))
#ifdef CS_OPT_AUTHON
		    return CS_OPT_AUTHON;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_CHAINXACTS"))
#ifdef CS_OPT_CHAINXACTS
		    return CS_OPT_CHAINXACTS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_CHARSET"))
#ifdef CS_OPT_CHARSET
		    return CS_OPT_CHARSET;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_CURCLOSEONXACT"))
#ifdef CS_OPT_CURCLOSEONXACT
		    return CS_OPT_CURCLOSEONXACT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_CURREAD"))
#ifdef CS_OPT_CURREAD
		    return CS_OPT_CURREAD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_CURWRITE"))
#ifdef CS_OPT_CURWRITE
		    return CS_OPT_CURWRITE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_DATEFIRST"))
#ifdef CS_OPT_DATEFIRST
		    return CS_OPT_DATEFIRST;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_DATEFORMAT"))
#ifdef CS_OPT_DATEFORMAT
		    return CS_OPT_DATEFORMAT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FIPSFLAG"))
#ifdef CS_OPT_FIPSFLAG
		    return CS_OPT_FIPSFLAG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FMTDMY"))
#ifdef CS_OPT_FMTDMY
		    return CS_OPT_FMTDMY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FMTDYM"))
#ifdef CS_OPT_FMTDYM
		    return CS_OPT_FMTDYM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FMTMDY"))
#ifdef CS_OPT_FMTMDY
		    return CS_OPT_FMTMDY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FMTMYD"))
#ifdef CS_OPT_FMTMYD
		    return CS_OPT_FMTMYD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FMTYDM"))
#ifdef CS_OPT_FMTYDM
		    return CS_OPT_FMTYDM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FMTYMD"))
#ifdef CS_OPT_FMTYMD
		    return CS_OPT_FMTYMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FORCEPLAN"))
#ifdef CS_OPT_FORCEPLAN
		    return CS_OPT_FORCEPLAN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FORMATONLY"))
#ifdef CS_OPT_FORMATONLY
		    return CS_OPT_FORMATONLY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_FRIDAY"))
#ifdef CS_OPT_FRIDAY
		    return CS_OPT_FRIDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_GETDATA"))
#ifdef CS_OPT_GETDATA
		    return CS_OPT_GETDATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_IDENTITYOFF"))
#ifdef CS_OPT_IDENTITYOFF
		    return CS_OPT_IDENTITYOFF;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_IDENTITYON"))
#ifdef CS_OPT_IDENTITYON
		    return CS_OPT_IDENTITYON;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_ISOLATION"))
#ifdef CS_OPT_ISOLATION
		    return CS_OPT_ISOLATION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_LEVEL1"))
#ifdef CS_OPT_LEVEL1
		    return CS_OPT_LEVEL1;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_LEVEL3"))
#ifdef CS_OPT_LEVEL3
		    return CS_OPT_LEVEL3;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_MONDAY"))
#ifdef CS_OPT_MONDAY
		    return CS_OPT_MONDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_NATLANG"))
#ifdef CS_OPT_NATLANG
		    return CS_OPT_NATLANG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_NOCOUNT"))
#ifdef CS_OPT_NOCOUNT
		    return CS_OPT_NOCOUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_NOEXEC"))
#ifdef CS_OPT_NOEXEC
		    return CS_OPT_NOEXEC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_PARSEONLY"))
#ifdef CS_OPT_PARSEONLY
		    return CS_OPT_PARSEONLY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_QUOTED_IDENT"))
#ifdef CS_OPT_QUOTED_IDENT
		    return CS_OPT_QUOTED_IDENT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_RESTREES"))
#ifdef CS_OPT_RESTREES
		    return CS_OPT_RESTREES;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_ROWCOUNT"))
#ifdef CS_OPT_ROWCOUNT
		    return CS_OPT_ROWCOUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_SATURDAY"))
#ifdef CS_OPT_SATURDAY
		    return CS_OPT_SATURDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_SHOWPLAN"))
#ifdef CS_OPT_SHOWPLAN
		    return CS_OPT_SHOWPLAN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_STATS_IO"))
#ifdef CS_OPT_STATS_IO
		    return CS_OPT_STATS_IO;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_STATS_TIME"))
#ifdef CS_OPT_STATS_TIME
		    return CS_OPT_STATS_TIME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_STR_RTRUNC"))
#ifdef CS_OPT_STR_RTRUNC
		    return CS_OPT_STR_RTRUNC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_SUNDAY"))
#ifdef CS_OPT_SUNDAY
		    return CS_OPT_SUNDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_TEXTSIZE"))
#ifdef CS_OPT_TEXTSIZE
		    return CS_OPT_TEXTSIZE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_THURSDAY"))
#ifdef CS_OPT_THURSDAY
		    return CS_OPT_THURSDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_TRUNCIGNORE"))
#ifdef CS_OPT_TRUNCIGNORE
		    return CS_OPT_TRUNCIGNORE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_TUESDAY"))
#ifdef CS_OPT_TUESDAY
		    return CS_OPT_TUESDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OPT_WEDNESDAY"))
#ifdef CS_OPT_WEDNESDAY
		    return CS_OPT_WEDNESDAY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OP_AVG"))
#ifdef CS_OP_AVG
		    return CS_OP_AVG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OP_COUNT"))
#ifdef CS_OP_COUNT
		    return CS_OP_COUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OP_MAX"))
#ifdef CS_OP_MAX
		    return CS_OP_MAX;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OP_MIN"))
#ifdef CS_OP_MIN
		    return CS_OP_MIN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_OP_SUM"))
#ifdef CS_OP_SUM
		    return CS_OP_SUM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ORDERBY_COLS"))
#ifdef CS_ORDERBY_COLS
		    return CS_ORDERBY_COLS;
#else
		goto not_there;
#endif
		break;
	      case 'P':
		if (strEQ(name, "CS_PACKAGE_CMD"))
#ifdef CS_PACKAGE_CMD
		    return CS_PACKAGE_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PACKETSIZE"))
#ifdef CS_PACKETSIZE
		    return CS_PACKETSIZE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PARAM_RESULT"))
#ifdef CS_PARAM_RESULT
		    return CS_PARAM_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PARENT_HANDLE"))
#ifdef CS_PARENT_HANDLE
		    return CS_PARENT_HANDLE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PARSE_TREE"))
#ifdef CS_PARSE_TREE
		    return CS_PARSE_TREE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PASSTHRU_EOM"))
#ifdef CS_PASSTHRU_EOM
		    return CS_PASSTHRU_EOM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PASSTHRU_MORE"))
#ifdef CS_PASSTHRU_MORE
		    return CS_PASSTHRU_MORE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PASSWORD"))
#ifdef CS_PASSWORD
		    return CS_PASSWORD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PENDING"))
#ifdef CS_PENDING
		    return CS_PENDING;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PREPARE"))
#ifdef CS_PREPARE
		    return CS_PREPARE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PREV"))
#ifdef CS_PREV
		    return CS_PREV;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROCNAME"))
#ifdef CS_PROCNAME
		    return CS_PROCNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROTO_BULK"))
#ifdef CS_PROTO_BULK
		    return CS_PROTO_BULK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROTO_DYNAMIC"))
#ifdef CS_PROTO_DYNAMIC
		    return CS_PROTO_DYNAMIC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROTO_DYNPROC"))
#ifdef CS_PROTO_DYNPROC
		    return CS_PROTO_DYNPROC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROTO_NOBULK"))
#ifdef CS_PROTO_NOBULK
		    return CS_PROTO_NOBULK;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROTO_NOTEXT"))
#ifdef CS_PROTO_NOTEXT
		    return CS_PROTO_NOTEXT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_PROTO_TEXT"))
#ifdef CS_PROTO_TEXT
		    return CS_PROTO_TEXT;
#else
		goto not_there;
#endif
		break;
	      case 'Q':
		if (strEQ(name, "CS_QUIET"))
#ifdef CS_QUIET
		    return CS_QUIET;
#else
		goto not_there;
#endif
		break;
	      case 'R':
		if (strEQ(name, "CS_READ_ONLY"))
#ifdef CS_READ_ONLY
		    return CS_READ_ONLY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REAL_TYPE"))
#ifdef CS_REAL_TYPE
		    return CS_REAL_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RECOMPILE"))
#ifdef CS_RECOMPILE
		    return CS_RECOMPILE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RELATIVE"))
#ifdef CS_RELATIVE
		    return CS_RELATIVE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RENAMED"))
#ifdef CS_RENAMED
		    return CS_RENAMED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_BCP"))
#ifdef CS_REQ_BCP
		    return CS_REQ_BCP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_CURSOR"))
#ifdef CS_REQ_CURSOR
		    return CS_REQ_CURSOR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_DYN"))
#ifdef CS_REQ_DYN
		    return CS_REQ_DYN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_LANG"))
#ifdef CS_REQ_LANG
		    return CS_REQ_LANG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_MSG"))
#ifdef CS_REQ_MSG
		    return CS_REQ_MSG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_MSTMT"))
#ifdef CS_REQ_MSTMT
		    return CS_REQ_MSTMT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_NOTIF"))
#ifdef CS_REQ_NOTIF
		    return CS_REQ_NOTIF;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_PARAM"))
#ifdef CS_REQ_PARAM
		    return CS_REQ_PARAM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_RPC"))
#ifdef CS_REQ_RPC
		    return CS_REQ_RPC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_REQ_URGNOTIF"))
#ifdef CS_REQ_URGNOTIF
		    return CS_REQ_URGNOTIF;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RES_NOEED"))
#ifdef CS_RES_NOEED
		    return CS_RES_NOEED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RES_NOMSG"))
#ifdef CS_RES_NOMSG
		    return CS_RES_NOMSG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RES_NOPARAM"))
#ifdef CS_RES_NOPARAM
		    return CS_RES_NOPARAM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RES_NOSTRIPBLANKS"))
#ifdef CS_RES_NOSTRIPBLANKS
		    return CS_RES_NOSTRIPBLANKS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RES_NOTDSDEBUG"))
#ifdef CS_RES_NOTDSDEBUG
		    return CS_RES_NOTDSDEBUG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RETURN"))
#ifdef CS_RETURN
		    return CS_RETURN;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ROWFMT_RESULT"))
#ifdef CS_ROWFMT_RESULT
		    return CS_ROWFMT_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ROW_COUNT"))
#ifdef CS_ROW_COUNT
		    return CS_ROW_COUNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ROW_FAIL"))
#ifdef CS_ROW_FAIL
		    return CS_ROW_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_ROW_RESULT"))
#ifdef CS_ROW_RESULT
		    return CS_ROW_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_RPC_CMD"))
#ifdef CS_RPC_CMD
		    return CS_RPC_CMD;
#else
		goto not_there;
#endif
		break;
	      case 'S':
		if (strEQ(name, "CS_SEC_APPDEFINED"))
#ifdef CS_SEC_APPDEFINED
		    return CS_SEC_APPDEFINED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SEC_CHALLENGE"))
#ifdef CS_SEC_CHALLENGE
		    return CS_SEC_CHALLENGE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SEC_ENCRYPTION"))
#ifdef CS_SEC_ENCRYPTION
		    return CS_SEC_ENCRYPTION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SEC_NEGOTIATE"))
#ifdef CS_SEC_NEGOTIATE
		    return CS_SEC_NEGOTIATE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SEND"))
#ifdef CS_SEND
		    return CS_SEND;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SEND_BULK_CMD"))
#ifdef CS_SEND_BULK_CMD
		    return CS_SEND_BULK_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SEND_DATA_CMD"))
#ifdef CS_SEND_DATA_CMD
		    return CS_SEND_DATA_CMD;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SENSITIVITY_TYPE"))
#ifdef CS_SENSITIVITY_TYPE
		    return CS_SENSITIVITY_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SERVERMSG_CB"))
#ifdef CS_SERVERMSG_CB
		    return CS_SERVERMSG_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SERVERMSG_TYPE"))
#ifdef CS_SERVERMSG_TYPE
		    return CS_SERVERMSG_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SERVERNAME"))
#ifdef CS_SERVERNAME
		    return CS_SERVERNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SET"))
#ifdef CS_SET
		    return CS_SET;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SETATTR"))
#ifdef CS_SETATTR
		    return CS_SETATTR;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SETCNT"))
#ifdef CS_SETCNT
		    return CS_SETCNT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SET_DBG_FILE"))
#ifdef CS_SET_DBG_FILE
		    return CS_SET_DBG_FILE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SET_FLAG"))
#ifdef CS_SET_FLAG
		    return CS_SET_FLAG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SET_PROTOCOL_FILE"))
#ifdef CS_SET_PROTOCOL_FILE
		    return CS_SET_PROTOCOL_FILE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SHORTMONTH"))
#ifdef CS_SHORTMONTH
		    return CS_SHORTMONTH;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SIGNAL_CB"))
#ifdef CS_SIGNAL_CB
		    return CS_SIGNAL_CB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SMALLINT_TYPE"))
#ifdef CS_SMALLINT_TYPE
		    return CS_SMALLINT_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SORT"))
#ifdef CS_SORT
		    return CS_SORT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SQLSTATE_SIZE"))
#ifdef CS_SQLSTATE_SIZE
		    return CS_SQLSTATE_SIZE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SRC_VALUE"))
#ifdef CS_SRC_VALUE
		    return CS_SRC_VALUE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_STATEMENTNAME"))
#ifdef CS_STATEMENTNAME
		    return CS_STATEMENTNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_STATUS"))
#ifdef CS_STATUS
		    return CS_STATUS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_STATUS_RESULT"))
#ifdef CS_STATUS_RESULT
		    return CS_STATUS_RESULT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SUB"))
#ifdef CS_SUB
		    return CS_SUB;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SUCCEED"))
#ifdef CS_SUCCEED
		    return CS_SUCCEED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_API_FAIL"))
#ifdef CS_SV_API_FAIL
		    return CS_SV_API_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_COMM_FAIL"))
#ifdef CS_SV_COMM_FAIL
		    return CS_SV_COMM_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_CONFIG_FAIL"))
#ifdef CS_SV_CONFIG_FAIL
		    return CS_SV_CONFIG_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_FATAL"))
#ifdef CS_SV_FATAL
		    return CS_SV_FATAL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_INFORM"))
#ifdef CS_SV_INFORM
		    return CS_SV_INFORM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_INTERNAL_FAIL"))
#ifdef CS_SV_INTERNAL_FAIL
		    return CS_SV_INTERNAL_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_RESOURCE_FAIL"))
#ifdef CS_SV_RESOURCE_FAIL
		    return CS_SV_RESOURCE_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SV_RETRY_FAIL"))
#ifdef CS_SV_RETRY_FAIL
		    return CS_SV_RETRY_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SYB_CHARSET"))
#ifdef CS_SYB_CHARSET
		    return CS_SYB_CHARSET;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SYB_LANG"))
#ifdef CS_SYB_LANG
		    return CS_SYB_LANG;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SYB_LANG_CHARSET"))
#ifdef CS_SYB_LANG_CHARSET
		    return CS_SYB_LANG_CHARSET;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SYB_SORTORDER"))
#ifdef CS_SYB_SORTORDER
		    return CS_SYB_SORTORDER;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_SYNC_IO"))
#ifdef CS_SYNC_IO
		    return CS_SYNC_IO;
#else
		goto not_there;
#endif
		break;
	      case 'T':
		if (strEQ(name, "CS_TABNAME"))
#ifdef CS_TABNAME
		    return CS_TABNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TABNUM"))
#ifdef CS_TABNUM
		    return CS_TABNUM;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TDS_40"))
#ifdef CS_TDS_40
		    return CS_TDS_40;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TDS_42"))
#ifdef CS_TDS_42
		    return CS_TDS_42;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TDS_46"))
#ifdef CS_TDS_46
		    return CS_TDS_46;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TDS_495"))
#ifdef CS_TDS_495
		    return CS_TDS_495;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TDS_50"))
#ifdef CS_TDS_50
		    return CS_TDS_50;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TDS_VERSION"))
#ifdef CS_TDS_VERSION
		    return CS_TDS_VERSION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TEXTLIMIT"))
#ifdef CS_TEXTLIMIT
		    return CS_TEXTLIMIT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TEXT_TYPE"))
#ifdef CS_TEXT_TYPE
		    return CS_TEXT_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_THREAD_RESOURCE"))
#ifdef CS_THREAD_RESOURCE
		    return CS_THREAD_RESOURCE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TIMED_OUT"))
#ifdef CS_TIMED_OUT
		    return CS_TIMED_OUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TIMEOUT"))
#ifdef CS_TIMEOUT
		    return CS_TIMEOUT;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TIMESTAMP"))
#ifdef CS_TIMESTAMP
		    return CS_TIMESTAMP;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TINYINT_TYPE"))
#ifdef CS_TINYINT_TYPE
		    return CS_TINYINT_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TP_SIZE"))
#ifdef CS_TP_SIZE
		    return CS_TP_SIZE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRANSACTION_NAME"))
#ifdef CS_TRANSACTION_NAME
		    return CS_TRANSACTION_NAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRANS_STATE"))
#ifdef CS_TRANS_STATE
		    return CS_TRANS_STATE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRAN_COMPLETED"))
#ifdef CS_TRAN_COMPLETED
		    return CS_TRAN_COMPLETED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRAN_FAIL"))
#ifdef CS_TRAN_FAIL
		    return CS_TRAN_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRAN_IN_PROGRESS"))
#ifdef CS_TRAN_IN_PROGRESS
		    return CS_TRAN_IN_PROGRESS;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRAN_STMT_FAIL"))
#ifdef CS_TRAN_STMT_FAIL
		    return CS_TRAN_STMT_FAIL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRAN_UNDEFINED"))
#ifdef CS_TRAN_UNDEFINED
		    return CS_TRAN_UNDEFINED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRUE"))
#ifdef CS_TRUE
		    return CS_TRUE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRUNCATED"))
#ifdef CS_TRUNCATED
		    return CS_TRUNCATED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TRYING"))
#ifdef CS_TRYING
		    return CS_TRYING;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_TS_SIZE"))
#ifdef CS_TS_SIZE
		    return CS_TS_SIZE;
#else
		goto not_there;
#endif
		break;
	      case 'U':
		if (strEQ(name, "CS_UNUSED"))
#ifdef CS_UNUSED
		    return CS_UNUSED;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_UPDATABLE"))
#ifdef CS_UPDATABLE
		    return CS_UPDATABLE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_UPDATECOL"))
#ifdef CS_UPDATECOL
		    return CS_UPDATECOL;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USERDATA"))
#ifdef CS_USERDATA
		    return CS_USERDATA;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USERNAME"))
#ifdef CS_USERNAME
		    return CS_USERNAME;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USER_ALLOC"))
#ifdef CS_USER_ALLOC
		    return CS_USER_ALLOC;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USER_FREE"))
#ifdef CS_USER_FREE
		    return CS_USER_FREE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USER_MAX_MSGID"))
#ifdef CS_USER_MAX_MSGID
		    return CS_USER_MAX_MSGID;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USER_MSGID"))
#ifdef CS_USER_MSGID
		    return CS_USER_MSGID;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USER_TYPE"))
#ifdef CS_USER_TYPE
		    return CS_USER_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_USE_DESC"))
#ifdef CS_USE_DESC
		    return CS_USE_DESC;
#else
		goto not_there;
#endif
		break;
	      case 'V':
		if (strEQ(name, "CS_VARBINARY_TYPE"))
#ifdef CS_VARBINARY_TYPE
		    return CS_VARBINARY_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_VARCHAR_TYPE"))
#ifdef CS_VARCHAR_TYPE
		    return CS_VARCHAR_TYPE;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_VERSION"))
#ifdef CS_VERSION
		    return CS_VERSION;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_VERSION_100"))
#ifdef CS_VERSION_100
		    return CS_VERSION_100;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_VERSION_KEY"))
#ifdef CS_VERSION_KEY
		    return CS_VERSION_KEY;
#else
		goto not_there;
#endif
		if (strEQ(name, "CS_VER_STRING"))
#ifdef CS_VER_STRING
		    return CS_VER_STRING;
#else
		goto not_there;
#endif
		break;
	      case 'W':
		if (strEQ(name, "CS_WILDCARD"))
#ifdef CS_WILDCARD
		    return CS_WILDCARD;
#else
		goto not_there;
#endif
		break;
	      case 'Z':
		if (strEQ(name, "CS_ZERO"))
#ifdef CS_ZERO
		    return CS_ZERO;
#else
		goto not_there;
#endif
		break;
	    }
	    break;
	  case 'T':
	    if (strEQ(name, "CTLIBVS"))
#ifdef CTLIBVS
		return CTLIBVS;
#else
	    goto not_there;
#endif
	    if (strEQ(name, "CT_BIND"))
#ifdef CT_BIND
		return CT_BIND;
#else
	    goto not_there;
#endif
	    if (strEQ(name, "CT_BR_COLUMN"))
#ifdef CT_BR_COLUMN
		return CT_BR_COLUMN;
#else
	    goto not_there;
#endif
	    if (strEQ(name, "CT_BR_TABLE"))
#ifdef CT_BR_TABLE
		return CT_BR_TABLE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CALLBACK"))
#ifdef CT_CALLBACK
	    return CT_CALLBACK;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CANCEL"))
#ifdef CT_CANCEL
	    return CT_CANCEL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CAPABILITY"))
#ifdef CT_CAPABILITY
	    return CT_CAPABILITY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CLOSE"))
#ifdef CT_CLOSE
	    return CT_CLOSE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CMD_ALLOC"))
#ifdef CT_CMD_ALLOC
	    return CT_CMD_ALLOC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CMD_DROP"))
#ifdef CT_CMD_DROP
	    return CT_CMD_DROP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CMD_PROPS"))
#ifdef CT_CMD_PROPS
	    return CT_CMD_PROPS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_COMMAND"))
#ifdef CT_COMMAND
	    return CT_COMMAND;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_COMPUTE_INFO"))
#ifdef CT_COMPUTE_INFO
	    return CT_COMPUTE_INFO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CONFIG"))
#ifdef CT_CONFIG
	    return CT_CONFIG;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CONNECT"))
#ifdef CT_CONNECT
	    return CT_CONNECT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CON_ALLOC"))
#ifdef CT_CON_ALLOC
	    return CT_CON_ALLOC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CON_DROP"))
#ifdef CT_CON_DROP
	    return CT_CON_DROP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CON_PROPS"))
#ifdef CT_CON_PROPS
	    return CT_CON_PROPS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CON_XFER"))
#ifdef CT_CON_XFER
	    return CT_CON_XFER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_CURSOR"))
#ifdef CT_CURSOR
	    return CT_CURSOR;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_DATA_INFO"))
#ifdef CT_DATA_INFO
	    return CT_DATA_INFO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_DEBUG"))
#ifdef CT_DEBUG
	    return CT_DEBUG;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_DESCRIBE"))
#ifdef CT_DESCRIBE
	    return CT_DESCRIBE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_DIAG"))
#ifdef CT_DIAG
	    return CT_DIAG;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_DYNAMIC"))
#ifdef CT_DYNAMIC
	    return CT_DYNAMIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_DYNDESC"))
#ifdef CT_DYNDESC
	    return CT_DYNDESC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_EXIT"))
#ifdef CT_EXIT
	    return CT_EXIT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_FETCH"))
#ifdef CT_FETCH
	    return CT_FETCH;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_GETFORMAT"))
#ifdef CT_GETFORMAT
	    return CT_GETFORMAT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_GETLOGINFO"))
#ifdef CT_GETLOGINFO
	    return CT_GETLOGINFO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_GET_DATA"))
#ifdef CT_GET_DATA
	    return CT_GET_DATA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_INIT"))
#ifdef CT_INIT
	    return CT_INIT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_KEYDATA"))
#ifdef CT_KEYDATA
	    return CT_KEYDATA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_LABELS"))
#ifdef CT_LABELS
	    return CT_LABELS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_NOTIFICATION"))
#ifdef CT_NOTIFICATION
	    return CT_NOTIFICATION;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_OPTIONS"))
#ifdef CT_OPTIONS
	    return CT_OPTIONS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_PARAM"))
#ifdef CT_PARAM
	    return CT_PARAM;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_POLL"))
#ifdef CT_POLL
	    return CT_POLL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_RECVPASSTHRU"))
#ifdef CT_RECVPASSTHRU
	    return CT_RECVPASSTHRU;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_REMOTE_PWD"))
#ifdef CT_REMOTE_PWD
	    return CT_REMOTE_PWD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_RESULTS"))
#ifdef CT_RESULTS
	    return CT_RESULTS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_RES_INFO"))
#ifdef CT_RES_INFO
	    return CT_RES_INFO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_SEND"))
#ifdef CT_SEND
	    return CT_SEND;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_SENDPASSTHRU"))
#ifdef CT_SENDPASSTHRU
	    return CT_SENDPASSTHRU;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_SEND_DATA"))
#ifdef CT_SEND_DATA
	    return CT_SEND_DATA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_SETLOGINFO"))
#ifdef CT_SETLOGINFO
	    return CT_SETLOGINFO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_USER_FUNC"))
#ifdef CT_USER_FUNC
	    return CT_USER_FUNC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "CT_WAKEUP"))
#ifdef CT_WAKEUP
	    return CT_WAKEUP;
#else
	    goto not_there;
#endif
	    break;
	}
    case 'S':
	if (strEQ(name, "SQLCA_TYPE"))
#ifdef SQLCA_TYPE
	    return SQLCA_TYPE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQLCODE_TYPE"))
#ifdef SQLCODE_TYPE
	    return SQLCODE_TYPE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "SQLSTATE_TYPE"))
#ifdef SQLSTATE_TYPE
	    return SQLSTATE_TYPE;
#else
	    goto not_there;
#endif
	break;
    }
    errno = EINVAL;
    return 0;

not_there:
    errno = ENOENT;
    return 0;
}


MODULE = Sybase::CTlib		PACKAGE = Sybase::CTlib

BOOT:
initialize();

double
constant(name,arg)
	char *		name
	int		arg

void
ct_connect(package="Sybase::CTlib", user=NULL, pwd=NULL, server=NULL, appname=NULL)
	char *	package
	char *	user
	char *	pwd
	char *	server
	char *	appname
  CODE:
{
    ConInfo *info;
    CS_CONNECTION *connection = NULL;
    CS_COMMAND *cmd;
    CS_RETCODE retcode;
    CS_INT len;
    SV *rv;
    SV *sv;
    HV *hv;
    HV *stash;

    if((retcode = ct_con_alloc(context, &connection)) != CS_SUCCEED)
	warn("ct_con_alloc failed");

    if(retcode == CS_SUCCEED && user && *user)
    {
	if((retcode = ct_con_props(connection, CS_SET, CS_USERNAME, 
				   user, CS_NULLTERM, NULL)) != CS_SUCCEED)
	    warn("ct_con_props(username) failed");
    }
    if(retcode == CS_SUCCEED && pwd && *pwd)
    {
	if((retcode = ct_con_props(connection, CS_SET, CS_PASSWORD, 
				   pwd, CS_NULLTERM, NULL)) != CS_SUCCEED)
	    warn("ct_con_props(password) failed");
    }
    if(retcode == CS_SUCCEED && appname && *appname)
    {
	if((retcode = ct_con_props(connection, CS_SET, CS_APPNAME, 
				   appname, CS_NULLTERM, NULL)) != CS_SUCCEED)
	    warn("ct_con_props(appname) failed");
    }

    if (retcode == CS_SUCCEED)
    {
	len = (server == NULL || !*server) ? 0 : CS_NULLTERM;
	if((retcode = ct_connect(connection, server, len)) != CS_SUCCEED)
	    warn("ct_connect failed");
    }

    if(retcode != CS_SUCCEED)
    {
	if(connection)
	    ct_con_drop(connection);
	ST(0) = sv_newmortal();
    }
    else
    {
	if((retcode = ct_cmd_alloc(connection, &cmd)) != CS_SUCCEED)
	{
	    warn("ct_cmd_alloc failed");
	    ct_con_drop(connection);
	    ST(0) = sv_newmortal();
	}
	else
	{
	    New(902, info, 1, ConInfo);
	    info->type = CON_CONNECTION;
	    info->connection = connection;
	    info->cmd = cmd;
	    info->numCols = 0;
	    info->coldata = NULL;
	    info->datafmt = NULL;
#if 0
	    info->paramHead = NULL;
#endif
	
	    hv = (HV*)sv_2mortal((SV*)newHV());
	    sv = newSViv((IV)info);
	    my_hv_store(hv, HV_coninfo, sv, 0);
	    rv = newRV((SV*)hv);
	    stash = gv_stashpv(package, TRUE);
	    ST(0) = sv_2mortal(sv_bless(rv, stash));
	}
    }
}



void
DESTROY(dbp)
	SV *	dbp
  CODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_RETCODE	retcode;
    CS_INT	close_option;

    /* FIXME:
       must check for pending results, and maybe cancel those before
       dropping the cmd structure. */
    
    ct_cmd_drop(info->cmd);

    if(info->type == CON_CONNECTION)
    {
	close_option = CS_FORCE_CLOSE;
	if((retcode = ct_close(info->connection, close_option)) != CS_SUCCEED)
	    warn("ct_close() failed");
	else
	    if((retcode = ct_con_drop(info->connection)) != CS_SUCCEED)
		warn("ct_con_drop() failed");
    }
    if(info->numCols)
    {
	Safefree(info->coldata);
	Safefree(info->datafmt);
    }
    Safefree(info);
}

int
ct_execute(dbp, query)
	SV *	dbp
	char *	query
  CODE:
{
    CS_COMMAND *cmd = get_cmd(dbp);
    CS_RETCODE ret;

    ret = ct_command(cmd, CS_LANG_CMD, query, CS_NULLTERM, CS_UNUSED);
    if(ret == CS_SUCCEED)
	ret = ct_send(cmd);
    RETVAL = ret;
}
OUTPUT:
RETVAL


int
ct_command(dbp, type, buffer, len, opt)
	SV *	dbp
	int	type
	char *	buffer
	int	len
	int	opt
CODE:
{
    CS_COMMAND *cmd = get_cmd(dbp);

    RETVAL = ct_command(cmd, type, buffer, len, opt);
}
OUTPUT:
RETVAL

int
ct_send(dbp)
	SV *	dbp
CODE:
{
    CS_COMMAND *cmd = get_cmd(dbp);

    RETVAL = ct_send(cmd);
}
OUTPUT:
RETVAL


int
ct_results(dbp, restype)
	SV *	dbp
	int	restype
CODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_INT retcode;

    if((RETVAL = ct_results(info->cmd, (CS_INT *)&restype)) == CS_SUCCEED)
    {
	info->lastResult = restype;
	switch(restype)
	{
	  case CS_CMD_DONE:
	  case CS_CMD_FAIL:
	  case CS_CMD_SUCCEED:
	    break;
	  case CS_COMPUTEFMT_RESULT:
	  case CS_ROWFMT_RESULT:
	  case CS_MSG_RESULT:
	  case CS_DESCRIBE_RESULT:
	    break;
	  case CS_COMPUTE_RESULT:
	  case CS_CURSOR_RESULT:
	  case CS_PARAM_RESULT:
	  case CS_ROW_RESULT:
	  case CS_STATUS_RESULT:
	    retcode = describe(info, dbp, restype);
	    break;
	}
    }
#if 0
    /* Free the parameter info if we're done fetching parameter type
       results */

    if(info->lastResult == CS_PARAM_RESULT && restype != CS_PARAM_RESULT)
    {
	struct ParamInfo *ptr = info->paramHead;
	struct ParamInfo *next;
	
	for(; ptr; ptr = next)
	{
	    next = ptr->next;
	    if(ptr->type == CS_CHAR_TYPE)
		Safefree(ptr->u.c);
	    Safefree(ptr);
	}
	info->paramHead = NULL;
    }
#endif
}
OUTPUT:
restype
RETVAL

void
ct_col_names(dbp)
	SV *	dbp
  PPCODE:
{
    ConInfo *info = get_ConInfo(dbp);
    int i;

    for(i = 0; i < info->numCols; ++i)
	XPUSHs(sv_2mortal(newSVpv(info->datafmt[i].name, 0)));
}

void
ct_col_types(dbp, doAssoc=0)
	SV *	dbp
	int	doAssoc
  PPCODE:
{
    ConInfo *info = get_ConInfo(dbp);
    int i;

    for(i = 0; i < info->numCols; ++i)
    {
	if(doAssoc)
	    XPUSHs(sv_2mortal(newSVpv(info->datafmt[i].name, 0)));
	XPUSHs(sv_2mortal(newSViv((CS_INT)info->datafmt[i].datatype)));
    }
}

int
ct_cancel(dbp, type)
	SV *	dbp
	int	type
CODE:
{
    CS_CONNECTION *connection = get_con(dbp);
    CS_COMMAND *cmd = get_cmd(dbp);

    switch(type)
    {
      default:
	break;
    }
    RETVAL = ct_cancel(connection, cmd, type);
}
OUTPUT:
RETVAL

void
ct_fetch(dbp, doAssoc=0)
    SV *	dbp
    int		doAssoc
PPCODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_RETCODE retcode;
    CS_INT rows_read;
    int i, len;
#if defined(UNDEF_BUG)
    int n_null = doAssoc;
#endif

  TryAgain:;
    retcode = ct_fetch(info->cmd, CS_UNUSED, CS_UNUSED, CS_UNUSED, &rows_read);

    switch(retcode)
    {
      case CS_ROW_FAIL:		/* not sure how I should handle this one! */
	goto TryAgain;
      case CS_SUCCEED:
	for(i = 0; i < info->numCols; ++i)
	{
	    len = 0;
	    if(doAssoc)
		XPUSHs(sv_2mortal(newSVpv(info->datafmt[i].name, 0)));

	    if(info->coldata[i].indicator == CS_NULLDATA) /* NULL data */
		XPUSHs(&sv_undef);
	    else
	    {
		switch(info->datafmt[i].datatype)
		{
		  case CS_TEXT_TYPE:
		    len = info->coldata[i].valuelen;
		  case CS_CHAR_TYPE:
		    XPUSHs(sv_2mortal(newSVpv(info->coldata[i].value.c,
					      len)));
		    break;
		  case CS_FLOAT_TYPE:
		    XPUSHs(sv_2mortal(newSVnv(info->coldata[i].value.f)));
		    break;
		  case CS_INT_TYPE:
		    XPUSHs(sv_2mortal(newSViv(info->coldata[i].value.i)));
		    break;
		}
#if defined(UNDEF_BUG)
		++n_null;
#endif
	    }
	}
#if defined(UNDEF_BUG)
	if(!n_null)
	    XPUSHs(sv_2mortal(newSVpv("__ALL NULL__", 0)));
#endif
	break;
      case CS_FAIL:		/* ohmygod */
	/* FIXME: Should we call ct_cancel() here, or should we let
	   the programmer handle it? */
	if(ct_cancel(info->connection, NULL, CS_CANCEL_ALL) == CS_FAIL)
	    croak("ct_cancel() failed - dying");
	/* FallThrough to next case! */
      case CS_END_DATA:		/* we've seen all the data for this
    				   result set, so cleanup now */
	cleanUp(info);
	break;
      default:
	warn("ct_fetch() returned an unexpected retcode");
    }
}


void
ct_options(dbp, action, option, param, type)
	SV *	dbp
	int	action
	int	option
	SV *	param
	int	type
PPCODE:
{
    CS_CONNECTION *connection = get_con(dbp);
    CS_VOID *param_ptr;
    char buff[256];
    CS_INT param_len = CS_UNUSED;
    CS_INT outlen, *outptr = NULL;
    CS_INT int_param;
    CS_RETCODE retcode;

    if(action == CS_GET)
    {
	if(type == CS_INT_TYPE)
	    param_ptr = &int_param;
	else
	    param_ptr = buff;
	param_len = CS_UNUSED;
	outptr = &outlen;
    }
    else if(action == CS_SET)
    {
	if(type == CS_INT_TYPE)
	{
	    int_param = SvIV(param);
	    param_ptr = &int_param;
	    param_len = CS_UNUSED;
	}
	else
	{
	    param_ptr = SvPV(param, na);
	    param_len = CS_NULLTERM;
	}
    }
    else
    {
	param_ptr = NULL;
	param_len = CS_UNUSED;
    }
    
    retcode = ct_options(connection, action, option,
			 param_ptr, param_len, outptr);
    
    XPUSHs(sv_2mortal(newSViv(retcode)));
    if(action == CS_GET)
    {
	if(type == CS_INT_TYPE)
	    XPUSHs(sv_2mortal(newSViv(int_param)));
	else
	    XPUSHs(sv_2mortal(newSVpv(buff, 0)));
    }
}

int
ct_res_info(dbp, info_type)
	SV *	dbp
	int	info_type
  CODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_RETCODE retcode;
    CS_INT res_info;

    if((retcode = ct_res_info(info->cmd, info_type, &res_info, CS_UNUSED, NULL)) !=
       CS_SUCCEED)
	RETVAL = retcode;
    else
	RETVAL = res_info;
}
OUTPUT:
RETVAL

void
ct_callback(type, func)
	int	type
	SV *	func
CODE:
{
    char *name;
    CallBackInfo *ci;
    SV *ret = NULL;

    switch(type)
    {
      case CS_CLIENTMSG_CB:
	ci = &client_cb;
	break;
      case CS_SERVERMSG_CB:
	ci = &server_cb;
	break;
      default:
	croak("Unsupported callback type");
    }
    
    if(ci->sub)
	ret = newSVsv(ci->sub);
    if(func == &sv_undef)
	ci->sub = NULL;
    else
    {
	if(!SvROK(func))
	{
	    name = SvPV(func, na);
	    if((func = (SV*) perl_get_cv(name, FALSE)))
		ci->sub = func;
	}
	else
	{
	    if(ci->sub == (SV*) NULL)
		ci->sub = newSVsv(func);
	    else
		SvSetSV(ci->sub, func);
	}
    }
    if(ret)
	ST(0) = sv_2mortal(newRV(ret));
    else
	ST(0) = sv_newmortal();
}


int
ct_cursor(dbp, type, sv_name, sv_text, option)
	SV *	dbp
	int	type
	SV *	sv_name
	SV *	sv_text
	int	option
CODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_RETCODE retcode;
    CS_CHAR *name = NULL;
    CS_INT namelen = CS_UNUSED;
    CS_CHAR *text = NULL;
    CS_INT textlen = CS_UNUSED;

    /* passing undef means a NULL value... */
    if(sv_name != &sv_undef)
    {
	name = SvPV(sv_name, na);
	namelen = CS_NULLTERM;
    }
    if(sv_text != &sv_undef)
    {
	text = SvPV(sv_text, na);
	textlen = CS_NULLTERM;
    }
    
    retcode = ct_cursor(info->cmd, type, name, namelen, text, textlen,
			option);

    RETVAL = retcode;
}
OUTPUT:
RETVAL

int
ct_param(dbp, sv_params)
	SV *	dbp
	SV *	sv_params
  CODE:
{
#if !defined COUNT
# define COUNT(x)	(sizeof(x)/ sizeof(*x))
#endif
    ConInfo *info = get_ConInfo(dbp);
    HV *hv;
    SV **svp;
    CS_RETCODE retcode;
    CS_DATAFMT datafmt;
#if 0
    struct ParamInfo *ptr;
#endif
    enum {
	k_name, k_datatype,
	k_status, k_indicator, k_value} key_id;
    static char *keys[] = {"name", "datatype", "status", "indicator", "value"};
    int i;
    int v_i;
    double v_f;
    CS_SMALLINT indicator = 0;
    CS_INT datalen = CS_UNUSED;
    CS_VOID *value = NULL;
    
    memset(&datafmt, 0, sizeof(datafmt));
    
    if(!SvROK(sv_params))
	croak("datafmt parameter is not a reference");
    hv = (HV *)SvRV(sv_params);

    /* We need to check the coherence of the keys that are in the hash
       table: */
    if(hv_iterinit(hv))
    {
	HE *he;
	char *key;
	STRLEN klen;
	while((he = hv_iternext(hv)))
	{
	    key = hv_iterkey(he, &klen);
	    for(i = 0; i < COUNT(keys); ++i)
		if(!strncmp(keys[i], key, klen))
		    break;
	    if(i == COUNT(keys))
		warn("Warning: invalid key '%s' in ct_param hash", key); /* FIXME!!! */
	}
    }
    if((svp = hv_fetch(hv, keys[k_name], strlen(keys[k_name]), FALSE)))
    {
	strcpy(datafmt.name, SvPV(*svp, na));
	datafmt.namelen = CS_NULLTERM; /*strlen(datafmt.name);*/
    }
    if((svp = hv_fetch(hv, keys[k_datatype], strlen(keys[k_datatype]), FALSE)))
	datafmt.datatype = SvIV(*svp);
    else
	datafmt.datatype = CS_CHAR_TYPE; /* default data type */
    
    if((svp = hv_fetch(hv, keys[k_status], strlen(keys[k_status]), FALSE)))
	datafmt.status = SvIV(*svp);
    
    svp = hv_fetch(hv, keys[k_value], strlen(keys[k_value]), FALSE);
#if 0
    New(902, ptr, 1, struct ParamInfo);
#endif
    /* FIXME:
       money & decimal/numeric types are treated as double precision
       floating point. */
    switch(datafmt.datatype)
    {
      case CS_BIT_TYPE:
      case CS_TINYINT_TYPE:
      case CS_SMALLINT_TYPE:
      case CS_INT_TYPE:
	datafmt.datatype = CS_INT_TYPE;
	if(svp || datafmt.status == CS_RETURN)
	{
	    datalen = datafmt.maxlength = CS_SIZEOF(CS_INT);
	    if(svp)
	    {
		v_i = SvIV(*svp);
		value = &v_i;
	    }
	}
	break;
      case CS_FLOAT_TYPE:
      case CS_REAL_TYPE:
      case CS_NUMERIC_TYPE:
      case CS_DECIMAL_TYPE:
      case CS_MONEY_TYPE:
      case CS_MONEY4_TYPE:
	datafmt.datatype = CS_FLOAT_TYPE;
	if(svp || datafmt.status == CS_RETURN)
	{
	    datalen = datafmt.maxlength = CS_SIZEOF(CS_FLOAT);
	    if(svp)
	    {
		v_f = SvNV(*svp);
		value = &v_f;
	    }
	}
	break;
      case CS_TEXT_TYPE:
      case CS_IMAGE_TYPE:
	warn("CS_TEXT_TYPE or CS_IMAGE_TYPE is invalid for ct_param - converting to CS_CHAR_TYPE");
      case CS_CHAR_TYPE:
      case CS_VARCHAR_TYPE:
      case CS_BINARY_TYPE:
      case CS_VARBINARY_TYPE:
      case CS_DATETIME_TYPE:
      case CS_DATETIME4_TYPE:
	    
      default:			/* assume CS_CHAR_TYPE */
	datafmt.datatype = CS_CHAR_TYPE;
	if(svp || datafmt.status == CS_RETURN)
	{
	    datafmt.maxlength = 255; /* FIXME???*/
	    if(svp)
	    {
		STRLEN klen;
		
		value = SvPV(*svp, klen);
		datalen = klen; /*strlen(ptr->u.c); */
	    }
	}
    }
        
    if((svp = hv_fetch(hv, keys[k_indicator], strlen(keys[k_indicator]), FALSE)))
	indicator = SvIV(*svp);
    

    retcode = ct_param(info->cmd, &datafmt, value, datalen, indicator);

    RETVAL = retcode;
}
OUTPUT:
RETVAL
