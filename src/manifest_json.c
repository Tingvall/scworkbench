#include <R.h>
#include <Rinternals.h>
#include <R_ext/Utils.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

/* Private, allocation-free eligibility followed by one bounded output buffer.
 * No translation/escaping/float formatting or row-sized metadata is needed. */
static int plain(SEXP x, SEXPTYPE type) {
    return TYPEOF(x) == type && !OBJECT(x) && !ALTREP(x) && ATTRIB(x) == R_NilValue;
}
static int safe_text(SEXP x, int digits, int nonempty) {
    if (x == NA_STRING || Rf_getCharCE(x) != CE_NATIVE) return 0;
    int n = LENGTH(x);
    if (n > 256 || (nonempty && !n)) return 0;
    const unsigned char *p = (const unsigned char *) CHAR(x);
    for (int i = 0; i < n; ++i) {
        unsigned char c = p[i];
        if (c >= '0' && c <= '9') continue;
        /* jsonlite1.8.8 emits these printable ASCII bytes literally. '<' is
         * excluded because its following '/' is contextually escaped. */
        if (digits || c < 32 || c > 126 || c == '"' || c == '<' || c == '\\')
            return 0;
    }
    return 1;
}
static int add_size(size_t *n, size_t extra) {
    if (extra > SIZE_MAX - *n) return 0;
    *n += extra;
    return *n < INT_MAX; /* Include the final NUL in the int-sized extent. */
}

