// SPDX-License-Identifier: BSD-3-Clause
#include "native_lib.h"

#include <climits>
#include <cstdlib>
#include <dlfcn.h>
#include <unistd.h>

namespace zcall::audio {

namespace {

std::string exeDir() {
    char buf[PATH_MAX];
    const ssize_t n = ::readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n <= 0) return {};
    std::string path(buf, static_cast<size_t>(n));
    const size_t slash = path.rfind('/');
    return slash == std::string::npos ? std::string() : path.substr(0, slash);
}

bool readable(const std::string& path) { return ::access(path.c_str(), R_OK) == 0; }

}

std::vector<std::string> fallbackLibDirs() {
    std::vector<std::string> dirs;
    if (const char* env = std::getenv("ZALOS_FALLBACK_LIB_DIR"); env && *env) dirs.emplace_back(env);
    const std::string dir = exeDir();
    if (!dir.empty()) {
        for (const char* up : {"/..", "/../.."}) {
            for (const char* lib : {"/lib/zalos/fallback", "/lib64/zalos/fallback"}) {
                dirs.push_back(dir + up + lib);
            }
        }
    }
    return dirs;
}

void* openNativeLib(std::initializer_list<const char*> names, std::string* origin, std::string* error) {
    std::string firstError;
    for (const char* name : names) {
        if (void* h = ::dlopen(name, RTLD_NOW | RTLD_LOCAL)) {
            if (origin) *origin = "system";
            return h;
        }
        if (firstError.empty()) {
            const char* e = ::dlerror();
            firstError = e ? e : std::string(name) + ": cannot open shared object file";
        }
    }
    for (const std::string& dir : fallbackLibDirs()) {
        for (const char* name : names) {
            const std::string path = dir + "/" + name;
            if (!readable(path)) continue;
            if (void* h = ::dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL)) {
                if (origin) *origin = path;
                return h;
            }
        }
    }
    if (error) *error = firstError;
    return nullptr;
}

}
