#include "DomIntrospection.h"
#include <functional>

// ============================================
// DOM Introspection API Implementation
// ============================================

int DomIntrospection::GetElementChildCount(Rml::Element* element) {
    if (!element) return 0;
    return element->GetNumChildren(false);  // false = don't include auto-generated text nodes
}

Rml::Element* DomIntrospection::GetElementChild(Rml::Element* element, int index) {
    if (!element || index < 0) return nullptr;
    return element->GetChild(index);
}

Rml::Element* DomIntrospection::GetElementParent(Rml::Element* element) {
    if (!element) return nullptr;
    return element->GetParentNode();
}

std::string DomIntrospection::GetElementTagName(Rml::Element* element) {
    if (!element) return "";
    return element->GetTagName();
}

std::string DomIntrospection::GetElementId(Rml::Element* element) {
    if (!element) return "";
    return element->GetId();
}

std::string DomIntrospection::GetElementClassName(Rml::Element* element) {
    if (!element) return "";
    return element->GetAttribute<std::string>("class", "");
}

bool DomIntrospection::IsElementVisible(Rml::Element* element) {
    if (!element) return false;
    return element->IsVisible(false);  // false = don't check ancestors
}

std::string DomIntrospection::GetElementText(Rml::Element* element) {
    if (!element) return "";

    // Get only the rendered text content (no markup)
    const std::string& inner_rml = element->GetInnerRML();

    // Simple approach: strip all tags
    std::string text;
    bool in_tag = false;
    for (char c : inner_rml) {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            text += c;
        }
    }

    // Trim whitespace
    size_t start = text.find_first_not_of(" \t\n\r");
    size_t end = text.find_last_not_of(" \t\n\r");
    if (start != std::string::npos && end != std::string::npos) {
        return text.substr(start, end - start + 1);
    }

    return "";
}

std::string DomIntrospection::GetElementInnerRML(Rml::Element* element) {
    if (!element) return "";
    return element->GetInnerRML();
}

std::string DomIntrospection::GetElementAttribute(Rml::Element* element, const std::string& name) {
    if (!element) return "";
    return element->GetAttribute<std::string>(name, "");
}

std::vector<std::string> DomIntrospection::GetElementAttributeNames(Rml::Element* element) {
    std::vector<std::string> names;
    if (!element) return names;

    // Note: RmlUi doesn't provide direct attribute iteration
    // We check common attributes manually
    const char* common_attrs[] = {
        "id", "class", "style", "name", "type", "value",
        "href", "src", "alt", "title", "placeholder",
        "data-model", "data-for", "data-if", "data-value",
        "onclick", "onchange", "onsubmit", "onblur", "onfocus"
    };

    for (const char* attr : common_attrs) {
        if (element->HasAttribute(attr)) {
            names.push_back(attr);
        }
    }

    return names;
}

// ============================================
// Lua Bindings
// ============================================

namespace {
    int lua_dom_get_child_count(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        if (!element) {
            lua_pushinteger(L, 0);
            return 1;
        }

        int count = DomIntrospection::GetElementChildCount(element);
        lua_pushinteger(L, count);
        return 1;
    }

    int lua_dom_get_child(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        int index = static_cast<int>(luaL_checkinteger(L, 2));

        if (!element) {
            lua_pushnil(L);
            return 1;
        }

        Rml::Element* child = DomIntrospection::GetElementChild(element, index);
        if (child) {
            Rml::Lua::LuaType<Rml::Element>::push(L, child, false);
        } else {
            lua_pushnil(L);
        }
        return 1;
    }

    int lua_dom_get_parent(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);

        if (!element) {
            lua_pushnil(L);
            return 1;
        }

        Rml::Element* parent = DomIntrospection::GetElementParent(element);
        if (parent) {
            Rml::Lua::LuaType<Rml::Element>::push(L, parent, false);
        } else {
            lua_pushnil(L);
        }
        return 1;
    }

    int lua_dom_get_tag_name(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        std::string tag = DomIntrospection::GetElementTagName(element);
        lua_pushstring(L, tag.c_str());
        return 1;
    }

    int lua_dom_get_id(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        std::string id = DomIntrospection::GetElementId(element);
        lua_pushstring(L, id.c_str());
        return 1;
    }

    int lua_dom_get_class_name(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        std::string class_name = DomIntrospection::GetElementClassName(element);
        lua_pushstring(L, class_name.c_str());
        return 1;
    }

    int lua_dom_is_visible(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        bool visible = DomIntrospection::IsElementVisible(element);
        lua_pushboolean(L, visible);
        return 1;
    }

    int lua_dom_get_text(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        std::string text = DomIntrospection::GetElementText(element);
        lua_pushstring(L, text.c_str());
        return 1;
    }

    int lua_dom_get_inner_rml(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        std::string rml = DomIntrospection::GetElementInnerRML(element);
        lua_pushstring(L, rml.c_str());
        return 1;
    }

    int lua_dom_get_attribute(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        const char* name = luaL_checkstring(L, 2);

        std::string value = DomIntrospection::GetElementAttribute(element, name);
        if (value.empty()) {
            lua_pushnil(L);
        } else {
            lua_pushstring(L, value.c_str());
        }
        return 1;
    }

    int lua_dom_get_attribute_names(lua_State* L) {
        Rml::Element* element = Rml::Lua::LuaType<Rml::Element>::check(L, 1);
        auto names = DomIntrospection::GetElementAttributeNames(element);

        lua_newtable(L);
        for (size_t i = 0; i < names.size(); ++i) {
            lua_pushstring(L, names[i].c_str());
            lua_rawseti(L, -2, i + 1);  // Lua is 1-indexed
        }
        return 1;
    }
}

void DomIntrospection::RegisterLuaBindings(lua_State* L) {
    // Create dom table
    lua_newtable(L);

    // Register functions
    lua_pushcfunction(L, lua_dom_get_child_count);
    lua_setfield(L, -2, "get_child_count");

    lua_pushcfunction(L, lua_dom_get_child);
    lua_setfield(L, -2, "get_child");

    lua_pushcfunction(L, lua_dom_get_parent);
    lua_setfield(L, -2, "get_parent");

    lua_pushcfunction(L, lua_dom_get_tag_name);
    lua_setfield(L, -2, "get_tag_name");

    lua_pushcfunction(L, lua_dom_get_id);
    lua_setfield(L, -2, "get_id");

    lua_pushcfunction(L, lua_dom_get_class_name);
    lua_setfield(L, -2, "get_class_name");

    lua_pushcfunction(L, lua_dom_is_visible);
    lua_setfield(L, -2, "is_visible");

    lua_pushcfunction(L, lua_dom_get_text);
    lua_setfield(L, -2, "get_text");

    lua_pushcfunction(L, lua_dom_get_inner_rml);
    lua_setfield(L, -2, "get_inner_rml");

    lua_pushcfunction(L, lua_dom_get_attribute);
    lua_setfield(L, -2, "get_attribute");

    lua_pushcfunction(L, lua_dom_get_attribute_names);
    lua_setfield(L, -2, "get_attribute_names");

    // Set as global 'dom'
    lua_setglobal(L, "dom");
}
