/* vi:set ts=8 sts=4 sw=4:
 *
 * VIM - Vi IMproved	by Bram Moolenaar
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * Gauche extensions by Kana Natsuno <http://whileimautomaton.net/>
 *
 * Functions which can be called by the deep of Vim MUST be written in K&R
 * style.  All of such functions are placed in the "Stuffs for Vim" section.
 * Other functions which cannot be called by such places SHOULD be written in
 * ANSI style.  All of such functions are not placed in the "Stuffs for Vim"
 * section.
 */

#include "vim.h"

#define GAUCHE_API_0_9        /* temporary compatibility stuff */
#include "gauche.h"




/* Common Utilities */  /*{{{1*/
/* Wrappers for Scm_Printf() - output by :echomsg or :echoerr */  /*{{{2*/

static void
Scm_Xmsgf(const char *fmt, va_list ap, int echoerrp)
{
    ScmObj s = Scm_Vsprintf(fmt, ap, TRUE);
    if (echoerrp)
	EMSG(Scm_GetString(SCM_STRING(s)));
    else
	MSG(Scm_GetString(SCM_STRING(s)));
}

static void
Scm_Msgf(const char *fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    Scm_Xmsgf(fmt, args, FALSE);
    va_end(args);
}

static void
Scm_Emsgf(const char* fmt, ...)
{
    va_list args;

    va_start(args, fmt);
    Scm_Xmsgf(fmt, args, TRUE);
    va_end(args);
}




/* Conversion rules for values between Vim script and Gauche */  /*{{{2*/

static const char *
vim_to_gauche(typval_T *tv, ScmObj *pobj)
{
    switch (tv->v_type)
    {
    default:
	return "vim_to_gauche: Internal error: Unexpected tv->v_type";
    case VAR_NUMBER:
	*pobj = Scm_MakeInteger(tv->vval.v_number);
	return NULL;
#ifdef FEAT_FLOAT
    case VAR_FLOAT:
	*pobj = Scm_MakeFlonum(tv->vval.v_float);
	return NULL;
#endif
    case VAR_STRING:
	*pobj = SCM_MAKE_STR_COPYING((char *)(tv->vval.v_string));
	return NULL;

    case VAR_LIST:  /* TODO: Support circular list */
    {
	list_T *l = tv->vval.v_list;
	listitem_T *li;
	ScmObj slist = SCM_NIL;

	if (l != NULL)
	{
	    for (li = l->lv_last; li != NULL; li = li->li_prev)
	    {
		ScmObj obj;
		const char *errmsg;

		errmsg = vim_to_gauche(&(li->li_tv), &obj);
		if (errmsg != NULL)
		    return errmsg;
		slist = Scm_Cons(obj, slist);
	    }
	}
	*pobj = slist;
	return NULL;
    }
    case VAR_DICT:  /* TODO: Support circular dictionary */
    {
	dict_T *vdict = tv->vval.v_dict;
	ScmObj shash;

	if (vdict != NULL)
	{
	    hashtab_T *ht = &(vdict->dv_hashtab);
	    hashitem_T *hi;
	    dictitem_T *di;
	    long_u todo = ht->ht_used;
	    shash = Scm_MakeHashTableSimple(SCM_HASH_STRING, (int)todo);

	    for (hi = ht->ht_array; 0 < todo; hi++)
	    {
		if (!HASHITEM_EMPTY(hi))
		{
		    ScmObj obj;
		    const char *errmsg;

		    errmsg = vim_to_gauche(&(di->di_tv), &obj);
		    if (errmsg != NULL)
			return errmsg;

		    todo--;
		    di = dict_lookup(hi);
		    Scm_HashTableSet(
			SCM_HASH_TABLE(shash),
			SCM_MAKE_STR_COPYING((char *)(hi->hi_key)),
			obj,
			0
		    );
		}
	    }
	}
	else
	{
	    shash = Scm_MakeHashTableSimple(SCM_HASH_STRING, 0);
	}
	*pobj = shash;
	return NULL;
    }
    case VAR_FUNC:
	return "Funcref is not supported yet";  /* TODO */
    }

    return "vim_to_gauche: Internal error: UNREACHABLE";
}


