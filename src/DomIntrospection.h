#pragma once

#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <string>
#include <vector>

// DOM Introspection API for Lua
// Provides access to RmlUi DOM tree from Lua scripts
class DomIntrospection {
public:
    // Register Lua bindings (call from RmlUiBridge::SetupLuaBindings)
    static void RegisterLuaBindings(lua_State* L);

    // DOM traversal
    static int GetElementChildCount(Rml::Element* element);
    static Rml::Element* GetElementChild(Rml::Element* element, int index);
    static Rml::Element* GetElementParent(Rml::Element* element);

    // Property getters
    static std::string GetElementTagName(Rml::Element* element);
    static std::string GetElementId(Rml::Element* element);
    static std::string GetElementClassName(Rml::Element* element);
    static bool IsElementVisible(Rml::Element* element);

    // Content extraction
    static std::string GetElementText(Rml::Element* element);
    static std::string GetElementInnerRML(Rml::Element* element);

    // Attribute access
    static std::string GetElementAttribute(Rml::Element* element, const std::string& name);
    static std::vector<std::string> GetElementAttributeNames(Rml::Element* element);
};
