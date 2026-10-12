#include <R.h>
#include <Rinternals.h>
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>

/* Initialize through RSQLite's loadable-extension API. Opening the same
 * database through a separately linked SQLite copy can clear RSQLite's POSIX
 * locks when that copy closes a descriptor. All calls below use this one
 * engine's API table; no second SQLite implementation is linked. */
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_scwbgraphbytes_init(sqlite3 *db, char **message,
                              const sqlite3_api_routines *api)
{
    (void)db;
    if (sqlite3_api && sqlite3_api != api) {
        if (message) *message = api->mprintf("Native observer SQLite engine changed.");
        return SQLITE_ERROR;
    }
    SQLITE_EXTENSION_INIT2(api);
    return SQLITE_OK;
}

SEXP scwb_graph_bytes_api_ready(void)
{
    return Rf_ScalarLogical(sqlite3_api != NULL);
}

SEXP scwb_graph_bytes_api_version(void)
{
    if (!sqlite3_api)
        Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: RSQLite byte API is not initialized.");
    return Rf_mkString(sqlite3_libversion());
}

/* Private getter observation. No writable handle or SQL supplied by a pack.
 * blob_open(...,0) reads the existing TEXT payload without an SQL TEXT/BLOB
 * conversion, which would allocate the entire value inside SQLite. */
#include "graph_sqlite_bytes.h"

static void bytes_close(SEXP pointer)
{
    graph_bytes *state = R_ExternalPtrAddr(pointer);
    if (!state) return;
    if (state->blob) sqlite3_blob_close(state->blob);
    if (state->db) sqlite3_close_v2(state->db);
    free(state);
    R_ClearExternalPtr(pointer);
}

static graph_bytes *bytes_state(SEXP pointer)
{
    if (TYPEOF(pointer) != EXTPTRSXP ||
        R_ExternalPtrTag(pointer) != Rf_install("scwb_graph_bytes") || !R_ExternalPtrAddr(pointer))
        Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: native byte reader is closed.");
    graph_bytes *state = R_ExternalPtrAddr(pointer);
    if (!state->db) Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: native byte reader is closed.");
    return state;
}

static void bytes_fail(graph_bytes *state, const char *message)
{
    char detail[256];
    snprintf(detail, sizeof(detail), "%s", state->db ? sqlite3_errmsg(state->db) : "no read-only database");
    if (state->blob) { sqlite3_blob_close(state->blob); state->blob = NULL; }
    if (state->db) { sqlite3_close_v2(state->db); state->db = NULL; }
    Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: %s: %s", message, detail);
}

static int data_version(graph_bytes *state)
{
    sqlite3_stmt *statement = NULL;
    int rc = sqlite3_prepare_v2(state->db, "PRAGMA data_version;", -1, &statement, NULL);
    if (rc != SQLITE_OK) bytes_fail(state, "native data-version observation");
    rc = sqlite3_step(statement);
    int value = rc == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1;
    sqlite3_finalize(statement);
    if (rc != SQLITE_ROW) bytes_fail(state, "native data-version observation");
    return value;
}

SEXP scwb_graph_bytes_open(SEXP path)
{
    if (!sqlite3_api)
        Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: RSQLite byte API is not initialized.");
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: missing native database path.");
    SEXP pointer = PROTECT(R_MakeExternalPtr(NULL, Rf_install("scwb_graph_bytes"), R_NilValue));
    graph_bytes *state = calloc(1, sizeof(graph_bytes));
    if (!state) Rf_error("GRAPH_RESOURCE_EXCEEDED: native reader allocation failed.");
    R_SetExternalPtrAddr(pointer, state);
    R_RegisterCFinalizerEx(pointer, bytes_close, TRUE);
    int flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX;
#ifdef SQLITE_OPEN_NOFOLLOW
    flags |= SQLITE_OPEN_NOFOLLOW;
#endif
    int rc = sqlite3_open_v2(Rf_translateCharUTF8(STRING_ELT(path, 0)), &state->db, flags, NULL);
    if (rc != SQLITE_OK) bytes_fail(state, "native read-only database open");
    if (sqlite3_db_readonly(state->db, "main") != 1)
        bytes_fail(state, "native database is not read-only");
    rc = sqlite3_exec(state->db,
        "PRAGMA query_only=ON; PRAGMA cache_size=-64; PRAGMA temp_store=FILE;", NULL, NULL, NULL);
    if (rc != SQLITE_OK) bytes_fail(state, "native reader cache admission");
    sqlite3_stmt *statement = NULL;
    rc = sqlite3_prepare_v2(state->db, "PRAGMA encoding;", -1, &statement, NULL);
    if (rc != SQLITE_OK) bytes_fail(state, "native text encoding observation");
    rc = sqlite3_step(statement);
    int utf8 = rc == SQLITE_ROW && !strcmp((const char *)sqlite3_column_text(statement, 0), "UTF-8");
    sqlite3_finalize(statement);
    if (!utf8) bytes_fail(state, "native database encoding is not UTF-8");
    state->version = data_version(state);
    rc = sqlite3_exec(state->db, "BEGIN;", NULL, NULL, NULL);
    if (rc != SQLITE_OK) bytes_fail(state, "native read snapshot");
    UNPROTECT(1);
    return pointer;
}