static const char *
gauche_to_vim(ScmObj obj, typval_T *result)
{
    result->v_lock = 0;

    if (SCM_INTEGERP(obj))
    {
	result->v_type = VAR_NUMBER;
	result->vval.v_number = Scm_GetInteger(obj);
	return NULL;
    }
#ifdef FEAT_FLOAT
    else if (SCM_REALP(obj))
    {
	result->v_type = VAR_FLOAT;
	result->vval.v_float = Scm_GetDouble(obj);
	return NULL;
    }
#endif
    else if (SCM_CHARP(obj))
    {
	ScmChar c = SCM_CHAR_VALUE(obj);
	int nb = SCM_CHAR_NBYTES(c);
	char_u buf[nb+1];  /* FIXME: extension */
	memset(buf, 0x00, sizeof(buf));
	SCM_CHAR_PUT(buf, c);

	result->v_type = VAR_STRING;
	result->vval.v_string = vim_strsave(buf);
	return NULL;
    }
    else if (SCM_STRINGP(obj))
    {
	result->v_type = VAR_STRING;
	result->vval.v_string =
	    vim_strsave((char_u *)Scm_GetString(SCM_STRING(obj)));
	return NULL;
    }
    else if (SCM_SYMBOLP(obj))
    {
	result->v_type = VAR_STRING;
	result->vval.v_string =
	    vim_strsave((char_u *)
			Scm_GetString(SCM_STRING(SCM_SYMBOL_NAME(obj))));
	return NULL;
    }
    else if (SCM_KEYWORDP(obj))
    {
	result->v_type = VAR_STRING;
	result->vval.v_string =
	    vim_strsave((char_u *)
			Scm_GetString(SCM_STRING(SCM_KEYWORD_NAME(obj))));
	return NULL;
    }
    else if (SCM_BOOLP(obj))
    {
	result->v_type = VAR_NUMBER;
	result->vval.v_number = (SCM_FALSEP(obj) ? 0 : 1);
	return NULL;
    }
    else if (SCM_LISTP(obj))
    {
	list_T *l = list_alloc();
	typval_T v;
	ScmObj p;
	const char *errmsg;

	if (l == NULL)
	    return "gauche_to_vim: Out of memory on list";

	result->v_type = VAR_LIST;
	result->vval.v_list = l;
	l->lv_refcount = 1;

	p = obj;
	while (SCM_PAIRP(p))
	{
	    errmsg = gauche_to_vim(SCM_CAR(p), &v);
	    if (errmsg != NULL)
	    {
		clear_tv(result);
		return errmsg;
	    }

	    list_append_tv(l, &v);
	    clear_tv(&v);
	    p = SCM_CDR(p);
	}

	if (!SCM_NULLP(p))
	{
	    errmsg = gauche_to_vim(p, &v);
	    if (errmsg != NULL)
	    {
		clear_tv(result);
		return errmsg;
	    }

	    list_append_tv(l, &v);
	    clear_tv(&v);
	}

	return NULL;
    }
    else if (SCM_VECTORP(obj))
    {
	list_T *l = list_alloc();
	typval_T v;
	int i;
	const char *errmsg;

	if (l == NULL)
	    return "gauche_to_vim: Out of memory on vector";

	result->v_type = VAR_LIST;
	result->vval.v_list = l;
	l->lv_refcount = 1;

	for (i = 0; i < SCM_VECTOR_SIZE(obj); i++)
	{
	    errmsg = gauche_to_vim(SCM_VECTOR_ELEMENT(obj, i), &v);
	    if (errmsg != NULL)
	    {
		clear_tv(result);
		return errmsg;
	    }

	    list_append_tv(l, &v);
	    clear_tv(&v);
	}

	return NULL;
    }
#if 0  /* TODO */
    else if (SCM_HASH_TABLE_P(obj))
    {
    }
#endif
    else
    {
	ScmObj s = Scm_MakeOutputStringPort(TRUE);
	Scm_Printf(SCM_PORT(s), "Unsupported object: %S(%S)",
		   obj, Scm_ClassOf(obj));
	return Scm_GetString(SCM_STRING(Scm_GetOutputString(SCM_PORT(s), 0)));
    }
}








/* Stuffs for Gauche */  /*{{{1*/
/* Initialization and Finalization */  /*{{{2*/

static void
sig_setup(void)
{
    sigset_t set;
    sigfillset(&set);
    sigdelset(&set, SIGABRT);
    sigdelset(&set, SIGILL);
#ifdef SIGKILL
    sigdelset(&set, SIGKILL);
#endif
#ifdef SIGCONT
    sigdelset(&set, SIGCONT);
#endif
#ifdef SIGSTOP
    sigdelset(&set, SIGSTOP);
#endif
    sigdelset(&set, SIGSEGV);
#ifdef SIGBUS
    sigdelset(&set, SIGBUS);
#endif /*SIGBUS*/
#if defined(GC_LINUX_THREADS)
    /* some signals are used in the system */
    sigdelset(&set, SIGPWR);  /* used in gc */
    sigdelset(&set, SIGXCPU); /* used in gc */
    sigdelset(&set, SIGUSR1); /* used in linux threads */
    sigdelset(&set, SIGUSR2); /* used in linux threads */
#endif /*GC_LINUX_THREADS*/
#if defined(GC_FREEBSD_THREADS)
    sigdelset(&set, SIGUSR1); /* used by GC to stop the world */
    sigdelset(&set, SIGUSR2); /* used by GC to restart the world */
#endif /*GC_FREEBSD_THREADS*/
    Scm_SetMasterSigmask(&set);
}


