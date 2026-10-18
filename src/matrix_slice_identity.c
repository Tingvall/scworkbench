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

/* Private bounded batching of the SAME scalar number() tokens. No caller
 * framing, parsing or identity semantics live here. A NULL result requests
 * the existing recursive R path, including its original first diagnostic. */
static int numeric_token_value(SEXP value, R_xlen_t index, double *out) {
    if (TYPEOF(value) == INTSXP) {
        int x = INTEGER_ELT(value, index);
        *out = x == NA_INTEGER ? NA_REAL : (double)x;
    } else if (TYPEOF(value) == REALSXP) {
        *out = REAL_ELT(value, index);
    } else return 0;
    return ISNAN(*out) || (R_FINITE(*out) &&
        (*out == 0 || fabs(*out) >= 1e-307));
}

static int numeric_token_item(SEXP value, R_xlen_t index, double *out) {
    if (TYPEOF(value) == VECSXP) {
        SEXP item = VECTOR_ELT(value, index);
        if ((TYPEOF(item) != INTSXP && TYPEOF(item) != REALSXP) ||
            OBJECT(item) || ATTRIB(item) != R_NilValue || XLENGTH(item) != 1)
            return 0;
        return numeric_token_value(item, 0, out);
    }
    return numeric_token_value(value, index, out);
}

SEXP scwb_canonical_numeric_tokens(SEXP value) {
    if (OBJECT(value) || ATTRIB(value) != R_NilValue ||
        (TYPEOF(value) != INTSXP && TYPEOF(value) != REALSXP &&
         TYPEOF(value) != VECSXP)) return R_NilValue;
    R_xlen_t n = XLENGTH(value);
    /* This ceiling also bounds all length/index and 256-byte ledger arithmetic
     * well below INT_MAX. ELT access never forces whole-vector DATAPTR. */
    if (n > (R_xlen_t)131072 || n > (R_xlen_t)INT_MAX / 256)
        return R_NilValue;
    double x;
    for (R_xlen_t i = 0; i < n; ++i)
        if (!numeric_token_item(value, i, &x)) return R_NilValue;
    SEXP result = PROTECT(Rf_allocVector(STRSXP, n));
    for (R_xlen_t i = 0; i < n; ++i) {
        /* Recheck on access as well: an unusual mutable ALTREP carrier cannot
         * make number() emit a partial invalid block to its caller. */
        if (!numeric_token_item(value, i, &x)) {
            UNPROTECT(1); return R_NilValue;
        }
        if (ISNAN(x)) SET_STRING_ELT(result, i, Rf_mkChar("null"));
        else {
            char token[64]; number(x, token);
            SET_STRING_ELT(result, i, Rf_mkChar(token));
        }
    }
    UNPROTECT(1);
    return result;
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

typedef struct {
    FILE *file;
    SEXP values, indices;
    int rows, columns, row_offset, column_offset;
} market_context;

static void market_cleanup(void *data, Rboolean jump) {
    market_context *context = data;
    if (context->file) { fclose(context->file); context->file = NULL; }
}

static SEXP market_body(void *data) {
    market_context *context = data;
    char buffer[4096]; size_t used = 0;
    for (int column = 0; column < context->columns; ++column) {
        for (int row = 0; row < context->rows; ++row) {
            double value = REAL(context->values)[row + (R_xlen_t)column * context->rows];
            if (!R_FINITE(value)) Rf_error("Matrix Market values must be finite.");
            if (value == 0) continue;
            char token[64], record[128]; number(value, token);
            int size = snprintf(record, sizeof(record), "%d %d %s\n",
                context->indices == R_NilValue ? row + context->row_offset + 1 :
                    INTEGER(context->indices)[row] + 1,
                column + context->column_offset + 1, token);
            if (size < 0 || size >= (int)sizeof(record)) Rf_error("Matrix Market record overflow.");
            if (used + size > sizeof(buffer)) {
                if (fwrite(buffer, 1, used, context->file) != used) Rf_error("Matrix Market write failed.");
                used = 0;
            }
            memcpy(buffer + used, record, size); used += size;
            if (row % 8192 == 0) R_CheckUserInterrupt();
        }
    }
    if (used && fwrite(buffer, 1, used, context->file) != used) Rf_error("Matrix Market write failed.");
    if (fflush(context->file)) Rf_error("Matrix Market flush failed.");
    return R_NilValue;
}

SEXP scwb_matrix_market_block(SEXP path, SEXP values, SEXP row_offset, SEXP column_offset) {
    SEXP dimensions = Rf_getAttrib(values, R_DimSymbol);
    int row = Rf_asInteger(row_offset), column = Rf_asInteger(column_offset);
    if (TYPEOF(values) != REALSXP || TYPEOF(dimensions) != INTSXP || XLENGTH(dimensions) != 2 ||
        row == NA_INTEGER || column == NA_INTEGER || row < 0 || column < 0 ||
        row > INT_MAX - INTEGER(dimensions)[0] || column > INT_MAX - INTEGER(dimensions)[1])
        Rf_error("Invalid Matrix Market block.");
    if (path == R_NilValue) {
        SEXP result = PROTECT(Rf_allocVector(REALSXP, 3));
        double count = 0; int finite = 1, range_edge = 0;
        for (R_xlen_t i = 0; i < XLENGTH(values); ++i) {
            double x = REAL(values)[i];
            if (!R_FINITE(x)) finite = 0;
            if (x != 0) ++count;
            if (x != 0 && fabs(x) < 1e-307) range_edge = 1;
            if (i % 8192 == 0) R_CheckUserInterrupt();
        }
        REAL(result)[0] = count; REAL(result)[1] = finite; REAL(result)[2] = range_edge;
        UNPROTECT(1); return result;
    }
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("Invalid Matrix Market path.");
    market_context context = {NULL, values, R_NilValue, INTEGER(dimensions)[0], INTEGER(dimensions)[1], row, column};
    context.file = fopen(Rf_translateCharUTF8(STRING_ELT(path, 0)), "ab");
    if (!context.file) Rf_error("Cannot open private Matrix Market stream.");
    return R_UnwindProtect(market_body, &context, market_cleanup, &context, NULL);
}

SEXP scwb_matrix_market_sparse(SEXP path, SEXP indices, SEXP values, SEXP column) {
    int current_column = Rf_asInteger(column);
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING ||
        TYPEOF(indices) != INTSXP || TYPEOF(values) != REALSXP ||
        XLENGTH(indices) != XLENGTH(values) || XLENGTH(values) > 8192 ||
        current_column == NA_INTEGER || current_column < 1)
        Rf_error("Invalid Matrix Market sparse batch.");
    for (R_xlen_t i = 0; i < XLENGTH(indices); ++i)
        if (INTEGER(indices)[i] == NA_INTEGER || INTEGER(indices)[i] < 0 || INTEGER(indices)[i] == INT_MAX)
            Rf_error("Invalid Matrix Market sparse row.");
    market_context context = {NULL, values, indices, (int)XLENGTH(values), 1, 0, current_column - 1};
    context.file = fopen(Rf_translateCharUTF8(STRING_ELT(path, 0)), "ab");
    if (!context.file) Rf_error("Cannot open private Matrix Market stream.");
    return R_UnwindProtect(market_body, &context, market_cleanup, &context, NULL);
}

