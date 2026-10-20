/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Host bridges for husk-tl-jni-more.c: the pieces of the Android framework whose
 * right answer lives in UIKit, AVFoundation or WebKit rather than in C.
 *
 * Everything guest-thread calls is bounced onto the main thread where UIKit
 * requires it. Objects the guest holds are pooled by small integer ids.
 */
#import <Foundation/Foundation.h>
#include <TargetConditionals.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <WebKit/WebKit.h>
#else
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#endif

void tl_log_line(const char *fmt, ...);

int tl_more_has_uikit = 0;

__attribute__((constructor)) static void tl_more_probe(void)
{
#if TARGET_OS_IPHONE
    tl_more_has_uikit = [UIApplication class] != Nil;
#else
    tl_more_has_uikit = 1;
#endif
}

static void on_main(dispatch_block_t b)
{
    if ([NSThread isMainThread]) b();
    else dispatch_sync(dispatch_get_main_queue(), b);
}
static void on_main_async(dispatch_block_t b) { dispatch_async(dispatch_get_main_queue(), b); }

/* ------------------------------------------------------------------ toast */

void tl_more_toast(const char *text)
{
#if TARGET_OS_IPHONE
    if (!text || !*text) return;
    NSString *t = @(text);
    on_main_async(^{
        UIWindow *win = UIApplication.sharedApplication.keyWindow;
        if (!win) win = UIApplication.sharedApplication.windows.firstObject;
        if (!win) return;
        UILabel *l = [[UILabel alloc] init];
        l.text = t; l.textColor = UIColor.whiteColor;
        l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
        l.font = [UIFont systemFontOfSize:14];
        l.textAlignment = NSTextAlignmentCenter;
        l.layer.cornerRadius = 10; l.clipsToBounds = YES;
        l.numberOfLines = 0; l.lineBreakMode = NSLineBreakByWordWrapping;
        CGSize max = CGSizeMake(win.bounds.size.width * 0.8, CGFLOAT_MAX);
        CGRect r = [l.text boundingRectWithSize:max options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName:l.font} context:nil];
        CGFloat w = ceil(r.size.width) + 32, h = ceil(r.size.height) + 16;
        l.frame = CGRectMake((win.bounds.size.width - w) / 2,
                             win.bounds.size.height - h - 80, w, h);
        l.alpha = 0;
        [win addSubview:l];
        [UIView animateWithDuration:0.25 animations:^{ l.alpha = 1; }
                         completion:^(BOOL f) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{ l.alpha = 0; }
                                 completion:^(BOOL f2) { [l removeFromSuperview]; }];
            });
        }];
    });
#else
    (void)text;
#endif
}

/* ------------------------------------------------------------ haptics */

void tl_more_haptic(int style)
{
#if TARGET_OS_IPHONE
    on_main_async(^{
        UIImpactFeedbackStyle s = style <= 0 ? UIImpactFeedbackStyleLight
                                : style == 1 ? UIImpactFeedbackStyleMedium
                                : UIImpactFeedbackStyleHeavy;
        UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:s];
        [g prepare]; [g impactOccurred];
    });
#else
    (void)style;
#endif
}

void tl_more_vibrate(int64_t ms)
{
#if TARGET_OS_IPHONE
    (void)ms;
    on_main_async(^{ AudioServicesPlaySystemSound(kSystemSoundID_Vibrate); });
#else
    (void)ms;
#endif
}

/* ----------------------------------------------------------- clipboard */

void tl_more_clipboard_set(const char *text)
{
#if TARGET_OS_IPHONE
    NSString *t = text ? @(text) : @"";
    on_main_async(^{ UIPasteboard.generalPasteboard.string = t; });
#else
    (void)text;
#endif
}

char *tl_more_clipboard_get(void)
{
#if TARGET_OS_IPHONE
    __block NSString *t = nil;
    on_main(^{ t = UIPasteboard.generalPasteboard.string; });
    return t ? strdup(t.UTF8String) : NULL;
#else
    return NULL;
#endif
}