static void
load_gauche_init(void)
{
    ScmLoadPacket lpak;
    if (Scm_Load("gauche-init.scm", 0, &lpak) < 0)
    {
	Scm_Emsgf(
	    "WARNING: Error while loading initialization file: %A(%A).",
	    Scm_ConditionMessage(lpak.exception),
	    Scm_ConditionTypeName(lpak.exception)
	);
    }
}




/* vim-echomsg-port and vim-echoerr-port */  /*{{{2*/

static ScmObj scm_vim_echomsg_port = SCM_UNBOUND;
static ScmObj scm_vim_echoerr_port = SCM_UNBOUND;


static void
putx(char_u* s, ScmPort *p)
{
    /* s must be NUL-terminated */
    if ((int)(p->src.vt.data))
	EMSG(s);
    else
	MSG(s);
}

static void
vim_echo_port_putb(ScmByte b, ScmPort *p)
{
    char_u buf[2] = {b, '\0'};
    putx(buf, p);
}
static void
vim_echo_port_putc(ScmChar c, ScmPort *p)
{
    int nb = SCM_CHAR_NBYTES(c);
    char_u buf[nb+1];  /* FIXME: extension - not worked with old compiler */
    memset(buf, 0x00, sizeof(buf));
    SCM_CHAR_PUT(buf, c);
    putx(buf, p);
}
static void
vim_echo_port_putz(const char *_buf, int size, ScmPort *p)
{
    char_u buf[size+1];  /* FIXME: extension - not worked with old compiler */
    memcpy(buf, _buf, size);
    buf[size] = '\0';
    putx(buf, p);
}
static void
vim_echo_port_puts(ScmString *s, ScmPort *p)
{
    putx((char_u *)Scm_GetStringConst(s), p);
}

static ScmPortVTable scm_null_port_vtable = {
    NULL,  /* (*Getb) */
    NULL,  /* (*Getc) */
    NULL,  /* (*Getz) */
    NULL,  /* (*Ready) */
    NULL,  /* (*Putb) */
    NULL,  /* (*Putc) */
    NULL,  /* (*Putz) */
    NULL,  /* (*Puts) */
    NULL,  /* (*Flush) */
    NULL,  /* (*Close) */
    NULL,  /* (*Seek) */
    NULL  /* *data */
};
static ScmPortVTable scm_vim_echomsg_port_vtable = {
    NULL,  /* (*Getb) */
    NULL,  /* (*Getc) */
    NULL,  /* (*Getz) */
    NULL,  /* (*Ready) */
    vim_echo_port_putb,  /* (*Putb) */
    vim_echo_port_putc,  /* (*Putc) */
    vim_echo_port_putz,  /* (*Putz) */
    vim_echo_port_puts,  /* (*Puts) */
    NULL,  /* (*Flush) */
    NULL,  /* (*Close) */
    NULL,  /* (*Seek) */
    (void*)FALSE  /* *data - use :echomsg */
};
static ScmPortVTable scm_vim_echoerr_port_vtable = {
    NULL,  /* (*Getb) */
    NULL,  /* (*Getc) */
    NULL,  /* (*Getz) */
    NULL,  /* (*Ready) */
    vim_echo_port_putb,  /* (*Putb) */
    vim_echo_port_putc,  /* (*Putc) */
    vim_echo_port_putz,  /* (*Putz) */
    vim_echo_port_puts,  /* (*Puts) */
    NULL,  /* (*Flush) */
    NULL,  /* (*Close) */
    NULL,  /* (*Seek) */
    (void*)TRUE  /* *data - use :echoerr */
};


static ScmObj
Scm_VimEchomsgPort(void)
{
    return scm_vim_echomsg_port;
}
static ScmObj
Scm_VimEchoerrPort(void)
{
    return scm_vim_echoerr_port;
}


