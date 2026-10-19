#define _GNU_SOURCE
#include <R.h>
#include <Rinternals.h>
#include <stdlib.h>
#include <string.h>
#include "matrix_digest.h"

/* Optional optimization, not a new crypto dependency. Since glibc 2.34 the
 * loader API is in libc (no additional libdl link requirement). Other builds
 * retain the original portable openssl(connection) path. Never load a provider
 * or use a private R-openssl interface. Opaque types follow public EVP's ABI. */
#if defined(__linux__)
#include <features.h>
#if defined(__GLIBC__) && defined(__GLIBC_PREREQ)
#if __GLIBC_PREREQ(2, 34) && !defined(SCWB_DISABLE_INCREMENTAL_MATRIX_DIGEST)
#define SCWB_MATRIX_EVP_LOADER 1
#include <dlfcn.h>
#endif
#endif
#endif

#ifdef SCWB_MATRIX_EVP_LOADER
typedef struct evp_md_ctx_st EVP_MD_CTX;
typedef struct evp_md_st EVP_MD;
typedef struct engine_st ENGINE;
typedef struct {
    void *handle;
    EVP_MD_CTX *context;
    EVP_MD_CTX *(*create)(void);
    void (*destroy)(EVP_MD_CTX *);
    const EVP_MD *(*sha256)(void);
    int (*init)(EVP_MD_CTX *, const EVP_MD *, ENGINE *);
    int (*update)(EVP_MD_CTX *, const void *, size_t);
    int (*final)(EVP_MD_CTX *, unsigned char *, unsigned int *);
} matrix_digest;

static SEXP digest_tag(void) { return Rf_install("scworkbench.matrix_digest.private"); }

static void digest_cleanup(SEXP pointer) {
    matrix_digest *sink = R_ExternalPtrAddr(pointer);
    if (!sink) return;
    if (sink->context && sink->destroy) sink->destroy(sink->context);
    sink->context = NULL;
    if (sink->handle) dlclose(sink->handle);
    free(sink);
    R_ClearExternalPtr(pointer);
}

static matrix_digest *digest_require(SEXP pointer) {
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != digest_tag() ||
        !R_ExternalPtrAddr(pointer)) Rf_error("Closed or invalid matrix digest stream.");
    matrix_digest *sink = R_ExternalPtrAddr(pointer);
    if (!sink->context) Rf_error("Closed or invalid matrix digest stream.");
    return sink;
}
#endif

SEXP scwb_matrix_digest_open(SEXP path) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        Rf_error("Invalid matrix digest provider path.");
#ifdef SCWB_MATRIX_EVP_LOADER
    const char *name = Rf_translateCharUTF8(STRING_ELT(path, 0));
    if (name[0] != '/') return R_NilValue;
    SEXP pointer = PROTECT(R_MakeExternalPtr(NULL, digest_tag(), R_NilValue));
    R_RegisterCFinalizerEx(pointer, digest_cleanup, TRUE);
    matrix_digest *sink = calloc(1, sizeof(*sink));
    if (!sink) { UNPROTECT(1); Rf_error("Cannot allocate matrix digest stream."); }
    R_SetExternalPtrAddr(pointer, sink);
    sink->handle = dlopen(name, RTLD_LAZY | RTLD_LOCAL | RTLD_NOLOAD);
    if (!sink->handle) { digest_cleanup(pointer); UNPROTECT(1); return R_NilValue; }
    void *origin = NULL;
    const char *names[] = {"EVP_MD_CTX_new", "EVP_MD_CTX_free", "EVP_sha256",
        "EVP_DigestInit_ex", "EVP_DigestUpdate", "EVP_DigestFinal_ex"};
    void *symbols[6];
    for (int i = 0; i < 6; ++i) {
        Dl_info info;
        dlerror();
        symbols[i] = dlsym(sink->handle, names[i]);
        const char *error = dlerror();
        if (error || !symbols[i] || !dladdr(symbols[i], &info) || !info.dli_fbase ||
            (origin && origin != info.dli_fbase)) {
            digest_cleanup(pointer); UNPROTECT(1); return R_NilValue;
        }
        origin = info.dli_fbase;
    }
    /* POSIX dlsym explicitly permits conversion to these function pointers. */
    sink->create = (EVP_MD_CTX *(*)(void))symbols[0];
    sink->destroy = (void (*)(EVP_MD_CTX *))symbols[1];
    sink->sha256 = (const EVP_MD *(*)(void))symbols[2];
    sink->init = (int (*)(EVP_MD_CTX *, const EVP_MD *, ENGINE *))symbols[3];
    sink->update = (int (*)(EVP_MD_CTX *, const void *, size_t))symbols[4];
    sink->final = (int (*)(EVP_MD_CTX *, unsigned char *, unsigned int *))symbols[5];
    sink->context = sink->create();
    const EVP_MD *algorithm = sink->sha256();
    if (!sink->context || !algorithm || sink->init(sink->context, algorithm, NULL) != 1) {
        digest_cleanup(pointer); UNPROTECT(1); Rf_error("Matrix SHA-256 initialization failed.");
    }
    UNPROTECT(1);
    return pointer;
#else
    return R_NilValue;
#endif
}

void scwb_matrix_digest_write(SEXP pointer, const void *bytes, size_t length) {
#ifdef SCWB_MATRIX_EVP_LOADER
    matrix_digest *sink = digest_require(pointer);
    if (sink->update(sink->context, bytes, length) != 1) {
        digest_cleanup(pointer);
        Rf_error("Matrix SHA-256 update failed.");
    }
#else
    Rf_error("Incremental matrix digest unavailable on this build.");
#endif
}

SEXP scwb_matrix_digest_update(SEXP pointer, SEXP bytes) {
    if (TYPEOF(bytes) != RAWSXP) Rf_error("Matrix digest update requires raw bytes.");
    scwb_matrix_digest_write(pointer, RAW(bytes), (size_t)XLENGTH(bytes));
    return R_NilValue;
}

SEXP scwb_matrix_digest_finish(SEXP pointer) {
#ifdef SCWB_MATRIX_EVP_LOADER
    matrix_digest *sink = digest_require(pointer);
    unsigned char bytes[64];
    unsigned int length = 0;
    int ok = sink->final(sink->context, bytes, &length);
    digest_cleanup(pointer);
    if (ok != 1 || length != 32) Rf_error("Matrix SHA-256 finalization failed.");
    static const char hex[] = "0123456789abcdef";
    char output[65];
    for (int i = 0; i < 32; ++i) {
        output[2*i] = hex[bytes[i] >> 4];
        output[2*i+1] = hex[bytes[i] & 15];
    }
    output[64] = '\0';
    return Rf_mkString(output);
#else
    Rf_error("Incremental matrix digest unavailable on this build.");
    return R_NilValue;
#endif
}

SEXP scwb_matrix_digest_close(SEXP pointer) {
#ifdef SCWB_MATRIX_EVP_LOADER
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != digest_tag())
        Rf_error("Invalid matrix digest stream.");
    digest_cleanup(pointer);
#endif
    return R_NilValue;
}
