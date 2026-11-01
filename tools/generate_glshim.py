#!/usr/bin/env python3
"""Generate glshim.c -- an LD_PRELOAD forwarding shim for the umi UT port.

The Mir graphics-android2 platform creates its EGL context through libhybris'
android_dlsym() against the Android libEGL/libGLESv2 of the container, while
lomiri-system-compositor resolves GL entry points through glvnd.  glvnd's
dispatch table is therefore empty and the first real GL call
(glCreateShader(GL_VERTEX_SHADER)) segfaults.

This shim answers every GL entry point the compositor uses by forwarding to
the *Android* libGLESv2 (resolved with libhybris' android_dlopen/android_dlsym),
so the context and the function table come from the same driver instance.

Usage:
    python3 generate_glshim.py > glshim.c
    clang --target=aarch64-linux-gnu -shared -fPIC -nostdlib \
          -fuse-ld=lld -o libglshim.so glshim.c
"""

TYPES = """\
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
typedef float GLfloat;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef char GLchar;
typedef unsigned char GLubyte;
typedef long GLsizeiptr;
typedef long GLintptr;
"""

# (name, return type, [(type, argname), ...])
FUNCS = [
    ("glGetString", "const GLubyte *", [("GLenum", "name")]),
    ("glGetStringi", "const GLubyte *", [("GLenum", "name"), ("GLuint", "index")]),
    ("glCreateShader", "GLuint", [("GLenum", "type")]),
    ("glShaderSource", "void", [("GLuint", "shader"), ("GLsizei", "count"),
                                ("const GLchar *const *", "string"), ("const GLint *", "length")]),
    ("glCompileShader", "void", [("GLuint", "shader")]),
    ("glGetShaderiv", "void", [("GLuint", "shader"), ("GLenum", "pname"), ("GLint *", "params")]),
    ("glGetShaderInfoLog", "void", [("GLuint", "shader"), ("GLsizei", "bufsize"),
                                    ("GLsizei *", "length"), ("GLchar *", "infoLog")]),
    ("glDeleteShader", "void", [("GLuint", "shader")]),
    ("glCreateProgram", "GLuint", []),
    ("glAttachShader", "void", [("GLuint", "program"), ("GLuint", "shader")]),
    ("glLinkProgram", "void", [("GLuint", "program")]),
    ("glGetProgramiv", "void", [("GLuint", "program"), ("GLenum", "pname"), ("GLint *", "params")]),
    ("glGetProgramInfoLog", "void", [("GLuint", "program"), ("GLsizei", "bufsize"),
                                     ("GLsizei *", "length"), ("GLchar *", "infoLog")]),
    ("glDeleteProgram", "void", [("GLuint", "program")]),
    ("glUseProgram", "void", [("GLuint", "program")]),
    ("glGetUniformLocation", "GLint", [("GLuint", "program"), ("const GLchar *", "name")]),
    ("glGetAttribLocation", "GLint", [("GLuint", "program"), ("const GLchar *", "name")]),
    ("glBindAttribLocation", "void", [("GLuint", "program"), ("GLuint", "index"), ("const GLchar *", "name")]),
    ("glUniform1i", "void", [("GLint", "location"), ("GLint", "v0")]),
    ("glUniform1f", "void", [("GLint", "location"), ("GLfloat", "v0")]),
    ("glUniform2f", "void", [("GLint", "location"), ("GLfloat", "v0"), ("GLfloat", "v1")]),
    ("glUniform3f", "void", [("GLint", "location"), ("GLfloat", "v0"), ("GLfloat", "v1"), ("GLfloat", "v2")]),
    ("glUniform4f", "void", [("GLint", "location"), ("GLfloat", "v0"), ("GLfloat", "v1"),
                             ("GLfloat", "v2"), ("GLfloat", "v3")]),
    ("glUniform1fv", "void", [("GLint", "location"), ("GLsizei", "count"), ("const GLfloat *", "value")]),
    ("glUniform4fv", "void", [("GLint", "location"), ("GLsizei", "count"), ("const GLfloat *", "value")]),
    ("glUniformMatrix3fv", "void", [("GLint", "location"), ("GLsizei", "count"),
                                    ("GLboolean", "transpose"), ("const GLfloat *", "value")]),
    ("glUniformMatrix4fv", "void", [("GLint", "location"), ("GLsizei", "count"),
                                    ("GLboolean", "transpose"), ("const GLfloat *", "value")]),
    ("glGenBuffers", "void", [("GLsizei", "n"), ("GLuint *", "buffers")]),
    ("glBindBuffer", "void", [("GLenum", "target"), ("GLuint", "buffer")]),
    ("glBufferData", "void", [("GLenum", "target"), ("GLsizeiptr", "size"),
                              ("const void *", "data"), ("GLenum", "usage")]),
    ("glBufferSubData", "void", [("GLenum", "target"), ("GLintptr", "offset"),
                                 ("GLsizeiptr", "size"), ("const void *", "data")]),
    ("glDeleteBuffers", "void", [("GLsizei", "n"), ("const GLuint *", "buffers")]),
    ("glGenVertexArrays", "void", [("GLsizei", "n"), ("GLuint *", "arrays")]),
    ("glBindVertexArray", "void", [("GLuint", "array")]),
    ("glDeleteVertexArrays", "void", [("GLsizei", "n"), ("const GLuint *", "arrays")]),
    ("glVertexAttribPointer", "void", [("GLuint", "index"), ("GLint", "size"), ("GLenum", "type"),
                                       ("GLboolean", "normalized"), ("GLsizei", "stride"),
                                       ("const void *", "pointer")]),
    ("glEnableVertexAttribArray", "void", [("GLuint", "index")]),
    ("glDisableVertexAttribArray", "void", [("GLuint", "index")]),
    ("glVertexAttrib4f", "void", [("GLuint", "index"), ("GLfloat", "x"), ("GLfloat", "y"),
                                  ("GLfloat", "z"), ("GLfloat", "w")]),
    ("glDrawArrays", "void", [("GLenum", "mode"), ("GLint", "first"), ("GLsizei", "count")]),
    ("glDrawElements", "void", [("GLenum", "mode"), ("GLsizei", "count"),
                                ("GLenum", "type"), ("const void *", "indices")]),
    ("glGenTextures", "void", [("GLsizei", "n"), ("GLuint *", "textures")]),
    ("glBindTexture", "void", [("GLenum", "target"), ("GLuint", "texture")]),
    ("glTexImage2D", "void", [("GLenum", "target"), ("GLint", "level"), ("GLint", "internalformat"),
                              ("GLsizei", "width"), ("GLsizei", "height"), ("GLint", "border"),
                              ("GLenum", "format"), ("GLenum", "type"), ("const void *", "pixels")]),
    ("glTexSubImage2D", "void", [("GLenum", "target"), ("GLint", "level"), ("GLint", "xoffset"),
                                 ("GLint", "yoffset"), ("GLsizei", "width"), ("GLsizei", "height"),
                                 ("GLenum", "format"), ("GLenum", "type"), ("const void *", "pixels")]),
    ("glTexParameteri", "void", [("GLenum", "target"), ("GLenum", "pname"), ("GLint", "param")]),
    ("glTexParameterf", "void", [("GLenum", "target"), ("GLenum", "pname"), ("GLfloat", "param")]),
    ("glActiveTexture", "void", [("GLenum", "texture")]),
    ("glDeleteTextures", "void", [("GLsizei", "n"), ("const GLuint *", "textures")]),
    ("glGenerateMipmap", "void", [("GLenum", "target")]),
    ("glGenFramebuffers", "void", [("GLsizei", "n"), ("GLuint *", "framebuffers")]),
    ("glBindFramebuffer", "void", [("GLenum", "target"), ("GLuint", "framebuffer")]),
    ("glFramebufferTexture2D", "void", [("GLenum", "target"), ("GLenum", "attachment"),
                                        ("GLenum", "textarget"), ("GLuint", "texture"),
                                        ("GLint", "level")]),
    ("glCheckFramebufferStatus", "GLenum", [("GLenum", "target")]),
    ("glDeleteFramebuffers", "void", [("GLsizei", "n"), ("const GLuint *", "framebuffers")]),
    ("glViewport", "void", [("GLint", "x"), ("GLint", "y"), ("GLsizei", "width"), ("GLsizei", "height")]),
    ("glScissor", "void", [("GLint", "x"), ("GLint", "y"), ("GLsizei", "width"), ("GLsizei", "height")]),
    ("glClear", "void", [("GLbitfield", "mask")]),
    ("glClearColor", "void", [("GLfloat", "red"), ("GLfloat", "green"),
                              ("GLfloat", "blue"), ("GLfloat", "alpha")]),
    ("glClearDepthf", "void", [("GLfloat", "depth")]),
    ("glClearStencil", "void", [("GLint", "s")]),
    ("glEnable", "void", [("GLenum", "cap")]),
    ("glDisable", "void", [("GLenum", "cap")]),
    ("glBlendFunc", "void", [("GLenum", "sfactor"), ("GLenum", "dfactor")]),
    ("glBlendFuncSeparate", "void", [("GLenum", "sfactorRGB"), ("GLenum", "dfactorRGB"),
                                     ("GLenum", "sfactorAlpha"), ("GLenum", "dfactorAlpha")]),
    ("glPixelStorei", "void", [("GLenum", "pname"), ("GLint", "param")]),
    ("glReadPixels", "void", [("GLint", "x"), ("GLint", "y"), ("GLsizei", "width"),
                              ("GLsizei", "height"), ("GLenum", "format"),
                              ("GLenum", "type"), ("void *", "pixels")]),
    ("glFinish", "void", []),
    ("glFlush", "void", []),
    ("glGetError", "GLenum", []),
    ("glGetIntegerv", "void", [("GLenum", "pname"), ("GLint *", "data")]),
    ("glDepthMask", "void", [("GLboolean", "flag")]),
    ("glColorMask", "void", [("GLboolean", "r"), ("GLboolean", "g"),
                             ("GLboolean", "b"), ("GLboolean", "a")]),
    ("glDepthFunc", "void", [("GLenum", "func")]),
    ("glCullFace", "void", [("GLenum", "mode")]),
    ("glFrontFace", "void", [("GLenum", "mode")]),
    ("glStencilFunc", "void", [("GLenum", "func"), ("GLint", "ref"), ("GLuint", "mask")]),
    ("glStencilOp", "void", [("GLenum", "fail"), ("GLenum", "zfail"), ("GLenum", "zpass")]),
    ("glStencilMask", "void", [("GLuint", "mask")]),
]

