#pragma once
#include <stdint.h>
#include <stddef.h>
typedef void *CCCryptorRef;
typedef uint32_t CCOperation; typedef uint32_t CCAlgorithm; typedef uint32_t CCPadding;
typedef uint32_t CCMode; typedef uint32_t CCModeOptions; typedef int32_t CCCryptorStatus;
#define kCCEncrypt 0
#define kCCDecrypt 1
#define kCCAlgorithmAES 0
#define kCCAlgorithmDES 1
#define kCCAlgorithm3DES 2
#define kCCSuccess 0
#define kCCModeECB 1
#define kCCModeCBC 2
#define kCCModeCFB 3
#define kCCModeCTR 4
#define kCCModeOFB 7
#define ccNoPadding 0
#define ccPKCS7Padding 1
CCCryptorStatus CCCryptorCreateWithMode(CCOperation, CCMode, CCAlgorithm, CCPadding,
    const void *, const void *, size_t, const void *, size_t, int, CCModeOptions, CCCryptorRef *);
CCCryptorStatus CCCryptorUpdate(CCCryptorRef, const void *, size_t, void *, size_t, size_t *);
CCCryptorStatus CCCryptorFinal(CCCryptorRef, void *, size_t, size_t *);
CCCryptorStatus CCCryptorRelease(CCCryptorRef);
