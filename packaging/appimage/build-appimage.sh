#!/usr/bin/env bash
set -eo pipefail

echo "=========================================================="
echo "📦 Building Zalos AppImage"
echo "=========================================================="

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
ARCH="$(uname -m)"
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "${ARCH}-linux-gnu")"
BUILD_DIR="${WORKSPACE_DIR}/build-appimage"
APP_DIR="${BUILD_DIR}/AppDir"
OUTPUT_DIR="${WORKSPACE_DIR}/dist"
VERSION=$(grep -m1 'project(zalos VERSION' "${WORKSPACE_DIR}/CMakeLists.txt" | sed -E 's/.*VERSION ([0-9.]+).*/\1/')

mkdir -p "${BUILD_DIR}" "${APP_DIR}" "${OUTPUT_DIR}"

# 1. Compile with CMake (or reuse build-deb if already built in the same Ubuntu 24.04 environment)
DISTRO_STAMP="$(. /etc/os-release && echo "${ID}-${VERSION_ID}")"
BUILD_JOBS="$(nproc)"
if [ "${ZALOS_EMULATED:-0}" = "1" ] && [ "${BUILD_JOBS}" -gt 5 ]; then
    BUILD_JOBS=5
fi
CMAKE_BUILD_DIR="${BUILD_DIR}"
if [ -x "${WORKSPACE_DIR}/build-deb/zalos" ] && [ -f "${WORKSPACE_DIR}/build-deb/CMakeCache.txt" ] \
   && [ ! "${WORKSPACE_DIR}/CMakeLists.txt" -nt "${WORKSPACE_DIR}/build-deb/CMakeCache.txt" ]; then
    echo "==> Reusing Release build from build-deb..."
    CMAKE_BUILD_DIR="${WORKSPACE_DIR}/build-deb"
    cmake --build "${CMAKE_BUILD_DIR}" --config Release -j"${BUILD_JOBS}"
else
    echo "==> Configuring and compiling Zalos..."
    if [ -f "${CMAKE_BUILD_DIR}/CMakeCache.txt" ] && [ "$(cat "${CMAKE_BUILD_DIR}/.distro" 2>/dev/null)" != "${DISTRO_STAMP}" ]; then
        echo "==> Build tree from another distro: reconfiguring from scratch"
        rm -rf "${CMAKE_BUILD_DIR:?}"
    fi
    mkdir -p "${CMAKE_BUILD_DIR}"
    echo "${DISTRO_STAMP}" > "${CMAKE_BUILD_DIR}/.distro"
    cmake -B "${CMAKE_BUILD_DIR}" -S "${WORKSPACE_DIR}" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_TESTING=OFF \
        -DZALOS_QML_AOT=OFF

    cmake --build "${CMAKE_BUILD_DIR}" --config Release -j"${BUILD_JOBS}"
fi
rm -rf "${APP_DIR}"
DESTDIR="${APP_DIR}" cmake --install "${CMAKE_BUILD_DIR}" --strip

# Host-Qt fallbacks (for distros with host Qt but missing OpenSSL 3 or Qt WebP plugin)
mkdir -p "${APP_DIR}/usr/lib/openssl3-fallback"
CRYPTO_LIB=$(ldd "${APP_DIR}/usr/bin/zalos" | awk '/libcrypto\.so\.3/ {print $3}')
if [ -n "${CRYPTO_LIB}" ]; then
    cp -L "${CRYPTO_LIB}" "${APP_DIR}/usr/lib/openssl3-fallback/"
    echo "==> Bundled $(basename "${CRYPTO_LIB}")"
fi

OPUS_LIB=""
for cand in "/usr/lib/${MULTIARCH}/libopus.so.0" "/lib/${MULTIARCH}/libopus.so.0" "/usr/lib64/libopus.so.0" "/usr/lib/libopus.so.0"; do
    if [ -f "${cand}" ]; then
        OPUS_LIB="${cand}"
        break
    fi
done
if [ -n "${OPUS_LIB}" ]; then
    mkdir -p "${APP_DIR}/usr/lib/opus-fallback"
    cp -L "${OPUS_LIB}" "${APP_DIR}/usr/lib/opus-fallback/libopus.so.0"
    echo "==> Bundled libopus.so.0"
fi

echo "==> Bundling WebP image plugin (animated stickers fallback)..."
WEBP_DIR="${APP_DIR}/usr/lib/webp-fallback"
QT_PLUG_SRC=""
for cand in "/usr/lib/${MULTIARCH}/qt6/plugins" "/usr/lib64/qt6/plugins" "/usr/lib/qt6/plugins"; do
    if [ -d "${cand}/platforms" ]; then
        QT_PLUG_SRC="${cand}"
        break
    fi
done
if [ -z "${QT_PLUG_SRC}" ]; then
    QT_PLUG_SRC=$(find /usr/lib -type d -name imageformats -path "*qt6*" 2>/dev/null | head -1 | xargs -r dirname || true)
fi
QT_QML_SRC=""
for cand in "/usr/lib/${MULTIARCH}/qt6/qml" "/usr/lib64/qt6/qml" "/usr/lib/qt6/qml"; do
    if [ -d "${cand}/QtQuick" ]; then
        QT_QML_SRC="${cand}"
        break
    fi
done

WEBP_PLUGIN="${QT_PLUG_SRC}/imageformats/libqwebp.so"
if [ -f "${WEBP_PLUGIN}" ]; then
    mkdir -p "${WEBP_DIR}/imageformats"
    cp -L "${WEBP_PLUGIN}" "${WEBP_DIR}/imageformats/"
    ldd "${WEBP_PLUGIN}" | awk '/libwebp|libsharpyuv/ {print $3}' | while read -r lib; do
        [ -n "${lib}" ] && cp -L "${lib}" "${WEBP_DIR}/"
    done
    patchelf --set-rpath '$ORIGIN/..' "${WEBP_DIR}/imageformats/libqwebp.so"
    echo "==> Bundled libqwebp.so + $(ls "${WEBP_DIR}"/*.so* 2>/dev/null | wc -l) libwebp libraries"
