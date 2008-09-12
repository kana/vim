/* vi:set ts=8 sts=4 sw=4:
 *
 * VIM - Vi IMproved	by Bram Moolenaar
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * Gauche extensions by Kana Natsuno.
 *
 * Functions which are called by Vim are written in old style.
 * Functions which are called by Gauche are written in new style.
 */

#include "vim.h"

#define GAUCHE_API_0_9        /* temporary compatibility stuff */
#include "gauche.h"




/* echomsg-port and echoerr-port */

static ScmObj scm_echomsg_port = SCM_UNBOUND;
static ScmObj scm_echoerr_port = SCM_UNBOUND;


    static void
putx(char_u* s, ScmPort *p)
{
    int (*fmsg)(char_u *);
    fmsg = p->src.vt.data;
    (*fmsg)(s);  /* s must be NUL-terminated */
}

    static void
scm_echo_port_putb(ScmByte b, ScmPort *p)
{
    char_u buf[2] = {b, '\0'};
    putx(buf, p);
}
    static void
scm_echo_port_putc(ScmChar c, ScmPort *p)
{
    int nb = SCM_CHAR_NBYTES(c);
    char_u buf[nb+1];  /* FIXME: extension - not worked with old compiler */
    memset(buf, 0x00, sizeof(buf));
    SCM_CHAR_PUT(buf, c);
    putx(buf, p);
}
    static void
scm_echo_port_putz(const char *_buf, int size, ScmPort *p)
{
    char_u buf[size+1];  /* FIXME: extension - not worked with old compiler */
    memcpy(buf, _buf, size);
    buf[size] = '\0';
    putx(buf, p);
}
    static void
scm_echo_port_puts(ScmString *s, ScmPort *p)
{
    putx((char_u *)Scm_GetStringConst(s), p);
}

static ScmPortVTable scm_echomsg_port_vtable = {
    NULL,  /* (*Getb) */
    NULL,  /* (*Getc) */
    NULL,  /* (*Getz) */
    NULL,  /* (*Ready) */
    scm_echo_port_putb,  /* (*Putb) */
    scm_echo_port_putc,  /* (*Putc) */
    scm_echo_port_putz,  /* (*Putz) */
    scm_echo_port_puts,  /* (*Puts) */
    NULL,  /* (*Flush) */
    NULL,  /* (*Close) */
    NULL,  /* (*Seek) */
    msg  /* *data */
};
static ScmPortVTable scm_echoerr_port_vtable = {
    NULL,  /* (*Getb) */
    NULL,  /* (*Getc) */
    NULL,  /* (*Getz) */
    NULL,  /* (*Ready) */
    scm_echo_port_putb,  /* (*Putb) */
    scm_echo_port_putc,  /* (*Putc) */
    scm_echo_port_putz,  /* (*Putz) */
    scm_echo_port_puts,  /* (*Puts) */
    NULL,  /* (*Flush) */
    NULL,  /* (*Close) */
    NULL,  /* (*Seek) */
    emsg  /* *data */
};


    static ScmObj
Scm_EchomsgPort(void)
{
    return scm_echomsg_port;
}
    static ScmObj
Scm_EchoerrPort(void)
{
    return scm_echoerr_port;
}








/* Initialization, finalization and misc. stuffs */

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
	Scm_Printf(SCM_CURERR, "gosh: WARNING: Error while loading initialization file: %A(%A).\n",
		   Scm_ConditionMessage(lpak.exception),
		   Scm_ConditionTypeName(lpak.exception));
    }
}

    void
gauche_init()
{
    GC_INIT();
    Scm_Init(GAUCHE_SIGNATURE);
    sig_setup();

    load_gauche_init();

    /* below is the initialization for +gauche own stuffs */
    scm_echomsg_port = Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_OUTPUT,
					   &scm_echomsg_port_vtable);
    scm_echoerr_port = Scm_MakeVirtualPort(SCM_CLASS_PORT, SCM_PORT_OUTPUT,
					   &scm_echoerr_port_vtable);
}




/* Ex commands */

    void
ex_gauche(eap)
    exarg_T *eap;
{
    MSG(":gauche");  /* FIXME: just a dummy to check how to add Ex command */
}

    void
ex_gafile(eap)
    exarg_T *eap;
{
    ScmLoadPacket lpak;

    /* equivalent to :gauche (load file) */
    if (Scm_Load((char *)(eap->arg), 0, &lpak) < 0)
    {
	/* FIXME: Here we should show also the message of a condition, but
	 * it's a hard work at this moment.  So here we show only the name of
	 * a condition.
	 *
	 * Scm_GetStringConst(
	 *  SCM_STRING(Scm_ConditionMessage(lpak.exception))),  */
	EMSG2("Error while loading file: (%s)",
	      Scm_GetStringConst(
		  SCM_STRING(Scm_ConditionTypeName(lpak.exception))));
    }
}

/* __END__ */
