/* -*-C-*-
 *	@(#)CTlib.xs	1.31	12/30/97
 */


/* Copyright (c) 1995-1997
   Michael Peppler

   Parts of this file are
   Copyright (c) 1995 Sybase, Inc.

   You may copy this under the terms of the GNU General Public License,
   or the Artistic License, copies of which should have accompanied
   your Perl kit. */

   
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#if defined(op)
#undef op
#endif
#if !defined(dTHR)
#define dTHR 	extern int errno
#endif

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


typedef struct _col_data
{
    CS_SMALLINT	indicator;
    CS_INT	type;
    CS_INT      realtype;
    union {
	CS_CHAR	*c;
	CS_INT i;
	CS_FLOAT f;
	CS_DATETIME dt;
	CS_MONEY mn;
	CS_NUMERIC num;
    } value;
    CS_INT	valuelen;
} ColData;

typedef enum
{
    CON_CONNECTION,
    CON_CMD,
    CON_EED_CMD
} ConType;

typedef struct _ref_con
{
    CS_CONNECTION *connection;
    int refcount;
} RefCon;


struct attribs {
    int UseDateTime;
    int UseMoney;
    int UseNumeric;
    int MaxRows;
    int ComputeId;
    int ExtendedError;
    int RowCount;
    int RC;
    int pid;
    HV *other;
};

typedef struct _con_info
{
    ConType type;
    int numCols;
    
    ColData *coldata;
    CS_DATAFMT *datafmt;
    RefCon *connection;
    CS_COMMAND *cmd;
    CS_INT lastResult;

    AV *av;
    HV *hv;

    struct attribs attr;
} ConInfo;


typedef struct
{
    SV *	sub ;
} CallBackInfo ;

static CallBackInfo server_cb 	= { 0 } ;
static CallBackInfo client_cb 	= { 0 } ;

typedef enum hash_key_id
{
    HV_use_datetime,
    HV_use_money,
    HV_use_numeric,
    HV_max_rows,
    HV_compute_id,
    HV_extended_error,
    HV_row_count,
    HV_rc,
    HV_pid,
    HV_coninfo
} hash_key_id;

static struct _hash_keys {
    char *key;
    int  id;
} hash_keys[] = {
    { "UseDateTime", HV_use_datetime },
    { "UseMoney",    HV_use_money },
    { "UseNumeric",  HV_use_numeric },
    { "MaxRows",     HV_max_rows },
    { "ComputeId",   HV_compute_id },
    { "ExtendedError", HV_extended_error },
    { "ROW_COUNT",   HV_row_count },
    { "RC",          HV_rc },
    { "__PID__",     HV_pid },
    {"__coninfo__",  HV_coninfo },
    { "",            -1 }
};

static CS_CONTEXT *context;

/* Debugging/tracing: */
#define TRACE_NONE	(0)
#define TRACE_DESTROY	(1 << 0)
#define TRACE_CREATE	(1 << 1)
#define TRACE_RESULTS	(1 << 2)
#define TRACE_FETCH	(1 << 3)
#define TRACE_CURSOR	(1 << 4)
#define TRACE_PARAMS	(1 << 5)
#define TRACE_OVERLOAD  (1 << 6)
#define TRACE_SQL	(1 << 7)
#define TRACE_ALL	((unsigned int)(~0))
static unsigned int debug_level = TRACE_NONE;

static char scriptName[255];

static char DateTimePkg[]="Sybase::CTlib::DateTime";
static char MoneyPkg[]="Sybase::CTlib::Money";
static char NumericPkg[]="Sybase::CTlib::Numeric";

static int attr_store _((ConInfo*, char*, int, SV*, int));
static SV* attr_fetch _((ConInfo*, char*, int));
static SV *newdbh _((ConInfo *, char *, SV*, SV*));
static ConInfo *get_ConInfoFromMagic _((HV*));
static ConInfo *get_ConInfo _((SV*));
static char *neatsvpv _((SV*, STRLEN));
static CS_DATETIME to_datetime _((char*));
static char *from_datetime _((CS_DATETIME*));
static SV *newdate _((CS_DATETIME*));
static CS_MONEY to_money _((char *));
static char *from_money _((CS_MONEY*));
static CS_FLOAT money2float _((CS_MONEY *));
static SV *newmoney _((CS_MONEY*));
static CS_NUMERIC to_numeric _((char*));
static char *from_numeric _((CS_NUMERIC*));
static CS_FLOAT numeric2float _((CS_NUMERIC *));
static SV *newnumeric _((CS_NUMERIC*));
static CS_CONNECTION *get_con _((SV*));
static CS_COMMAND *get_cmd _((SV*));
static void cleanUp _((ConInfo *));
static char *GetAggOp _((CS_INT));
static CS_INT display_dlen _((CS_DATAFMT *));
static CS_RETCODE display_header _((CS_INT, CS_DATAFMT*));
static CS_RETCODE describe _((ConInfo *, SV*, int));
static CS_RETCODE fetch_data _((CS_COMMAND*));
static CS_RETCODE clientmsg_cb _((CS_CONTEXT*, CS_CONNECTION*, CS_CLIENTMSG*));
static CS_RETCODE servermsg_cb _((CS_CONTEXT*, CS_CONNECTION*, CS_SERVERMSG*));
static CS_RETCODE notification_cb _((CS_CONNECTION*, CS_CHAR*, CS_INT));
static void initialize _((void));
static int not_here _((char*));
static double constant _((char*,int));



static int
attr_store(info, key, keylen, sv, flag)
    ConInfo *info;
    char *key;
    int keylen;
    SV *sv;
    int flag;
{
    int i;
    
    for(i = 0; hash_keys[i].id >= 0; ++i)
	if(strlen(hash_keys[i].key) == keylen && strEQ(key, hash_keys[i].key))
	    break;

    if(hash_keys[i].id < 0) {
#if defined(DO_TIE)
	if(!flag) {
	    if(!hv_exists(info->attr.other, key, keylen)) {
		warn("'%s' is not a valid Sybase::CTlib attribute", key);
		return 0;
	    }
	}
#endif
	hv_store(info->attr.other, key, keylen, newSVsv(sv), 0);
	return 1;
    }

    switch(hash_keys[i].id) {
      case HV_use_datetime:
	  info->attr.UseDateTime   = SvTRUE(sv);
	  break;
      case HV_use_money:
	  info->attr.UseMoney      = SvTRUE(sv);
	  break;
      case HV_use_numeric:
	  info->attr.UseNumeric    = SvTRUE(sv);
	  break;
      case HV_max_rows:
	  info->attr.MaxRows       = SvIV(sv);
	  break;
      case HV_compute_id:
	  info->attr.ComputeId     = SvIV(sv);
	  break;
      case HV_extended_error:
	  info->attr.ExtendedError = SvIV(sv);
	  break;
      case HV_row_count:
	  info->attr.RowCount      = SvIV(sv);
	  break;
      case HV_rc:
	  info->attr.RC            = SvIV(sv);
	  break;
      case HV_pid:
	  info->attr.pid           = SvIV(sv);
	  break;
      default:
	  return 0;
    }

    return 1;
}

static SV*
attr_fetch(info, key, keylen)
    ConInfo *info;
    char *key;
    int keylen;
{
    int i;
    SV *sv = Nullsv;
    
    for(i = 0; hash_keys[i].id >= 0; ++i)
	if(strlen(hash_keys[i].key) == keylen && strEQ(key, hash_keys[i].key))
	    break;

    if(hash_keys[i].id < 0) {
	SV **svp;
#if defined(DO_TIE)
	if(!hv_exists(info->attr.other, key, keylen)) {
	    warn("'%s' is not a valid Sybase::CTlib attribute", key);
	    return Nullsv;
	}
#endif
	svp = hv_fetch(info->attr.other, key, keylen, 0);
	return svp ? *svp : Nullsv;
    }

    switch(hash_keys[i].id) {
      case HV_use_datetime:
	  sv = newSViv(info->attr.UseDateTime);
	  break;
      case HV_use_money:
	  sv = newSViv(info->attr.UseMoney);
	  break;
      case HV_use_numeric:
	  sv = newSViv(info->attr.UseNumeric);
	  break;
      case HV_max_rows:
	  sv = newSViv(info->attr.MaxRows);
	  break;
      case HV_compute_id:
	  sv = newSViv(info->attr.ComputeId);
	  break;
      case HV_extended_error:
	  sv = newSViv(info->attr.ExtendedError);
	  break;
      case HV_row_count:
	  sv = newSViv(info->attr.RowCount);
	  break;
      case HV_rc:
	  sv = newSViv(info->attr.RC);
	  break;
      case HV_pid:
	  sv = newSViv(info->attr.pid);
	  break;
      case HV_coninfo:
	  sv = newSViv((IV)info);
	  break;
      default:
	  return Nullsv;
    }

    return sv;
}


