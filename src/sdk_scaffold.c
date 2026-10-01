#define _GNU_SOURCE
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>
#include <errno.h>
#include <string.h>

#if defined(__linux__) && !defined(SCWB_SDK_DISABLE_RENAMEAT2)
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
#endif

static SEXP scwb_sdk_publish_noreplace(SEXP source, SEXP destination)
{
    if (TYPEOF(source) != STRSXP || XLENGTH(source) != 1 ||
        STRING_ELT(source, 0) == NA_STRING ||
        TYPEOF(destination) != STRSXP || XLENGTH(destination) != 1 ||
        STRING_ELT(destination, 0) == NA_STRING)
        Rf_error("Atomic scaffold publication requires two nonmissing paths.");

#if defined(__linux__) && defined(SYS_renameat2) && !defined(SCWB_SDK_DISABLE_RENAMEAT2)
    /* Flag 1 is Linux UAPI RENAME_NOREPLACE. There is intentionally no
       ordinary rename, shell move, or cooperative-lock fallback. */
    if (syscall(SYS_renameat2, AT_FDCWD,
                Rf_translateCharUTF8(STRING_ELT(source, 0)), AT_FDCWD,
                Rf_translateCharUTF8(STRING_ELT(destination, 0)), 1U) != 0) {
        int failure = errno;
        if (failure == ENOSYS || failure == EINVAL || failure == EOPNOTSUPP)
            Rf_error("Atomic scaffold publication unsupported: renameat2(RENAME_NOREPLACE): %s. No replacing fallback.",
                     strerror(failure));
        Rf_error("Atomic scaffold publication rejected: renameat2(RENAME_NOREPLACE): %s. Destination not replaced.",
                 strerror(failure));
    }
    return R_NilValue;
#else
    Rf_error("Atomic scaffold publication unsupported: Linux renameat2(RENAME_NOREPLACE) unavailable. No replacing fallback.");
    return R_NilValue;
#endif
}

static const R_CallMethodDef sdk_calls[] = {
    {"scwb_sdk_publish_noreplace", (DL_FUNC) &scwb_sdk_publish_noreplace, 2},
    {NULL, NULL, 0}
};

void attribute_visible R_init_scworkbench(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, sdk_calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
