#include "KeybindingRegistry.h"
#include "Logger.h"
#include <algorithm>
#include <cctype>

KeybindingRegistry::KeybindingRegistry() {
}

KeybindingRegistry::~KeybindingRegistry() {
}

void KeybindingRegistry::MapKeybinding(const KeyCombo& combo, const std::string& command) {
    bindings_[combo] = command;
    LOG_INFO("Mapped keybinding: key={} ctrl={} shift={} alt={} -> command='{}'",
             static_cast<int>(combo.key), combo.ctrl, combo.shift, combo.alt, command);
}

std::string KeybindingRegistry::LookupCommand(const KeyCombo& combo) const {
    auto it = bindings_.find(combo);
    if (it != bindings_.end()) {
        return it->second;
    }
    return "";
}

void KeybindingRegistry::Clear() {
    bindings_.clear();
}

KeybindingRegistry::KeyCombo KeybindingRegistry::ParseKeyCombo(const std::string& combo_str) {
    KeyCombo combo{Rml::Input::KI_UNKNOWN, false, false, false};

    // Convert to lowercase for case-insensitive parsing
    std::string lower = combo_str;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    // Parse modifiers and key
    size_t pos = 0;
    while (pos < lower.length()) {
        size_t next_plus = lower.find('+', pos);
        std::string part;

        if (next_plus == std::string::npos) {
            part = lower.substr(pos);
            pos = lower.length();
        } else {
            part = lower.substr(pos, next_plus - pos);
            pos = next_plus + 1;
        }

        // Trim whitespace
        part.erase(0, part.find_first_not_of(" \t"));
        part.erase(part.find_last_not_of(" \t") + 1);

        if (part == "ctrl" || part == "control") {
            combo.ctrl = true;
        } else if (part == "shift") {
            combo.shift = true;
        } else if (part == "alt") {
            combo.alt = true;
        } else {
            // This should be the key itself
            // Map common key names to KeyIdentifier
            if (part == "a") combo.key = Rml::Input::KI_A;
            else if (part == "b") combo.key = Rml::Input::KI_B;
            else if (part == "c") combo.key = Rml::Input::KI_C;
            else if (part == "d") combo.key = Rml::Input::KI_D;
            else if (part == "e") combo.key = Rml::Input::KI_E;
            else if (part == "f") combo.key = Rml::Input::KI_F;
            else if (part == "g") combo.key = Rml::Input::KI_G;
            else if (part == "h") combo.key = Rml::Input::KI_H;
            else if (part == "i") combo.key = Rml::Input::KI_I;
            else if (part == "j") combo.key = Rml::Input::KI_J;
            else if (part == "k") combo.key = Rml::Input::KI_K;
            else if (part == "l") combo.key = Rml::Input::KI_L;
            else if (part == "m") combo.key = Rml::Input::KI_M;
            else if (part == "n") combo.key = Rml::Input::KI_N;
            else if (part == "o") combo.key = Rml::Input::KI_O;
            else if (part == "p") combo.key = Rml::Input::KI_P;
            else if (part == "q") combo.key = Rml::Input::KI_Q;
            else if (part == "r") combo.key = Rml::Input::KI_R;
            else if (part == "s") combo.key = Rml::Input::KI_S;
            else if (part == "t") combo.key = Rml::Input::KI_T;
            else if (part == "u") combo.key = Rml::Input::KI_U;
            else if (part == "v") combo.key = Rml::Input::KI_V;
            else if (part == "w") combo.key = Rml::Input::KI_W;
            else if (part == "x") combo.key = Rml::Input::KI_X;
            else if (part == "y") combo.key = Rml::Input::KI_Y;
            else if (part == "z") combo.key = Rml::Input::KI_Z;
            else if (part == "0") combo.key = Rml::Input::KI_0;
            else if (part == "1") combo.key = Rml::Input::KI_1;
            else if (part == "2") combo.key = Rml::Input::KI_2;
            else if (part == "3") combo.key = Rml::Input::KI_3;
            else if (part == "4") combo.key = Rml::Input::KI_4;
            else if (part == "5") combo.key = Rml::Input::KI_5;
            else if (part == "6") combo.key = Rml::Input::KI_6;
            else if (part == "7") combo.key = Rml::Input::KI_7;
            else if (part == "8") combo.key = Rml::Input::KI_8;
            else if (part == "9") combo.key = Rml::Input::KI_9;
            else if (part == "f1") combo.key = Rml::Input::KI_F1;
            else if (part == "f2") combo.key = Rml::Input::KI_F2;
            else if (part == "f3") combo.key = Rml::Input::KI_F3;
            else if (part == "f4") combo.key = Rml::Input::KI_F4;
            else if (part == "f5") combo.key = Rml::Input::KI_F5;
            else if (part == "f6") combo.key = Rml::Input::KI_F6;
            else if (part == "f7") combo.key = Rml::Input::KI_F7;
            else if (part == "f8") combo.key = Rml::Input::KI_F8;
            else if (part == "f9") combo.key = Rml::Input::KI_F9;
            else if (part == "f10") combo.key = Rml::Input::KI_F10;
            else if (part == "f11") combo.key = Rml::Input::KI_F11;
            else if (part == "f12") combo.key = Rml::Input::KI_F12;
            else if (part == "escape" || part == "esc") combo.key = Rml::Input::KI_ESCAPE;
            else if (part == "space") combo.key = Rml::Input::KI_SPACE;
            else if (part == "return" || part == "enter") combo.key = Rml::Input::KI_RETURN;
            else if (part == "tab") combo.key = Rml::Input::KI_TAB;
            else if (part == "backspace") combo.key = Rml::Input::KI_BACK;
            else if (part == "delete" || part == "del") combo.key = Rml::Input::KI_DELETE;
            else if (part == "home") combo.key = Rml::Input::KI_HOME;
            else if (part == "end") combo.key = Rml::Input::KI_END;
            else if (part == "pageup") combo.key = Rml::Input::KI_PRIOR;
            else if (part == "pagedown") combo.key = Rml::Input::KI_NEXT;
            else if (part == "left") combo.key = Rml::Input::KI_LEFT;
            else if (part == "right") combo.key = Rml::Input::KI_RIGHT;
            else if (part == "up") combo.key = Rml::Input::KI_UP;
            else if (part == "down") combo.key = Rml::Input::KI_DOWN;
            else {
                LOG_WARN("Unknown key in combo string: '{}'", part);
            }
        }
    }

    return combo;
}