static SV *
newdbh(info, package, attr_ref, dbp)
    ConInfo *info;
    char *package;
    SV *attr_ref;
    SV *dbp;
{
    HV *hv, *thv, *stash, *Att;
    SV *rv, *sv, **svp;
    int count;

    /* If this is a cmd_alloc, then copy the old attribute values
       to this db handle */
    if(dbp != NULL && dbp != &sv_undef && SvROK(dbp))
    {
	ConInfo *tmp = get_ConInfo(dbp);
	Copy(&tmp->attr, &info->attr, 1, struct attribs);
    }
    info->attr.other = newHV();
    info->av = newAV();
    info->hv = newHV();
    
    thv = (HV*)sv_2mortal((SV*)newHV());
    /* FIXME
       This creates a small memory leak, because the tied _attribs hash
       does not get automatically destroyed when the dbhandle goes out of
       scope. */
    sv = newSViv((IV)info);
    sv_magic((SV*)thv, sv, '~', "CTlib", 5);
    rv = newRV((SV*)thv);
    stash = gv_stashpv("Sybase::CTlib::_attribs", TRUE);
    (void)sv_bless(rv, stash);
    hv = (HV*)sv_2mortal((SV*)newHV());

    /* Turn on the 'tie' magic */
    sv_magic((SV*)hv, rv, 'P', Nullch, 0);
    sv_magic((SV*)hv, sv, '~', "CTlib", 5);

    if((attr_ref != &sv_undef)) {
	if(!SvROK(attr_ref))
	    warn("Attributes parameter is not a reference");
	else
	{
	    char *key;
	    I32 klen;
	    HV *nhv = (HV*)SvRV(attr_ref);
	    hv_iterinit(nhv);
	    while((sv = hv_iternextsv(nhv, &key, &klen))) {
		attr_store(info, key, klen, sv, 1);
	    }
	}
    }
    /* If this is a cmd_alloc, then copy the old attribute values
       to this db handle */
    if(dbp != NULL && dbp != &sv_undef && SvROK(dbp))
    {
	ConInfo *tmp = get_ConInfo(dbp);
	char *key;
	I32 klen;
	HV *nhv = tmp->attr.other;
	hv_iterinit(nhv);
	while((sv = hv_iternextsv(nhv, &key, &klen)))
	    attr_store(info, key, klen, sv, 1);
    }
    else
    {
	if((Att = perl_get_hv("Sybase::CTlib::Att", FALSE)))
	{
	    if((svp = hv_fetch(Att, hash_keys[HV_use_datetime].key, 
			       strlen(hash_keys[HV_use_datetime].key), 0)))
		info->attr.UseDateTime = SvTRUE(*svp);
	    else
		info->attr.UseDateTime = 0;
	    if((svp = hv_fetch(Att, hash_keys[HV_use_money].key, 
			       strlen(hash_keys[HV_use_money].key), 0)))
		info->attr.UseMoney = SvTRUE(*svp);
	    else
		info->attr.UseMoney = 0;
	    if((svp = hv_fetch(Att, hash_keys[HV_use_numeric].key,
			       strlen(hash_keys[HV_use_numeric].key), 0)))
		info->attr.UseNumeric = SvTRUE(*svp);
	    else
		info->attr.UseNumeric = 0;
	    if((svp = hv_fetch(Att, hash_keys[HV_max_rows].key,
			       strlen(hash_keys[HV_max_rows].key), 0)))
		info->attr.MaxRows = SvIV(*svp);
	    else
		info->attr.MaxRows = 0;
	}
	else
	{
	    info->attr.UseDateTime = 0;
	    info->attr.UseMoney    = 0;
	    info->attr.UseNumeric  = 0;
	    info->attr.MaxRows     = 0;
	}
	info->attr.RowCount   = 0;
	info->attr.RC         = 0;
	info->attr.ComputeId  = 0;
	info->attr.pid        = getpid(); /* XXX - is this portable to NT??? */
	info->attr.ExtendedError = 0;
    }


    rv = newRV((SV*)hv);
    stash = gv_stashpv(package, TRUE);
    sv = sv_bless(rv, stash);
        
    return sv;
}

static ConInfo *
get_ConInfoFromMagic(hv)
    HV *hv;
{
    ConInfo *info = NULL;
    IV i;
    MAGIC *m;

    m = mg_find((SV*)hv, '~');
    if(!m)
	croak("no connection key in hash");

    /* When doing global destruction, the tied _attribs hash gets freed
       before we get here. The statement below causes the program to exit
       under the debugger. */
    if((i = SvIV(m->mg_obj)) != 0)
	info = (void *)i;
    return info;
}

static ConInfo *
get_ConInfo(dbp)
    SV *dbp;
{
    ConInfo *info;
    dTHR;

#if 0
#if defined(DO_TIE)
    if(dirty)
	return NULL;
#endif
#endif
    
    if(!SvROK(dbp))
	croak("connection parameter is not a reference");
    info = get_ConInfoFromMagic((HV *)SvRV(dbp));

    return info;
}

/* Borrowed/adapted from DBI.xs */

static char *
neatsvpv(sv, maxlen) /* return a tidy ascii value, for debugging only */
    SV * sv;
    STRLEN maxlen;
{
    STRLEN len;
    SV *nsv = NULL;
    char *v;
    int is_ovl = 0;
    
    if (!sv)
	return "NULL";
    
    /* If this sv is a ref with overload magic, we need to turn it off
       before calling SvPV() so that the package name is returned, not
       the content. */
    if(SvROK(sv) && (is_ovl = SvAMAGIC(sv)))
	SvAMAGIC_off(sv);
    v = (SvOK(sv)) ? SvPV(sv,len) : "undef";
    if(is_ovl)
	SvAMAGIC_on(sv);
    /* undef and numbers get no special treatment */
    if (!SvOK(sv) || SvIOK(sv) || SvNOK(sv))
	return v;
    if (SvROK(sv))
	return v;

	
    /* for strings we limit the length and translate codes */
    nsv = sv_2mortal(newSVpv("'",1));
    if (maxlen == 0)
	maxlen = 64; /* FIXME */
    if (len > maxlen)
    {
	sv_catpvn(nsv, v, maxlen);
	sv_catpv( nsv, "...");
    }
    else
    {
	sv_catpvn(nsv, v, len);
	sv_catpv( nsv, "'");
    }
    v = SvPV(nsv, len);
    while(len-- > 0)
    { /* cleanup string (map control chars to ascii etc) */
	if (!isprint(v[len]) && !isspace(v[len]))
	    v[len] = '.';
    }
    return v;
}


static CS_DATETIME
to_datetime(str)
    char *str;
{
    CS_DATETIME dt;
    CS_DATAFMT srcfmt, destfmt;
    CS_INT reslen;

    memset(&dt, 0, sizeof(dt));

    if(!str)
	return dt;
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_CHAR_TYPE;
    srcfmt.maxlength = strlen(str);
    srcfmt.format    = CS_FMT_NULLTERM;
    srcfmt.locale    = NULL;
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.datatype  = CS_DATETIME_TYPE;
    destfmt.locale    = NULL;
    destfmt.maxlength = sizeof(CS_DATETIME);
    destfmt.format    = CS_FMT_UNUSED;
    
    if (cs_convert(context, &srcfmt, str, &destfmt,
		   &dt, &reslen) != CS_SUCCEED)
	warn("cs_convert failed (to_datetime(%s))", str);

    if(reslen == CS_UNUSED)
	warn("conversion failed: to_datetime(%s)", str);

    return dt;
}

static char *
from_datetime(dt)
    CS_DATETIME *dt;
{
    CS_DATAFMT srcfmt, destfmt;
    static char buff[256];
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_DATETIME_TYPE;
    srcfmt.locale    = NULL;
    srcfmt.maxlength = sizeof(CS_DATETIME);
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.maxlength = 256;
    destfmt.datatype  = CS_CHAR_TYPE;
    destfmt.format    = CS_FMT_NULLTERM;
    destfmt.locale    = NULL;
	    
    if (cs_convert(context, &srcfmt, dt, &destfmt,
		   buff, NULL) == CS_SUCCEED)
	return buff;

    return NULL;
}


static SV
*newdate(dt)
    CS_DATETIME *dt;
{
    SV *sv;
    CS_DATETIME *ptr;
    char *package=DateTimePkg;

    New(902, ptr, 1, CS_DATETIME);

    if(dt)
	*ptr = *(CS_DATETIME *)dt;
    else
    {
	/* According to the Sybase docs I can initialize the
           CS_DATETIME entry to be Jan 1 1900 00:00 by setting all the
           fields to 0. */
	memset(ptr, 0, sizeof(CS_DATETIME));
    }
    sv = newSV(0);
    sv_setref_pv(sv, package, (void*)ptr);
    
    if(debug_level & TRACE_CREATE)
	warn("Created %s", neatsvpv(sv, 0));
    
    return sv;
}