fi

# 2. Bundle surgical Qt6 runtime fallback for hosts without Qt >= 6.4 or QML modules
echo "==> Bundling surgical Qt6 runtime fallback..."
QT_FALLBACK="${APP_DIR}/usr/lib/qt6-fallback"
mkdir -p "${QT_FALLBACK}/lib" "${QT_FALLBACK}/plugins" "${QT_FALLBACK}/qml"

copy_plugin() {
    local sub="$1" file="$2"
    if [ -f "${QT_PLUG_SRC}/${sub}/${file}" ]; then
        mkdir -p "${QT_FALLBACK}/plugins/${sub}"
        cp -L "${QT_PLUG_SRC}/${sub}/${file}" "${QT_FALLBACK}/plugins/${sub}/"
    fi
}

for p in libqxcb.so libqoffscreen.so libqwayland-generic.so; do
    copy_plugin platforms "$p"
done
for d in xcbglintegrations wayland-shell-integration wayland-graphics-integration-client platforminputcontexts; do
    if [ -d "${QT_PLUG_SRC}/${d}" ]; then
        mkdir -p "${QT_FALLBACK}/plugins/${d}"
        find "${QT_PLUG_SRC}/${d}" -maxdepth 1 -name '*.so' -exec cp -L {} "${QT_FALLBACK}/plugins/${d}/" \;
    fi
done
copy_plugin platformthemes libqxdgdesktopportal.so
copy_plugin sqldrivers libqsqlite.so
copy_plugin tls libqopensslbackend.so
copy_plugin tls libqcertonlybackend.so
for p in libqjpeg.so libqgif.so libqwebp.so libqsvg.so libqico.so; do
    copy_plugin imageformats "$p"
done
copy_plugin iconengines libqsvgicon.so

# Copy minimal QML runtime (Basic style only — exclude Material/Universal/Imagine/Fusion & designer/qmltypes)
for mod in QtCore QtQml QtMultimedia; do
    [ -d "${QT_QML_SRC}/${mod}" ] && cp -a "${QT_QML_SRC}/${mod}" "${QT_FALLBACK}/qml/"
done
mkdir -p "${QT_FALLBACK}/qml/QtQuick/Controls"
for f in qmldir libqtquick2plugin.so; do
    [ -f "${QT_QML_SRC}/QtQuick/${f}" ] && cp -L "${QT_QML_SRC}/QtQuick/${f}" "${QT_FALLBACK}/qml/QtQuick/"
done
for sub in Layouts Window Templates Shapes Dialogs; do
    [ -d "${QT_QML_SRC}/QtQuick/${sub}" ] && cp -a "${QT_QML_SRC}/QtQuick/${sub}" "${QT_FALLBACK}/qml/QtQuick/"
done
for f in qmldir libqtquickcontrols2plugin.so; do
    [ -f "${QT_QML_SRC}/QtQuick/Controls/${f}" ] && cp -L "${QT_QML_SRC}/QtQuick/Controls/${f}" "${QT_FALLBACK}/qml/QtQuick/Controls/"
done
for sub in Basic impl; do
    [ -d "${QT_QML_SRC}/QtQuick/Controls/${sub}" ] && cp -a "${QT_QML_SRC}/QtQuick/Controls/${sub}" "${QT_FALLBACK}/qml/QtQuick/Controls/"
done
find "${QT_FALLBACK}/qml" -type d -name designer -prune -exec rm -rf {} +
find "${QT_FALLBACK}/qml" -type f -name '*.qmltypes' -delete

# Resolve non-excludelist / non-base-OS shared libraries iteratively
is_excluded_lib() {
    case "$1" in
        linux-vdso.so*|ld-linux-*.so*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|\
        libresolv.so*|libutil.so*|libnsl.so*|libanl.so*|libcrypt.so*|libstdc++.so*|libgcc_s.so*|\
        libGL.so*|libGLX.so*|libGLdispatch.so*|libOpenGL.so*|libEGL.so*|libvulkan.so*|libdrm*.so*|libgbm.so*|libwayland-*.so*|\
        libX11.so*|libX11-xcb.so*|libXau.so*|libXdmcp.so*|libXext.so*|libXfixes.so*|libXrender.so*|libXrandr.so*|\
        libXi.so*|libXcursor.so*|libXinerama.so*|libICE.so*|libSM.so*|\
        libxcb.so*|libxcb-dri*.so*|libxcb-present.so*|\
        libglib-2.0.so*|libgobject-2.0.so*|libgio-2.0.so*|libgmodule-2.0.so*|libdbus-1.so*|libsystemd.so*|libudev.so*|\
        libcap.so*|libuuid.so*|libselinux.so*|libmount.so*|libblkid.so*|libapparmor.so*|libffi.so*|libpcre2-8.so*|\
        libfontconfig.so*|libfreetype.so*|libexpat.so*|libfribidi.so*|\
        libz.so*|libzstd.so*|liblzma.so*|liblz4.so*|libbz2.so*|libbrotli*.so*|libpng16.so*|libxkbcommon.so*|\
        libgssapi_krb5.so*|libkrb5*.so*|libk5crypto.so*|libcom_err.so*|libkeyutils.so*|libssl.so*|libcrypto.so*|\
        libpulse*.so*|libasound.so*|libsndfile.so*|libFLAC.so*|libvorbis*.so*|libogg.so*|libopus.so*|\
        libmp3lame.so*|libmpg123.so*|libasyncns.so*|libpipewire-*.so*|libjack*.so*|\
        libicu*.so*|libproxy.so*|libpxbackend-*.so*|libcurl*.so*|libduktape.so*|libunistring.so*|\
        libidn2.so*|libpsl.so*|libssh.so*|librtmp.so*|libnghttp2.so*|libldap*.so*|liblber*.so*|\
        libsasl2.so*|libgnutls.so*|libnettle.so*|libhogweed.so*|libtasn1.so*|libp11-kit.so*|\
        libgcrypt.so*|libgpg-error.so*|libgmp.so*|libbsd.so*|libmd.so*|libzalos-glibc-compat.so)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