HEADER = '''\
/* glshim.c -- AUTO-GENERATED by generate_glshim.py.  Do not edit by hand.
 *
 * LD_PRELOAD forwarding shim for the umi (Xiaomi Mi 10) Ubuntu Touch port.
 *
 * The Mir graphics-android2 platform creates its EGL context through
 * libhybris' android_dlsym() against the Android libEGL/libGLESv2 of the
 * container, while lomiri-system-compositor resolves GL entry points through
 * glvnd.  glvnd's dispatch table stays empty, so the first real GL call
 * (glCreateShader(GL_VERTEX_SHADER), x1 = 0x8b31) segfaults.
 *
 * Every GL entry point below is forwarded to the Android libGLESv2 obtained
 * with libhybris' android_dlopen()/android_dlsym(), so the context and the
 * function table come from the same driver instance.
 */
'''

BODY = r'''
#define RTLD_NEXT ((void *)-1l)
#define RTLD_NOW 2

extern void *dlsym(void *handle, const char *symbol);
extern int dprintf(int fd, const char *fmt, ...);
extern void *dlopen(const char *file, int mode);
extern int strcmp(const char *a, const char *b);

typedef void *(*dlopen_fn)(const char *, int);
typedef void *(*dlsym_fn)(void *, const char *);

static void *android_gles;
static void *hybris_handle;
static __thread int in_resolve;

#define RTLD_GLOBAL 0x100

static void *hybris_lib(void)
{
    if (!hybris_handle)
        hybris_handle = dlopen("libhybris-common.so.1", RTLD_NOW | RTLD_GLOBAL);
    return hybris_handle;
}

static void *android_handle(void)
{
    if (!android_gles) {
        void *hc = hybris_lib();
        dlopen_fn dl = hc ? (dlopen_fn)dlsym(hc, "android_dlopen") : 0;
        if (dl)
            android_gles = dl("libGLESv2.so", RTLD_NOW);
    }
    return android_gles;
}

static void *resolve(const char *name)
{
    void *hc, *h;
    dlsym_fn ds;

    if (in_resolve)
        return 0;
    in_resolve = 1;
    hc = hybris_lib();
    h = android_handle();
    ds = hc ? (dlsym_fn)dlsym(hc, "android_dlsym") : 0;
    in_resolve = 0;
    if (!h || !ds)
        return 0;
    return ds(h, name);
}

/* --- keep a current EGL context on every thread ---------------------------
 * lomiri-system-compositor calls GL from threads where the Android EGL
 * context has never been made current; the Android per-thread dispatch table
 * is then empty and glCreateShader jumps to a null pointer.
 * We remember the display/surface/context that the platform bound and re-bind
 * it on demand before forwarding a call.
 */
typedef void *EGLDisplay_;
typedef void *EGLSurface_;
typedef void *EGLContext_;
typedef unsigned int EGLBoolean_;

static EGLDisplay_ g_dpy;
static EGLSurface_ g_draw, g_read;
static EGLContext_ g_ctx;
static int g_have_ctx;
static int g_ctx_thread = -1; /* tid that owns the context, -1 = none */

extern long syscall(long number, ...);
#define UMI_SYS_gettid 178

static int umi_gettid(void) { return (int)syscall(UMI_SYS_gettid); }

static EGLBoolean_ (*android_eglMakeCurrent_)(EGLDisplay_, EGLSurface_, EGLSurface_, EGLContext_);
static void *(*real_android_dlsym_)(void *, const char *);

static void *get_android_dlsym(void)
{
    void *hc, *p;

    if (real_android_dlsym_)
        return real_android_dlsym_;
    hc = hybris_lib();
    if (hc) {
        p = dlsym(hc, "android_dlsym");
        if (p) {
            real_android_dlsym_ = (void *(*)(void *, const char *))p;
            return real_android_dlsym_;
        }
    }
    return 0;
}

static EGLBoolean_ (*host_eglMakeCurrent_)(EGLDisplay_, EGLSurface_, EGLSurface_, EGLContext_);

static EGLBoolean_ call_make_current(EGLDisplay_ dpy, EGLSurface_ draw,
                                     EGLSurface_ read, EGLContext_ ctx)
{
    if (android_eglMakeCurrent_)
        return android_eglMakeCurrent_(dpy, draw, read, ctx);
    if (host_eglMakeCurrent_)
        return host_eglMakeCurrent_(dpy, draw, read, ctx);
    return 0;
}

static EGLBoolean_ umi_eglMakeCurrent(EGLDisplay_ dpy, EGLSurface_ draw,
                                      EGLSurface_ read, EGLContext_ ctx)
{
    EGLBoolean_ r = call_make_current(dpy, draw, read, ctx);
    {
        static int n;
        if (n < 8) { n++; dprintf(2, "SHIM makeCurrent(dpy=%p ctx=%p) -> %d\n", dpy, ctx, r); }
    }
    if (ctx) {
        g_dpy = dpy;
        g_draw = draw;
        g_read = read;
        g_ctx = ctx;
        g_have_ctx = 1;
        g_ctx_thread = umi_gettid();
    } else {
        g_ctx_thread = -1;
    }
    return r;
}

void *android_dlsym(void *handle, const char *symbol)
{
    if (!in_resolve && strcmp(symbol, "eglMakeCurrent") == 0) {
        void *(*real)(void *, const char *) = get_android_dlsym();
        if (real) {
            android_eglMakeCurrent_ = (EGLBoolean_ (*)(EGLDisplay_, EGLSurface_, EGLSurface_,
                                                      EGLContext_))real(handle, symbol);
            return (void *)&umi_eglMakeCurrent;
        }
    }
    {
        void *(*real)(void *, const char *) = get_android_dlsym();
        return real ? real(handle, symbol) : 0;
    }
}

static void ensure_context(void)
{
    if (!g_have_ctx)
        return;
    if (g_ctx_thread == umi_gettid())
        return;
    /* Try the surface-bound form first; some drivers refuse to share a
     * surface between threads, so fall back to a context-only binding. */
    if (call_make_current(g_dpy, g_draw, g_read, g_ctx)) {
        g_ctx_thread = umi_gettid();
        return;
    }
    if (call_make_current(g_dpy, (EGLSurface_)0, (EGLSurface_)0, g_ctx)) {
        g_ctx_thread = umi_gettid();
        return;
    }
    {
        static int warned;
        if (!warned) {
            warned = 1;
            dprintf(2, "SHIM ensure_context: makeCurrent failed (dpy=%p ctx=%p)\n", g_dpy, g_ctx);
        }
    }
}

/* Interpose the host EGL entry point too: the platform may reach
 * eglMakeCurrent through a normal PLT call instead of android_dlsym(). */
EGLBoolean_ eglMakeCurrent(EGLDisplay_ dpy, EGLSurface_ draw, EGLSurface_ read,
                           EGLContext_ ctx)
{
    if (!host_eglMakeCurrent_)
        host_eglMakeCurrent_ = (EGLBoolean_ (*)(EGLDisplay_, EGLSurface_, EGLSurface_,
                                                EGLContext_))dlsym(RTLD_NEXT, "eglMakeCurrent");
    return umi_eglMakeCurrent(dpy, draw, read, ctx);
}
'''