int tl_more_clipboard_has(void)
{
#if TARGET_OS_IPHONE
    __block BOOL h = NO;
    on_main(^{ h = UIPasteboard.generalPasteboard.hasStrings; });
    return h ? 1 : 0;
#else
    return 0;
#endif
}

/* -------------------------------------------------------------- openURL */

int tl_more_open_url(const char *url)
{
#if TARGET_OS_IPHONE
    if (!url) return 0;
    NSURL *u = [NSURL URLWithString:@(url)];
    if (!u) return 0;
    __block BOOL ok = NO;
    on_main(^{ ok = [UIApplication.sharedApplication canOpenURL:u]; });
    if (!ok) return 0;
    on_main_async(^{ [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; });
    return 1;
#else
    (void)url;
    return 0;
#endif
}

/* -------------------------------------------------------- idle / battery */

void tl_more_idle_timer(int keep_on)
{
#if TARGET_OS_IPHONE
    on_main_async(^{ UIApplication.sharedApplication.idleTimerDisabled = keep_on != 0; });
#else
    (void)keep_on;
#endif
}

int tl_more_battery_pct(void)
{
#if TARGET_OS_IPHONE
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    float l = UIDevice.currentDevice.batteryLevel;
    return l < 0 ? 100 : (int)(l * 100);
#else
    return 100;
#endif
}

int tl_more_battery_state(void)
{
#if TARGET_OS_IPHONE
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    switch (UIDevice.currentDevice.batteryState) {
        case UIDeviceBatteryStateCharging: return 2;
        case UIDeviceBatteryStateFull:     return 5;
        case UIDeviceBatteryStateUnplugged:return 3;
        default:                           return 1;
    }
#else
    return 5;
#endif
}

int tl_more_image_info(const char *path, int *w, int *h)
{
    if (!path) return 0;
    NSURL *u = [NSURL fileURLWithPath:@(path)];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)u, NULL);
    if (!src) return 0;
    NSDictionary *p = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!p) return 0;
    NSNumber *pw = p[(NSString *)kCGImagePropertyPixelWidth], *ph = p[(NSString *)kCGImagePropertyPixelHeight];
    if (!pw || !ph) return 0;
    if (w) *w = pw.intValue;
    if (h) *h = ph.intValue;
    return 1;
}

/* Real RGBA8888 decode for BitmapFactory: CGImageSource handles PNG/JPEG/GIF/
 * WebP/HEIC. Caller frees *out. Returns 1 on success. */
static int decode_into(CGDataProviderRef prov, int *w, int *h, void **out)
{
    CGImageSourceRef src = CGImageSourceCreateWithDataProvider(prov, NULL);
    if (!src) return 0;
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CFRelease(src);
    if (!img) return 0;
    size_t W = CGImageGetWidth(img), H = CGImageGetHeight(img);
    if (!W || !H || W > 16384 || H > 16384) { CGImageRelease(img); return 0; }
    uint8_t *px = malloc(W * H * 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, W, H, 8, W * 4, cs,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(px); CGImageRelease(img); return 0; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), img);
    CGContextRelease(ctx); CGImageRelease(img);
    /* Android Bitmap is RGBA_8888 = premultiplied RGBA big-endian, which is
     * exactly what we rendered. */
    *w = (int)W; *h = (int)H; *out = px;
    return 1;
}

int tl_more_decode_image(const char *path, int *w, int *h, void **out)
{
    if (!path || !out) return 0;
    *out = NULL;
    NSData *d = [NSData dataWithContentsOfFile:@(path)];
    if (!d) return 0;
    CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)d);
    int ok = decode_into(prov, w, h, out);
    CGDataProviderRelease(prov);
    return ok;
}

int tl_more_decode_image_mem(const void *data, size_t n, int *w, int *h, void **out)
{
    if (!data || !n || !out) return 0;
    *out = NULL;
    NSData *d = [NSData dataWithBytes:data length:n];
    CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)d);
    int ok = decode_into(prov, w, h, out);
    CGDataProviderRelease(prov);
    return ok;
}

