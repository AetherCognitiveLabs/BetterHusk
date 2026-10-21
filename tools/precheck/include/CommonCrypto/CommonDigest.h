#pragma once
#include <stdint.h>
typedef struct { uint32_t x[64]; } CC_MD5_CTX, CC_SHA1_CTX, CC_SHA256_CTX, CC_SHA512_CTX, CC_SHA224_CTX, CC_SHA384_CTX;
typedef uint32_t CC_LONG;
#define CC_MD5_DIGEST_LENGTH 16
#define CC_SHA1_DIGEST_LENGTH 20
#define CC_SHA256_DIGEST_LENGTH 32
#define CC_SHA512_DIGEST_LENGTH 64
#define CC_SHA224_DIGEST_LENGTH 28
#define CC_SHA384_DIGEST_LENGTH 48
int CC_MD5_Init(CC_MD5_CTX*); int CC_MD5_Update(CC_MD5_CTX*, const void*, CC_LONG); int CC_MD5_Final(uint8_t*, CC_MD5_CTX*);
int CC_SHA1_Init(CC_SHA1_CTX*); int CC_SHA1_Update(CC_SHA1_CTX*, const void*, CC_LONG); int CC_SHA1_Final(uint8_t*, CC_SHA1_CTX*);
int CC_SHA256_Init(CC_SHA256_CTX*); int CC_SHA256_Update(CC_SHA256_CTX*, const void*, CC_LONG); int CC_SHA256_Final(uint8_t*, CC_SHA256_CTX*);
int CC_SHA512_Init(CC_SHA512_CTX*); int CC_SHA512_Update(CC_SHA512_CTX*, const void*, CC_LONG); int CC_SHA512_Final(uint8_t*, CC_SHA512_CTX*);
int CC_SHA224_Init(CC_SHA224_CTX*); int CC_SHA224_Update(CC_SHA224_CTX*, const void*, CC_LONG); int CC_SHA224_Final(uint8_t*, CC_SHA224_CTX*);
int CC_SHA384_Init(CC_SHA384_CTX*); int CC_SHA384_Update(CC_SHA384_CTX*, const void*, CC_LONG); int CC_SHA384_Final(uint8_t*, CC_SHA384_CTX*);