GLSTRING_BODY = """\
const GLubyte * glGetString(GLenum name)
{
    static const GLubyte * (*fn)(GLenum name);
    if (!fn)
        fn = (const GLubyte * (*)(GLenum name))resolve("glGetString");
    if (fn) {
        const GLubyte *r = fn(name);
        if (r)
            return r;
    }
    /* The compositor probes GL strings when no context is current on its
     * thread; fall back to the known Adreno values. */
    switch (name) {
    case 0x1F00: return (const GLubyte *)"Qualcomm";
    case 0x1F01: return (const GLubyte *)"Adreno (TM) 650";
    case 0x1F02: return (const GLubyte *)"OpenGL ES 3.2";
    case 0x1F03: return (const GLubyte *)"OpenGL ES GLSL ES 3.20";
    default: return (const GLubyte *)0;
    }
}
"""


def emit(func):
    name, ret, args = func
    if name == "glGetString":
        return GLSTRING_BODY
    params = ", ".join(f"{t} {n}" for t, n in args) if args else "void"
    argnames = ", ".join(n for _, n in args)
    void = ret == "void"
    lines = []
    lines.append(f"{ret} {name}({params})")
    lines.append("{")
    lines.append(f"    static {ret} (*fn)({params});")
    lines.append("    ensure_context();")
    lines.append("    if (!fn)")
    lines.append(f"        fn = ({ret} (*)({params}))resolve(\"{name}\");")
    if void:
        lines.append("    if (fn)")
        lines.append(f"        fn({argnames});")
    else:
        lines.append("    if (!fn)")
        lines.append(f"        return ({ret})0;" if ret.endswith("*") else "        return 0;")
        lines.append(f"    return fn({argnames});")
    lines.append("}")
    return "\n".join(lines)

def main():
    print(HEADER)
    print(TYPES)
    print(BODY)
    for f in FUNCS:
        print(emit(f))

if __name__ == "__main__":
    main()