/* ------------------------------------------------------- MediaPlayer pool */

static pthread_mutex_t g_mp_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary<NSNumber *, AVAudioPlayer *> *g_mp;
static _Atomic int g_mp_next = 1;

int tl_mp_new(void)
{
    pthread_mutex_lock(&g_mp_lock);
    if (!g_mp) g_mp = [NSMutableDictionary new];
    int id = g_mp_next++;
    g_mp[@(id)] = (AVAudioPlayer *)[NSNull null];
    pthread_mutex_unlock(&g_mp_lock);
    return id;
}
static AVAudioPlayer *mp_get(int id)
{
    pthread_mutex_lock(&g_mp_lock);
    AVAudioPlayer *p = g_mp[@(id)];
    pthread_mutex_unlock(&g_mp_lock);
    return [p isKindOfClass:[AVAudioPlayer class]] ? p : nil;
}
static void mp_put(int id, AVAudioPlayer *p)
{
    pthread_mutex_lock(&g_mp_lock);
    if (p) g_mp[@(id)] = p; else g_mp[@(id)] = (AVAudioPlayer *)[NSNull null];
    pthread_mutex_unlock(&g_mp_lock);
}

void tl_mp_source_path(int id, const char *path)
{
    if (!path) return;
    NSURL *u = [NSURL fileURLWithPath:@(path)];
    __block AVAudioPlayer *p;
    on_main(^{ p = [[AVAudioPlayer alloc] initWithContentsOfURL:u error:nil]; });
    if (p) { [p prepareToPlay]; mp_put(id, p); }
}

void tl_mp_source_fd(int id, int fd, int64_t off, int64_t len)
{
    if (fd < 0) return;
    lseek(fd, off, SEEK_SET);
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)len];
    ssize_t got = read(fd, d.mutableBytes, (size_t)len);
    if (got <= 0) return;
    d.length = (NSUInteger)got;
    __block AVAudioPlayer *p;
    on_main(^{ p = [[AVAudioPlayer alloc] initWithData:d error:nil]; });
    if (p) { [p prepareToPlay]; mp_put(id, p); }
}

void tl_mp_source_url(int id, const char *url)
{
    if (!url) return;
    NSURL *u = [NSURL URLWithString:@(url)];
    if (!u) return;
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (!d) return;
    __block AVAudioPlayer *p;
    on_main(^{ p = [[AVAudioPlayer alloc] initWithData:d error:nil]; });
    if (p) { [p prepareToPlay]; mp_put(id, p); }
}

void tl_mp_prepare(int id, int async) { (void)id; (void)async; }
void tl_mp_start(int id)    { AVAudioPlayer *p = mp_get(id); if (p) on_main_async(^{ [p play]; }); }
void tl_mp_pause(int id)    { AVAudioPlayer *p = mp_get(id); if (p) [p pause]; }
void tl_mp_stop(int id)     { AVAudioPlayer *p = mp_get(id); if (p) { [p stop]; p.currentTime = 0; } }
void tl_mp_release(int id)
{
    pthread_mutex_lock(&g_mp_lock);
    AVAudioPlayer *p = g_mp[@(id)];
    [p stop];
    [g_mp removeObjectForKey:@(id)];
    pthread_mutex_unlock(&g_mp_lock);
}
void tl_mp_seek(int id, int ms)
{
    AVAudioPlayer *p = mp_get(id);
    if (p) p.currentTime = ms / 1000.0;
}
int tl_mp_pos(int id)
{
    AVAudioPlayer *p = mp_get(id);
    return p ? (int)(p.currentTime * 1000) : 0;
}
int tl_mp_dur(int id)
{
    AVAudioPlayer *p = mp_get(id);
    return p ? (int)(p.duration * 1000) : 0;
}
int tl_mp_playing(int id)
{
    AVAudioPlayer *p = mp_get(id);
    return p && p.playing ? 1 : 0;
}
void tl_mp_looping(int id, int on)
{
    AVAudioPlayer *p = mp_get(id);
    if (p) p.numberOfLoops = on ? -1 : 0;
}
void tl_mp_volume(int id, float l, float r)
{
    AVAudioPlayer *p = mp_get(id);
    if (p) p.volume = l < r ? r : l;
}