static CS_MONEY
to_money(str)
    char *str;
{
    CS_MONEY mn;
    CS_DATAFMT srcfmt, destfmt;
    CS_INT reslen;

    memset(&mn, 0, sizeof(mn));

    if(!str)
	return mn;
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_CHAR_TYPE;
    srcfmt.maxlength = strlen(str);
    srcfmt.format    = CS_FMT_NULLTERM;
    srcfmt.locale    = NULL;
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.datatype  = CS_MONEY_TYPE;
    destfmt.locale    = NULL;
    destfmt.maxlength = sizeof(CS_MONEY);
    destfmt.format    = CS_FMT_UNUSED;
    
    if (cs_convert(context, &srcfmt, str, &destfmt,
		   &mn, &reslen) != CS_SUCCEED)
	warn("cs_convert failed (to_money(%s))", str);

    if(reslen == CS_UNUSED)
	warn("conversion failed: to_money(%s)", str);

    return mn;
}

static char *
from_money(mn)
    CS_MONEY *mn;
{
    CS_DATAFMT srcfmt, destfmt;
    static char buff[256];
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_MONEY_TYPE;
    srcfmt.locale    = NULL;
    srcfmt.maxlength = sizeof(CS_MONEY);
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.maxlength = 256;
    destfmt.datatype  = CS_CHAR_TYPE;
    destfmt.format    = CS_FMT_NULLTERM;
    destfmt.locale    = NULL;
	    
    if (cs_convert(context, &srcfmt, mn, &destfmt,
		   buff, NULL) == CS_SUCCEED)
	return buff;

    return NULL;
}

static CS_FLOAT
money2float(mn)
    CS_MONEY *mn;
{
    CS_DATAFMT srcfmt, destfmt;
    CS_FLOAT ret;
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_MONEY_TYPE;
    srcfmt.locale    = NULL;
    srcfmt.maxlength = sizeof(CS_MONEY);
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.maxlength = sizeof(CS_FLOAT);
    destfmt.datatype  = CS_FLOAT_TYPE;
    destfmt.format    = CS_FMT_UNUSED;
    destfmt.locale    = NULL;
	    
    if (cs_convert(context, &srcfmt, mn, &destfmt,
		   &ret, NULL) == CS_SUCCEED)
	return ret;

    return 0.0;
}

static SV
*newmoney(mn)
    CS_MONEY *mn;
{
    SV *sv;
    CS_MONEY *value;
    char *package=MoneyPkg;

    Newz(902, value, 1, CS_MONEY);
    if(mn)
	*value = *mn;

    sv = newSV(0);
    sv_setref_pv(sv, package, (void*)value);

    if(debug_level & TRACE_CREATE)
	warn("Created %s", neatsvpv(sv, 0));
    
    return sv;
}
    
static CS_NUMERIC
to_numeric(str)
    char *str;
{
    CS_NUMERIC mn;
    CS_DATAFMT srcfmt, destfmt;
    CS_INT reslen;
    char *p;

    memset(&mn, 0, sizeof(mn));

    if(!str || !*str)
	str = "0";
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_CHAR_TYPE;
    srcfmt.maxlength = strlen(str);
    srcfmt.format    = CS_FMT_NULLTERM;
    srcfmt.locale    = NULL;
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.datatype  = CS_NUMERIC_TYPE;
    destfmt.locale    = NULL;
    destfmt.maxlength = sizeof(CS_NUMERIC);
    destfmt.format    = CS_FMT_UNUSED;

    /* FIXME: */
    if((p = strchr(str, '.')))
	destfmt.scale = strlen(p+1);
    else
	destfmt.scale = 0;
    destfmt.precision = strlen(str);
    
    if (cs_convert(context, &srcfmt, str, &destfmt,
		   &mn, &reslen) != CS_SUCCEED)
	warn("cs_convert failed (to_numeric(%s))", str);

    if(reslen == CS_UNUSED)
	warn("conversion failed: to_numeric(%s)", str);

    return mn;
}

static char *
from_numeric(mn)
    CS_NUMERIC *mn;
{
    CS_DATAFMT srcfmt, destfmt;
    static char buff[256];
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_NUMERIC_TYPE;
    srcfmt.locale    = NULL;
    srcfmt.maxlength = sizeof(CS_NUMERIC);
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.maxlength = 256;
    destfmt.datatype  = CS_CHAR_TYPE;
    destfmt.format    = CS_FMT_NULLTERM;
    destfmt.locale    = NULL;
	    
    if (cs_convert(context, &srcfmt, mn, &destfmt,
		   buff, NULL) == CS_SUCCEED)
	return buff;

    return NULL;
}

static CS_FLOAT
numeric2float(mn)
    CS_NUMERIC *mn;
{
    CS_DATAFMT srcfmt, destfmt;
    static CS_FLOAT ret;
    
    memset(&srcfmt, 0, sizeof(srcfmt));
    srcfmt.datatype  = CS_NUMERIC_TYPE;
    srcfmt.locale    = NULL;
    srcfmt.maxlength = sizeof(CS_NUMERIC);
	    
    memset(&destfmt, 0, sizeof(destfmt));
	    
    destfmt.maxlength = sizeof(CS_FLOAT);
    destfmt.datatype  = CS_FLOAT_TYPE;
    destfmt.format    = CS_FMT_UNUSED;
    destfmt.locale    = NULL;
	    
    if (cs_convert(context, &srcfmt, mn, &destfmt,
		   &ret, NULL) == CS_SUCCEED)
	return ret;

    return 0.0;
}


