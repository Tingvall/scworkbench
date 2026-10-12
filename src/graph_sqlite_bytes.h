#ifndef SCWB_GRAPH_SQLITE_BYTES_H
#define SCWB_GRAPH_SQLITE_BYTES_H
#include <sqlite3ext.h>
typedef struct { sqlite3 *db; sqlite3_blob *blob; int bytes; int version; } graph_bytes;
#endif
