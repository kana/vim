/*
 * guess.c - guessing character encoding 
 *
 *   Copyright (c) 2000-2007  Shiro Kawai  <shiro@acm.org>
 * 
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 * 
 *   1. Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *
 *   2. Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *
 *   3. Neither the name of the authors nor the names of its contributors
 *      may be used to endorse or promote products derived from this
 *      software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 *   TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *  $Id: guess.c,v 1.5 2007/03/02 07:39:04 shirok Exp $
 */

#include <stdio.h>
#include <string.h>
#include "vim.h"

typedef struct guess_arc_rec {
    unsigned int next;          /* next state */
    double score;               /* score */
} guess_arc;

typedef struct guess_dfa_rec {
    const char *name;
    signed char (*states)[256];
    guess_arc *arcs;
    int state;
    double score;
} guess_dfa;

#define DFA_INIT(name, st, ar) \
    { name, st, ar, 0, 1.0 }

#define DFA_NEXT(dfa, ch)                               \
    do {                                                \
        int arc__;                                      \
        if (dfa.state >= 0) {                           \
            arc__ = dfa.states[dfa.state][ch];          \
            if (arc__ < 0) {                            \
                dfa.state = -1;                         \
            } else {                                    \
                dfa.state = dfa.arcs[arc__].next;       \
                dfa.score *= dfa.arcs[arc__].score;     \
            }                                           \
        }                                               \
    } while (0)

#define DFA_ALIVE(dfa)  (dfa.state >= 0)

/* include DFA table generated by guess.scm */
#include "guess_tab.c"

static const char *guess_jp(FILE *in, const char *def)
{
    int i, c, c2, alive;
    guess_dfa dfa[] = {
        DFA_INIT("utf-8",       guess_utf8_st, guess_utf8_ar),
        DFA_INIT("cp932",       guess_sjis_st, guess_sjis_ar),
        DFA_INIT("euc-jp",      guess_eucj_st, guess_eucj_ar),
        DFA_INIT("utf-16be",    guess_utf16be_st, guess_utf16be_ar),
        DFA_INIT("utf-16le",    guess_utf16le_st, guess_utf16le_ar),
        DFA_INIT(NULL, NULL, NULL)
    };
    guess_dfa *utf16be = &dfa[3];
    guess_dfa *utf16le = &dfa[4];
    guess_dfa *top = NULL;

    /* set UTF-16 low priority */
    utf16be->score = 0.1;
    utf16le->score = 0.1;

    while ((c = fgetc(in)) != EOF) {

        /* UTF-16 */
        if (utf16be->state == 0 || utf16le->state == 0) {
            if ((c2 = fgetc(in)) != EOF) {
                if (utf16be->state == 0 &&
                        c == 0x00 && (c2 == 0x0A || c2 == 0x0D))
                    return "utf-16be";
                if (utf16le->state == 0 &&
                        (c == 0x0A || c == 0x0D) && c2 == 0x00)
                    return "utf-16le";
                ungetc(c2, in);
            }
        }

        /* special treatment of jis escape sequence */
        if (c == 0x1b) {
            if ((c2 = fgetc(in)) != EOF) {
                if (c2 == '$' || c2 == '(') return "iso-2022-jp";
                ungetc(c2, in);
            }
        }

        alive = 0;
        for (i = 0; dfa[i].name != NULL; ++i) {
            if (DFA_ALIVE(dfa[i])) {
                DFA_NEXT(dfa[i], c);
                if (DFA_ALIVE(dfa[i]))
                    ++alive;
            }
        }

        if (alive == 0) {
            /* we ran out the possibilities */
            return NULL;
        } else if (alive == 1) {
            break;
        }
    }

    /* Now, we have ambigous code.  Pick the highest score.  If more than
       one candidate tie, pick the default encoding. */
    for (i = 0; dfa[i].name != NULL; ++i) {
        if (DFA_ALIVE(dfa[i])) {
            if (!top || top->score < dfa[i].score ||
                    (top->score == dfa[i].score &&
                     strcmp(dfa[i].name, def) == 0))
                top = &dfa[i];
        }
    }
    if (top)
        return top->name;
    return NULL;
}

static const char *guess_bom(FILE *in)
{
    int c, c2, c3;

    c = fgetc(in);
    if (c == 0xFE || c == 0xFF) {
        c2 = fgetc(in);
        if (c == 0xFE && c2 == 0xFF) return "utf-16be";
        if (c == 0xFF && c2 == 0xFE) return "utf-16le";
        ungetc(c2, in);
    } else if (c == 0xEF) {
        c2 = fgetc(in);
        c3 = fgetc(in);
        if (c2 == 0xBB && c3 == 0xBF) return "utf-8";
        ungetc(c3, in);
        ungetc(c2, in);
    }
    ungetc(c, in);
    return NULL;
}

int guess_encode(char_u** fenc, int* fenc_alloced, char_u* fname)
{
    FILE *in;
    const char *enc;

    if (p_verbose >= 1)
    {
        verbose_enter();
        smsg((char_u*)"guess_encode:");
        smsg((char_u*)"    init: fenc=%s alloced=%d fname=%s\n",
            *fenc, *fenc_alloced, fname);
        verbose_leave();
    }

    if (!fname)
        return 0;
    in = mch_fopen((const char *)fname, "r");
    if (!in)
        return 0;

    enc = guess_bom(in);
    if (!enc)
        enc = guess_jp(in, "utf-8");
    fclose(in);

    if (enc)
    {
        if (p_verbose >= 1)
        {
            verbose_enter();
            smsg("    result: newenc=%s\n", enc);
            verbose_leave();
        }
        if (*fenc_alloced)
            vim_free(*fenc);
        *fenc = vim_strsave((char_u*)enc);
        *fenc_alloced = TRUE;
    }
    return 1;
}