static int projection_row(SEXP sorted, SEXP order, int value) {
    R_xlen_t left = 0, right = XLENGTH(sorted);
    while (left < right) {
        R_xlen_t middle = left + (right - left) / 2;
        if (INTEGER(sorted)[middle] < value) left = middle + 1; else right = middle;
    }
    return left < XLENGTH(sorted) && INTEGER(sorted)[left] == value ? INTEGER(order)[left] : -1;
}

static void projection_swap(SEXP rows, SEXP values, R_xlen_t left, R_xlen_t right) {
    int row = INTEGER(rows)[left]; INTEGER(rows)[left] = INTEGER(rows)[right]; INTEGER(rows)[right] = row;
    if (values == R_NilValue) return;
    if (TYPEOF(values) == REALSXP) {
        double value = REAL(values)[left]; REAL(values)[left] = REAL(values)[right]; REAL(values)[right] = value;
    } else {
        int value = LOGICAL(values)[left]; LOGICAL(values)[left] = LOGICAL(values)[right]; LOGICAL(values)[right] = value;
    }
}

static void projection_sift(SEXP rows, SEXP values, R_xlen_t start, R_xlen_t root, R_xlen_t size) {
    while (root < size / 2) {
        R_xlen_t child = root * 2 + 1;
        if (child + 1 < size && INTEGER(rows)[start + child] < INTEGER(rows)[start + child + 1]) ++child;
        if (INTEGER(rows)[start + root] >= INTEGER(rows)[start + child]) return;
        projection_swap(rows, values, start + root, start + child); root = child;
    }
}

/* The final selected CSC slots are ordinary selected-object storage. Aside
 * from them, only selected-axis metadata is retained. No source-height map,
 * whole dense projection, Matrix subset dispatch or per-column sort carrier. */