SEXP scwb_graph_bytes_column(SEXP pointer, SEXP rowid, SEXP column, SEXP table)
{
    graph_bytes *state = bytes_state(pointer);
    if (TYPEOF(rowid) != STRSXP || XLENGTH(rowid) != 1 || STRING_ELT(rowid, 0) == NA_STRING ||
        TYPEOF(column) != STRSXP || XLENGTH(column) != 1 || STRING_ELT(column, 0) == NA_STRING ||
        TYPEOF(table) != STRSXP || XLENGTH(table) != 1 || STRING_ELT(table, 0) == NA_STRING)
        bytes_fail(state, "invalid native column selector");
    const char *name = Rf_translateCharUTF8(STRING_ELT(column, 0));
    const char *table_name = Rf_translateCharUTF8(STRING_ELT(table, 0));
    const char *id_text = CHAR(STRING_ELT(rowid, 0));
    char *end = NULL;
    errno = 0;
    long long id = strtoll(id_text, &end, 10);
    if (errno || !*id_text || *end) bytes_fail(state, "invalid native rowid");
    if (state->blob) { sqlite3_blob_close(state->blob); state->blob = NULL; }
    char *sql = sqlite3_mprintf("SELECT typeof(\"%w\") FROM \"%w\" WHERE rowid=?;", name, table_name);
    if (!sql) bytes_fail(state, "native selector allocation");
    sqlite3_stmt *statement = NULL;
    int rc = sqlite3_prepare_v2(state->db, sql, -1, &statement, NULL);
    sqlite3_free(sql);
    if (rc != SQLITE_OK) bytes_fail(state, "native storage type observation");
    sqlite3_bind_int64(statement, 1, (sqlite3_int64)id);
    rc = sqlite3_step(statement);
    int is_null = rc == SQLITE_ROW && !strcmp((const char *)sqlite3_column_text(statement, 0), "null");
    int is_text = rc == SQLITE_ROW && !strcmp((const char *)sqlite3_column_text(statement, 0), "text");
    int is_blob = rc == SQLITE_ROW && !strcmp((const char *)sqlite3_column_text(statement, 0), "blob");
    sqlite3_finalize(statement);
    if (!is_null && !is_text && !is_blob) bytes_fail(state, "native column is missing or not TEXT/BLOB");
    if (is_null) { state->bytes = 0; return R_NilValue; }
    rc = sqlite3_blob_open(state->db, "main", table_name, name, (sqlite3_int64)id, 0, &state->blob);
    if (rc != SQLITE_OK) bytes_fail(state, "native incremental TEXT open");
    state->bytes = sqlite3_blob_bytes(state->blob);
    SEXP size = PROTECT(Rf_ScalarInteger(state->bytes));
    Rf_setAttrib(size, Rf_install("wb_sqlite_type"), Rf_mkString(is_text ? "text" : "blob"));
    UNPROTECT(1);
    return size;
}

SEXP scwb_graph_bytes_read(SEXP pointer, SEXP offset, SEXP count)
{
    graph_bytes *state = bytes_state(pointer);
    double start = Rf_asReal(offset), length = Rf_asReal(count);
    if (!state->blob || !R_FINITE(start) || !R_FINITE(length) || start < 0 || length < 0 ||
        start > INT_MAX || start != (int)start || length > 65536 || length != (int)length ||
        start > state->bytes || length > state->bytes - start)
        Rf_error("GRAPH_RESOURCE_POLICY_INVALID: invalid bounded native byte slice.");
    SEXP result = PROTECT(Rf_allocVector(RAWSXP, (int)length));
    int rc = sqlite3_blob_read(state->blob, RAW(result), (int)length, (int)start);
    if (rc != SQLITE_OK) bytes_fail(state, "native incremental TEXT read");
    UNPROTECT(1);
    return result;
}