static ScmObj
vim_echomsg_port_proc(ScmObj *args, int nargs, void *data)
{
    return Scm_VimEchomsgPort();
}
static SCM_DEFINE_STRING_CONST(vim_echomsg_port_NAME, "vim-echomsg-port",
			       16, 16);
static SCM_DEFINE_SUBR(vim_echomsg_port_STUB, 0, 0,
		       SCM_OBJ(&vim_echomsg_port_NAME), vim_echomsg_port_proc,
		       NULL, NULL);

static ScmObj
vim_echoerr_port_proc(ScmObj *args, int nargs, void *data)
{
    return Scm_VimEchoerrPort();
}
static SCM_DEFINE_STRING_CONST(vim_echoerr_port_NAME, "vim-echoerr-port",
			       16, 16);
static SCM_DEFINE_SUBR(vim_echoerr_port_STUB, 0, 0,
		       SCM_OBJ(&vim_echoerr_port_NAME), vim_echoerr_port_proc,
		       NULL, NULL);




/* vim-apply */  /*{{{2*/

static ScmObj
vim_apply_proc(ScmObj *args, int nargs, void *data)
{
    ScmObj func = args[0];
    int i;
    typval_T argvars[3+1];
    typval_T rettv;
    ScmObj result;
    const char *errmsg;

    /* {func} */
    if (!SCM_STRINGP(args[0]))
	Scm_TypeError("vim-apply", "string", args[0]);
    argvars[0].v_type = VAR_STRING;
    argvars[0].v_lock = 0;
    argvars[0].vval.v_string =
	vim_strsave((char_u*)Scm_GetString(SCM_STRING(args[0])));

    /* {arglist} */
    /* Note that Gauche passes optional arguments as a list.  This subr is
     * equivalent to (define (vim-apply func arg1 . args) ...), so Gauche
     * passes just func as args[0], arg1 as args[1] and args as args[2].  */
    {
	int n;
	ScmObj *a = Scm_ListToArray(Scm_Cons(args[1], args[2]), &n, NULL, 0);
	ScmObj sargs = a[--n];
	while (0 <= --n)
	    sargs = Scm_Cons(a[n], sargs);
	errmsg = gauche_to_vim(sargs, argvars + 1);
	if (errmsg != NULL)
	{
	    clear_tv(argvars + 0);
	    Scm_Error("%s", errmsg);
	}
    }

    /* {dict} */  /* TODO */
    argvars[2].v_type = VAR_UNKNOWN;

    /* :call */
    argvars[3].v_type = VAR_UNKNOWN;
    rettv.v_type = VAR_UNKNOWN;
    rettv.v_lock = 0;
    f_call(argvars, &rettv);
    errmsg = vim_to_gauche(&rettv, &result);

    /* clean up */
    clear_tv(argvars + 0);
    clear_tv(argvars + 1);
    clear_tv(argvars + 2);
    clear_tv(&rettv);
    if (errmsg != NULL)
	Scm_Error("%s", errmsg);
    return result;
}
static SCM_DEFINE_STRING_CONST(vim_apply_NAME, "vim-apply", 9, 9);
static SCM_DEFINE_SUBR(vim_apply_STUB, 2, 1,
		       SCM_OBJ(&vim_apply_NAME), vim_apply_proc,
		       NULL, NULL);




/* vim-eval and vim-execute */  /*{{{2*/
/* TODO: provide choice for caller - do :echoerr by Vim or raise a condition
 * for Gauche if an error is occured in the given vim script. */

static ScmObj
vim_eval_proc(ScmObj *args, int nargs, void *data)
{
    ScmObj s = args[0];
    typval_T *tv;
    ScmObj result;
    const char *errmsg;

    if (!SCM_STRINGP(s))
	Scm_TypeError("vim-eval", "string", s);

    tv = eval_expr((char_u *)Scm_GetString(SCM_STRING(s)), NULL);
    if (tv == NULL)
	Scm_Error("Invalid expression: %S", s);

    errmsg = vim_to_gauche(tv, &result);
    free_tv(tv);

    if (errmsg != NULL)
	Scm_Error("%s", errmsg);
    return result;
}
static SCM_DEFINE_STRING_CONST(vim_eval_NAME, "vim-eval", 8, 8);
static SCM_DEFINE_SUBR(vim_eval_STUB, 1, 0,
		       SCM_OBJ(&vim_eval_NAME), vim_eval_proc,
		       NULL, NULL);

