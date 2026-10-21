#pragma once
#include <stdint.h>
typedef unsigned char Byte; typedef Byte Bytef;
typedef unsigned int uInt; typedef unsigned long uLong; typedef unsigned long uLongf;
typedef struct z_stream_s {
    const Bytef *next_in; uInt avail_in; uLong total_in;
    Bytef *next_out; uInt avail_out; uLong total_out;
    char *msg; void *state; void *zalloc, *zfree, *opaque; int data_type;
    uLong adler, reserved;
} z_stream;
#define Z_OK 0
#define Z_STREAM_END 1
#define Z_BUF_ERROR -5
#define Z_STREAM_ERROR -2
#define Z_NO_FLUSH 0
#define Z_SYNC_FLUSH 2
#define Z_FINISH 4
#define Z_DEFLATED 8
#define Z_DEFAULT_COMPRESSION -1
#define Z_DEFAULT_STRATEGY 0
#define MAX_WBITS 15
int deflateInit2_(z_stream*, int, int, int, int, int, const char*, int);
#define deflateInit2(a,b,c,d,e,f) deflateInit2_(a,b,c,d,e,f,"1.2",sizeof(z_stream))
int deflateInit_(z_stream*, int, const char*, int);
#define deflateInit(a,b) deflateInit_(a,b,"1.2",sizeof(z_stream))
int inflateInit_(z_stream*, const char*, int);
#define inflateInit(a) inflateInit_(a,"1.2",sizeof(z_stream))
int inflateInit2_(z_stream*, int, const char*, int);
#define inflateInit2(a,b) inflateInit2_(a,b,"1.2",sizeof(z_stream))
int deflate(z_stream*, int); int deflateEnd(z_stream*); int deflateReset(z_stream*);
int inflate(z_stream*, int); int inflateEnd(z_stream*); int inflateReset(z_stream*);
uLong crc32(uLong, const Bytef*, uInt);
uLong adler32(uLong, const Bytef*, uInt);
int compress(Bytef*, uLongf*, const Bytef*, uLong);
int compress2(Bytef*, uLongf*, const Bytef*, uLong, int);
int uncompress(Bytef*, uLongf*, const Bytef*, uLong);
uLong compressBound(uLong);
