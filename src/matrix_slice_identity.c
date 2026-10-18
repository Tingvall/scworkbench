#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Canonical JSON v1's 15-significant-digit scientific representation, using
 * the same %.15g conversion as formatC(digits=15, format="g"). No R object
 * per coordinate and no whole-matrix representation are constructed. */
static void number(double x, char *out) {
    char token[64], digits[32];
    int n = 0, before = 0, exponent = 0, decimal = 0;
    if (!R_FINITE(x)) Rf_error("Canonical matrix values must be finite.");
    if (x == 0) { strcpy(out, "0"); return; }
    snprintf(token, sizeof(token), "%.15g", x);
    char *p = token;
    int negative = *p == '-';
    if (negative) ++p;
    while (*p && *p != 'e' && *p != 'E') {
        if (*p == '.') decimal = 1;
        else {
            if (*p < '0' || *p > '9') Rf_error("Non-C numeric locale in matrix identity.");
            digits[n++] = *p;
            if (!decimal) ++before;
        }
        ++p;
    }
    if (*p) exponent = atoi(p + 1);
    int first = 0, last = n - 1;
    while (first < n && digits[first] == '0') ++first;
    while (last > first && digits[last] == '0') --last;
    int adjusted = exponent + before - first - 1;
    if (adjusted < -307 || adjusted > 308)
        Rf_error("Canonical matrix number is outside the supported exponent range.");
    char *q = out;
    if (negative) *q++ = '-';
    *q++ = digits[first];
    if (last > first) {
        *q++ = '.';
        for (int i = first + 1; i <= last; ++i) *q++ = digits[i];
    }
    sprintf(q, "e%d", adjusted);
}

SEXP scwb_matrix_slice_entries(SEXP rows, SEXP columns, SEXP values) {
    R_xlen_t n = XLENGTH(values);
    if (TYPEOF(rows) != INTSXP || TYPEOF(columns) != INTSXP ||
        TYPEOF(values) != REALSXP || XLENGTH(rows) != n || XLENGTH(columns) != n)
        Rf_error("Invalid matrix coordinate vectors.");
    SEXP result = PROTECT(Rf_allocVector(STRSXP, n));
    for (R_xlen_t i = 0; i < n; ++i) {
        char row[64], column[64], value[64], record[256];
        number(INTEGER(rows)[i], row);
        number(INTEGER(columns)[i], column);
        number(REAL(values)[i], value);
        snprintf(record, sizeof(record), "{\"column\":%s,\"row\":%s,\"value\":%s}", column, row, value);
        SET_STRING_ELT(result, i, Rf_mkChar(record));
        if (i % 8192 == 0) R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return result;
}
