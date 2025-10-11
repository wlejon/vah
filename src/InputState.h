#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <variant>
#include <sol/sol.hpp>

// Simple payload type that can cross lua states
using PayloadValue = std::variant<std::monostate, bool, int, double, std::string>;
using PayloadMap = std::unordered_map<std::string, PayloadValue>;

struct UIEvent {
    std::string name;
    PayloadMap payload;  // Simple key-value pairs that can be recreated in any lua state
};

// SDL Input Events
enum class MouseButton { Left = 0, Right = 1, Middle = 2 };

struct MouseButtonEvent {
    MouseButton button;
    int x;
    int y;
    bool pressed;  // true = down, false = up
};

struct MouseMoveEvent {
    int x;
    int y;
    int dx;
    int dy;
};

struct KeyEvent {
    std::string key_name;
    bool pressed;  // true = down, false = up
};

struct InputState {
    // Mouse state (polled)
    int mouse_x = 0;
    int mouse_y = 0;
    bool mouse_left = false;
    bool mouse_right = false;
    bool mouse_middle = false;

    // Keyboard state (key name -> pressed)
    std::unordered_map<std::string, bool> keyboard;

    // UI events accumulated this frame
    std::vector<UIEvent> ui_events;

    // SDL Input events accumulated this frame
    std::vector<MouseButtonEvent> mouse_button_events;
    std::vector<MouseMoveEvent> mouse_move_events;
    std::vector<KeyEvent> key_events;

    // Frame counter
    uint64_t frame_number = 0;

    // Clear events (called each frame after processing)
    void ClearEvents() {
        ui_events.clear();
        mouse_button_events.clear();
        mouse_move_events.clear();
        key_events.clear();
    }
};