static SV
*newnumeric(mn)
    CS_NUMERIC *mn;
{
    SV *sv;
    CS_NUMERIC *value;
    char *package=NumericPkg;

    Newz(902, value, 1, CS_NUMERIC);
    if(mn)
	*value = *mn;

    sv = newSV(0);
    sv_setref_pv(sv, package, (void*)value);

    if(debug_level & TRACE_CREATE)
	warn("Created %s", neatsvpv(sv, 0));
    
    return sv;
}
    

    
static CS_CONNECTION
*get_con(dbp)
    SV *dbp;
{
    ConInfo *info = get_ConInfo(dbp);

    return info->connection->connection;
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
	if(info->coldata[i].type == CS_CHAR_TYPE ||
	   info->coldata[i].type == CS_TEXT_TYPE)
	    Safefree(info->coldata[i].value.c);
    
    if(info->datafmt)
	Safefree(info->datafmt);
    if(info->coldata)
	Safefree(info->coldata);
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

/* FIXME:
   All of the output in this function goes to stdout. The function is
   called from fetch_data (which is called from servermsg_cb), which
   normally outputs it's messages to stderr... */
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

static CS_RETCODE
describe(info, dbp, restype)
    ConInfo *info;
    SV *dbp;
    int restype;
{
    CS_RETCODE retcode;
    int i;
    int use_datetime = 0;
    int use_money = 0;
    int use_numeric = 0;
    
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

    av_clear(info->av);
    hv_clear(info->hv);
    i = info->numCols;
    while(i--)
	av_store(info->av, i, newSV(0));
    
    if(restype == CS_COMPUTE_RESULT) {
	CS_INT comp_id, outlen;
    
	if((retcode = ct_compute_info(info->cmd, CS_COMP_ID, CS_UNUSED,
				      &comp_id, CS_UNUSED, &outlen)) != CS_SUCCEED)
        {
	    warn("ct_compute_info failed");
	    goto GoodBye;
	}
	info->attr.ComputeId = comp_id;
    }
    else
	info->attr.ComputeId = 0;
    use_datetime = info->attr.UseDateTime;
    use_money    = info->attr.UseMoney;
    use_numeric  = info->attr.UseNumeric;


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
	
	info->coldata[i].realtype = info->datafmt[i].datatype;

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
	  DoFloat:;
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
	    info->datafmt[i].format   = CS_FMT_UNUSED; /*CS_FMT_NULLTERM;*/
	    New(902, info->coldata[i].value.c, info->datafmt[i].maxlength, char);
	    info->coldata[i].type = CS_TEXT_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      info->coldata[i].value.c,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
		
	  case CS_NUMERIC_TYPE:
	  case CS_DECIMAL_TYPE:
	    /* FIXME:
	       Should this be DoChar: when not using native numeric
	       formats (overflow problems...)? */
	    if(!use_numeric)
		goto DoFloat;
	    info->datafmt[i].maxlength = sizeof(CS_NUMERIC);
	    info->datafmt[i].datatype = CS_NUMERIC_TYPE;
	    info->datafmt[i].format   = CS_FMT_UNUSED;
	    info->coldata[i].type = CS_NUMERIC_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      &info->coldata[i].value.num,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
	    
	  case CS_MONEY_TYPE:
	  case CS_MONEY4_TYPE:
	    if(!use_money)
		goto DoFloat;
	    info->datafmt[i].maxlength = sizeof(CS_MONEY);
	    info->datafmt[i].datatype = CS_MONEY_TYPE;
	    info->datafmt[i].format   = CS_FMT_UNUSED;
	    info->coldata[i].type = CS_MONEY_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      &info->coldata[i].value.mn,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
	    
	  case CS_DATETIME_TYPE:
	  case CS_DATETIME4_TYPE:
	    if(!use_datetime)
		goto DoChar;
	    info->datafmt[i].maxlength = sizeof(CS_DATETIME);
	    info->datafmt[i].datatype = CS_DATETIME_TYPE;
	    info->datafmt[i].format   = CS_FMT_UNUSED;
	    info->coldata[i].type = CS_DATETIME_TYPE;
	    retcode = ct_bind(info->cmd, (i + 1), &info->datafmt[i],
			      &info->coldata[i].value.dt,
			      &info->coldata[i].valuelen,
			      &info->coldata[i].indicator);
	    break;
	    
	  case CS_CHAR_TYPE:
	  case CS_VARCHAR_TYPE:
	  case CS_BINARY_TYPE:
	  case CS_VARBINARY_TYPE:
	  default:
	  DoChar:;
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

/* FIXME:
   All of the output in this function goes to stdout. The function is
   called from servermsg_cb, which normally outputs it's messages
   to stderr... */

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
    if((retcode = ct_res_info(cmd, CS_NUMDATA,
			      &num_cols, CS_UNUSED, NULL)) != CS_SUCCEED)
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
			      coldata[i].value.c, &coldata[i].valuelen,
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
    dTHR;
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
    dTHR;
    
    if(server_cb.sub)	/* a perl error handler has been installed */
    {
	dSP;
	SV *sv, **svp;
	HV *hv;
	char *package = "Sybase::CTlib";
	int retval, count;
	ConInfo *info;
	RefCon *refCon;

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

	    New(902, info, 1, ConInfo);
	    if((hv = perl_get_hv("Sybase::CTlib::_refCon", FALSE)))
	    {
		if((svp = hv_fetch(hv, (char*)connection, sizeof(connection), 0)))
		{
		    refCon = (RefCon*)SvIV(*svp);
		    info->connection = refCon;
		}
	    }
	    info->cmd = cmd;
	    info->numCols = 0;
	    info->coldata = NULL;
	    info->datafmt = NULL;
	    info->type = CON_EED_CMD;
	    ++info->connection->refcount;

	    describe(info, NULL, 0);

	    sv = newdbh(info, package, &sv_undef, NULL);
	    if(!SvROK(sv))
		croak("The newly created dbh is not a reference (this should never happen!)");
	    info->attr.ExtendedError = TRUE;
	    if(debug_level & TRACE_CREATE)
		warn("Created %s", neatsvpv(sv, 0));
	    
	    XPUSHs(sv_2mortal(sv));
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
	/* Don't print informational messages... */
	if(srvmsg->severity > 10)
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

    if((sv = perl_get_sv("Sybase::CTlib::Version", TRUE|GV_ADDMULTI)))
    {
	char buff[256];
	sprintf(buff, "This is sybperl, version %s\n\nSybase::CTlib version 1.31 12/30/97\n\nCopyright (c) 1995-1997 Michael Peppler\nPortions Copyright (c) 1995 Sybase, Inc.\n\n",
		SYBPLVER);
	sv_setnv(sv, atof(SYBPLVER));
	sv_setpv(sv, buff);
	SvNOK_on(sv);
    }
    if((sv = perl_get_sv("Sybase::CTlib::VERSION", TRUE|GV_ADDMULTI)))
    {
	sv_setnv(sv, atof(SYBPLVER));
    }

    if((sv = perl_get_sv("0", FALSE)))
    {
	char *p;
	strcpy(scriptName, SvPV(sv, na));
	if((p = strrchr(scriptName, '/')))
	{
	    ++p;
	    strcpy(scriptName, p);
	}
    }
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
		if (strEQ(name, "CS_BLK_HAS_TEXT"))
#ifdef CS_BLK_HAS_TEXT
		    return CS_BLK_HAS_TEXT;
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
		if (strEQ(name, "CS_LOC_PROP"))
#ifdef CS_LOC_PROP
		    return CS_LOC_PROP;
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
      case 'T':
	if (strEQ(name, "TRACE_NONE"))
	    return TRACE_NONE;
	if (strEQ(name, "TRACE_DESTROY"))
	    return TRACE_DESTROY;
	if (strEQ(name, "TRACE_CREATE"))
	    return TRACE_CREATE;
	if (strEQ(name, "TRACE_RESULTS"))
	    return TRACE_RESULTS;
	if (strEQ(name, "TRACE_FETCH"))
	    return TRACE_FETCH;
	if (strEQ(name, "TRACE_CURSOR"))
	    return TRACE_CURSOR;
	if (strEQ(name, "TRACE_PARAMS"))
	    return TRACE_PARAMS;
	if (strEQ(name, "TRACE_OVERLOAD"))
	    return TRACE_OVERLOAD;
	if (strEQ(name, "TRACE_SQL"))
	    return TRACE_SQL;
	if (strEQ(name, "TRACE_ALL"))
	    return TRACE_ALL;
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
ct_connect(package="Sybase::CTlib", user=NULL, pwd=NULL, server=NULL, appname=NULL, attr=&sv_undef)
	char *	package
	char *	user
	char *	pwd
	char *	server
	char *	appname
	SV *	attr
  CODE:
{
    ConInfo *info;
    RefCon *refCon;
    CS_CONNECTION *connection = NULL;
    CS_COMMAND *cmd;
    CS_RETCODE retcode;
    CS_INT len;
    SV *sv;
    HV *hv;

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
    if(retcode == CS_SUCCEED)
    {
	if(!appname || !*appname)
	    appname = scriptName;
	if((retcode = ct_con_props(connection, CS_SET, CS_APPNAME, 
				   appname, CS_NULLTERM, NULL)) != CS_SUCCEED)
	    warn("ct_con_props(appname) failed");
    }

    if(attr && attr != &sv_undef && SvROK(attr)) {
	SV **svp = hv_fetch((HV*)SvRV(attr), "CON_PROPS", 9, 0);
	SV *sv;
	HV *hv;
	if(svp && SvROK(*svp)) {
	    int i;
	    CS_RETCODE ret;
	    static struct props {
		char *name; int attr; int type; 
	    } props[] = {
		{ "CS_HOSTNAME", CS_HOSTNAME, CS_CHAR_TYPE},
		{ "CS_ANSI_BINDS", CS_ANSI_BINDS, CS_INT_TYPE},
		{ "CS_CHARSETCNV", CS_CHARSETCNV, CS_INT_TYPE},
		{ "CS_PACKETSIZE", CS_PACKETSIZE, CS_INT_TYPE},
		{ "CS_SEC_APPDEFINED", CS_SEC_APPDEFINED, CS_INT_TYPE},
		{ "CS_SEC_CHALLENGE", CS_SEC_CHALLENGE, CS_INT_TYPE},
		{ "CS_SEC_ENCRYPTION", CS_SEC_ENCRYPTION, CS_INT_TYPE},
		{ "CS_SEC_NEGOTIATE", CS_SEC_NEGOTIATE, CS_INT_TYPE},
		{ "", 0, 0}
	    };
	    hv = (HV*)SvRV(*svp);
	    for(i = 0; props[i].name[0] != 0; ++i) {
		svp = hv_fetch(hv, props[i].name, strlen(props[i].name), 0);
		if(svp && *svp != &sv_undef) {
		    if(props[i].type == CS_CHAR_TYPE) {
			ret = ct_con_props(connection, CS_SET, props[i].attr,
					   SvPV(*svp, na), CS_NULLTERM, NULL);
		    } else {
			int k = SvIV(*svp);
			ret = ct_con_props(connection, CS_SET, props[i].attr,
					   &k, CS_UNUSED, NULL);
		    }
		    if(ret != CS_SUCCEED) {
			warn("ct_con_props(%s, %s) failed.",
			     props[i].name, neatsvpv(*svp, 0));
		    }
		}
	    }
	}
    }

    /* FIXME: should set the host name as well (CS_HOSTNAME) */

    if (retcode == CS_SUCCEED)
    {
	len = (server == NULL || !*server) ? 0 : CS_NULLTERM;
	retcode = ct_connect(connection, server, len);
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
	    Newz(902, info, 1, ConInfo);
	    Newz(902, refCon, 1, RefCon);
	    refCon->connection = connection;
	    refCon->refcount = 1;
	    info->type = CON_CONNECTION;
	    info->connection = refCon; /*connection; */
	    info->cmd = cmd;
	    info->numCols = 0;
	    info->coldata = NULL;
	    info->datafmt = NULL;


	    hv = perl_get_hv("Sybase::CTlib::_refCon", TRUE);
	    sv = newSViv((IV)refCon);
	    hv_store(hv, (char *)connection, sizeof(connection), sv, 0);
	    hv = perl_get_hv("Sybase::CTlib::_conInfo", TRUE);
	    sv = newSViv((IV)info);
	    hv_store(hv, (char *)cmd, sizeof(cmd), sv, 0);

	    sv = newdbh(info, package, attr, NULL);

	    if(debug_level & TRACE_CREATE)
		warn("Created %s", neatsvpv(sv, 0));

	    ST(0) = sv_2mortal(sv);
	}
    }
}

void
debug(level)
	int	level
  CODE:
{
    debug_level = level;
}
    
void
ct_cmd_alloc(dbp)
	SV *	dbp
  CODE:
{
    ConInfo *info, *o_info = get_ConInfo(dbp);
    CS_CONNECTION *connection = o_info->connection->connection;
    CS_COMMAND *cmd;
    CS_RETCODE retcode;
    CS_INT len;
    SV *sv;
    HV *hv;
    char *package;

    if((retcode = ct_cmd_alloc(connection, &cmd)) != CS_SUCCEED)
	ST(0) = sv_newmortal();
    else
    {
	hv = SvSTASH(SvRV(dbp));
	package = HvNAME(hv);
	
	New(902, info, 1, ConInfo);
	info->connection = o_info->connection;
	info->cmd = cmd;
	info->numCols = 0;
	info->coldata = NULL;
	info->datafmt = NULL;
	info->type = CON_CMD;
	++info->connection->refcount;
	
	hv = perl_get_hv("Sybase::CTlib::_conInfo", TRUE);
	sv = newSViv((IV)info);
	hv_store(hv, (char *)cmd, sizeof(cmd), sv, 0);

	/* FIXME
	   This should copy the attributes from the existing
	   connection! */
	sv = newdbh(info, package, &sv_undef, dbp);

	if(debug_level & TRACE_CREATE)
	    warn("Created %s", neatsvpv(sv, 0));
	
	ST(0) = sv_2mortal(sv);
    }
}


void
DESTROY(dbp)
	SV *	dbp
CODE:
{
    ConInfo *info = get_ConInfo(dbp);
    RefCon *refCon;
    CS_RETCODE	retcode;
    CS_INT	close_option;
    HV *hv;
    SV **svp;
     
    if(info) {
	if(info->attr.pid != getpid()) {
	    if(debug_level & TRACE_DESTROY)
		warn("Skipping Destroying %s", neatsvpv(dbp, 0));
	    XSRETURN_EMPTY;
	}
    }

    /* FIXME:
       must check for pending results, and maybe cancel those before
       dropping the cmd structure. */

    if(dirty && !info)
    {
	if(debug_level & TRACE_DESTROY)
	    warn("Skipping Destroying %s", neatsvpv(dbp, 0));
        XSRETURN_EMPTY;
    }

    if(debug_level & TRACE_DESTROY)
	warn("Destroying %s", neatsvpv(dbp, 0));
    
    if(info == NULL)
	croak("No connection info available");

    refCon = info->connection;
    
    if((hv = perl_get_hv("Sybase::CTlib::_conInfo", FALSE)))
	hv_delete(hv, (char *)info->cmd, sizeof(info->cmd), 0);
    
    ct_cmd_drop(info->cmd);
    --refCon->refcount;

    if(refCon->refcount == 0)
    {
	close_option = CS_FORCE_CLOSE;
	ct_close(refCon->connection, close_option);
	ct_con_drop(refCon->connection);

	if((hv = perl_get_hv("Sybase::CTlib::_refCon", FALSE)))
	    hv_delete(hv, (char *)refCon->connection, sizeof(refCon->connection), 0);
	Safefree(refCon);
    }
    
    if(info->numCols)
    {
	Safefree(info->coldata);
	Safefree(info->datafmt);
    }
    hv_undef(info->attr.other);
    hv_undef(info->hv);
    av_undef(info->av);
    Safefree(info);    
}

int
ct_cmd_realloc(dbp)
	SV *	dbp
  CODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_COMMAND *cmd;
    HV *hv;
    
    if((RETVAL = ct_cmd_alloc(info->connection->connection, &cmd)) == CS_SUCCEED)
    {
	if((hv = perl_get_hv("Sybase::CTlib::_conInfo", FALSE)))
	    hv_delete(hv, (char *)info->cmd, sizeof(info->cmd), 0);
	if((RETVAL = ct_cmd_drop(info->cmd)) == CS_SUCCEED)
	{
	    info->cmd = cmd;
	    hv_store(hv, (char*)info->cmd, sizeof(info->cmd), newSViv((IV)info), 0);
	}
	else
	    ct_cmd_drop(cmd);
    }
}
 OUTPUT:
RETVAL


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

    if(debug_level & TRACE_SQL)
	warn("%s->ct_execute('%s') == %d",
	     neatsvpv(dbp, 0), query, ret);

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
    if(debug_level & TRACE_SQL)
	warn("%s->ct_command(%d, '%s', %d, %d) == %d",
	     neatsvpv(dbp, 0), type, buffer, len, opt, RETVAL);
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
    if(debug_level & TRACE_RESULTS)
	warn("%s->ct_results(%d) == %d",
	     neatsvpv(dbp, 0), restype, RETVAL);
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
	XPUSHs(sv_2mortal(newSViv((CS_INT)info->coldata[i].realtype)));
    }
}