/* -------------------------------------------------------- SoundPool pool */

static pthread_mutex_t g_sp_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary<NSNumber *, NSData *> *g_sp_sounds;   /* sid -> data */
static NSMutableDictionary<NSNumber *, AVAudioPlayer *> *g_sp_streams; /* stream -> player */
static _Atomic int g_sp_next_sound = 1, g_sp_next_stream = 1;

static int sp_load(NSData *d)
{
    if (!d) return 0;
    pthread_mutex_lock(&g_sp_lock);
    if (!g_sp_sounds) g_sp_sounds = [NSMutableDictionary new];
    if (!g_sp_streams) g_sp_streams = [NSMutableDictionary new];
    int sid = g_sp_next_sound++;
    g_sp_sounds[@(sid)] = d;
    pthread_mutex_unlock(&g_sp_lock);
    return sid;
}
int tl_sp_load_path(const char *path)
{
    if (!path) return 0;
    return sp_load([NSData dataWithContentsOfFile:@(path)]);
}
int tl_sp_load_fd(int fd, int64_t off, int64_t len)
{
    if (fd < 0) return 0;
    lseek(fd, off, SEEK_SET);
    NSMutableData *d = [NSMutableData dataWithLength:(NSUInteger)len];
    ssize_t got = read(fd, d.mutableBytes, (size_t)len);
    if (got <= 0) return 0;
    d.length = (NSUInteger)got;
    return sp_load(d);
}
int tl_sp_play(int sid, float lv, float rv, int prio, int loop, float rate)
{
    pthread_mutex_lock(&g_sp_lock);
    NSData *d = g_sp_sounds[@(sid)];
    pthread_mutex_unlock(&g_sp_lock);
    if (!d) return 0;
    __block AVAudioPlayer *p;
    on_main(^{ p = [[AVAudioPlayer alloc] initWithData:d error:nil]; });
    if (!p) return 0;
    (void)prio;
    p.numberOfLoops = loop ? -1 : 0;
    p.volume = lv < rv ? rv : lv;
    p.enableRate = YES;
    if (rate > 0) p.rate = rate;
    int stream = g_sp_next_stream++;
    pthread_mutex_lock(&g_sp_lock);
    g_sp_streams[@(stream)] = p;
    pthread_mutex_unlock(&g_sp_lock);
    on_main_async(^{ [p play]; });
    return stream;
}
static AVAudioPlayer *sp_stream(int s)
{
    pthread_mutex_lock(&g_sp_lock);
    AVAudioPlayer *p = g_sp_streams[@(s)];
    pthread_mutex_unlock(&g_sp_lock);
    return p;
}
void tl_sp_stop(int s)   { [sp_stream(s) stop]; }
void tl_sp_pause(int s)  { [sp_stream(s) pause]; }
void tl_sp_resume(int s) { [sp_stream(s) play]; }
void tl_sp_volume(int s, float lv, float rv)
{
    AVAudioPlayer *p = sp_stream(s);
    if (p) p.volume = lv < rv ? rv : lv;
}
void tl_sp_loop(int s, int loop)
{
    AVAudioPlayer *p = sp_stream(s);
    if (p) p.numberOfLoops = loop ? -1 : 0;
}
void tl_sp_rate(int s, float rate)
{
    AVAudioPlayer *p = sp_stream(s);
    if (p) { p.enableRate = YES; p.rate = rate; }
}
void tl_sp_unload(int sid)
{
    pthread_mutex_lock(&g_sp_lock);
    [g_sp_sounds removeObjectForKey:@(sid)];
    pthread_mutex_unlock(&g_sp_lock);
}