/* RSQLite uses SQLite scalar coercion when a query's numeric column later
 * encounters TEXT. Preserve that behavior for admitted scalar metadata. The
 * caller must measure this field before permitting SQLite scalar decoding. */
SEXP scwb_graph_bytes_numeric(SEXP pointer, SEXP rowid, SEXP column, SEXP table, SEXP type, SEXP maximum)
{
    graph_bytes *state = bytes_state(pointer);
    if (TYPEOF(rowid) != STRSXP || XLENGTH(rowid) != 1 || STRING_ELT(rowid, 0) == NA_STRING ||
        TYPEOF(column) != STRSXP || XLENGTH(column) != 1 || STRING_ELT(column, 0) == NA_STRING ||
        TYPEOF(table) != STRSXP || XLENGTH(table) != 1 || STRING_ELT(table, 0) == NA_STRING ||
        TYPEOF(type) != STRSXP || XLENGTH(type) != 1 || STRING_ELT(type, 0) == NA_STRING)
        bytes_fail(state, "invalid native scalar selector");
    char *end = NULL;
    errno = 0;
    long long id = strtoll(CHAR(STRING_ELT(rowid, 0)), &end, 10);
    if (errno || !*CHAR(STRING_ELT(rowid, 0)) || *end)
        bytes_fail(state, "invalid native scalar rowid");
    double limit = Rf_asReal(maximum);
    if (!R_FINITE(limit) || limit < 0 || state->bytes > limit)
        Rf_error("GRAPH_RESOURCE_EXCEEDED: numeric-coerced TEXT exceeds scalar decoder admission.");
    char *sql = sqlite3_mprintf("SELECT \"%w\" FROM \"%w\" WHERE rowid=?;",
        Rf_translateCharUTF8(STRING_ELT(column, 0)), Rf_translateCharUTF8(STRING_ELT(table, 0)));
    if (!sql) bytes_fail(state, "native scalar selector allocation");
    sqlite3_stmt *statement = NULL;
    int rc = sqlite3_prepare_v2(state->db, sql, -1, &statement, NULL);
    sqlite3_free(sql);
    if (rc != SQLITE_OK) bytes_fail(state, "native scalar prepare");
    sqlite3_bind_int64(statement, 1, (sqlite3_int64)id);
    rc = sqlite3_step(statement);
    if (rc != SQLITE_ROW) {sqlite3_finalize(statement); bytes_fail(state, "native scalar observation");}
    const char *kind = CHAR(STRING_ELT(type, 0));
    SEXP value = R_NilValue;
    if (!strcmp(kind, "integer64")) {
        char number[32];
        snprintf(number, sizeof(number), "%lld", (long long)sqlite3_column_int64(statement, 0));
        sqlite3_finalize(statement);
        return Rf_mkString(number);
    } else if (!strcmp(kind, "integer")) {
        int number = sqlite3_column_int(statement, 0);
        sqlite3_finalize(statement);
        return Rf_ScalarInteger(number);
    } else if (!strcmp(kind, "numeric")) {
        double number = sqlite3_column_double(statement, 0);
        sqlite3_finalize(statement);
        return Rf_ScalarReal(number);
    }
    sqlite3_finalize(statement);
    (void)value;
    bytes_fail(state, "unsupported numeric scalar coercion");
    return R_NilValue;
}

SEXP scwb_graph_bytes_finish(SEXP pointer)
{
    graph_bytes *state = bytes_state(pointer);
    if (state->blob) { sqlite3_blob_close(state->blob); state->blob = NULL; }
    int rc = sqlite3_exec(state->db, "COMMIT;", NULL, NULL, NULL);
    if (rc != SQLITE_OK) bytes_fail(state, "native read snapshot finish");
    int unchanged = data_version(state) == state->version;
    bytes_close(pointer);
    if (!unchanged) Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: source changed during native byte observation.");
    return R_NilValue;
}

SEXP scwb_graph_bytes_close(SEXP pointer)
{
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != Rf_install("scwb_graph_bytes"))
        Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: invalid byte reader.");
    bytes_close(pointer);
    return R_NilValue;
}