void
ct_describe(dbp, doAssoc = 0)
	SV *	dbp
	int	doAssoc
  PPCODE:
{
    ConInfo *info = get_ConInfo(dbp);
    int i;
    HV *hv;
    SV *sv;

    for(i = 0; i < info->numCols; ++i)
    {
	hv = newHV();

	hv_store(hv, "NAME", 4, newSVpv(info->datafmt[i].name,0), 0);
	hv_store(hv, "TYPE", 4, newSViv(info->datafmt[i].datatype), 0);
	hv_store(hv, "MAXLENGTH", 9, newSViv(info->datafmt[i].maxlength), 0);
	hv_store(hv, "SCALE", 5, newSViv(info->datafmt[i].scale), 0);
	hv_store(hv, "PRECISION", 9, newSViv(info->datafmt[i].precision), 0);
	hv_store(hv, "STATUS", 6, newSViv(info->datafmt[i].status), 0);
	sv = newRV((SV*)hv);
	
	if(doAssoc)
	    XPUSHs(sv_2mortal(newSVpv(info->datafmt[i].name, 0)));
	XPUSHs(sv_2mortal(sv));
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
      case CS_CANCEL_CURRENT:
	connection = NULL;
	break;
      default:
	cmd = NULL;
	break;
    }
    RETVAL = ct_cancel(connection, cmd, type);
}
OUTPUT:
RETVAL

void
ct_fetch(dbp, doAssoc=0, wantref=0)
    SV *	dbp
    int		doAssoc
    int		wantref
