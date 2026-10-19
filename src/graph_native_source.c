#include <R.h>
#include <Rinternals.h>
#include <dirent.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <stdio.h>
#if defined(__linux__)
#include <unistd.h>
#endif

/* Exactly the two byte-oriented (^|/) ownership-prefix predicates used after
 * an actual descriptor readlink. This classifies a name only: the R caller
 * still observes every descriptor, admits metadata and stats/deduplicates
 * actual inodes. Unsupported carriers retain the original R predicates. */
static int graph_spill_path_kind_bytes(const char *start, size_t length)
{
    int stage = 0;
    for (size_t i = 0; i < length; ++i) {
        if (i && start[i - 1] != '/') continue;
        const char *p = start + i;
        size_t left = length - i;
#define SPILL_PREFIX(text) (left >= sizeof(text) - 1 && !memcmp(p, text, sizeof(text) - 1))
        if (SPILL_PREFIX("etilqs_") || SPILL_PREFIX("scwb_graph_tokens_") ||
            SPILL_PREFIX("scwb_graph_identity_") || SPILL_PREFIX("scwb_object_meta_"))
            return 1;
        if (SPILL_PREFIX("scwb_graph_stage_")) stage = 1;
#undef SPILL_PREFIX
    }
    return stage ? 2 : 0;
}

SEXP scwb_graph_spill_path_kind(SEXP value)
{
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1 || OBJECT(value) ||
        ATTRIB(value) != R_NilValue || ALTREP(value) ||
        STRING_ELT(value, 0) == NA_STRING)
        return R_NilValue;
    SEXP text = STRING_ELT(value, 0);
    return Rf_ScalarInteger(graph_spill_path_kind_bytes(CHAR(text), (size_t)LENGTH(text)));
}

SEXP scwb_graph_readlink(SEXP path, SEXP allowance)
{
#if defined(__linux__)
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: invalid spill descriptor path.");
    double limit = Rf_asReal(allowance);
    if (!R_FINITE(limit) || limit < 0)
        Rf_error("GRAPH_RESOURCE_EXCEEDED: exhausted spill metadata admission.");
    char target[8192];
    ssize_t bytes = readlink(Rf_translateCharUTF8(STRING_ELT(path, 0)), target, sizeof(target));
    if (bytes < 0) {
        if (errno == ENOENT) return R_NilValue;
        Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: spill readlink: %s", strerror(errno));
    }
    double charge = 1024.0 + 8.0 * (bytes + 1.0);
    if (bytes >= (ssize_t)sizeof(target) || charge > limit)
        Rf_error("GRAPH_RESOURCE_EXCEEDED: spill path metadata exceeds bounded admission.");
    /* The third scalar fits the existing conservative 1024-byte base charge;
     * preserve target/charge and classify the actual bounded readlink bytes,
     * which need not be NUL terminated. No additional descriptor observation. */
    SEXP output = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(output, 0, Rf_ScalarString(Rf_mkCharLenCE(target, (int)bytes, CE_BYTES)));
    SET_VECTOR_ELT(output, 1, Rf_ScalarReal(charge));
    SET_VECTOR_ELT(output, 2, Rf_ScalarInteger(graph_spill_path_kind_bytes(target, (size_t)bytes)));
    UNPROTECT(1);
    return output;
#else
    (void)path; (void)allowance;
    Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: Linux spill descriptor accounting required.");
    return R_NilValue;
#endif
}

SEXP scwb_graph_file_identity(SEXP path)
{
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: invalid scratch identity path.");
    struct stat info;
    if (stat(Rf_translateCharUTF8(STRING_ELT(path, 0)), &info)) {
        if (errno == ENOENT) return Rf_ScalarString(NA_STRING);
        Rf_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE: scratch stat: %s", strerror(errno));
    }
    char identity[96];
    snprintf(identity, sizeof(identity), "%llu:%llu",
        (unsigned long long)info.st_dev, (unsigned long long)info.st_ino);
    return Rf_mkString(identity);
}

/* One directory only. Admission precedes every allocation, including a huge
 * flat directory; R assembles the admitted preorder and uses native R sort.
 * No R allocation/error/interrupt while DIR is open. The deliberately generous
 * charge also reserves retained R strings, traversal frames and sort copies. */
static int compare_names(const void *a, const void *b)
{
    return strcmp(*(const char * const *)a, *(const char * const *)b);
}

typedef struct { char **names; size_t count; double charge; } source_names;

static void free_source_names(void *data, Rboolean jump)
{
    (void)jump;
    source_names *state = data;
    for (size_t i = 0; i < state->count; i++) free(state->names[i]);
    free(state->names);
}

static SEXP source_names_result(void *data)
{
    source_names *state = data;
    SEXP result = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)state->count));
    for (size_t i = 0; i < state->count; i++)
        SET_STRING_ELT(result, i, Rf_mkCharCE(state->names[i], CE_UTF8));
    SEXP output = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(output, 0, result);
    SET_VECTOR_ELT(output, 1, Rf_ScalarReal(state->charge));
    UNPROTECT(2);
    return output;
}

SEXP scwb_graph_source_directory(SEXP root, SEXP allowance)
{
    if (TYPEOF(root) != STRSXP || XLENGTH(root) != 1 ||
        STRING_ELT(root, 0) == NA_STRING)
        Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: missing native source directory.");
    double limit = Rf_asReal(allowance);
    if (!R_FINITE(limit) || limit < 0)
        Rf_error("GRAPH_RESOURCE_POLICY_INVALID: invalid file metadata allowance.");
    const char *path = Rf_translateCharUTF8(STRING_ELT(root, 0));
    DIR *dir = opendir(path);
    if (!dir) Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: native directory: %s", strerror(errno));
    char **names = NULL;
    size_t count = 0;
    double charge = 0;
    int failure = 0, exhausted = 0;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(dir);
        if (!entry) { failure = errno; break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t bytes = strlen(entry->d_name);
        double next = charge + 1024.0 + 8.0 * (strlen(path) + bytes + 2.0);
        if (next > limit) { exhausted = 1; break; }
        /* old+new pointer vectors during realloc are covered by 1024/entry. */
        char **grown = realloc(names, (count + 1) * sizeof(char *));
        if (!grown) { failure = ENOMEM; break; }
        names = grown;
        names[count] = malloc(bytes + 1);
        if (!names[count]) { failure = ENOMEM; break; }
        memcpy(names[count], entry->d_name, bytes + 1);
        count++; charge = next;
    }
    closedir(dir);
    if (failure || exhausted) {
        for (size_t i = 0; i < count; i++) free(names[i]);
        free(names);
        if (exhausted) Rf_error("GRAPH_RESOURCE_EXCEEDED: native source file-name metadata exceeds working admission.");
        Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: native directory enumeration: %s", strerror(failure));
    }
    if (count) qsort(names, count, sizeof(char *), compare_names);
    source_names state = {names, count, charge};
    return R_UnwindProtect(source_names_result, &state,
                           free_source_names, &state, NULL);
}
