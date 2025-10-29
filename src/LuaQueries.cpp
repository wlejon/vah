#include "LuaQueries.h"
#include "LuaConversions.h"
#include "Logger.h"
#include <chrono>

namespace LuaQueries {

sol::table QueryDocumentList(LuaThread* thread) {
    if (!thread) {
        LOG_ERROR("QueryDocumentList: null thread pointer");
        sol::state temp_lua;
        return temp_lua.create_table();
    }

    auto& lua = thread->GetLuaState();
    auto promise = std::make_shared<std::promise<PayloadMap>>();
    auto future = promise->get_future();

    Commands::QueryDocumentList cmd;
    cmd.request_id = thread->AllocateRequestId();
    cmd.requesting_thread_id = thread->GetId();
    cmd.promise = promise;  // Promise travels with command
    thread->EnqueueCommand(std::move(cmd));

    // Block until main thread sets the promise (or timeout)
    auto status = future.wait_for(std::chrono::seconds(30));
    if (status == std::future_status::timeout) {
        LOG_ERROR("Lua thread {} query 'ui.list_documents' timed out", thread->GetId());
        return lua.create_table();
    }

    try {
        PayloadMap result = future.get();
        auto result_table = lua.create_table();
        for (const auto& [key, value] : result) {
            result_table[key] = LuaConversions::DynamicValueToLua(lua, value);
        }
        return result_table;
    } catch (const std::exception& e) {
        LOG_ERROR("Lua thread {} query 'ui.list_documents' failed: {}", thread->GetId(), e.what());
        return lua.create_table();
    }
}

sol::table QueryDocumentInfo(LuaThread* thread, const std::string& document_id) {
    if (!thread) {
        LOG_ERROR("QueryDocumentInfo: null thread pointer");
        sol::state temp_lua;
        return temp_lua.create_table();
    }

    auto& lua = thread->GetLuaState();
    auto promise = std::make_shared<std::promise<PayloadMap>>();
    auto future = promise->get_future();

    Commands::QueryDocumentInfo cmd;
    cmd.request_id = thread->AllocateRequestId();
    cmd.requesting_thread_id = thread->GetId();
    cmd.document_id = document_id;
    cmd.promise = promise;
    thread->EnqueueCommand(std::move(cmd));

    auto status = future.wait_for(std::chrono::seconds(30));
    if (status == std::future_status::timeout) {
        LOG_ERROR("Lua thread {} query 'ui.get_document_info' timed out", thread->GetId());
        return lua.create_table();
    }

    try {
        PayloadMap result = future.get();
        auto result_table = lua.create_table();
        for (const auto& [key, value] : result) {
            result_table[key] = LuaConversions::DynamicValueToLua(lua, value);
        }
        return result_table;
    } catch (const std::exception& e) {
        LOG_ERROR("Lua thread {} query 'ui.get_document_info' failed: {}", thread->GetId(), e.what());
        return lua.create_table();
    }
}

sol::table QueryThreadList(LuaThread* thread) {
    if (!thread) {
        LOG_ERROR("QueryThreadList: null thread pointer");
        sol::state temp_lua;
        return temp_lua.create_table();
    }

    auto& lua = thread->GetLuaState();
    auto promise = std::make_shared<std::promise<PayloadMap>>();
    auto future = promise->get_future();

    Commands::QueryThreadList cmd;
    cmd.request_id = thread->AllocateRequestId();
    cmd.requesting_thread_id = thread->GetId();
    cmd.promise = promise;
    thread->EnqueueCommand(std::move(cmd));

    auto status = future.wait_for(std::chrono::seconds(30));
    if (status == std::future_status::timeout) {
        LOG_ERROR("Lua thread {} query 'thread.list' timed out", thread->GetId());
        return lua.create_table();
    }

    try {
        PayloadMap result = future.get();
        auto result_table = lua.create_table();
        for (const auto& [key, value] : result) {
            result_table[key] = LuaConversions::DynamicValueToLua(lua, value);
        }
        return result_table;
    } catch (const std::exception& e) {
        LOG_ERROR("Lua thread {} query 'thread.list' failed: {}", thread->GetId(), e.what());
        return lua.create_table();
    }
}

sol::table QueryThreadInfo(LuaThread* thread, int thread_id) {
    if (!thread) {
        LOG_ERROR("QueryThreadInfo: null thread pointer");
        sol::state temp_lua;
        return temp_lua.create_table();
    }

    auto& lua = thread->GetLuaState();
    auto promise = std::make_shared<std::promise<PayloadMap>>();
    auto future = promise->get_future();

    Commands::QueryThreadInfo cmd;
    cmd.request_id = thread->AllocateRequestId();
    cmd.requesting_thread_id = thread->GetId();
    cmd.thread_id = thread_id;
    cmd.promise = promise;
    thread->EnqueueCommand(std::move(cmd));

    auto status = future.wait_for(std::chrono::seconds(30));
    if (status == std::future_status::timeout) {
        LOG_ERROR("Lua thread {} query 'thread.get_info' timed out", thread->GetId());
        return lua.create_table();
    }

    try {
        PayloadMap result = future.get();
        auto result_table = lua.create_table();
        for (const auto& [key, value] : result) {
            result_table[key] = LuaConversions::DynamicValueToLua(lua, value);
        }
        return result_table;
    } catch (const std::exception& e) {
        LOG_ERROR("Lua thread {} query 'thread.get_info' failed: {}", thread->GetId(), e.what());
        return lua.create_table();
    }
}

} // namespace LuaQueries
