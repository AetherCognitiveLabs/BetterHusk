static void Surf_init_tex(tl_jcall *c)   /* <init>(SurfaceTexture): texture-backed window */
{
    if (c->args[0].l) tl_jni_set_field(c->self, "huskTexture", "Landroid/graphics/SurfaceTexture;", c->args[0]);
}

/* ---- SurfaceView / SurfaceHolder / GLSurfaceView ----
 * Hybrid engines drive their surface through these Java objects. The holder
 * hands out one persistent Surface; callbacks fire surfaceCreated +
 * surfaceChanged immediately (our window already exists), which is what the
 * surfaceReady flag on real devices converges to. lockCanvas draws into a
 * bitmap whose pixels are posted to the window on unlock. */
void *tl_nwindow_get(void);
void tl_nwindow_post(void *window, const void *rgba, int w, int h, bool flip);
int tl_nwindow_width(void *window);
int tl_nwindow_height(void *window);

typedef struct { jobj *cb; } hcb;
typedef struct { jvec cbs; jobj *surf; void *win; jobj *canvas, *cbmp; } holder;
static holder *holder_of(jobj *o) { if (!o->native) o->native = calloc(1, sizeof(holder)); return o->native; }

static jobj *holder_surface(holder *h)
{
    if (!h->surf) { h->surf = tl_jni_ref(make("android/view/Surface")); h->surf->native = h; }
    return h->surf;
}
static void SH_addCallback(tl_jcall *c)
{
    holder *h = holder_of(c->self);
    jobj *cb = c->args[0].l;
    if (!cb) return;
    for (size_t i = 0; i < h->cbs.n; i++) if (h->cbs.p[i].l == cb) return;
    vec_push(&h->cbs, tl_jni_ref(cb));
    /* the surface already exists: report created + changed right away */
    jvalue s[1] = { { .j = 0, .l = c->self } };
    tl_jni_call(cb, "surfaceCreated", "(Landroid/view/SurfaceHolder;)V", s);
    if (tl_jni_pending()) tl_jni_clear();
    jvalue s2[3] = { { .j = 0, .l = c->self }, { .i = 1 /* RGBA_8888 */ }, { .i = 0 } };
    int w = 0, hh = 0;
    if (h->win) { w = tl_nwindow_width(h->win); hh = tl_nwindow_height(h->win); }
    jvalue s3[4] = { { .j = 0, .l = c->self }, { .i = 1 }, { .i = w }, { .i = hh } };
    tl_jni_call(cb, "surfaceChanged", "(Landroid/view/SurfaceHolder;III)V", s3);
    if (tl_jni_pending()) tl_jni_clear();
    (void)s2;
}
static void SH_removeCallback(tl_jcall *c)
{
    holder *h = holder_of(c->self); jobj *cb = c->args[0].l;
    for (size_t i = 0; i < h->cbs.n; i++) if (h->cbs.p[i].l == cb) {
        memmove(&h->cbs.p[i], &h->cbs.p[i + 1], (h->cbs.n - i - 1) * sizeof(jvalue)); h->cbs.n--; break;
    }
}
static void SH_getSurface(tl_jcall *c)  { c->ret = vl(holder_surface(holder_of(c->self))); }
static void SH_isCreating(tl_jcall *c)  { c->ret = vz(0); }
static void SH_setFixedSize(tl_jcall *c) { set_int(c->self, "fixedW", c->args[0].i); set_int(c->self, "fixedH", c->args[1].i); }
static void SH_setFormat(tl_jcall *c)    { set_int(c->self, "format", c->args[0].i); }
static void SH_setKeepScreenOn(tl_jcall *c) { (void)c; }
static void SH_setSizeFromLayout(tl_jcall *c) { (void)c; }
static void SH_getSurfaceFrame(tl_jcall *c)
{
    holder *h = holder_of(c->self);
    int w = h->win ? tl_nwindow_width(h->win) : 0, hh = h->win ? tl_nwindow_height(h->win) : 0;
    jobj *r = make("android/graphics/Rect");
    set_int(r, "left", 0); set_int(r, "top", 0); set_int(r, "right", w); set_int(r, "bottom", hh);
    c->ret = vl(r);
}
static void SH_lockCanvas(tl_jcall *c)
{
    holder *h = holder_of(c->self);
    if (!h->win) h->win = tl_nwindow_get();
    int w = tl_nwindow_width(h->win), hh = tl_nwindow_height(h->win);
    if (w <= 0 || hh <= 0) { w = 1080; hh = 2400; }
    if (!h->cbmp) {
        jvalue a[3] = { { .i = w }, { .i = hh }, { .j = 0, .l = NULL } };
        h->cbmp = tl_jni_ref(tl_jni_call(NULL, "android/graphics/Bitmap", "createBitmap", "(IILjava/lang/Object;)Ljava/lang/Object;", a).l);
    }
    if (!h->canvas) {
        h->canvas = tl_jni_ref(make("android/graphics/Canvas"));
        if (h->canvas) {
            jvalue a[1] = { { .j = 0, .l = h->cbmp } };
            tl_jni_call(h->canvas, "<init>", "(Ljava/lang/Object;)V", a);
        }
    }
    c->ret = vl(h->canvas);
}
static void SH_unlockCanvasAndPost(tl_jcall *c)
{
    holder *h = holder_of(c->self);
    if (h->win && h->cbmp) {
        bmpx *p = bmpx_of(h->cbmp);
        if (p->px) tl_nwindow_post(h->win, p->px, p->w, p->h, false);
    }
}
static void SV_init(tl_jcall *c) { (void)c; }
static void SV_getHolder(tl_jcall *c)
{
    jobj *h = tl_jni_get_field(c->self, "holder", "Landroid/view/SurfaceHolder;").l;
    if (!h) {
        h = make("android/view/SurfaceHolder");
        ((holder *)holder_of(h))->win = tl_nwindow_get();
        tl_jni_set_field(c->self, "holder", "Landroid/view/SurfaceHolder;", vl(h));
    }
    c->ret = vl(h);
}
static void SV_zorder(tl_jcall *c) { (void)c; }
static void SV_setSecure(tl_jcall *c)  { (void)c; }

