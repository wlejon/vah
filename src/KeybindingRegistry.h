#pragma once

#include <string>
#include <unordered_map>
#include <RmlUi/Core/Input.h>

/**
 * KeybindingRegistry - Maps keyboard combinations to command strings
 *
 * Allows application to define semantic commands (like "command_copy")
 * and map them to physical key combinations (like "Ctrl+C").
 * When a key combination is pressed, the registry returns the command name
 * which can be emitted to Lua for handling.
 */
class KeybindingRegistry {
public:
    KeybindingRegistry();
    ~KeybindingRegistry();

    // Key combination structure
    struct KeyCombo {
        Rml::Input::KeyIdentifier key;
        bool ctrl;
        bool shift;
        bool alt;

        bool operator==(const KeyCombo& other) const {
            return key == other.key && ctrl == other.ctrl &&
                   shift == other.shift && alt == other.alt;
        }
    };

    // Hash function for KeyCombo
    struct KeyComboHash {
        std::size_t operator()(const KeyCombo& combo) const {
            return std::hash<int>()(static_cast<int>(combo.key)) ^
                   (std::hash<bool>()(combo.ctrl) << 1) ^
                   (std::hash<bool>()(combo.shift) << 2) ^
                   (std::hash<bool>()(combo.alt) << 3);
        }
    };

    // Register a keybinding
    void MapKeybinding(const KeyCombo& combo, const std::string& command);

    // Look up command for key combination
    // Returns empty string if no mapping exists
    std::string LookupCommand(const KeyCombo& combo) const;

    // Clear all keybindings
    void Clear();

    // Parse key combo from string (e.g. "ctrl+c", "ctrl+shift+s")
    static KeyCombo ParseKeyCombo(const std::string& combo_str);

private:
    std::unordered_map<KeyCombo, std::string, KeyComboHash> bindings_;
};