collect_deps_pass() {
    local added=0
    local roots=(
        "${APP_DIR}/usr/bin/zalos"
        "${APP_DIR}/usr/libexec/zalos/"*
    )
    while IFS= read -r -d '' f; do
        roots+=("$f")
    done < <(find "${QT_FALLBACK}/plugins" "${QT_FALLBACK}/qml" "${QT_FALLBACK}/lib" -type f -name '*.so*' -print0 2>/dev/null)

    while read -r name path; do
        [ -n "${name}" ] && [ -f "${path}" ] || continue
        if is_excluded_lib "${name}"; then
            continue
        fi
        if [ ! -e "${QT_FALLBACK}/lib/${name}" ]; then
            cp -L "${path}" "${QT_FALLBACK}/lib/${name}"
            added=1
        fi
    done < <(ldd "${roots[@]}" 2>/dev/null | awk '/=> \// {print $1, $3}' | sort -u)
    return "${added}"
}

while true; do
    if collect_deps_pass; then
        break
    fi
done
echo "==> Bundled $(ls "${QT_FALLBACK}/lib"/*.so* 2>/dev/null | wc -l) Qt6 & helper shared libraries"

# 3. Compile runtime compatibility shims (glibc 2.38 / GLIBCXX 3.4.32 + dynamic host-ICU + libproxy)
SHIM_TMP="$(mktemp -d)"
trap 'rm -rf "${SHIM_TMP}"' EXIT

mkdir -p "${APP_DIR}/usr/lib"
cat > "${SHIM_TMP}/glibc_compat.c" <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

extern long real_strtol(const char *, char **, int) __asm__("strtol");
extern unsigned long real_strtoul(const char *, char **, int) __asm__("strtoul");
extern long long real_strtoll(const char *, char **, int) __asm__("strtoll");
extern unsigned long long real_strtoull(const char *, char **, int) __asm__("strtoull");
extern intmax_t real_strtoimax(const char *, char **, int) __asm__("strtoimax");
extern uintmax_t real_strtoumax(const char *, char **, int) __asm__("strtoumax");
extern int real_vsscanf(const char *, const char *, va_list) __asm__("__isoc99_vsscanf");
extern int real_vfscanf(void *, const char *, va_list) __asm__("__isoc99_vfscanf");

long __isoc23_strtol(const char *s, char **e, int b) { return real_strtol(s, e, b); }
unsigned long __isoc23_strtoul(const char *s, char **e, int b) { return real_strtoul(s, e, b); }
long long __isoc23_strtoll(const char *s, char **e, int b) { return real_strtoll(s, e, b); }
unsigned long long __isoc23_strtoull(const char *s, char **e, int b) { return real_strtoull(s, e, b); }
intmax_t __isoc23_strtoimax(const char *s, char **e, int b) { return real_strtoimax(s, e, b); }
uintmax_t __isoc23_strtoumax(const char *s, char **e, int b) { return real_strtoumax(s, e, b); }

int __isoc23_vsscanf(const char *s, const char *fmt, va_list ap) {
    return real_vsscanf(s, fmt, ap);
}

int __isoc23_sscanf(const char *s, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = real_vsscanf(s, fmt, ap);
    va_end(ap);
    return r;
}

int __isoc23_vfscanf(void *fp, const char *fmt, va_list ap) {
    return real_vfscanf(fp, fmt, ap);
}

int __isoc23_fscanf(void *fp, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int r = real_vfscanf(fp, fmt, ap);
    va_end(ap);
    return r;
}

void arc4random_buf(void *buf, size_t n) {
    uint8_t *p = (uint8_t *)buf;
    while (n > 0) {
        size_t chunk = n > 256 ? 256 : n;
        if (getentropy(p, chunk) != 0) break;
        p += chunk;
        n -= chunk;
    }
}

uint32_t arc4random(void) {
    uint32_t v = 0;
    arc4random_buf(&v, sizeof(v));
    return v;
}

void __attribute__((constructor(101))) _ZSt21ios_base_library_initv(void) {
    static int done = 0;
    static unsigned long long io_init[8];
    if (__atomic_exchange_n(&done, 1, __ATOMIC_ACQ_REL)) return;
    typedef void (*fn_t)(void);
    fn_t next_fn = (fn_t)dlsym(RTLD_NEXT, "_ZSt21ios_base_library_initv");
    if (next_fn && next_fn != &_ZSt21ios_base_library_initv) {
        next_fn();
        return;
    }
    typedef void (*ctor_t)(void *);
    ctor_t ctor = (ctor_t)dlsym(RTLD_DEFAULT, "_ZNSt8ios_base4InitC1Ev");
    if (ctor) ctor(io_init);
}
EOF
gcc -O2 -shared -fPIC -Wall -Wextra "${SHIM_TMP}/glibc_compat.c" \
    -Wl,-soname,libzalos-glibc-compat.so -ldl -o "${APP_DIR}/usr/lib/libzalos-glibc-compat.so"

