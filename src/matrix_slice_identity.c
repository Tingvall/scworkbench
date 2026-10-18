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

typedef struct {
    FILE *file;
    SEXP rows, columns, values;
    int first;
} append_context;

static void append_cleanup(void *data, Rboolean jump) {
    append_context *context = data;
    if (context->file) { fclose(context->file); context->file = NULL; }
}

static SEXP append_body(void *data) {
    append_context *context = data;
    char buffer[65536];
    size_t used = 0;
    for (R_xlen_t i = 0; i < XLENGTH(context->values); ++i) {
        char row[64], column[64], value[64], record[256];
        number(INTEGER(context->rows)[i], row);
        number(INTEGER(context->columns)[i], column);
        number(REAL(context->values)[i], value);
        int bytes = snprintf(record, sizeof(record), "%s{\"column\":%s,\"row\":%s,\"value\":%s}",
            context->first ? "" : ",", column, row, value);
        if (used + bytes > sizeof(buffer)) {
            if (fwrite(buffer, 1, used, context->file) != used) Rf_error("Matrix identity write failed.");
            used = 0;
        }
        memcpy(buffer + used, record, bytes); used += bytes;
        context->first = 0;
        if (i % 8192 == 0) R_CheckUserInterrupt();
    }
    if (used && fwrite(buffer, 1, used, context->file) != used) Rf_error("Matrix identity write failed.");
    if (fflush(context->file)) Rf_error("Matrix identity flush failed.");
    return R_NilValue;
}

SEXP scwb_matrix_slice_append(SEXP path, SEXP rows, SEXP columns, SEXP values, SEXP first) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING ||
        TYPEOF(rows) != INTSXP || TYPEOF(columns) != INTSXP || TYPEOF(values) != REALSXP ||
        XLENGTH(rows) != XLENGTH(values) || XLENGTH(columns) != XLENGTH(values))
        Rf_error("Invalid matrix identity append vectors.");
    append_context context = {NULL, rows, columns, values, Rf_asLogical(first) == TRUE};
    context.file = fopen(Rf_translateCharUTF8(STRING_ELT(path, 0)), "ab");
    if (!context.file) Rf_error("Cannot open private matrix identity stream.");
    return R_UnwindProtect(append_body, &context, append_cleanup, &context, NULL);
}
