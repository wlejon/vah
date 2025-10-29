#pragma once

#include <sol/sol.hpp>
#include "Commands.h"
#include "LuaThread.h"

// Forward declaration
class LuaThread;

namespace LuaQueries {
    // Synchronous query functions that block until response arrives
    // These are called from Lua bindings and block the Lua thread until main thread responds

    // Query list of loaded RML documents
    sol::table QueryDocumentList(LuaThread* thread);

    // Query specific document info
    sol::table QueryDocumentInfo(LuaThread* thread, const std::string& document_id);

    // Query list of running threads
    sol::table QueryThreadList(LuaThread* thread);

    // Query specific thread info
    sol::table QueryThreadInfo(LuaThread* thread, int thread_id);
}