/* --------------------------------------------------------- WebView pool */

static pthread_mutex_t g_wv_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary<NSNumber *, WKWebView *> *g_wv;
static _Atomic int g_wv_next = 1;

static UIView *wv_host(void)
{
#if TARGET_OS_IPHONE
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (!w) w = UIApplication.sharedApplication.windows.firstObject;
    return w.rootViewController.view;
#else
    return NSApplication.sharedApplication.keyWindow.contentView;
#endif
}

int tl_wv_new(void)
{
    int id = g_wv_next++;
    on_main(^{
        pthread_mutex_lock(&g_wv_lock);
        if (!g_wv) g_wv = [NSMutableDictionary new];
        WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
        cfg.preferences.javaScriptEnabled = YES;
        WKWebView *v = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
        g_wv[@(id)] = v;
        pthread_mutex_unlock(&g_wv_lock);
    });
    return id;
}
static WKWebView *wv_get(int id)
{
    pthread_mutex_lock(&g_wv_lock);
    WKWebView *v = g_wv[@(id)];
    pthread_mutex_unlock(&g_wv_lock);
    return v;
}
void tl_wv_load_url(int id, const char *url)
{
    if (!url) return;
    NSURL *u = [NSURL URLWithString:@(url)];
    if (!u) return;
    on_main_async(^{ [wv_get(id) loadRequest:[NSURLRequest requestWithURL:u]]; });
}
void tl_wv_load_html(int id, const char *html, const char *base)
{
    if (!html) return;
    NSString *h = @(html);
    NSURL *b = base ? [NSURL URLWithString:@(base)] : nil;
    on_main_async(^{ [wv_get(id) loadHTMLString:h baseURL:b]; });
}
void tl_wv_frame(int id, double x, double y, double w, double h)
{
    on_main_async(^{ wv_get(id).frame = CGRectMake(x, y, w, h); });
}
void tl_wv_visible(int id, int vis)
{
    on_main_async(^{
        WKWebView *v = wv_get(id);
        if (!v) return;
        if (vis && !v.superview) [wv_host() addSubview:v];
        v.hidden = vis == 0;
    });
}
void tl_wv_js(int id, int enabled)
{
    on_main_async(^{
        WKWebView *v = wv_get(id);
        if (v) v.configuration.preferences.javaScriptEnabled = enabled != 0;
    });
}
void tl_wv_destroy(int id)
{
    on_main_async(^{
        WKWebView *v = wv_get(id);
        [v stopLoading];
        [v removeFromSuperview];
        pthread_mutex_lock(&g_wv_lock);
        [g_wv removeObjectForKey:@(id)];
        pthread_mutex_unlock(&g_wv_lock);
    });
}
char *tl_wv_url(int id)
{
    __block NSString *u;
    on_main(^{ u = wv_get(id).URL.absoluteString; });
    return u ? strdup(u.UTF8String) : NULL;
}
char *tl_wv_title(int id)
{
    __block NSString *t;
    on_main(^{ t = wv_get(id).title; });
    return t ? strdup(t.UTF8String) : NULL;
}
int tl_wv_can_back(int id)
{
    __block BOOL b = NO;
    on_main(^{ b = wv_get(id).canGoBack; });
    return b ? 1 : 0;
}
void tl_wv_back(int id)   { on_main_async(^{ [wv_get(id) goBack]; }); }
void tl_wv_reload(int id) { on_main_async(^{ [wv_get(id) reload]; }); }
void tl_wv_stop(int id)   { on_main_async(^{ [wv_get(id) stopLoading]; }); }
void tl_wv_eval(int id, const char *js)
{
    if (!js) return;
    NSString *j = @(js);
    on_main_async(^{ [wv_get(id) evaluateJavaScript:j completionHandler:nil]; });
}
int tl_wv_progress(int id)
{
    __block double p = 0;
    on_main(^{ p = wv_get(id).estimatedProgress; });
    return (int)(p * 100);
}