/* GLSurfaceView: store the renderer + surface state, run queueEvent
 * inline, and fire the Renderer interface when it is installed so engines
 * that create their EGL state from those callbacks still get them. */
typedef struct { jobj *renderer; int es; bool resumed; } glsv;
static glsv *glsv_of(jobj *o) { if (!o->native) o->native = calloc(1, sizeof(glsv)); return o->native; }
static void GLSV_init(tl_jcall *c) { (void)c; }
static void GLSV_setEGLContextClientVersion(tl_jcall *c) { glsv_of(c->self)->es = c->args[0].i; }
static void GLSV_queueEvent(tl_jcall *c)
{
    if (c->args[0].l) { tl_jni_call(c->args[0].l, "run", "()V", NULL); if (tl_jni_pending()) tl_jni_clear(); }
}
static void glsv_fire(glsv *g, jobj *holder_surf)
{
    if (!g->renderer) return;
    jobj *cfg = make("javax/microedition/khronos/egl/EGLConfig");
    jobj *gl  = make("javax/microedition/khronos/opengles/GL10");
    jvalue a[2] = { { .j = 0, .l = gl }, { .j = 0, .l = cfg } };
    tl_jni_call(g->renderer, "onSurfaceCreated", "(Ljavax/microedition/khronos/opengles/GL10;Ljavax/microedition/khronos/egl/EGLConfig;)V", a);
    if (tl_jni_pending()) tl_jni_clear();
    int w = 0, h = 0;
    jvalue a2[3] = { { .j = 0, .l = gl }, { .i = w }, { .i = h } };
    tl_jni_call(g->renderer, "onSurfaceChanged", "(Ljavax/microedition/khronos/opengles/GL10;II)V", a2);
    if (tl_jni_pending()) tl_jni_clear();
    (void)holder_surf;
}
static void GLSV_setRenderer(tl_jcall *c)
{
    glsv *g = glsv_of(c->self);
    g->renderer = tl_jni_ref(c->args[0].l);
    g->resumed = true;
    glsv_fire(g, NULL);
}
static void GLSV_onPause(tl_jcall *c)  { glsv_of(c->self)->resumed = false; }
static void GLSV_onResume(tl_jcall *c) { glsv_of(c->self)->resumed = true; }
static void GLSV_setPreserveEGLContextOnPause(tl_jcall *c) { (void)c; }
static void GLSV_requestRender(tl_jcall *c)
{
    glsv *g = glsv_of(c->self);
    if (g->renderer) {
        jvalue a[1] = { { .j = 0, .l = make("javax/microedition/khronos/opengles/GL10") } };
        tl_jni_call(g->renderer, "onDrawFrame", "(Ljavax/microedition/khronos/opengles/GL10;)V", a);
        if (tl_jni_pending()) tl_jni_clear();
    }
}
static void GLSV_setRenderMode(tl_jcall *c) { set_int(c->self, "renderMode", c->args[0].i); }
static void GLSV_getRenderMode(tl_jcall *c) { c->ret = vi(get_int(c->self, "renderMode")); }

