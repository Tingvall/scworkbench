/* Getter-only bounded JSON lexical observation over the owning RSQLite API
 * and private metadata files. Fixed input/output buffers; no whole TEXT decode. */
#include <R.h>
#include <Rinternals.h>
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT3
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>
#include "graph_sqlite_bytes.h"
typedef struct {
  int offset, at, available, string;
  FILE *file; double read_bytes, limit; struct stat initial;
  unsigned char input[4096], output[4096];
} json_lexer;
static void lexer_close(SEXP pointer) {
  if(TYPEOF(pointer)!=EXTPTRSXP || R_ExternalPtrTag(pointer)!=Rf_install("scwb_graph_json_lexer"))
    Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: invalid bounded JSON reader.");
  json_lexer *state=R_ExternalPtrAddr(pointer);
  if(state && state->file)fclose(state->file);
  free(state); R_ClearExternalPtr(pointer);
}
SEXP scwb_graph_json_open(SEXP owner) {
  if(!sqlite3_api)Rf_error("Bounded RSQLite API is not initialized.");
  if(TYPEOF(owner)!=EXTPTRSXP || R_ExternalPtrTag(owner)!=Rf_install("scwb_graph_bytes") || !R_ExternalPtrAddr(owner))
    Rf_error("Invalid bounded byte observer.");
  SEXP pointer=PROTECT(R_MakeExternalPtr(NULL,Rf_install("scwb_graph_json_lexer"),owner));
  json_lexer *state=calloc(1,sizeof(json_lexer));
  if(!state) Rf_error("Bounded lexer allocation failed.");
  R_SetExternalPtrAddr(pointer,state); R_RegisterCFinalizerEx(pointer,lexer_close,TRUE);
  UNPROTECT(1); return pointer;
}
SEXP scwb_graph_json_file_open(SEXP path,SEXP allowance) {
  if(TYPEOF(path)!=STRSXP || XLENGTH(path)!=1 || STRING_ELT(path,0)==NA_STRING)
    Rf_error("Invalid bounded JSON file path.");
  double limit=Rf_asReal(allowance);
  if(!R_FINITE(limit) || limit<0)Rf_error("GRAPH_RESOURCE_EXCEEDED: invalid JSON file admission.");
  SEXP pointer=PROTECT(R_MakeExternalPtr(NULL,Rf_install("scwb_graph_json_lexer"),R_NilValue));
  json_lexer *state=calloc(1,sizeof(json_lexer));
  if(!state)Rf_error("Bounded lexer allocation failed.");
  R_SetExternalPtrAddr(pointer,state);R_RegisterCFinalizerEx(pointer,lexer_close,TRUE);
  state->file=fopen(Rf_translateCharUTF8(STRING_ELT(path,0)),"rb");state->limit=limit;
  if(!state->file || fstat(fileno(state->file),&state->initial)) {
    lexer_close(pointer);Rf_error("Bounded JSON file open failed.");
  }
  if((double)state->initial.st_size>limit) {
    lexer_close(pointer);Rf_error("GRAPH_RESOURCE_EXCEEDED: JSON file bytes exceed admission.");
  }
  UNPROTECT(1);return pointer;
}
SEXP scwb_graph_json_close(SEXP pointer) {lexer_close(pointer);return R_NilValue;}
static void file_finish(json_lexer *state) {
  struct stat actual;
  if(fstat(fileno(state->file),&actual) || actual.st_dev!=state->initial.st_dev ||
      actual.st_ino!=state->initial.st_ino || actual.st_size!=state->initial.st_size ||
      actual.st_mtim.tv_sec!=state->initial.st_mtim.tv_sec || actual.st_mtim.tv_nsec!=state->initial.st_mtim.tv_nsec ||
      actual.st_ctim.tv_sec!=state->initial.st_ctim.tv_sec || actual.st_ctim.tv_nsec!=state->initial.st_ctim.tv_nsec)
    Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: bounded JSON file changed during verification.");
}
static int peek(json_lexer *state, graph_bytes *source) {
  if(state->at==state->available) {
    if(state->file) {
      size_t n=fread(state->input,1,4096,state->file);
      if(!n) {
        if(ferror(state->file))Rf_error("Bounded JSON file read failed.");
        file_finish(state);return -1;
      }
      state->read_bytes+=n;
      if(state->read_bytes>state->limit)Rf_error("GRAPH_RESOURCE_EXCEEDED: JSON file grew beyond admission.");
      state->available=(int)n;state->at=0;
      return state->input[0];
    }
    if(state->offset>=source->bytes) return -1;
    int n=source->bytes-state->offset; if(n>4096)n=4096;
    if(sqlite3_blob_read(source->blob,state->input,n,state->offset)!=SQLITE_OK)
      Rf_error("Bounded JSON read failed.");
    state->offset+=n; state->available=n; state->at=0;
  }
  return state->input[state->at];
}
static int next(json_lexer *state, graph_bytes *source) {
  int b=peek(state,source); if(b>=0)state->at++; return b;
}
static void invalid(void) { Rf_error("Invalid JSON lexical input."); }
static unsigned int hex4(json_lexer *state,graph_bytes *source) {
  unsigned int n=0;
  for(int i=0;i<4;i++) {
    int b=next(state,source); int digit;
    if(b>='0'&&b<='9') digit=b-'0';
    else if(b>='A'&&b<='F') digit=b-'A'+10;
    else if(b>='a'&&b<='f') digit=b-'a'+10;
    else {invalid();return 0;}
    n=16*n+digit;
  }
  return n;
}
static int codepoint(unsigned int u,unsigned char *out) {
  if(!u || (u>=0xd800&&u<=0xdfff) || u>0x10ffff) {invalid();return 0;}
  if(u<0x80) {out[0]=u;return 1;}
  if(u<0x800) {out[0]=0xc0|(u>>6);out[1]=0x80|(u&63);return 2;}
  if(u<0x10000) {out[0]=0xe0|(u>>12);out[1]=0x80|((u>>6)&63);out[2]=0x80|(u&63);return 3;}
  out[0]=0xf0|(u>>18);out[1]=0x80|((u>>12)&63);out[2]=0x80|((u>>6)&63);out[3]=0x80|(u&63);return 4;
}
static SEXP token(const char *type,const unsigned char *value,int n) {
  SEXP result=PROTECT(Rf_allocVector(VECSXP,2));
  SET_VECTOR_ELT(result,0,Rf_mkString(type));
  SET_VECTOR_ELT(result,1,Rf_ScalarString(Rf_mkCharLenCE((const char*)value,n,CE_UTF8)));
  SEXP names=PROTECT(Rf_allocVector(STRSXP,2));
  SET_STRING_ELT(names,0,Rf_mkChar("type"));SET_STRING_ELT(names,1,Rf_mkChar("value"));
  Rf_setAttrib(result,R_NamesSymbol,names);UNPROTECT(2);return result;
}
SEXP scwb_graph_json_next(SEXP pointer) {
  if(TYPEOF(pointer)!=EXTPTRSXP || R_ExternalPtrTag(pointer)!=Rf_install("scwb_graph_json_lexer"))
    Rf_error("GRAPH_SOURCE_PAYLOAD_INVALID: invalid bounded JSON reader.");
  if(TYPEOF(pointer)!=EXTPTRSXP || R_ExternalPtrTag(pointer)!=Rf_install("scwb_graph_json_lexer"))invalid();
  json_lexer *state=R_ExternalPtrAddr(pointer);
  SEXP owner=R_ExternalPtrProtected(pointer);
  graph_bytes *source=TYPEOF(owner)==EXTPTRSXP?R_ExternalPtrAddr(owner):NULL;
  if(!state || (!state->file && (!source || !source->blob)))invalid();
  R_CheckUserInterrupt();
  if(!state->string) {
    int b;
    do {b=peek(state,source);if(b==' '||b=='\n'||b=='\r'||b=='\t')next(state,source);else break;}while(1);
    if(b<0)return token("end",(unsigned char*)"",0);
    b=next(state,source);
    if(b=='"')state->string=1;
    else if(b=='{'||b=='}'||b=='['||b==']'||b==':'||b==',') {
      state->output[0]=b;return token("punctuation",state->output,1);
    } else {
      int n=0;state->output[n++]=b;
      while((b=peek(state,source))>=0 && b!=' '&&b!='\n'&&b!='\r'&&b!='\t'&&b!=','&&b!=']'&&b!='}') {
        if(n>=128)Rf_error("GRAPH_RESOURCE_EXCEEDED: JSON scalar exceeds bounded decoder admission.");state->output[n++]=next(state,source);
      }
      return token("scalar",state->output,n);
    }
  }
  int n=0;
  while(n<=4092) {
    int b=next(state,source);if(b<0)invalid();
    if(b=='"') {state->string=0;return token("string_end",state->output,n);}
    if(b=='\\') {
      b=next(state,source);
      if(b=='"'||b=='\\'||b=='/')state->output[n++]=b;
      else if(b=='b')state->output[n++]=8;
      else if(b=='f')state->output[n++]=12;
      else if(b=='n')state->output[n++]=10;
      else if(b=='r')state->output[n++]=13;
      else if(b=='t')state->output[n++]=9;
      else if(b=='u') {
        unsigned int u=hex4(state,source);
        if(u>=0xd800 && u<=0xdbff) {
          if(next(state,source)!='\\'||next(state,source)!='u')invalid();
          unsigned int low=hex4(state,source);if(low<0xdc00||low>0xdfff)invalid();
          u=0x10000+((u-0xd800)<<10)+(low-0xdc00);
        }
        n+=codepoint(u,state->output+n);
      } else invalid();
    } else if(b<32)invalid();
    else if(b<128)state->output[n++]=b;
    else {
      unsigned int u;int width;
      if(b>=0xc2&&b<=0xdf) {width=2;u=b&31;}
      else if(b>=0xe0&&b<=0xef) {width=3;u=b&15;}
      else if(b>=0xf0&&b<=0xf4) {width=4;u=b&7;}
      else {invalid();return R_NilValue;}
      for(int i=1;i<width;i++) {int c=next(state,source);if(c<0x80||c>0xbf)invalid();u=(u<<6)|(c&63);}
      if((width==2&&u<0x80)||(width==3&&u<0x800)||(width==4&&u<0x10000))invalid();
      n+=codepoint(u,state->output+n);
    }
  }
  return token("string_part",state->output,n);
}

SEXP scwb_graph_json_position(SEXP pointer) {
  if(TYPEOF(pointer)!=EXTPTRSXP || R_ExternalPtrTag(pointer)!=Rf_install("scwb_graph_json_lexer"))invalid();
  json_lexer *state=R_ExternalPtrAddr(pointer);
  if(!state || !state->file)invalid();
  return Rf_ScalarReal(state->read_bytes-state->available+state->at);
}
