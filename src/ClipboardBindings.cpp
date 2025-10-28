#include "ClipboardBindings.h"
#include "Logger.h"
#include <SDL2/SDL.h>

namespace ClipboardBindings {

// Get text from clipboard
std::tuple<sol::object, std::string> GetText(sol::this_state s) {
    sol::state_view lua(s);

    if (!SDL_HasClipboardText()) {
        return {sol::nil, ""};
    }

    char* text = SDL_GetClipboardText();
    if (!text) {
        return {sol::nil, "Failed to get clipboard text"};
    }

    std::string result(text);
    SDL_free(text);

    return {sol::make_object(lua, result), ""};
}

// Set text to clipboard
std::tuple<bool, std::string> SetText(const std::string& text) {
    if (SDL_SetClipboardText(text.c_str()) != 0) {
        return {false, std::string("Failed to set clipboard: ") + SDL_GetError()};
    }
    return {true, ""};
}

// Check if clipboard has text
bool HasText() {
    return SDL_HasClipboardText() == SDL_TRUE;
}

void SetupBindings(sol::state& lua) {
    auto clipboard_table = lua.create_table();

    clipboard_table["get_text"] = GetText;
    clipboard_table["set_text"] = SetText;
    clipboard_table["has_text"] = HasText;

    lua["clipboard"] = clipboard_table;
}

} // namespace ClipboardBindings