# Dynamic ICU forwarding shims (delegates to host libicuuc/libicui18n of any version 58..90; saves ~30 MB)
QT_CORE_BUNDLED="${QT_FALLBACK}/lib/libQt6Core.so.6"
ICU_SONAMES="$(readelf -d "${QT_CORE_BUNDLED}" | awk -F'[][]' '/NEEDED.*libicu/ {print $2}')"
ICU_VER="$(echo "${ICU_SONAMES}" | grep -oE '\.so\.[0-9]+' | grep -oE '[0-9]+' | head -n1)"
rm -f "${QT_FALLBACK}/lib/libicu"*.so*
if [ -n "${ICU_VER}" ]; then
    echo "==> Building dynamic host-ICU forwarding shims for ICU ABI .${ICU_VER}..."
    python3 - "${QT_CORE_BUNDLED}" "/usr/lib/${MULTIARCH}" "${ICU_VER}" "${SHIM_TMP}" <<'PY'
import os, re, subprocess, sys

qt_core, sys_lib, ver, out_dir = sys.argv[1:5]
und_out = subprocess.check_output(["objdump", "-T", qt_core], text=True)
syms = sorted({
    m.group(1)
    for line in und_out.splitlines()
    if "*UND*" in line
    for m in [re.search(rf"\b([A-Za-z0-9_]+_{re.escape(ver)})$", line)]
    if m
})

def exported(so_name):
    for d in [sys_lib, f"/lib/{os.path.basename(sys_lib)}", "/usr/lib64", "/lib64", "/usr/lib", "/lib"]:
        p = os.path.join(d, so_name)
        if os.path.exists(p):
            out = subprocess.check_output(["nm", "-D", "--defined-only", p], text=True)
            return {l.split()[-1] for l in out.splitlines() if l.strip()}
    return set()

uc_exports = exported(f"libicuuc.so.{ver}")
i18n_exports = exported(f"libicui18n.so.{ver}")
uc_syms = [s for s in syms if s in uc_exports]
i18n_syms = [s for s in syms if s in i18n_exports and s not in uc_exports]

header = r"""#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static void *g_uc = NULL;
static void *g_i18n = NULL;
static int g_host_ver = 0;

static const char *const kHostDirs[] = {
#if defined(__aarch64__)
    "/lib/aarch64-linux-gnu", "/usr/lib/aarch64-linux-gnu",
#elif defined(__x86_64__)
    "/lib/x86_64-linux-gnu", "/usr/lib/x86_64-linux-gnu",
#endif
    "/usr/lib64", "/lib64", "/usr/lib", "/lib"
};

static void icu_init(void) {
    char p1[256], p2[256];
    for (int v = 90; v >= 58; --v) {
        for (size_t i = 0; i < sizeof(kHostDirs) / sizeof(kHostDirs[0]); ++i) {
            snprintf(p1, sizeof(p1), "%s/libicuuc.so.%d", kHostDirs[i], v);
            void *uc = dlopen(p1, RTLD_NOW | RTLD_GLOBAL);
            if (!uc) continue;
            snprintf(p2, sizeof(p2), "%s/libicui18n.so.%d", kHostDirs[i], v);
            void *i18n = dlopen(p2, RTLD_NOW | RTLD_GLOBAL);
            if (i18n) {
                g_uc = uc;
                g_i18n = i18n;
                g_host_ver = v;
                return;
            }
        }
    }
    for (int v = 90; v >= 58; --v) {
        if (v == ICU_SHIM_VER) continue;
        snprintf(p1, sizeof(p1), "libicuuc.so.%d", v);
        void *uc = dlopen(p1, RTLD_NOW | RTLD_GLOBAL);
        if (!uc) continue;
        snprintf(p2, sizeof(p2), "libicui18n.so.%d", v);
        void *i18n = dlopen(p2, RTLD_NOW | RTLD_GLOBAL);
        if (i18n) {
            g_uc = uc;
            g_i18n = i18n;
            g_host_ver = v;
            return;
        }
    }
}

static void *resolve_sym(void **handle, const char *base) {
    pthread_once(&g_once, icu_init);
    if (!*handle || g_host_ver <= 0) return NULL;
    char name[256];
    snprintf(name, sizeof(name), "%s_%d", base, g_host_ver);
    return dlsym(*handle, name);
}
""".replace("ICU_SHIM_VER", ver)

def emit_c(path, sym_list, handle_expr):
    lines = [header]
    suffix = f"_{ver}"
    for s in sym_list:
        base = s[:-len(suffix)]
        if base == "ucal_setMillis":
            lines.append(f"""void {s}(void *cal, double dt, int32_t *st) {{
    typedef void (*fn_t)(void *, double, int32_t *);
    fn_t fn = (fn_t)resolve_sym(&{handle_expr}, "{base}");
    if (fn) {{ fn(cal, dt, st); return; }}
    if (st && *st <= 0) *st = 16;
}}""")
        else:
            lines.append(f"""uintptr_t {s}(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3,
                         uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7,
                         uintptr_t a8, uintptr_t a9) {{
    typedef uintptr_t (*fn_t)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t,
                              uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);
    fn_t fn = (fn_t)resolve_sym(&{handle_expr}, "{base}");
    if (fn) return fn(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9);
    return 0;
}}""")
    with open(path, "w") as fp:
        fp.write("\n".join(lines) + "\n")

