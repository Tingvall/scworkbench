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

extern SEXP scwb_graph_source_directory(SEXP, SEXP);
extern SEXP scwb_matrix_slice_append(SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_matrix_slice_csc_append(SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_matrix_slice_dense_append(SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_matrix_digest_open(SEXP);
extern SEXP scwb_matrix_digest_update(SEXP, SEXP);
extern SEXP scwb_matrix_digest_finish(SEXP);
extern SEXP scwb_matrix_digest_close(SEXP);
extern SEXP scwb_matrix_market_block(SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_matrix_market_sparse(SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_matrix_market_projection(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_canonical_numeric(SEXP);
extern SEXP scwb_canonical_numeric_tokens(SEXP);
extern SEXP scwb_table_row_hash_eligible(SEXP);
extern SEXP scwb_promotion_table_observable(SEXP);
extern SEXP scwb_manifest_scalar_json(SEXP, SEXP, SEXP);
extern SEXP scwb_canonical_numeric_array(SEXP, SEXP);
extern SEXP scwb_json_index_floor(SEXP, SEXP);
extern SEXP scwb_graph_file_identity(SEXP);
extern SEXP scwb_graph_readlink(SEXP, SEXP);
extern SEXP scwb_graph_spill_path_kind(SEXP);
extern SEXP scwb_graph_bytes_api_ready(void);
extern SEXP scwb_graph_bytes_api_version(void);
extern SEXP scwb_graph_bytes_open(SEXP, SEXP);
extern SEXP scwb_graph_bytes_column(SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_graph_bytes_read(SEXP, SEXP, SEXP);
extern SEXP scwb_graph_bytes_numeric(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP scwb_graph_bytes_finish(SEXP);
extern SEXP scwb_graph_bytes_close(SEXP);

extern SEXP scwb_graph_json_open(SEXP);
extern SEXP scwb_graph_json_file_open(SEXP,SEXP);
extern SEXP scwb_graph_json_next(SEXP);
extern SEXP scwb_graph_json_position(SEXP);
extern SEXP scwb_graph_json_close(SEXP);

static const R_CallMethodDef sdk_calls[] = {
    {"scwb_matrix_digest_open", (DL_FUNC) &scwb_matrix_digest_open, 1},
    {"scwb_matrix_digest_update", (DL_FUNC) &scwb_matrix_digest_update, 2},
    {"scwb_matrix_digest_finish", (DL_FUNC) &scwb_matrix_digest_finish, 1},
    {"scwb_matrix_digest_close", (DL_FUNC) &scwb_matrix_digest_close, 1},
    {"scwb_matrix_slice_append", (DL_FUNC) &scwb_matrix_slice_append, 5},
    {"scwb_matrix_slice_csc_append", (DL_FUNC) &scwb_matrix_slice_csc_append, 4},
    {"scwb_matrix_slice_dense_append", (DL_FUNC) &scwb_matrix_slice_dense_append, 4},
    {"scwb_matrix_market_block", (DL_FUNC) &scwb_matrix_market_block, 4},
    {"scwb_matrix_market_sparse", (DL_FUNC) &scwb_matrix_market_sparse, 4},
    {"scwb_matrix_market_projection", (DL_FUNC) &scwb_matrix_market_projection, 7},
    {"scwb_canonical_numeric", (DL_FUNC) &scwb_canonical_numeric, 1},
    {"scwb_canonical_numeric_tokens", (DL_FUNC) &scwb_canonical_numeric_tokens, 1},
    {"scwb_table_row_hash_eligible", (DL_FUNC) &scwb_table_row_hash_eligible, 1},
    {"scwb_promotion_table_observable", (DL_FUNC) &scwb_promotion_table_observable, 1},
    {"scwb_manifest_scalar_json", (DL_FUNC) &scwb_manifest_scalar_json, 3},
    {"scwb_canonical_numeric_array", (DL_FUNC) &scwb_canonical_numeric_array, 2},
    {"scwb_json_index_floor", (DL_FUNC) &scwb_json_index_floor, 2},
    {"scwb_graph_json_open", (DL_FUNC) &scwb_graph_json_open, 1},
    {"scwb_graph_json_file_open", (DL_FUNC) &scwb_graph_json_file_open, 2},
    {"scwb_graph_json_next", (DL_FUNC) &scwb_graph_json_next, 1},
    {"scwb_graph_json_position", (DL_FUNC) &scwb_graph_json_position, 1},
    {"scwb_graph_json_close", (DL_FUNC) &scwb_graph_json_close, 1},
    {"scwb_sdk_publish_noreplace", (DL_FUNC) &scwb_sdk_publish_noreplace, 2},
    {"scwb_graph_source_directory", (DL_FUNC) &scwb_graph_source_directory, 2},
    {"scwb_graph_file_identity", (DL_FUNC) &scwb_graph_file_identity, 1},
    {"scwb_graph_readlink", (DL_FUNC) &scwb_graph_readlink, 2},
    {"scwb_graph_spill_path_kind", (DL_FUNC) &scwb_graph_spill_path_kind, 1},
    {"scwb_graph_bytes_api_version", (DL_FUNC) &scwb_graph_bytes_api_version, 0},
    {"scwb_graph_bytes_api_ready", (DL_FUNC) &scwb_graph_bytes_api_ready, 0},
    {"scwb_graph_bytes_open", (DL_FUNC) &scwb_graph_bytes_open, 2},
    {"scwb_graph_bytes_column", (DL_FUNC) &scwb_graph_bytes_column, 4},
    {"scwb_graph_bytes_read", (DL_FUNC) &scwb_graph_bytes_read, 3},
    {"scwb_graph_bytes_numeric", (DL_FUNC) &scwb_graph_bytes_numeric, 6},
    {"scwb_graph_bytes_finish", (DL_FUNC) &scwb_graph_bytes_finish, 1},
    {"scwb_graph_bytes_close", (DL_FUNC) &scwb_graph_bytes_close, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_scworkbench(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, sdk_calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