PPCODE:
{
    ConInfo *info = get_ConInfo(dbp);
    CS_RETCODE retcode;
    CS_INT rows_read;
    SV *sv;
    int i, len;
#if defined(UNDEF_BUG)
    int n_null = doAssoc;
#endif

    if(debug_level & TRACE_FETCH)
	warn("%s->ct_fetch() called in %s context", neatsvpv(dbp, 0),
	     wantref ? "SCALAR" : "SCALAR");

  TryAgain:;
    retcode = ct_fetch(info->cmd, CS_UNUSED, CS_UNUSED, CS_UNUSED, &rows_read);
    if(debug_level & TRACE_FETCH)
	warn("%s->ct_fetch(%s) == %d", neatsvpv(dbp, 0),
	     doAssoc ? "TRUE" : "FALSE", retcode);

    switch(retcode) {
      case CS_ROW_FAIL:		/* not sure how I should handle this one! */
	  if(debug_level & TRACE_FETCH)
	      warn("%s->ct_fetch() returned CS_ROW_FAIL",  neatsvpv(dbp, 0));
	  /* FALL THROUGH */
      case CS_SUCCEED:
	  for(i = 0; i < info->numCols; ++i) {
	    sv = AvARRAY(info->av)[i];
	    len = 0;
	    if(doAssoc && !wantref) {
		SV *namesv = newSVpv(info->datafmt[i].name, 0);
		if(debug_level & TRACE_FETCH)
		    warn("%s->ct_fetch pushes %s on the stack (doAssoc == TRUE)",
			 neatsvpv(dbp, 0), neatsvpv(namesv, 0));
		XPUSHs(sv_2mortal(namesv));
	    }

	    if(info->coldata[i].indicator == CS_NULLDATA) { /* NULL data */
		(void)SvOK_off(sv);
	    } else {
		switch(info->datafmt[i].datatype) {
		  case CS_TEXT_TYPE:
		    len = info->coldata[i].valuelen;
		    sv_setpvn(sv, info->coldata[i].value.c, len);
		    break;
		  case CS_CHAR_TYPE:
		    sv_setpv(sv, info->coldata[i].value.c);
		    break;
		  case CS_FLOAT_TYPE:
		    sv_setnv(sv, info->coldata[i].value.f);
		    break;
		  case CS_INT_TYPE:
		    sv_setiv(sv, info->coldata[i].value.i);
		    break;
		  case CS_DATETIME_TYPE:
		    sv_setsv(sv, newdate(&info->coldata[i].value.dt));
		    break;
		  case CS_MONEY_TYPE:
		    sv_setsv(sv, newmoney(&info->coldata[i].value.mn));
		    break;
		  case CS_NUMERIC_TYPE:
		    sv_setsv(sv, newnumeric(&info->coldata[i].value.num));
		    break;
		  default:
		    croak("ct_fetch: unknown datatype: %d, column %d",
			  info->datafmt[i].datatype, i);
		}
	    }
	    if(debug_level & TRACE_FETCH)
		warn("%s->ct_fetch pushes %s on the stack",
		     neatsvpv(dbp, 0), neatsvpv(sv, 0));
	    if(!wantref)
		XPUSHs(sv_mortalcopy(sv));
	    else {
		if(doAssoc) {
		    hv_store(info->hv, info->datafmt[i].name,
			     strlen(info->datafmt[i].name), 
			     newSVsv(sv), 0);
		}
#if defined(UNDEF_BUG)
		++n_null;
#endif
	    }
	}
	if(wantref) {
	    if(doAssoc) {
		XPUSHs(sv_2mortal((SV*)newRV((SV*)info->hv)));
	    } else {
		XPUSHs(sv_2mortal((SV*)newRV((SV*)info->av)));
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
	if(ct_cancel(info->connection->connection, NULL, CS_CANCEL_ALL) == CS_FAIL)
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
ct_config(action, property, param, type=CS_CHAR_TYPE)
	int	action
	int	property
	SV *	param
	int	type
CODE:
{
    char buff[256];
    CS_INT outlen, *outptr = NULL;
    CS_INT int_param;
    CS_RETCODE retcode;
    CS_VOID *param_ptr;
    CS_INT param_len;

    if(action == CS_GET)
    {
	if(type == CS_INT_TYPE) {
	    param_ptr = &int_param;
	    param_len = CS_UNUSED;
	}
	else {
	    param_ptr = buff;
	    param_len = 255;
	}
	retcode = ct_config(context, action, property, param_ptr, param_len,
			    NULL);
    }
    else if(action == CS_SET)
    {
	if(type == CS_INT_TYPE) {
	    int_param = SvIV(param);
	    param_ptr = &int_param;
	    param_len = CS_UNUSED;
	} else {
	    param_ptr = SvPV(param, na);
	    param_len = CS_NULLTERM;
	}
	retcode = ct_config(context, action, property, param_ptr, param_len,
			    NULL);
    }
    RETVAL = retcode;
    /* This is a hack: */
    if(action == CS_GET) {
	if(type == CS_INT_TYPE)
	    sv_setiv((SV*)ST(2), int_param);
	else
	    sv_setpv((SV*)ST(2), buff);
    }
}
 OUTPUT:
RETVAL

int
cs_dt_info(action, type, item, buffer)
    int		action;
    int		type;
    int		item;
    char	*buffer;
CODE:
{
    char buf[255];
    char *bufptr;
    int intptr;
    int len;
    CS_RETCODE ret;
    
    if(action == CS_SET) {
	bufptr = buffer;
	len = strlen(bufptr);
	ret = cs_dt_info(context, action, NULL, type, item, bufptr,
			 len, NULL);
    } else {
	len = 255;
	if(item == CS_12HOUR) {
	    ret = cs_dt_info(context, action, NULL, type, item, &intptr,
			     CS_UNUSED, NULL);
	    sv_setiv((SV*)ST(3), intptr);
	} else {
	    bufptr = &buf[0];
	    ret = cs_dt_info(context, action, NULL, type, item, buf,
			     len, NULL);
	    sv_setpv((SV*)ST(3), bufptr);
	}
    }
    RETVAL = ret;
}
OUTPUT:
RETVAL
	

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
		if(ci->sub == (SV*) NULL)
		    ci->sub = newSVsv(newRV(func));
		else
		    sv_setsv(ci->sub, newRV(func));
	}
	else
	{
	    if(ci->sub == (SV*) NULL)
		ci->sub = newSVsv(func);
	    else
		sv_setsv(ci->sub, func);
	}
    }
    if(ret)
	ST(0) = sv_2mortal(ret);
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

    if(debug_level & TRACE_CURSOR)
	warn("%s->ct_cursor(%d, %s, %s, %d) == %d",
	     neatsvpv(dbp, 0), type, neatsvpv(sv_name, 0),
	     neatsvpv(sv_text, 0), option, retcode);
    
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
    enum {
	k_name, k_datatype,
	k_status, k_indicator, k_value} key_id;
    static char *keys[] = {"name", "datatype", "status", "indicator", "value"};
    int i;
    int v_i;
    double v_f;
    CS_DATETIME v_dt;
    CS_MONEY v_mn;
    CS_NUMERIC v_num;
    CS_SMALLINT indicator = 0;
    CS_INT datalen = CS_UNUSED;
    CS_VOID *value = NULL;
    
    memset(&datafmt, 0, sizeof(datafmt));

    if(debug_level & TRACE_PARAMS)
	warn("%s->ct_param(%s):\n", neatsvpv(dbp, 0), neatsvpv(sv_params, 0));
    
    if(!SvROK(sv_params))
	croak("datafmt parameter is not a reference");
    hv = (HV *)SvRV(sv_params);

    /* We need to check the coherence of the keys that are in the hash
       table: */
    if(hv_iterinit(hv))
    {
	HE *he;
	char *key;
	I32 klen;
	
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
    if(debug_level & TRACE_PARAMS)
	warn("\tdatafmt.name: %s\n", datafmt.name);
    if((svp = hv_fetch(hv, keys[k_datatype], strlen(keys[k_datatype]), FALSE)))
	datafmt.datatype = SvIV(*svp);
    else
	datafmt.datatype = CS_CHAR_TYPE; /* default data type */
    if(debug_level & TRACE_PARAMS)
	warn("\tdatafmt.datatype: %d\n", datafmt.datatype);
    
    if((svp = hv_fetch(hv, keys[k_status], strlen(keys[k_status]), FALSE)))
	datafmt.status = SvIV(*svp);
    if(debug_level & TRACE_PARAMS)
	warn("\tdatafmt.status: %d\n", datafmt.status);
    
    svp = hv_fetch(hv, keys[k_value], strlen(keys[k_value]), FALSE);
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

      case CS_NUMERIC_TYPE:
      case CS_DECIMAL_TYPE:
	datafmt.datatype = CS_NUMERIC_TYPE;
	if(svp || datafmt.status == CS_RETURN)
	{
	    datalen = datafmt.maxlength = CS_SIZEOF(CS_NUMERIC);
	    if(svp)
	    {
		if (sv_isa(*svp, NumericPkg)) {
		    IV tmp = SvIV((SV*)SvRV(*svp));
		    v_num = *(CS_NUMERIC *) tmp;
		}
		else
		    v_num = to_numeric(SvPV(*svp, na));
		value = &v_num;
	    }
	}
	break;
	
      case CS_MONEY_TYPE:
      case CS_MONEY4_TYPE:
	datafmt.datatype = CS_MONEY_TYPE;
	if(svp || datafmt.status == CS_RETURN)
	{
	    datalen = datafmt.maxlength = CS_SIZEOF(CS_MONEY);
	    if(svp)
	    {
		if (sv_isa(*svp, MoneyPkg)) {
		    IV tmp = SvIV((SV*)SvRV(*svp));
		    v_mn = *(CS_MONEY *) tmp;
		}
		else
		    v_mn = to_money(SvPV(*svp, na));
		value = &v_mn;
	    }
	}
	break;
	
      case CS_DATETIME_TYPE:
      case CS_DATETIME4_TYPE:
	datafmt.datatype = CS_DATETIME_TYPE;
	if(svp || datafmt.status == CS_RETURN)
	{
	    datalen = datafmt.maxlength = CS_SIZEOF(CS_DATETIME);
	    if(svp)
	    {
		if (sv_isa(*svp, DateTimePkg)) {
		    IV tmp = SvIV((SV*)SvRV(*svp));
		    v_dt = *(CS_DATETIME *) tmp;
		}
		else
		    v_dt = to_datetime(SvPV(*svp, na));
		value = &v_dt;
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
    if(debug_level & TRACE_PARAMS)
	warn("\tvalue: %s\n", svp ? neatsvpv(*svp, 0) : "NULL");
        
    if((svp = hv_fetch(hv, keys[k_indicator], strlen(keys[k_indicator]), FALSE)))
	indicator = SvIV(*svp);

    if(debug_level & TRACE_PARAMS)
	warn("\tindicator: %d\n", indicator);

    retcode = ct_param(info->cmd, &datafmt, value, datalen, indicator);

    if(debug_level & TRACE_PARAMS)
	warn("%s->ct_param == %d", neatsvpv(dbp, 0), retcode);
    
    RETVAL = retcode;
}
OUTPUT:
RETVAL


void
newdate(dbp=&sv_undef,dt=NULL)
	SV *	dbp
	char *	dt
  CODE:
{
    CS_DATETIME d;
    d = to_datetime(dt);
    ST(0) = sv_2mortal(newdate(&d));
}

void
newmoney(dbp=&sv_undef, mn=NULL)
	SV *	dbp
	char *	mn
  CODE:
{
    CS_MONEY m;
    m = to_money(mn);
    ST(0) = sv_2mortal(newmoney(&m));
}

void
newnumeric(dbp=&sv_undef, num=NULL)
	SV *	dbp
	char *	num
  CODE:
{
    CS_NUMERIC n;
    n = to_numeric(num);
    ST(0) = sv_2mortal(newnumeric(&n));
}


MODULE = Sybase::CTlib		PACKAGE = Sybase::CTlib::DateTime


void
DESTROY(valp)
	SV *	valp
  CODE:
{
    CS_DATETIME *ptr;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);

    if(debug_level & TRACE_DESTROY)
	warn("Destroying %s", neatsvpv(valp, 0));

    Safefree(ptr);
}

char *
str(valp)
	SV *	valp
  CODE:
{
    CS_DATETIME *ptr;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);
    
    RETVAL = from_datetime(ptr);

    if(debug_level & TRACE_OVERLOAD)
	warn("%s->str == %s", neatsvpv(valp,0), RETVAL);
}
 OUTPUT:
RETVAL

void
crack(valp)
	SV *	valp
  PPCODE:
{
    CS_DATEREC rec;
    CS_DATETIME *ptr;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);
    if(cs_dt_crack(context, CS_DATETIME_TYPE, ptr,
		&rec) == CS_SUCCEED)
    {
	XPUSHs(sv_2mortal(newSViv(rec.dateyear)));
	XPUSHs(sv_2mortal(newSViv(rec.datemonth)));
	XPUSHs(sv_2mortal(newSViv(rec.datedmonth)));
	XPUSHs(sv_2mortal(newSViv(rec.datedyear)));
	XPUSHs(sv_2mortal(newSViv(rec.datedweek)));
	XPUSHs(sv_2mortal(newSViv(rec.datehour)));
	XPUSHs(sv_2mortal(newSViv(rec.dateminute)));
	XPUSHs(sv_2mortal(newSViv(rec.datesecond)));
	XPUSHs(sv_2mortal(newSViv(rec.datemsecond)));
	XPUSHs(sv_2mortal(newSViv(rec.datetzone)));
    }
}

int
cmp(valp, valp2, ord = &sv_undef)
	SV *	valp
	SV *	valp2
	SV *	ord
  CODE:
{
    SV *sv;
    CS_DATETIME *d1, *d2, *tmp, dt;
    CS_INT result;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	d1 = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);
    
    if(!SvROK(valp2))
    {
	dt = to_datetime(SvPV(valp2, na));
	d2 = &dt;
    }
    else
    {
	sv = (SV *)SvRV(valp2);
	d2 = (CS_DATETIME *)SvIV(sv);
    }
    if(ord != &sv_undef && SvTRUE(ord))
    {
	tmp = d1;
	d1 = d2;
	d2 = tmp;
    }

    if(cs_cmp(context, CS_DATETIME_TYPE, d1, d2, &result) != CS_SUCCEED)
    {
	warn("cs_cmp(CS_DATETIME) failed");
	result = 0;
    }
    RETVAL = result;
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->cmp(%s, %s) == %d", neatsvpv(valp,0),
	     neatsvpv(valp2, 0), SvTRUE(ord) ? "TRUE" : "FALSE", RETVAL);
}
 OUTPUT:
RETVAL

void
calc(valp, days, msecs = 0)
	SV *	valp
	int	days
	int	msecs
  CODE:
{
    CS_DATETIME *ptr, tmp;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);
    tmp = *ptr;			/* make a copy: we don't want to change the original! */
    tmp.dtdays += days;
    tmp.dttime += msecs;
    ST(0) = sv_2mortal(newdate(&tmp));
}


void
diff(valp, valp2, ord = &sv_undef)
	SV *	valp
	SV *	valp2
	SV *	ord
  PPCODE:
{
    SV *sv;
    CS_DATETIME *d1, *d2, *tmp, dt;
    CS_INT days, msecs;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	d1 = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);
    
    if(!SvROK(valp2))
    {
	dt = to_datetime(SvPV(valp2, na));
	d2 = &dt;
    }
    else
    {
	sv = (SV *)SvRV(valp2);
	d2 = (CS_DATETIME *)SvIV(sv);
    }
    if(ord != &sv_undef && SvTRUE(ord))
    {
	tmp = d1;
	d1 = d2;
	d2 = tmp;
    }

    days = d2->dtdays - d1->dtdays;
    msecs = d2->dttime - d1->dttime;
    XPUSHs(sv_2mortal(newSViv(days)));
    XPUSHs(sv_2mortal(newSViv(msecs)));
}

char *
info(valp, op)
	SV *	valp
	int	op
  CODE:
{
    CS_DATEREC rec;
    char buff[32];
    CS_INT item, ret;
    CS_DATETIME *ptr;
    if (sv_isa(valp, DateTimePkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_DATETIME *) tmp;
    }
    else
	croak("valp is not of type %s", DateTimePkg);
    
    if(cs_dt_crack(context, CS_DATETIME_TYPE, ptr,
		&rec) == CS_SUCCEED)
    {
	switch(op)
	{
	  case CS_MONTH:
	  case CS_SHORTMONTH:
	    item = rec.datemonth;
	    break;
	  case CS_DAYNAME:
	    item = rec.datedweek;
	    break;
	  default:
	    croak("cs_dt_info(%d) is not supported", op);
	}

	if(cs_dt_info(context, CS_GET, NULL, op, item,
		      buff, 32, &ret) != CS_SUCCEED)
	    warn("cs_dt_info failed");
	else
	    RETVAL = buff;
    }
}
 OUTPUT:
RETVAL


MODULE = Sybase::CTlib		PACKAGE = Sybase::CTlib::Money


void
DESTROY(valp)
	SV *	valp
  CODE:
{
    CS_MONEY *ptr;
    if (sv_isa(valp, MoneyPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_MONEY *) tmp;
    }
    else
	croak("valp is not of type %s", MoneyPkg);

    if(debug_level & TRACE_DESTROY)
	warn("Destroying %s", neatsvpv(valp, 0));

    Safefree(ptr);
}

char *
str(valp)
	SV *	valp
  CODE:
{
    CS_MONEY *ptr;
    if (sv_isa(valp, MoneyPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_MONEY *) tmp;
    }
    else
	croak("valp is not of type %s", MoneyPkg);

    RETVAL = from_money(ptr);
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->str == %s", neatsvpv(valp,0), RETVAL);
}
 OUTPUT:
RETVAL

double
num(valp)
	SV *	valp
  CODE:
{
    CS_MONEY *ptr;
    if (sv_isa(valp, MoneyPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_MONEY *) tmp;
    }
    else
	croak("valp is not of type %s", MoneyPkg);

    RETVAL = money2float(ptr);
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->num == %f", neatsvpv(valp,0), RETVAL);
}
 OUTPUT:
RETVAL

void
set(valp, str)
	SV *	valp
	char *	str
  CODE:
{
    CS_MONEY *ptr;
    if (sv_isa(valp, MoneyPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_MONEY *) tmp;
    }
    else
	croak("valp is not of type %s", MoneyPkg);

    *ptr = to_money(str);
}

