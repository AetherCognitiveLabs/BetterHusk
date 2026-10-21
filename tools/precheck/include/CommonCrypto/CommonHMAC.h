#pragma once
#include <stdint.h>
#include <stddef.h>
typedef enum {
    kCCHmacAlgSHA1, kCCHmacAlgMD5, kCCHmacAlgSHA256, kCCHmacAlgSHA384, kCCHmacAlgSHA512, kCCHmacAlgSHA224,
} CCHmacAlgorithm;
void CCHmac(CCHmacAlgorithm, const void*, size_t, const void*, size_t, void*);
