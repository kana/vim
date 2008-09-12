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
 */

#include "vim.h"

#define GAUCHE_API_0_9        /* temporary compatibility stuff */
#include "gauche.h"




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
}




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
