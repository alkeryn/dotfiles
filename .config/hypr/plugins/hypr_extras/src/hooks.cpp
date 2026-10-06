#include "hooks.hpp"

#include <dlfcn.h>
#include <link.h>
#include <stdexcept>

namespace extras {

function_span find_function(HANDLE handle, const std::string& name, std::string_view signature) {
    void* address = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, name)) {
        if (match.demangled != signature)
            continue;
        if (address)
            throw std::runtime_error("hypr_extras: ambiguous function: " + std::string(signature));
        address = match.address;
    }

    Dl_info info{};
    void* extra = nullptr;
    if (!address || !dladdr1(address, &info, &extra, RTLD_DL_SYMENT) || info.dli_saddr != address || !extra)
        throw std::runtime_error("hypr_extras: missing ELF function: " + std::string(signature));
    const auto* symbol = static_cast<const ElfW(Sym)*>(extra);
    if (ELF64_ST_TYPE(symbol->st_info) != STT_FUNC || !symbol->st_size)
        throw std::runtime_error("hypr_extras: missing function bounds: " + std::string(signature));
    return {address, symbol->st_size};
}

CFunctionHook* hooks::add(const function_span& source, void* replacement) {
    auto* hook = HyprlandAPI::createFunctionHook(owner, source.address, replacement);
    if (!hook)
        throw std::runtime_error("hypr_extras: could not create function hook");
    entries.push_back(hook);
    if (!hook->hook())
        throw std::runtime_error("hypr_extras: could not install function hook (already hooked or unsupported code)");
    return hook;
}

void hooks::clear() {
    for (auto it = entries.rbegin(); it != entries.rend(); ++it)
        HyprlandAPI::removeFunctionHook(owner, *it);
    entries.clear();
}

} // namespace extras