emit_c(os.path.join(out_dir, "icuuc_shim.c"), uc_syms, "g_uc")
emit_c(os.path.join(out_dir, "icui18n_shim.c"), i18n_syms, "g_i18n")
print(f"Generated {len(uc_syms)} libicuuc + {len(i18n_syms)} libicui18n shims")
PY

    gcc -O2 -shared -fPIC "${SHIM_TMP}/icuuc_shim.c" \
        -Wl,-soname,"libicuuc.so.${ICU_VER}" -ldl -lpthread -o "${QT_FALLBACK}/lib/libicuuc.so.${ICU_VER}"
    gcc -O2 -shared -fPIC "${SHIM_TMP}/icui18n_shim.c" \
        -Wl,-soname,"libicui18n.so.${ICU_VER}" -ldl -lpthread -o "${QT_FALLBACK}/lib/libicui18n.so.${ICU_VER}"
    gcc -O2 -shared -fPIC -x c - -Wl,-soname,"libicudata.so.${ICU_VER}" \
        -o "${QT_FALLBACK}/lib/libicudata.so.${ICU_VER}" </dev/null
fi

# Lightweight libproxy.so.1 shim (avoids pulling 5+ MB of libpxbackend/curl/duktape/unistring/ldap)
cat > "${SHIM_TMP}/proxy_shim.c" <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static void *g_lib = NULL;
static void *(*real_new)(void) = NULL;
static char **(*real_get)(void *, const char *) = NULL;
static void (*real_free)(void *) = NULL;
static void (*real_free_proxies)(char **) = NULL;

static void proxy_init(void) {
    static const char *const paths[] = {
#if defined(__aarch64__)
        "/usr/lib/aarch64-linux-gnu/libproxy.so.1", "/lib/aarch64-linux-gnu/libproxy.so.1",
#elif defined(__x86_64__)
        "/usr/lib/x86_64-linux-gnu/libproxy.so.1", "/lib/x86_64-linux-gnu/libproxy.so.1",
#endif
        "/usr/lib64/libproxy.so.1", "/lib64/libproxy.so.1", "/usr/lib/libproxy.so.1"
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); ++i) {
        g_lib = dlopen(paths[i], RTLD_LAZY | RTLD_LOCAL);
        if (g_lib) {
            real_new = dlsym(g_lib, "px_proxy_factory_new");
            real_get = dlsym(g_lib, "px_proxy_factory_get_proxies");
            real_free = dlsym(g_lib, "px_proxy_factory_free");
            real_free_proxies = dlsym(g_lib, "px_proxy_factory_free_proxies");
            if (real_new && real_get && real_free) return;
            dlclose(g_lib);
            g_lib = NULL;
        }
    }
}

void *px_proxy_factory_new(void) {
    pthread_once(&g_once, proxy_init);
    if (real_new) return real_new();
    return malloc(1);
}

char **px_proxy_factory_get_proxies(void *pf, const char *url) {
    pthread_once(&g_once, proxy_init);
    if (real_get) return real_get(pf, url);
    const char *env = NULL;
    if (url && strncmp(url, "https://", 8) == 0) env = getenv("https_proxy");
    if (!env && url && strncmp(url, "http://", 7) == 0) env = getenv("http_proxy");
    if (!env) env = getenv("all_proxy");
    if (!env) env = getenv("ALL_PROXY");
    char **res = (char **)calloc(2, sizeof(char *));
    if (!res) return NULL;
    res[0] = strdup((env && *env) ? env : "direct://");
    res[1] = NULL;
    return res;
}

void px_proxy_factory_free_proxies(char **proxies) {
    if (real_free_proxies) { real_free_proxies(proxies); return; }
    if (!proxies) return;
    for (size_t i = 0; proxies[i]; ++i) free(proxies[i]);
    free(proxies);
}

void px_proxy_factory_free(void *pf) {
    if (real_free) { real_free(pf); return; }
    free(pf);
}
EOF
cat > "${SHIM_TMP}/proxy.map" <<'EOF'
LIBPROXY_0.4.16 {
    global: *;
};
EOF
gcc -O2 -shared -fPIC "${SHIM_TMP}/proxy_shim.c" \
    -Wl,-soname,libproxy.so.1 -Wl,--version-script,"${SHIM_TMP}/proxy.map" \
    -ldl -lpthread -o "${QT_FALLBACK}/lib/libproxy.so.1"

# 4. ELF version scrubber: rewrite GLIBC >= 2.36 / GLIBCXX >= 3.4.31 / CXXABI >= 1.3.14 to Base (glibc 2.35 floor)
cat > "${SHIM_TMP}/elf_compat_patch.c" <<'EOF'
#include <elf.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static int is_too_new_ver(const char *v) {
    int a = 0, b = 0, c = 0;
    if (sscanf(v, "GLIBC_%d.%d.%d", &a, &b, &c) >= 2 || sscanf(v, "GLIBC_%d.%d", &a, &b) == 2) {
        return a > 2 || (a == 2 && b > 35);
    }
    if (sscanf(v, "GLIBCXX_%d.%d.%d", &a, &b, &c) == 3) {
        return a > 3 || (a == 3 && (b > 4 || (b == 4 && c > 30)));
    }
    if (sscanf(v, "CXXABI_%d.%d.%d", &a, &b, &c) == 3) {
        return a > 1 || (a == 1 && (b > 3 || (b == 3 && c > 13)));
    }
    return 0;
}

