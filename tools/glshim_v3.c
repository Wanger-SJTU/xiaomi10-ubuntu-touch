/* glshim.c -- LD_PRELOAD shim for the umi (Xiaomi Mi 10) Ubuntu Touch port.
 *
 * Strategy: hand the Mir graphics-android2 platform the *host* glvnd
 * libEGL/libGLESv2 entry points instead of the Android ones it would get from
 * libhybris' android_dlsym().  Then the platform's EGL context is created
 * through glvnd, glvnd's dispatch table is populated, and the compositor's own
 * GL calls (which already go through glvnd) work.  One dispatch layer, one
 * context -- no forwarding, no thread trickery.
 *
 * The real android_dlsym is resolved from a dlopen("libhybris-common.so.1")
 * handle: RTLD_NEXT does not find it because the platform loads libhybris with
 * RTLD_LOCAL (that mistake cost several rounds -- see OPERATIONS.md 8.21/8.22).
 *
 * Build (no aarch64 sysroot required):
 *   clang --target=aarch64-linux-gnu -shared -fPIC -nostdlib \
 *         -fuse-ld=lld -o libglshim.so glshim.c
 */
typedef unsigned int GLenum;

#define RTLD_NEXT ((void *)-1l)
#define RTLD_NOW 2
#define RTLD_GLOBAL 0x100

extern void *dlsym(void *handle, const char *symbol);
extern void *dlopen(const char *file, int mode);
extern int strncmp(const char *a, const char *b, unsigned long n);
extern int dprintf(int fd, const char *fmt, ...);

typedef void *(*dlsym_fn)(void *, const char *);

static void *hybris_handle;
static void *host_egl;
static void *host_gles;
static __thread int in_hook;

static void *hybris_lib(void)
{
    if (!hybris_handle)
        hybris_handle = dlopen("libhybris-common.so.1", RTLD_NOW | RTLD_GLOBAL);
    return hybris_handle;
}

static dlsym_fn real_android_dlsym(void)
{
    static dlsym_fn f;
    void *hc;

    if (f)
        return f;
    hc = hybris_lib();
    if (hc)
        f = (dlsym_fn)dlsym(hc, "android_dlsym");
    return f;
}

static void *host_symbol(const char *name)
{
    void *p;

    /* eglGetProcAddress must stay with the Android driver: it is used to look
     * up vendor extensions and redirecting it deadlocks platform init. */
    if (strncmp(name, "eglGetProcAddress", 17) == 0)
        return 0;

    if (!host_egl)
        host_egl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!host_gles)
        host_gles = dlopen("libGLESv2.so.2", RTLD_NOW | RTLD_GLOBAL);

    if (strncmp(name, "egl", 3) == 0 && host_egl) {
        p = dlsym(host_egl, name);
        if (p)
            return p;
    }
    if (strncmp(name, "gl", 2) == 0) {
        if (host_gles && (p = dlsym(host_gles, name)))
            return p;
        if (host_egl && (p = dlsym(host_egl, name))) /* glXxx lives in GLES */
            return p;
    }
    return 0;
}

void *android_dlsym(void *handle, const char *symbol)
{
    dlsym_fn real;

    if (!in_hook) {
        void *p;
        in_hook = 1;
        p = host_symbol(symbol);
        in_hook = 0;
        if (p) {
            static int n;
            if (n < 10) { n++; dprintf(2, "SHIM android_dlsym(%s) -> host\n", symbol); }
            return p;
        }
    }
    real = real_android_dlsym();
    return real ? real(handle, symbol) : 0;
}

/* The compositor probes GL strings when no context is current on its thread;
 * fall back to the known Adreno values so it does not bail out. */
typedef const unsigned char *(*glGetString_fn)(GLenum name);
static glGetString_fn real_glGetString;

const unsigned char *glGetString(GLenum name)
{
    const unsigned char *r;

    if (!real_glGetString)
        real_glGetString = (glGetString_fn)dlsym(RTLD_NEXT, "glGetString");
    if (real_glGetString && (r = real_glGetString(name)))
        return r;

    switch (name) {
    case 0x1F00: return (const unsigned char *)"Qualcomm";
    case 0x1F01: return (const unsigned char *)"Adreno (TM) 650";
    case 0x1F02: return (const unsigned char *)"OpenGL ES 3.2";
    case 0x1F03: return (const unsigned char *)"OpenGL ES GLSL ES 3.20";
    default: return (const unsigned char *)0;
    }
}
