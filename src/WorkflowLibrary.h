#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <functional>
#include <sol/forward.hpp>

namespace WorkflowLibrary {

/**
 * Definition for a library that can be registered with the workflow system.
 * Each library provides functionality that workflows can request access to.
 */
struct LibraryDefinition {
    std::string id;                     // Unique identifier (e.g., "db", "fs", "http")
    std::string name;                   // Human-readable name (e.g., "Database Access")
    std::string description;            // Full description of what the library does
    std::string access_description;     // Description of what data/resources it can access
    std::function<void(sol::state&)> register_func;  // Function to register bindings in sol::state
};

/**
 * Registry for workflow libraries.
 * Manages available libraries and handles registration into lua_States.
 */
class WorkflowLibraryRegistry {
public:
    /**
     * Register all built-in libraries with the registry.
     * This should be called once during application initialization.
     */
    static void RegisterBuiltinLibraries();

    /**
     * Register a single library with the registry.
     * @param def The library definition to register
     * @return true if registered successfully, false if ID already exists
     */
    static bool RegisterLibrary(const LibraryDefinition& def);

    /**
     * Check if a library with the given ID is available.
     * @param id The library ID to check
     * @return true if the library is registered, false otherwise
     */
    static bool IsLibraryAvailable(const std::string& id);

    /**
     * Register requested libraries into a sol::state.
     * Only the requested libraries will be made available in the state.
     * @param lua The sol::state to register libraries into
     * @param library_ids List of library IDs to register
     * @return Number of libraries successfully registered
     */
    static int RegisterRequestedLibraries(sol::state& lua, const std::vector<std::string>& library_ids);

    /**
     * Get the definition for a specific library.
     * @param id The library ID to look up
     * @return Pointer to the library definition, or nullptr if not found
     */
    static const LibraryDefinition* GetLibraryDefinition(const std::string& id);

    /**
     * Get a list of all registered library IDs.
     * @return Vector of all registered library IDs
     */
    static std::vector<std::string> GetRegisteredLibraryIds();

private:
    static std::unordered_map<std::string, LibraryDefinition> s_libraries;
};

} // namespace WorkflowLibrary
