#include <R.h>
#include <Rinternals.h>
#include <string.h>

/* Non-dispatch metadata admission: no scientific value scan or ALTREP force.
 * Borrowed ordinary values obey R COW, not a new persistent seal. */
static int plain(SEXP x) {
    return !OBJECT(x) && !IS_S4_OBJECT(x) && !ALTREP(x) && ATTRIB(x) == R_NilValue;
}
static int text(SEXP x, size_t *bytes) {
    if (x == NA_STRING || LENGTH(x) > 256) return 0;
    *bytes += (size_t)LENGTH(x) + 64;
    return *bytes <= 65536;
}
static int names_ok(SEXP x, R_xlen_t n, size_t *bytes) {
    if (!plain(x) || TYPEOF(x) != STRSXP || XLENGTH(x) != n) return 0;
    for (R_xlen_t i = 0; i < n; ++i)
        if (!text(STRING_ELT(x, i), bytes)) return 0;
    return 1;
}
static int metadata(SEXP x, int depth, int *nodes, size_t *bytes) {
    if (depth > 8 || ++*nodes > 256 || OBJECT(x) || IS_S4_OBJECT(x) || ALTREP(x)) return 0;
    if (x == R_NilValue) return 1;
    SEXPTYPE type = TYPEOF(x);
    if (type != VECSXP && type != STRSXP && type != INTSXP && type != REALSXP && type != LGLSXP) return 0;
    R_xlen_t n = XLENGTH(x);
    if (n > 256) return 0;
    int attrs = 0;
    for (SEXP a = ATTRIB(x); a != R_NilValue; a = CDR(a)) {
        if (++attrs > 1 || TAG(a) != R_NamesSymbol || !names_ok(CAR(a), n, bytes)) return 0;
    }
    *bytes += 64 + (size_t)n * 8;
    if (*bytes > 65536) return 0;
    if (type == VECSXP) {
        for (R_xlen_t i = 0; i < n; ++i)
            if (!metadata(VECTOR_ELT(x, i), depth + 1, nodes, bytes)) return 0;
    } else if (type == STRSXP) {
        for (R_xlen_t i = 0; i < n; ++i) {
            SEXP s = STRING_ELT(x, i);
            if (s != NA_STRING && !text(s, bytes)) return 0;
        }
    }
    return 1;
}
static int scalar(SEXP x, size_t *bytes) {
    return plain(x) && TYPEOF(x) == STRSXP && XLENGTH(x) == 1 && text(STRING_ELT(x, 0), bytes);
}
static int admitted(SEXP prim) {
    if (TYPEOF(prim) != VECSXP || ALTREP(prim) || IS_S4_OBJECT(prim)) return 0;
    SEXP names = R_NilValue, cls = R_NilValue;
    int attrs = 0; size_t bytes = 0;
    for (SEXP a = ATTRIB(prim); a != R_NilValue; a = CDR(a)) {
        if (++attrs > 2) return 0;
        if (TAG(a) == R_NamesSymbol && names == R_NilValue) names = CAR(a);
        else if (TAG(a) == R_ClassSymbol && cls == R_NilValue) cls = CAR(a);
        else return 0;
    }
    if (attrs != 2 || !scalar(cls, &bytes) || strcmp(CHAR(STRING_ELT(cls, 0)), "wb_primitive")) return 0;
    R_xlen_t n = XLENGTH(prim);
    if (n < 4 || n > 6 || !names_ok(names, n, &bytes) ||
        !scalar(VECTOR_ELT(prim, 0), &bytes)) return 0;
    const char *kind = CHAR(STRING_ELT(VECTOR_ELT(prim, 0), 0));
    int feature = !strcmp(kind, "feature_table");
    if (!feature && strcmp(kind, "obs_table")) return 0;
    R_xlen_t base = feature ? 4 : 5;
    int typed = n == base + 1;
    if (n != base && !typed) return 0;
    const char *ft[] = {"kind", "table_type", "table", "meta", "table_storage"};
    const char *ot[] = {"kind", "table_type", "entity_kind", "table", "meta", "table_storage"};
    const char **fields = feature ? ft : ot;
    for (R_xlen_t i = 0; i < n; ++i)
        if (strcmp(CHAR(STRING_ELT(names, i)), fields[i])) return 0;
    if (!scalar(VECTOR_ELT(prim, 1), &bytes) ||
        (!feature && !scalar(VECTOR_ELT(prim, 2), &bytes))) return 0;
    SEXP table = VECTOR_ELT(prim, base - 2);
    if (TYPEOF(table) != VECSXP || ALTREP(table) || IS_S4_OBJECT(table)) return 0;
    SEXP tn = R_NilValue, tc = R_NilValue, rn = R_NilValue;
    attrs = 0;
    for (SEXP a = ATTRIB(table); a != R_NilValue; a = CDR(a)) {
        if (++attrs > 3) return 0;
        if (TAG(a) == R_NamesSymbol && tn == R_NilValue) tn = CAR(a);
        else if (TAG(a) == R_ClassSymbol && tc == R_NilValue) tc = CAR(a);
        else if (TAG(a) == R_RowNamesSymbol && rn == R_NilValue) rn = CAR(a);
        else return 0;
    }
    R_xlen_t nc = XLENGTH(table);
    if (attrs != 3 || nc < 1 || nc > 128 || !names_ok(tn, nc, &bytes) ||
        !scalar(tc, &bytes) || strcmp(CHAR(STRING_ELT(tc, 0)), "data.frame") ||
        !plain(rn) || (TYPEOF(rn) != INTSXP && TYPEOF(rn) != STRSXP)) return 0;
    R_xlen_t nr = 0;
    for (R_xlen_t j = 0; j < nc; ++j) {
        SEXP col = VECTOR_ELT(table, j); SEXPTYPE type = TYPEOF(col);
        if (!plain(col) || (type != INTSXP && type != REALSXP && type != LGLSXP && type != STRSXP)) return 0;
        if (!j) nr = XLENGTH(col);
        else if (XLENGTH(col) != nr) return 0;
    }
    /* Raw compact row names: never getAttrib's row-name expansion. */
    int compact = TYPEOF(rn) == INTSXP && XLENGTH(rn) == 2 &&
        INTEGER_ELT(rn, 0) == NA_INTEGER && nr <= 2147483647 &&
        (INTEGER_ELT(rn, 1) == (int)nr || INTEGER_ELT(rn, 1) == -(int)nr);
    if (!compact && XLENGTH(rn) != nr) return 0;
    int nodes = 0;
    return metadata(VECTOR_ELT(prim, base - 1), 0, &nodes, &bytes) &&
        (!typed || metadata(VECTOR_ELT(prim, base), 0, &nodes, &bytes));
}
SEXP scwb_promotion_table_observable(SEXP prim) {
    return Rf_ScalarLogical(admitted(prim));
}
