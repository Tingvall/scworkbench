#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <limits.h>
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

/* Same canonical number rule for ordinary R numeric scalars in downstream
 * table/space receipts. Parsed JSON lexemes still use the existing R parser.
 * Unsupported/range-edge values fall back to its exact typed diagnostics. */
SEXP scwb_canonical_numeric(SEXP value) {
    if ((TYPEOF(value) != INTSXP && TYPEOF(value) != REALSXP) || XLENGTH(value) != 1)
        return R_NilValue;
    double x = Rf_asReal(value);
    if (!R_FINITE(x) || (x != 0 && fabs(x) < 1e-307)) return R_NilValue;
    char result[64]; number(x, result);
    return Rf_mkString(result);
}

/* PCRE-produced positions are already sorted. R 4.4 findInterval checks the
 * complete vector on every lookup, defeating pre-indexing of large snapshots. */
SEXP scwb_json_index_floor(SEXP positions, SEXP value) {
    if (TYPEOF(positions) != INTSXP && TYPEOF(positions) != REALSXP)
        Rf_error("Invalid JSON lexical index.");
    double x = Rf_asReal(value);
    R_xlen_t left = 0, right = XLENGTH(positions);
    while (left < right) {
        R_xlen_t mid = left + (right - left) / 2;
        double at = TYPEOF(positions) == INTSXP ? INTEGER(positions)[mid] : REAL(positions)[mid];
        if (at <= x) left = mid + 1; else right = mid;
    }
    return Rf_ScalarReal((double)left);
}

typedef struct {
    FILE *file;
    SEXP rows, columns, values;
    int first;
} append_context;

/* Coordinates are positive R integers, exactly representable in the canonical
 * 15-digit scheme. Emit their scientific token without floating conversion. */
static size_t coordinate(int x, char *out) {
    if (x <= 0) { number((double)x, out); return strlen(out); }
    char reverse[10], digits[10];
    unsigned int value = (unsigned int)x;
    size_t count = 0;
    do { reverse[count++] = (char)('0' + value % 10); value /= 10; } while (value);
    for (size_t i = 0; i < count; ++i) digits[i] = reverse[count - i - 1];
    size_t last = count - 1;
    while (last > 0 && digits[last] == '0') --last;
    char *p = out;
    *p++ = digits[0];
    if (last) { *p++ = '.'; memcpy(p, digits + 1, last); p += last; }
    *p++ = 'e'; *p++ = (char)('0' + count - 1); *p = '\0';
    return (size_t)(p - out);
}

static void append_cleanup(void *data, Rboolean jump) {
    append_context *context = data;
    if (context->file) { fclose(context->file); context->file = NULL; }
}

static SEXP append_body(void *data) {
    append_context *context = data;
    char buffer[65536];
    size_t used = 0;
    char column[64];
    int previous_column = 0, have_column = 0;
    size_t column_bytes = 0;
    for (R_xlen_t i = 0; i < XLENGTH(context->values); ++i) {
        char row[64], value[64], record[256];
        size_t row_bytes = coordinate(INTEGER(context->rows)[i], row);
        int current_column = INTEGER(context->columns)[i];
        if (!have_column || current_column != previous_column) {
            column_bytes = coordinate(current_column, column);
            previous_column = current_column; have_column = 1;
        }
        if (TYPEOF(context->values) == LGLSXP)
            strcpy(value, LOGICAL(context->values)[i] ? "true" : "false");
        else {
            double x = REAL(context->values)[i];
            /* Exact positive int32 values need no floating conversion either.
             * This changes token construction only; nonintegers retain %.15g. */
            if (x >= 1 && x <= INT_MAX && x == (int)x)
                coordinate((int)x, value);
            else number(x, value);
        }
        char *p = record;
        if (!context->first) *p++ = ',';
        memcpy(p, "{\"column\":", 10); p += 10;
        memcpy(p, column, column_bytes); p += column_bytes;
        memcpy(p, ",\"row\":", 7); p += 7;
        memcpy(p, row, row_bytes); p += row_bytes;
        memcpy(p, ",\"value\":", 9); p += 9;
        size_t value_bytes = strlen(value);
        memcpy(p, value, value_bytes); p += value_bytes;
        *p++ = '}';
        size_t bytes = (size_t)(p - record);
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
        TYPEOF(rows) != INTSXP || TYPEOF(columns) != INTSXP ||
        (TYPEOF(values) != REALSXP && TYPEOF(values) != LGLSXP) ||
        XLENGTH(rows) != XLENGTH(values) || XLENGTH(columns) != XLENGTH(values))
        Rf_error("Invalid matrix identity append vectors.");
    append_context context = {NULL, rows, columns, values, Rf_asLogical(first) == TRUE};
    context.file = fopen(Rf_translateCharUTF8(STRING_ELT(path, 0)), "ab");
    if (!context.file) Rf_error("Cannot open private matrix identity stream.");
    return R_UnwindProtect(append_body, &context, append_cleanup, &context, NULL);
}
