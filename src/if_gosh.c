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
 * Functions which are called by Vim are written in old style.
 * Functions which are called by Gauche are written in new style.
 */

#include "vim.h"

#define GAUCHE_API_0_9        /* temporary compatibility stuff */
#include "gauche.h"




/* Common Utilities */  /*{{{1*/

/* Wrappers for Scm_Printf() - output by :echomsg or :echoerr */

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








/* Stuffs for Gauche */  /*{{{1*/
/* Initialization and Finalization */  /*{{{2*/

    static void
sig_setup()
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
load_gauche_init()
{
    ScmLoadPacket lpak;
    if (Scm_Load("gauche-init.scm", 0, &lpak) < 0) {
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
    int (*fmsg)(char_u *);
    fmsg = p->src.vt.data;
    (*fmsg)(s);  /* s must be NUL-terminated */
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
    msg  /* *data */
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
    emsg  /* *data */
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
}




/* Ex commands */  /*{{{2*/

    void
ex_gauche(eap)
    exarg_T *eap;
{
    char_u *script;

    script = script_get(eap, eap->arg);
    if (!(eap->skip)) {
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
	if (errmsg[0] != '\0') {
	    char* s = errmsg;
	    char* e;

	    while ((e = strchr(s, '\n')) != NULL) {
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