SEXP scwb_matrix_market_projection(SEXP p, SEXP i, SEXP x, SEXP dimensions,
                                   SEXP sorted, SEXP order, SEXP columns) {
    if (TYPEOF(p) != INTSXP || TYPEOF(i) != INTSXP || TYPEOF(dimensions) != INTSXP ||
        XLENGTH(dimensions) != 2 || INTEGER(dimensions)[0] < 0 || INTEGER(dimensions)[1] < 0 ||
        TYPEOF(sorted) != INTSXP || TYPEOF(order) != INTSXP || TYPEOF(columns) != INTSXP ||
        XLENGTH(sorted) != XLENGTH(order) || XLENGTH(sorted) > INT_MAX || XLENGTH(columns) > INT_MAX ||
        (x != R_NilValue && TYPEOF(x) != REALSXP && TYPEOF(x) != LGLSXP) ||
        (x != R_NilValue && XLENGTH(x) != XLENGTH(i)) ||
        XLENGTH(p) != (R_xlen_t)INTEGER(dimensions)[1] + 1 ||
        INTEGER_ELT(p,0) != 0 || INTEGER_ELT(p,XLENGTH(p)-1) < 0 ||
        INTEGER_ELT(p,XLENGTH(p)-1) > XLENGTH(i))
        Rf_error("Invalid general CSC projection slots.");
    unsigned char *seen = (unsigned char *)R_alloc(XLENGTH(sorted), sizeof(unsigned char));
    if (XLENGTH(sorted)) memset(seen, 0, XLENGTH(sorted));
    int previous = -1;
    for (R_xlen_t j = 0; j < XLENGTH(sorted); ++j) {
        if (INTEGER(sorted)[j] <= previous || INTEGER(sorted)[j] >= INTEGER(dimensions)[0] ||
            INTEGER(order)[j] < 0 || INTEGER(order)[j] >= XLENGTH(sorted) || seen[INTEGER(order)[j]])
            Rf_error("Invalid general CSC projection row selection.");
        previous = INTEGER(sorted)[j];
        seen[INTEGER(order)[j]] = 1;
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(names,0,Rf_mkChar("p")); SET_STRING_ELT(names,1,Rf_mkChar("i")); SET_STRING_ELT(names,2,Rf_mkChar("x"));
    Rf_setAttrib(result,R_NamesSymbol,names);
    SEXP output_p = PROTECT(Rf_allocVector(INTSXP, XLENGTH(columns)+1));
    SET_VECTOR_ELT(result,0,output_p); INTEGER(output_p)[0] = 0;
    R_xlen_t count = 0;
    for (R_xlen_t column = 0; column < XLENGTH(columns); ++column) {
        int selected = INTEGER(columns)[column];
        if (selected < 0 || selected >= INTEGER(dimensions)[1]) Rf_error("Invalid general CSC projection column.");
        int start = INTEGER_ELT(p,selected), end = INTEGER_ELT(p,selected+1);
        if (start < 0 || end < start || end > XLENGTH(i)) Rf_error("Invalid general CSC projection pointers.");
        previous = -1;
        for (R_xlen_t at = start; at < end; ++at) {
            int row = INTEGER_ELT(i,at);
            if (row <= previous || row >= INTEGER(dimensions)[0]) Rf_error("Invalid general CSC projection source row.");
            previous = row;
            if (projection_row(sorted,order,row) >= 0 && ++count > INT_MAX)
                Rf_error("General CSC projection exceeds its existing integer slot limit.");
            if (at % 8192 == 0) R_CheckUserInterrupt();
        }
        INTEGER(output_p)[column+1] = (int)count;
    }
    SEXP output_i = PROTECT(Rf_allocVector(INTSXP,count)); SET_VECTOR_ELT(result,1,output_i);
    SEXP output_x = R_NilValue;
    if (x != R_NilValue) { output_x = PROTECT(Rf_allocVector(TYPEOF(x),count)); SET_VECTOR_ELT(result,2,output_x); }
    R_xlen_t target = 0;
    for (R_xlen_t column = 0; column < XLENGTH(columns); ++column) {
        int selected = INTEGER(columns)[column];
        for (R_xlen_t at = INTEGER_ELT(p,selected); at < INTEGER_ELT(p,selected+1); ++at) {
            if (at % 8192 == 0) R_CheckUserInterrupt();
            int row = projection_row(sorted,order,INTEGER_ELT(i,at));
            if (row < 0) continue;
            INTEGER(output_i)[target] = row;
            if (x != R_NilValue) {
                if (TYPEOF(x) == REALSXP) REAL(output_x)[target] = REAL_ELT(x,at);
                else LOGICAL(output_x)[target] = LOGICAL_ELT(x,at);
            }
            ++target;
        }
        R_xlen_t start = INTEGER(output_p)[column], size = INTEGER(output_p)[column+1] - start;
        for (R_xlen_t root = size / 2; root > 0;) projection_sift(output_i,output_x,start,--root,size);
        for (R_xlen_t end = size; end > 1;) {
            --end; projection_swap(output_i,output_x,start,start+end);
            projection_sift(output_i,output_x,start,0,end);
        }
    }
    UNPROTECT(x == R_NilValue ? 4 : 5); return result;
}
