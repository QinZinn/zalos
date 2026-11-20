// SPDX-License-Identifier: BSD-3-Clause
#pragma once

#include <initializer_list>
#include <string>
#include <vector>

namespace zcall::audio {

std::vector<std::string> fallbackLibDirs();
void* openNativeLib(std::initializer_list<const char*> names, std::string* origin, std::string* error);

}