static int is_allowed_compat_sym(const char *name) {
    if (strcmp(name, "fmod") == 0 || strcmp(name, "fmodf") == 0 || strcmp(name, "fmodl") == 0) return 1;
    if (strncmp(name, "__isoc23_", 9) == 0) return 1;
    if (strncmp(name, "arc4random", 10) == 0) return 1;
    if (strcmp(name, "_ZSt21ios_base_library_initv") == 0) return 1;
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int fd = open(argv[1], O_RDWR);
    if (fd < 0) { perror(argv[1]); return 1; }
    struct stat st;
    if (fstat(fd, &st) != 0) { perror("fstat"); close(fd); return 1; }
    if ((size_t)st.st_size < sizeof(Elf64_Ehdr)) { close(fd); return 0; }

    uint8_t *base = mmap(NULL, (size_t)st.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (base == MAP_FAILED) { perror("mmap"); close(fd); return 1; }

    if (memcmp(base, ELFMAG, SELFMAG) != 0 || base[EI_CLASS] != ELFCLASS64) {
        munmap(base, (size_t)st.st_size);
        close(fd);
        return 0;
    }

    Elf64_Ehdr *eh = (Elf64_Ehdr *)base;
    if (eh->e_type != ET_EXEC && eh->e_type != ET_DYN) {
        munmap(base, (size_t)st.st_size);
        close(fd);
        return 0;
    }
    Elf64_Shdr *sh = (Elf64_Shdr *)(base + eh->e_shoff);
    Elf64_Shdr *dynsym_sh = NULL, *dynstr_sh = NULL, *versym_sh = NULL, *verneed_sh = NULL, *dynamic_sh = NULL;

    for (int i = 0; i < eh->e_shnum; ++i) {
        if (sh[i].sh_type == SHT_DYNSYM) {
            dynsym_sh = &sh[i];
            if (sh[i].sh_link < eh->e_shnum) dynstr_sh = &sh[sh[i].sh_link];
        } else if (sh[i].sh_type == SHT_GNU_versym) {
            versym_sh = &sh[i];
        } else if (sh[i].sh_type == SHT_GNU_verneed) {
            verneed_sh = &sh[i];
        } else if (sh[i].sh_type == SHT_DYNAMIC) {
            dynamic_sh = &sh[i];
        }
    }

    if (!dynsym_sh || !dynstr_sh || !versym_sh || !verneed_sh) {
        munmap(base, (size_t)st.st_size);
        close(fd);
        return 0;
    }

    const char *dynstr = (const char *)(base + dynstr_sh->sh_offset);
    size_t dynstr_sz = dynstr_sh->sh_size;
    Elf64_Sym *syms = (Elf64_Sym *)(base + dynsym_sh->sh_offset);
    size_t nsyms = dynsym_sh->sh_size / sizeof(Elf64_Sym);
    Elf64_Half *versym = (Elf64_Half *)(base + versym_sh->sh_offset);

    uint8_t bad_idx[65536];
    memset(bad_idx, 0, sizeof(bad_idx));
    int has_bad = 0;

    uint8_t *vn_start = base + verneed_sh->sh_offset;
    size_t vn_sz = verneed_sh->sh_size;
    size_t vn_pos = 0;
    for (Elf64_Word n = 0; n < verneed_sh->sh_info && vn_pos + sizeof(Elf64_Verneed) <= vn_sz; ++n) {
        Elf64_Verneed *vn = (Elf64_Verneed *)(vn_start + vn_pos);
        size_t aux_pos = vn_pos + vn->vn_aux;
        for (Elf64_Half a = 0; a < vn->vn_cnt && aux_pos + sizeof(Elf64_Vernaux) <= vn_sz; ++a) {
            Elf64_Vernaux *aux = (Elf64_Vernaux *)(vn_start + aux_pos);
            if (aux->vna_name < dynstr_sz) {
                const char *vname = dynstr + aux->vna_name;
                if (is_too_new_ver(vname)) {
                    Elf64_Half idx = aux->vna_other & 0x7fff;
                    bad_idx[idx] = 1;
                    has_bad = 1;
                }
            }
            if (aux->vna_next == 0) break;
            aux_pos += aux->vna_next;
        }
        if (vn->vn_next == 0) break;
        vn_pos += vn->vn_next;
    }

    if (!has_bad) {
        munmap(base, (size_t)st.st_size);
        close(fd);
        return 0;
    }

    for (size_t i = 0; i < nsyms; ++i) {
        if (syms[i].st_shndx != SHN_UNDEF) continue;
        Elf64_Half idx = versym[i] & 0x7fff;
        if (!bad_idx[idx]) continue;
        const char *sname = (syms[i].st_name < dynstr_sz) ? (dynstr + syms[i].st_name) : "";
        if (!is_allowed_compat_sym(sname)) {
            fprintf(stderr, "❌ Unhandled newer glibc/GLIBCXX symbol in %s: %s\n", argv[1], sname);
            munmap(base, (size_t)st.st_size);
            close(fd);
            return 1;
        }
        versym[i] = 1;
    }

    uint8_t *rebuilt = (uint8_t *)calloc(1, vn_sz);
    if (!rebuilt) { munmap(base, (size_t)st.st_size); close(fd); return 1; }

    size_t out_pos = 0;
    Elf64_Word kept_vn_cnt = 0;
    Elf64_Verneed *prev_out_vn = NULL;

    vn_pos = 0;
    for (Elf64_Word n = 0; n < verneed_sh->sh_info && vn_pos + sizeof(Elf64_Verneed) <= vn_sz; ++n) {
        Elf64_Verneed *vn = (Elf64_Verneed *)(vn_start + vn_pos);
        Elf64_Verneed *out_vn = (Elf64_Verneed *)(rebuilt + out_pos);
        size_t aux_write = out_pos + sizeof(Elf64_Verneed);
        Elf64_Half kept_aux = 0;
        Elf64_Vernaux *prev_out_aux = NULL;

        size_t aux_pos = vn_pos + vn->vn_aux;
        for (Elf64_Half a = 0; a < vn->vn_cnt && aux_pos + sizeof(Elf64_Vernaux) <= vn_sz; ++a) {
            Elf64_Vernaux *aux = (Elf64_Vernaux *)(vn_start + aux_pos);
            Elf64_Half idx = aux->vna_other & 0x7fff;
            if (!bad_idx[idx]) {
                Elf64_Vernaux *dst = (Elf64_Vernaux *)(rebuilt + aux_write);
                *dst = *aux;
                dst->vna_next = 0;
                if (prev_out_aux) {
                    prev_out_aux->vna_next = (Elf64_Word)((uint8_t *)dst - (uint8_t *)prev_out_aux);
                }
                prev_out_aux = dst;
                aux_write += sizeof(Elf64_Vernaux);
                kept_aux++;
            }
            if (aux->vna_next == 0) break;
            aux_pos += aux->vna_next;
        }

        if (kept_aux > 0) {
            *out_vn = *vn;
            out_vn->vn_cnt = kept_aux;
            out_vn->vn_aux = (Elf64_Word)sizeof(Elf64_Verneed);
            out_vn->vn_next = 0;
            if (prev_out_vn) {
                prev_out_vn->vn_next = (Elf64_Word)((uint8_t *)out_vn - (uint8_t *)prev_out_vn);
            }
            prev_out_vn = out_vn;
            out_pos = aux_write;
            kept_vn_cnt++;
        }

        if (vn->vn_next == 0) break;
        vn_pos += vn->vn_next;
    }

    memcpy(vn_start, rebuilt, vn_sz);
    free(rebuilt);
    verneed_sh->sh_info = kept_vn_cnt;

    if (dynamic_sh) {
        Elf64_Dyn *dyn = (Elf64_Dyn *)(base + dynamic_sh->sh_offset);
        size_t ndyn = dynamic_sh->sh_size / sizeof(Elf64_Dyn);
        if (kept_vn_cnt > 0) {
            for (size_t i = 0; i < ndyn && dyn[i].d_tag != DT_NULL; ++i) {
                if (dyn[i].d_tag == DT_VERNEEDNUM) {
                    dyn[i].d_un.d_val = kept_vn_cnt;
                }
            }
        } else {
            size_t w = 0;
            for (size_t i = 0; i < ndyn && dyn[i].d_tag != DT_NULL; ++i) {
                if (dyn[i].d_tag == DT_VERNEED || dyn[i].d_tag == DT_VERNEEDNUM) continue;
                dyn[w++] = dyn[i];
            }
            while (w < ndyn) {
                dyn[w].d_tag = DT_NULL;
                dyn[w].d_un.d_val = 0;
                w++;
            }
        }
    }

    msync(base, (size_t)st.st_size, MS_SYNC);
    munmap(base, (size_t)st.st_size);
    close(fd);
    return 0;
}
EOF
gcc -O2 -Wall -Wextra "${SHIM_TMP}/elf_compat_patch.c" -o "${SHIM_TMP}/elf-compat-patch"

# 5. Normalize RPATHs, add DT_NEEDED libzalos-glibc-compat.so where needed, scrub glibc/GLIBCXX versions, strip
echo "==> Patching RPATHs & scrubbing glibc > 2.35 / GLIBCXX > 3.4.30 references..."
python3 - "${APP_DIR}" "${QT_FALLBACK}" "${SHIM_TMP}/elf-compat-patch" <<'PY'
import os, re, subprocess, sys

app_dir, qt_fallback, patcher = sys.argv[1:4]
qt_lib = os.path.join(qt_fallback, "lib")
usr_lib = os.path.join(app_dir, "usr", "lib")

compat_sym_re = re.compile(r"\*UND\*.*\b(__isoc23_[A-Za-z0-9_]+|arc4random[A-Za-z0-9_]*|_ZSt21ios_base_library_initv)\b")

def is_elf(path):
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as fp:
            return fp.read(4) == b"\x7fELF"
    except OSError:
        return False

for root_dir, _, files in os.walk(app_dir):
    for fn in sorted(files):
        p = os.path.join(root_dir, fn)
        if not is_elf(p):
            continue
        bn = os.path.basename(p)
        if bn in ("libzalos-glibc-compat.so", "libproxy.so.1") or bn.startswith("libicu"):
            continue

        rel_from_dir = os.path.relpath(usr_lib, root_dir)
        rpath_usr = "$ORIGIN" if rel_from_dir == "." else "$ORIGIN/" + rel_from_dir

        if p.startswith(qt_fallback + "/"):
            rel_qt = os.path.relpath(qt_lib, root_dir)
            rpath_qt = "$ORIGIN" if rel_qt == "." else "$ORIGIN/" + rel_qt
            rpath = f"{rpath_qt}:{rpath_usr}"
        elif p.startswith(os.path.join(usr_lib, "webp-fallback") + "/"):
            rel_webp = os.path.relpath(os.path.join(usr_lib, "webp-fallback"), root_dir)
            rpath = ("$ORIGIN" if rel_webp == "." else "$ORIGIN/" + rel_webp) + f":{rpath_usr}"
        else:
            rpath = rpath_usr

        subprocess.check_call(["patchelf", "--set-rpath", rpath, p])

        need_compat = (
            p == os.path.join(app_dir, "usr", "bin", "zalos")
            or p.startswith(os.path.join(app_dir, "usr", "libexec", "zalos") + "/")
        )
        if not need_compat:
            und = subprocess.check_output(["objdump", "-T", p], text=True, stderr=subprocess.DEVNULL)
            need_compat = bool(compat_sym_re.search(und))
        if need_compat:
            needed = subprocess.check_output(["patchelf", "--print-needed", p], text=True).splitlines()
            if "libzalos-glibc-compat.so" not in needed:
                subprocess.check_call(["patchelf", "--add-needed", "libzalos-glibc-compat.so", p])

        subprocess.check_call([patcher, p])

        if ".so" in bn:
            subprocess.run(["strip", "--strip-unneeded", p], check=False)
PY

strip --strip-unneeded "${APP_DIR}/usr/lib/libzalos-glibc-compat.so" \
    "${QT_FALLBACK}/lib/libicu"*.so* "${QT_FALLBACK}/lib/libproxy.so.1"

# Verify zero > GLIBC_2.35 / GLIBCXX_3.4.30 / CXXABI_1.3.13 remain anywhere in AppDir
BAD_SYMS="$(find "${APP_DIR}" -type f -exec sh -c 'objdump -T "$1" 2>/dev/null | awk "/\*UND\*/ && /(GLIBC_2\.(3[6-9]|[4-9][0-9])|GLIBCXX_3\.4\.(3[1-9]|[4-9][0-9])|CXXABI_1\.3\.(1[4-9]|[2-9][0-9]))/ {print FILENAME \": \" \$0}"' _ {} \;)"
if [ -n "${BAD_SYMS}" ]; then
    echo "❌ Remaining newer glibc/GLIBCXX symbols in AppDir:"
    echo "${BAD_SYMS}"
    exit 1
fi
echo "✅ Zero GLIBC > 2.35 or GLIBCXX > 3.4.30 references in AppDir."

# 6. Setup AppDir metadata (single *appdata.xml matching <id>)
echo "==> Preparing AppDir metadata..."
cp "${WORKSPACE_DIR}/packaging/appimage/AppRun" "${APP_DIR}/AppRun"
chmod +x "${APP_DIR}/AppRun"

cp "${WORKSPACE_DIR}/assets/zalos.desktop" "${APP_DIR}/zalos.desktop"
cp "${WORKSPACE_DIR}/assets/icons/zalos.svg" "${APP_DIR}/zalos.svg"
mkdir -p "${APP_DIR}/usr/share/metainfo"
rm -f "${APP_DIR}/usr/share/metainfo/"*.xml
cp "${WORKSPACE_DIR}/assets/metainfo/io.github.cpfriend1721994.zalos.metainfo.xml" \
    "${APP_DIR}/usr/share/metainfo/io.github.cpfriend1721994.zalos.appdata.xml"

if command -v rsvg-convert &>/dev/null; then
    rsvg-convert -w 256 -h 256 "${WORKSPACE_DIR}/assets/icons/zalos.svg" -o "${APP_DIR}/zalos.png"
    cp "${APP_DIR}/zalos.png" "${APP_DIR}/.DirIcon"
fi

# 7. Download appimagetool if not present (architecture-matched: x86_64 or aarch64)
mkdir -p /tmp/tools
TOOL="/tmp/tools/appimagetool-${ARCH}"
if [ ! -f "${TOOL}" ]; then
    echo "==> Downloading appimagetool (${ARCH})..."
    if ! curl -sSfL --retry 5 --retry-delay 3 --retry-all-errors -o "${TOOL}" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"; then
        echo "==> appimagetool download failed (no network access to github.com from this environment)"
        rm -f "${TOOL}"
    fi
    [ -f "${TOOL}" ] && chmod +x "${TOOL}" || true
fi

# 8. Generate AppImage with zstd -22 + 1M block size (AppImage type2-runtime supports zlib and zstd)
rm -f "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}.AppImage" "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}-AppDir.tar.gz"
BUILT=0
LOG="/tmp/tools/appimagetool-${ARCH}.log"
: > "${LOG}"
if [ -f "${TOOL}" ] && [ -x "${TOOL}" ]; then
    RUNTIME_FILE="/tmp/tools/runtime-${ARCH}"
    if [ ! -f "${RUNTIME_FILE}" ]; then
        OFFSET=$("${TOOL}" --appimage-offset 2>/dev/null || true)
        if [ -n "${OFFSET}" ] && [ "${OFFSET}" -gt 0 ] 2>/dev/null; then
            head -c "${OFFSET}" "${TOOL}" > "${RUNTIME_FILE}" || rm -f "${RUNTIME_FILE}"
        fi
    fi

    RUNTIME_ARGS=(-n --comp zstd --mksquashfs-opt -Xcompression-level --mksquashfs-opt 22 --mksquashfs-opt -b --mksquashfs-opt 1M)
    [ -s "${RUNTIME_FILE}" ] && RUNTIME_ARGS+=(--runtime-file "${RUNTIME_FILE}")

    echo "==> Generating AppImage via appimagetool (zstd -22 + 1M blocks)..."
    if ARCH="${ARCH}" "${TOOL}" --appimage-extract-and-run "${RUNTIME_ARGS[@]}" "${APP_DIR}" "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}.AppImage" >>"${LOG}" 2>&1; then
        BUILT=1
    else
        (
            cd /tmp/tools
            rm -rf "squashfs-root-${ARCH}"
            "${TOOL}" --appimage-extract >/dev/null 2>&1 || true
            [ -d squashfs-root ] && mv squashfs-root "squashfs-root-${ARCH}"
        ) >>"${LOG}" 2>&1 || true
        if [ -x "/tmp/tools/squashfs-root-${ARCH}/AppRun" ]; then
            ARCH="${ARCH}" "/tmp/tools/squashfs-root-${ARCH}/AppRun" "${RUNTIME_ARGS[@]}" "${APP_DIR}" "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}.AppImage" >>"${LOG}" 2>&1 && BUILT=1 || echo "==> appimagetool execution failed in this environment."
        fi
    fi
fi

if [ "${BUILT}" = "1" ] && [ -f "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}.AppImage" ]; then
    ls -lh "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}.AppImage"
    echo "✅ Generated ${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}.AppImage"
else
    echo "==> appimagetool could not produce an AppImage; last lines of ${LOG}:"
    tail -n 15 "${LOG}" 2>/dev/null || true
    echo "==> Packaging portable AppDir bundle (the CI host wraps it into .AppImage)..."
    tar -czf "${OUTPUT_DIR}/Zalos-${VERSION}-${ARCH}-AppDir.tar.gz" -C "${APP_DIR}" .
fi

echo "✅ AppImage build step completed. Artifacts saved in dist/"
