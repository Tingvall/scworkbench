/* Test-only carrier construction. R's ordinary dim<- materializes compact
 * REAL sequences; install dimensions on a freshly owned sequence without that
 * setter. Nothing in this DLL is installed or registered with the engine. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

static SEXP dense_deferred(SEXP end) {
    if (TYPEOF(end) != INTSXP || OBJECT(end) || ALTREP(end) ||
        ATTRIB(end) != R_NilValue || XLENGTH(end) != 1 ||
        INTEGER(end)[0] < 1 || INTEGER(end)[0] > 1000)
        Rf_error("Invalid deferred test fixture extent.");
    SEXP from = PROTECT(Rf_ScalarInteger(1));
    SEXP sequence_call = PROTECT(Rf_lang3(Rf_install("seq.int"), from, end));
    SEXP sequence = PROTECT(Rf_eval(sequence_call, R_BaseEnv));
    SEXP double_call = PROTECT(Rf_lang2(Rf_install("as.double"), sequence));
    SEXP value = PROTECT(Rf_eval(double_call, R_BaseEnv));
    if (TYPEOF(value) != REALSXP || !ALTREP(value) ||
        ATTRIB(value) != R_NilValue || XLENGTH(value) != INTEGER(end)[0])
        Rf_error("Fresh REAL ALTREP test fixture is unavailable.");
    SEXP dims = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(dims)[0] = INTEGER(end)[0]; INTEGER(dims)[1] = 1;
    SEXP attrs = PROTECT(Rf_cons(dims, R_NilValue));
    SET_TAG(attrs, R_DimSymbol);
    SET_ATTRIB(value, attrs);
    UNPROTECT(7);
    return value;
}

static SEXP is_deferred(SEXP value) {
    return Rf_ScalarLogical(ALTREP(value));
}

/* Attach caller-owned metadata without invoking names<- (which may wrap the
 * numeric source in ALTREP). Used only to distinguish data and metadata gates. */
static SEXP numeric_names(SEXP value, SEXP names, SEXP array) {
    if (TYPEOF(value) != REALSXP || OBJECT(value) || ALTREP(value) ||
        ATTRIB(value) != R_NilValue || TYPEOF(names) != STRSXP ||
        XLENGTH(names) != XLENGTH(value) || TYPEOF(array) != LGLSXP ||
        XLENGTH(array) != 1 || LOGICAL(array)[0] == NA_LOGICAL)
        Rf_error("Invalid numeric-name test fixture.");
    SEXP result = PROTECT(Rf_duplicate(value));
    if (LOGICAL(array)[0]) {
        SEXP dims = PROTECT(Rf_ScalarInteger((int)XLENGTH(value)));
        SEXP axes = PROTECT(Rf_allocVector(VECSXP, 1));
        SET_VECTOR_ELT(axes, 0, names);
        SEXP tail = PROTECT(Rf_cons(axes, R_NilValue));
        SET_TAG(tail, R_DimNamesSymbol);
        SEXP attrs = PROTECT(Rf_cons(dims, tail));
        SET_TAG(attrs, R_DimSymbol); SET_ATTRIB(result, attrs);
        UNPROTECT(4);
    } else {
        SEXP attrs = PROTECT(Rf_cons(names, R_NilValue));
        SET_TAG(attrs, R_NamesSymbol); SET_ATTRIB(result, attrs);
        UNPROTECT(1);
    }
    UNPROTECT(1);
    return result;
}

static const R_CallMethodDef calls[] = {
    {"dense_deferred", (DL_FUNC)&dense_deferred, 1},
    {"is_deferred", (DL_FUNC)&is_deferred, 1},
    {"numeric_names", (DL_FUNC)&numeric_names, 3},
    {NULL, NULL, 0}
};

void R_init_engine_dense_fixture(DllInfo *dll) {
    R_registerRoutines(dll, NULL, calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