static ScmObj
vim_execute_proc(ScmObj *args, int nargs, void *data)
{
    ScmObj s = args[0];

    if (!SCM_STRINGP(s))
	Scm_TypeError("vim-execute", "string", s);

    do_cmdline_cmd((char_u*)Scm_GetString(SCM_STRING(s)));
    return SCM_UNDEFINED;
}
static SCM_DEFINE_STRING_CONST(vim_execute_NAME, "vim-execute", 11, 11);
static SCM_DEFINE_SUBR(vim_execute_STUB, 1, 0,
		       SCM_OBJ(&vim_execute_NAME), vim_execute_proc,
		       NULL, NULL);








/* Stuffs for Vim */  /*{{{1*/
/* Initialization, finalization and misc. stuffs */  /*{{{2*/

    int
gauche_enabled(verbose)
    int verbose;
{
    /* FIXME */
    return TRUE;
}


    void
gauche_end()
{
    Scm_Cleanup();
}

    void
gauche_init()
{
    GC_INIT();
    Scm_Init(GAUCHE_SIGNATURE);
    sig_setup();

    load_gauche_init();

    /* below is the initialization for +gauche own stuffs */

	/* (vim-echomsg-port) and (vim-echoerr-port) */
    scm_vim_echomsg_port = Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_OUTPUT,
					       &scm_vim_echomsg_port_vtable);
    scm_vim_echoerr_port = Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_OUTPUT,
					       &scm_vim_echoerr_port_vtable);
    SCM_DEFINE(Scm_UserModule(), "vim-echomsg-port",
	       SCM_OBJ(&vim_echomsg_port_STUB));
    SCM_DEFINE(Scm_UserModule(), "vim-echoerr-port",
	       SCM_OBJ(&vim_echoerr_port_STUB));

	/* disable (current-input-port), (current-output-port) and
	 * (current-error-port) to avoid some probnlems.
	 * FIXME: Show warning if these ports are used.  */
    Scm_SetCurrentInputPort(
	SCM_PORT(Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_INPUT,
				     &scm_null_port_vtable)));
    Scm_SetCurrentOutputPort(
	SCM_PORT(Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_OUTPUT,
				     &scm_null_port_vtable)));
    Scm_SetCurrentErrorPort(
	SCM_PORT(Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_OUTPUT,
				     &scm_null_port_vtable)));

	/* (vim-eval) and (vim-execute) */
    SCM_DEFINE(Scm_UserModule(), "vim-eval", SCM_OBJ(&vim_eval_STUB));
    SCM_DEFINE(Scm_UserModule(), "vim-execute", SCM_OBJ(&vim_execute_STUB));

	/* (vim-apply) */
    SCM_DEFINE(Scm_UserModule(), "vim-apply", SCM_OBJ(&vim_apply_STUB));
}




/* Ex commands */  /*{{{2*/

    void
ex_gauche(eap)
    exarg_T *eap;
{
    char_u *script;

    script = script_get(eap, eap->arg);
    if (!(eap->skip))
    {
	ScmObj s = SCM_MAKE_STR_COPYING((char *)(script != NULL ? script
						                : eap->arg));
	ScmObj inp = Scm_MakeInputStringPort(SCM_STRING(s), TRUE);
	ScmObj inp_orig;
	ScmObj errp = Scm_MakeOutputStringPort(TRUE);
	ScmObj errp_orig;
	char *errmsg;

	inp_orig = Scm_SetCurrentInputPort(SCM_PORT(inp));
	errp_orig = Scm_SetCurrentErrorPort(SCM_PORT(errp));

	Scm_Repl(SCM_FALSE, SCM_FALSE, Scm_NullProc(), Scm_NullProc());

	Scm_SetCurrentErrorPort(SCM_PORT(errp_orig));
	Scm_SetCurrentInputPort(SCM_PORT(inp_orig));

	errmsg = Scm_GetString(SCM_STRING(Scm_GetOutputString(SCM_PORT(errp),
							      0)));
	if (errmsg[0] != '\0')
	{
	    char* s = errmsg;
	    char* e;

	    while ((e = strchr(s, '\n')) != NULL)
	    {
		*e = '\0';
		EMSG(s);
		s = e + 1;
	    }

	    if (*s != '\0')
		EMSG(s);
	}
    }
    vim_free(script);
}

    void
ex_gafile(eap)
    exarg_T *eap;
{
    ScmLoadPacket lpak;

    /* equivalent to :gauche (load file) */
    if (Scm_Load((char *)(eap->arg), 0, &lpak) < 0)
    {
	Scm_Emsgf("Error while loading file: %A(%A)",
		  Scm_ConditionMessage(lpak.exception),
		  Scm_ConditionTypeName(lpak.exception));
    }
}








/* __END__  {{{1
 * vim: foldmethod=marker
 */