SEXP scwb_manifest_scalar_json(SEXP rows, SEXP keys, SEXP bound) {
    if (TYPEOF(rows) != VECSXP || ALTREP(rows) ||
        !plain(bound, REALSXP) || XLENGTH(bound) != 1) return R_NilValue;
    double old_bound = REAL_ELT(bound, 0);
    if (!R_FINITE(old_bound) || old_bound < 0) return R_NilValue;
    SEXP names = R_NilValue, row_names = R_NilValue, cls = R_NilValue;
    int attributes = 0;
    /* getAttrib(row.names) expands compact names; inspect the raw pairlist. */
    for (SEXP a = ATTRIB(rows); a != R_NilValue; a = CDR(a)) {
        if (++attributes > 3) return R_NilValue;
        if (TAG(a) == R_NamesSymbol && names == R_NilValue) names = CAR(a);
        else if (TAG(a) == R_RowNamesSymbol && row_names == R_NilValue) row_names = CAR(a);
        else if (TAG(a) == R_ClassSymbol && cls == R_NilValue) cls = CAR(a);
        else return R_NilValue;
    }
    if (attributes != 3 || !plain(cls, STRSXP) || XLENGTH(cls) != 1 ||
        STRING_ELT(cls, 0) == NA_STRING || strcmp(CHAR(STRING_ELT(cls, 0)), "data.frame") ||
        !plain(names, STRSXP) || TYPEOF(keys) != STRSXP || OBJECT(keys) || ALTREP(keys)) return R_NilValue;
    for (SEXP a = ATTRIB(keys); a != R_NilValue; a = CDR(a))
        if (TAG(a) != R_NamesSymbol) return R_NilValue;
    R_xlen_t nc = XLENGTH(rows);
    if (nc < 1 || nc > 8 || XLENGTH(names) != nc || XLENGTH(keys) != nc) return R_NilValue;
    SEXP columns[8]; SEXPTYPE types[8]; const char *key[8]; size_t key_len[8];
    for (R_xlen_t j = 0; j < nc; ++j) {
        columns[j] = VECTOR_ELT(rows, j); types[j] = TYPEOF(columns[j]);
        if ((types[j] != STRSXP && types[j] != INTSXP && types[j] != LGLSXP) ||
            OBJECT(columns[j]) || ALTREP(columns[j]) || ATTRIB(columns[j]) != R_NilValue)
            return R_NilValue;
    }
    R_xlen_t nr = XLENGTH(columns[0]);
    if (nr < 1 || nr > 5000) return R_NilValue;
    for (R_xlen_t j = 0; j < nc; ++j) {
        if (XLENGTH(columns[j]) != nr || !safe_text(STRING_ELT(names, j), 0, 1)) return R_NilValue;
        SEXP k = STRING_ELT(keys, j), name = STRING_ELT(names, j);
        for (R_xlen_t previous = 0; previous < j; ++previous) {
            SEXP other = STRING_ELT(names, previous);
            if (LENGTH(name) == LENGTH(other) && !memcmp(CHAR(name), CHAR(other), (size_t)LENGTH(name)))
                return R_NilValue;
        }
        if (k == NA_STRING || Rf_getCharCE(k) != CE_NATIVE || LENGTH(k) != LENGTH(name) + 2)
            return R_NilValue;
        key[j] = CHAR(k); key_len[j] = (size_t)LENGTH(k);
        if (key[j][0] != '"' || key[j][key_len[j] - 1] != '"' ||
            memcmp(key[j] + 1, CHAR(name), (size_t)LENGTH(name))) return R_NilValue;
    }
    if (plain(row_names, INTSXP)) {
        int compact = XLENGTH(row_names) == 2 && INTEGER_ELT(row_names, 0) == NA_INTEGER &&
            (INTEGER_ELT(row_names, 1) == (int)nr ||
             INTEGER_ELT(row_names, 1) == -(int)nr);
        if (!compact) {
            if (XLENGTH(row_names) != nr) return R_NilValue;
            for (R_xlen_t i = 0; i < nr; ++i) if (INTEGER_ELT(row_names, i) == NA_INTEGER ||
                INTEGER_ELT(row_names, i) < 0) return R_NilValue;
        }
    } else if (plain(row_names, STRSXP) && XLENGTH(row_names) == nr) {
        for (R_xlen_t i = 0; i < nr; ++i)
            if (!safe_text(STRING_ELT(row_names, i), 1, 1)) return R_NilValue;
    } else return R_NilValue;
    size_t size = 2; char integer[16];
    /* Complete first pass: all actual values validated and exact bytes counted
     * before R_alloc or any output token/string allocation. */
    for (R_xlen_t i = 0; i < nr; ++i) {
        if (!(i % 128)) R_CheckUserInterrupt();
        if (!add_size(&size, 2 + (i != 0))) return R_NilValue;
        for (R_xlen_t j = 0; j < nc; ++j) {
            if (!add_size(&size, key_len[j] + 1 + (j != 0))) return R_NilValue;
            size_t token;
            if (types[j] == STRSXP) {
                SEXP x = STRING_ELT(columns[j], i);
                if (x == NA_STRING) token = 4;
                else {if (!safe_text(x, 0, 0)) return R_NilValue; token = (size_t)LENGTH(x) + 2;}
            } else {
                int x = types[j] == INTSXP ? INTEGER_ELT(columns[j], i) : LOGICAL_ELT(columns[j], i);
                if (x == NA_INTEGER) token = 4;
                else if (types[j] == LGLSXP) token = x ? 4 : 5;
                else {int n = snprintf(integer, sizeof(integer), "%d", x);
                    if (n < 1 || n >= (int)sizeof(integer)) return R_NilValue;
                    token = (size_t)n;}
            }
            if (!add_size(&size, token)) return R_NilValue;
        }
    }
    /* Buffer + R string + scalar/header framing; caller's substring/raw copies
     * remain inside the ORIGINAL eight-encoded-byte envelope, not a new quota. */
    if ((double)size > old_bound || 6.0 * ((double)size + 1) + 256 > 8 * old_bound)
        return R_NilValue;
    char *buffer = (char *)R_alloc(size + 1, 1), *p = buffer, *end = buffer + size;
#define PUT(TEXT, LENGTH) do { \
    size_t bytes = (size_t)(LENGTH); \
    if (bytes > (size_t)(end - p)) Rf_error("Manifest native JSON buffer exceeded."); \
    memcpy(p, (TEXT), bytes); p += bytes; \
} while (0)
    PUT("[", 1);
    for (R_xlen_t i = 0; i < nr; ++i) {
        if (!(i % 128)) R_CheckUserInterrupt();
        if (i) PUT(",", 1);
        PUT("{", 1);
        for (R_xlen_t j = 0; j < nc; ++j) {
            if (j) PUT(",", 1);
            PUT(key[j], key_len[j]); PUT(":", 1);
            const char *text; size_t length;
            if (types[j] == STRSXP) {
                SEXP x = STRING_ELT(columns[j], i);
                if (x == NA_STRING) {text = "null"; length = 4;}
                else {PUT("\"", 1); length = (size_t)LENGTH(x); PUT(CHAR(x), length);
                    PUT("\"", 1); continue;}
            } else {
                int x = types[j] == INTSXP ? INTEGER_ELT(columns[j], i) : LOGICAL_ELT(columns[j], i);
                if (x == NA_INTEGER) {text = "null"; length = 4;}
                else if (types[j] == LGLSXP) {text = x ? "true" : "false"; length = x ? 4 : 5;}
                else {int n = snprintf(integer, sizeof(integer), "%d", x);
                    if (n < 1 || n >= (int)sizeof(integer)) Rf_error("Manifest native JSON integer changed.");
                    length = (size_t)n; text = integer;}
            }
            PUT(text, length);
        }
        PUT("}", 1);
    }
    PUT("]", 1); *p = 0;
#undef PUT
    if ((size_t)(p - buffer) != size) Rf_error("Manifest native JSON byte count changed.");
    SEXP text = PROTECT(Rf_mkCharLenCE(buffer, (int)size, CE_NATIVE));
    SEXP answer = PROTECT(Rf_ScalarString(text));
    UNPROTECT(2); return answer;
}