int
cmp(valp, valp2, ord = &sv_undef)
	SV *	valp
	SV *	valp2
	SV *	ord
  CODE:
{
    CS_MONEY *m1, *m2, *tmp, mn;
    CS_INT result;

    if (sv_isa(valp, MoneyPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	m1 = (CS_MONEY *) tmp;
    }
    else
	croak("valp is not of type %s", MoneyPkg);
    
    if(!SvROK(valp2) ||	!sv_isa(valp2, MoneyPkg))
    {
	char buff[64];

	sprintf(buff, "%f", SvNV(valp2));
	mn = to_money(buff);
	m2 = &mn;
    }
    else
    {
	IV tmp = SvIV((SV*)SvRV(valp2));
	m2 = (CS_MONEY *) tmp;
    }
    if(ord != &sv_undef && SvTRUE(ord))
    {
	tmp = m1;
	m1 = m2;
	m2 = tmp;
    }

    if(cs_cmp(context, CS_MONEY_TYPE, m1, m2, &result) != CS_SUCCEED)
    {
	warn("cs_cmp(CS_MONEY) failed");
	result = 0;
    }
    RETVAL = result;
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->cmp(%s, %s) == %d", neatsvpv(valp,0),
	     neatsvpv(valp2, 0), SvTRUE(ord) ? "TRUE" : "FALSE", RETVAL);
}
 OUTPUT:
RETVAL

void
calc(valp1, valp2, op, ord = &sv_undef)
	SV *	valp1
	SV *	valp2
	char	op
	SV *	ord
  CODE:
{
    CS_MONEY *m1, *m2, *tmp, mn;
    CS_MONEY result;
    CS_INT cs_op;

    switch(op)
    {
      case '+': cs_op = CS_ADD; break;
      case '-': cs_op = CS_SUB; break;
      case '*': cs_op = CS_MULT; break;
      case '/': cs_op = CS_DIV; break;
      default:
	croak("Invalid operator %c to Sybase::CTlib::Money::calc", op);
    }
    
    if (sv_isa(valp1, MoneyPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp1));
	m1 = (CS_MONEY *) tmp;
    }
    else
	croak("valp1 is not of type %s", MoneyPkg);
    
    if(!SvROK(valp2) ||	!sv_isa(valp2, MoneyPkg))
    {
	char buff[64];

	sprintf(buff, "%f", SvNV(valp2));
	mn = to_money(buff);
	m2 = &mn;
    }
    else
    {
	IV tmp = SvIV((SV*)SvRV(valp2));
	m2 = (CS_MONEY *) tmp;
    }
    if(ord != &sv_undef && SvTRUE(ord))
    {
	tmp = m1;
	m1 = m2;
	m2 = tmp;
    }

    memset(&result, 0, sizeof(CS_MONEY));
    if(cs_calc(context, cs_op, CS_MONEY_TYPE, m1, m2, &result) != CS_SUCCEED)
    {
	warn("cs_calc(CS_MONEY) failed");
    }
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->calc(%s, %c, %s) == %s", neatsvpv(valp1, 0),
	     neatsvpv(valp2, 0), op, SvTRUE(ord) ? "TRUE" : "FALSE",
	     from_money(&result));

    ST(0) = sv_2mortal(newmoney(&result));
}    

MODULE = Sybase::CTlib		PACKAGE = Sybase::CTlib::Numeric


void
DESTROY(valp)
	SV *	valp
  CODE:
{
    CS_NUMERIC *ptr;
    if (sv_isa(valp, NumericPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_NUMERIC *) tmp;
    }
    else
	croak("valp is not of type %s", NumericPkg);

    if(debug_level & TRACE_DESTROY)
	warn("Destroying %s", neatsvpv(valp, 0));

    Safefree(ptr);
}

char *
str(valp)
	SV *	valp
  CODE:
{
    CS_NUMERIC *ptr;
    if (sv_isa(valp, NumericPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_NUMERIC *) tmp;
    }
    else
	croak("valp is not of type %s", NumericPkg);

    RETVAL = from_numeric(ptr);
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->str == %s", neatsvpv(valp,0), RETVAL);
}
 OUTPUT:
RETVAL

double
num(valp)
	SV *	valp
  CODE:
{
    CS_NUMERIC *ptr;
    if (sv_isa(valp, NumericPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_NUMERIC *) tmp;
    }
    else
	croak("valp is not of type %s", NumericPkg);

    RETVAL = numeric2float(ptr);
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->num == %f", neatsvpv(valp,0), RETVAL);
}
 OUTPUT:
RETVAL

void
set(valp, str)
	SV *	valp
	char *	str
  CODE:
{
    CS_NUMERIC *ptr;
    if (sv_isa(valp, NumericPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	ptr = (CS_NUMERIC *) tmp;
    }
    else
	croak("valp is not of type %s", NumericPkg);

    *ptr = to_numeric(str);
}

int
cmp(valp, valp2, ord = &sv_undef)
	SV *	valp
	SV *	valp2
	SV *	ord
  CODE:
{
    CS_NUMERIC *m1, *m2, *tmp, mn;
    CS_INT result;
    
    if (sv_isa(valp, NumericPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp));
	m1 = (CS_NUMERIC *) tmp;
    }
    else
	croak("valp is not of type %s", NumericPkg);
    
    if(!SvROK(valp2) ||	!sv_isa(valp2, NumericPkg))
    {
	char buff[64];

	sprintf(buff, "%f", SvNV(valp2));
	mn = to_numeric(buff);
	m2 = &mn;
    }
    else
    {
	IV tmp = SvIV((SV*)SvRV(valp2));
	m2 = (CS_NUMERIC *) tmp;
    }
    if(ord != &sv_undef && SvTRUE(ord))
    {
	tmp = m1;
	m1 = m2;
	m2 = tmp;
    }

    if(cs_cmp(context, CS_NUMERIC_TYPE, m1, m2, &result) != CS_SUCCEED)
    {
	warn("cs_cmp(CS_NUMERIC) failed");
	result = 0;
    }
    RETVAL = result;
    if(debug_level & TRACE_OVERLOAD)
	warn("%s->cmp(%s, %s) == %d", neatsvpv(valp,0),
	     neatsvpv(valp2, 0), SvTRUE(ord) ? "TRUE" : "FALSE", RETVAL);
}
 OUTPUT:
RETVAL

void
calc(valp1, valp2, op, ord = &sv_undef)
	SV *	valp1
	SV *	valp2
	char	op
	SV *	ord
  CODE:
{
    CS_NUMERIC *m1, *m2, *tmp, mn;
    CS_NUMERIC result;
    CS_INT cs_op;

    switch(op)
    {
      case '+': cs_op = CS_ADD; break;
      case '-': cs_op = CS_SUB; break;
      case '*': cs_op = CS_MULT; break;
      case '/': cs_op = CS_DIV; break;
      default:
	croak("Invalid operator %c to Sybase::CTlib::Numeric::calc", op);
    }
    
    if (sv_isa(valp1, NumericPkg)) {
	IV tmp = SvIV((SV*)SvRV(valp1));
	m1 = (CS_NUMERIC *) tmp;
    }
    else
	croak("valp1 is not of type %s", NumericPkg);
    
    if(!SvROK(valp2) ||	!sv_isa(valp2, NumericPkg))
    {
	char buff[64];

	sprintf(buff, "%f", SvNV(valp2));
	mn = to_numeric(buff);
	m2 = &mn;
    }
    else
    {
	IV tmp = SvIV((SV*)SvRV(valp2));
	m2 = (CS_NUMERIC *) tmp;
    }
    if(ord != &sv_undef && SvTRUE(ord))
    {
	tmp = m1;
	m1 = m2;
	m2 = tmp;
    }

    memset(&result, 0, sizeof(CS_NUMERIC));
    if(cs_calc(context, cs_op, CS_NUMERIC_TYPE, m1, m2, &result) != CS_SUCCEED)
	warn("cs_calc(CS_NUMERIC) failed");

    if(debug_level & TRACE_OVERLOAD)
	warn("%s->calc(%s, %c, %s) == %s", neatsvpv(valp1, 0),
	     neatsvpv(valp2, 0), op, SvTRUE(ord) ? "TRUE" : "FALSE",
	     from_numeric(&result));
    
    ST(0) = sv_2mortal(newnumeric(&result));
}    

MODULE = Sybase::CTlib		PACKAGE = Sybase::CTlib::_attribs

void
FETCH(sv, keysv)
	SV *	sv
	SV *	keysv
CODE:
{
    ConInfo *info = get_ConInfoFromMagic((HV*)SvRV(sv));
    SV *valuesv = attr_fetch(info, SvPV(keysv, na), sv_len(keysv));
    ST(0) = valuesv;
}

void
STORE(sv, keysv, valuesv)
	SV *	sv
	SV *	keysv
	SV *	valuesv
CODE:
{
    ConInfo *info = get_ConInfoFromMagic((HV*)SvRV(sv));

    attr_store(info, SvPV(keysv, na), sv_len(keysv), valuesv, 0);
}
