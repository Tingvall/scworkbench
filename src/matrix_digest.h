#ifndef SCWB_MATRIX_DIGEST_H
#define SCWB_MATRIX_DIGEST_H
#include <Rinternals.h>
#include <stddef.h>
void scwb_matrix_digest_write(SEXP sink, const void *bytes, size_t length);
#endif
