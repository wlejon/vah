#include "DocumentManager.h"
#include "ElementTextEditor.h"
#include "RmlUiBridge.h"
#include "EventDispatcher.h"
#include "Logger.h"
#include <algorithm>
#include <filesystem>
#include <vector>
#include <RmlUi/Lua/Interpreter.h>
#include <SDL2/SDL.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

DocumentManager::DocumentManager(Rml::Context* context, RmlUiBridge* rmlui_bridge, EventDispatcher* event_dispatcher)
    : context_(context)
    , rmlui_bridge_(rmlui_bridge)
    , event_dispatcher_(event_dispatcher)
{
}

void DocumentManager::LoadDocument(const std::string& document_path, bool show, const std::string& document_id) {
    if (!context_) {
        LOG_WARN("Cannot load document: context is null");
        // Dispatch error event to the requesting thread
        if (event_dispatcher_ && !document_id.empty()) {
            event_dispatcher_->DispatchEvent(document_id, "document_load_failed",
                {{"error", "Context is null"}, {"path", document_path}});
        }
        return;
    }

    auto doc = context_->LoadDocument(document_path.c_str());
    if (doc) {
        // Set the document's ID if provided
        if (!document_id.empty()) {
            doc->SetId(document_id.c_str());
            loaded_documents_[document_id] = doc;
            LOG_INFO("Stored document with ID: {}", document_id);

            // Set this as the current document in RmlUiBridge
            if (rmlui_bridge_) {
                rmlui_bridge_->SetCurrentDocument(document_id);
            }
        }

        if (show) {
            doc->Show();
        } else {
            doc->Hide();
        }

        // Force context update AND render to fully rebuild layout and stacking
        context_->Update();
        context_->Render();

        // Get current mouse position and force hover recalculation
        int mouse_x, mouse_y;
        SDL_GetMouseState(&mouse_x, &mouse_y);
        context_->ProcessMouseMove(mouse_x, mouse_y, 0);

        LOG_INFO("Loaded UI document: {}", document_path);
    } else {
        LOG_WARN("Failed to load UI document: {}", document_path);
        // Dispatch error event to the requesting thread
        if (event_dispatcher_ && !document_id.empty()) {
            event_dispatcher_->DispatchEvent(document_id, "document_load_failed",
                {{"error", "Failed to load document"}, {"path", document_path}});
        }
    }
}

void DocumentManager::ShowDocument(const std::string& document_id) {
    auto it = loaded_documents_.find(document_id);
    if (it != loaded_documents_.end()) {
        it->second->Show();
        if (context_) {
            context_->Update();
        }

        // Set this as the current document in RmlUiBridge
        if (rmlui_bridge_) {
            rmlui_bridge_->SetCurrentDocument(document_id);
        }

        LOG_INFO("Showing document: {}", document_id);
    } else {
        LOG_WARN("Document not found: {}", document_id);
    }
}

void DocumentManager::HideDocument(const std::string& document_id) {
    auto it = loaded_documents_.find(document_id);
    if (it != loaded_documents_.end()) {
        it->second->Hide();
        if (context_) {
            context_->Update();
        }
        LOG_INFO("Hiding document: {}", document_id);
    } else {
        LOG_WARN("Document not found: {}", document_id);
    }
}

void DocumentManager::ReloadDocument(const std::string& document_id) {
    auto it = loaded_documents_.find(document_id);
    if (it != loaded_documents_.end() && context_) {
        LOG_INFO("Reloading UI document: {}", document_id);
        auto doc = it->second;
        std::string src = doc->GetSourceURL();

        // Close the old document
        doc->Close();
        loaded_documents_.erase(it);

        // Reload it
        auto new_doc = context_->LoadDocument(src.c_str());
        if (new_doc) {
            loaded_documents_[document_id] = new_doc;
            new_doc->Show();
            LOG_INFO("Reloaded UI document: {}", src);
        } else {
            LOG_ERROR("Failed to reload UI document: {}", src);
        }
    } else {
        LOG_WARN("Cannot reload document: {} not found", document_id);
    }
}

void DocumentManager::SetElementText(const std::string& element_id, const std::string& text) {
    auto element = FindElementById(element_id);
    if (element) {
        element->SetInnerRML(text.c_str());
    }
}

void DocumentManager::SetElementAttribute(const std::string& element_id, const std::string& attribute_name, const std::string& value) {
    auto element = FindElementById(element_id);
    if (element) {
        element->SetAttribute(attribute_name.c_str(), value.c_str());
    }
}

void DocumentManager::SetElementStyle(const std::string& element_id, const std::string& property, const std::string& value) {
    auto element = FindElementById(element_id);
    if (element) {
        element->SetProperty(property.c_str(), value.c_str());
    }
}

void DocumentManager::AddElementClass(const std::string& element_id, const std::string& class_name) {
    auto element = FindElementById(element_id);
    if (element) {
        element->SetClass(class_name.c_str(), true);
    }
}

void DocumentManager::RemoveElementClass(const std::string& element_id, const std::string& class_name) {
    auto element = FindElementById(element_id);
    if (element) {
        element->SetClass(class_name.c_str(), false);
    }
}

void DocumentManager::SetTextEditorContent(const std::string& element_id, const std::string& content) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("SetTextEditorContent: Element '{}' not found", element_id);
        return;
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("SetTextEditorContent: Element '{}' is not a texteditor", element_id);
        return;
    }

    // Set content
    editor->SetText(content);
}

void DocumentManager::SetTextEditorTokens(const std::string& element_id, const DynamicTable& tokens) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("SetTextEditorTokens: Element '{}' not found", element_id);
        return;
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("SetTextEditorTokens: Element '{}' is not a texteditor", element_id);
        return;
    }

    // Set tokens
    editor->SetTokens(tokens);
}

void DocumentManager::SetTextEditorEditable(const std::string& element_id, bool editable) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("SetTextEditorEditable: Element '{}' not found", element_id);
        return;
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("SetTextEditorEditable: Element '{}' is not a texteditor", element_id);
        return;
    }

    // Set editable state
    editor->SetEditable(editable);
}

void DocumentManager::SetTextEditorModified(const std::string& element_id, bool modified) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("SetTextEditorModified: Element '{}' not found", element_id);
        return;
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("SetTextEditorModified: Element '{}' is not a texteditor", element_id);
        return;
    }

    // Set modified state
    editor->SetModified(modified);
}

void DocumentManager::SetTextEditorConfig(const std::string& element_id, const std::string& config_key, const DynamicValue& value) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("SetTextEditorConfig: Element '{}' not found", element_id);
        return;
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("SetTextEditorConfig: Element '{}' is not a texteditor", element_id);
        return;
    }

    // Get config
    auto& config = editor->GetConfig();

    // Apply config value based on key
    if (config_key == "cursor_blink_period") {
        if (std::holds_alternative<double>(value)) {
            config.cursor_blink_period = std::get<double>(value);
        } else {
            LOG_WARN("SetTextEditorConfig: cursor_blink_period requires a number");
        }
    } else if (config_key == "cursor_width") {
        if (std::holds_alternative<double>(value)) {
            config.cursor_width = static_cast<float>(std::get<double>(value));
        } else {
            LOG_WARN("SetTextEditorConfig: cursor_width requires a number");
        }
    } else if (config_key == "use_spaces_for_tab") {
        if (std::holds_alternative<bool>(value)) {
            config.use_spaces_for_tab = std::get<bool>(value);
        } else {
            LOG_WARN("SetTextEditorConfig: use_spaces_for_tab requires a boolean");
        }
    } else if (config_key == "tab_width") {
        if (std::holds_alternative<int64_t>(value)) {
            config.tab_width = static_cast<int>(std::get<int64_t>(value));
        } else {
            LOG_WARN("SetTextEditorConfig: tab_width requires an integer");
        }
    } else {
        LOG_WARN("SetTextEditorConfig: Unknown config key '{}'", config_key);
    }

    LOG_INFO("SetTextEditorConfig: Set '{}' config '{}' for texteditor '{}'", config_key, element_id, element_id);
}

void DocumentManager::TextEditorCopy(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) return;

    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (editor) {
        editor->CopyToClipboard();
    }
}

void DocumentManager::TextEditorPaste(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) return;

    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (editor) {
        editor->PasteFromClipboard();
    }
}

void DocumentManager::TextEditorCut(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) return;

    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (editor) {
        editor->CutToClipboard();
    }
}

void DocumentManager::TextEditorSelectAll(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) return;

    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (editor) {
        editor->SelectAll();
    }
}

void DocumentManager::TextEditorUndo(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) return;

    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (editor) {
        editor->Undo();
    }
}

void DocumentManager::TextEditorRedo(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) return;

    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (editor) {
        editor->Redo();
    }
}

std::string DocumentManager::GetTextEditorContent(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("GetTextEditorContent: Element '{}' not found", element_id);
        return "";
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("GetTextEditorContent: Element '{}' is not a texteditor", element_id);
        return "";
    }

    return editor->GetText();
}

bool DocumentManager::GetTextEditorModified(const std::string& element_id) {
    auto element = FindElementById(element_id);
    if (!element) {
        LOG_WARN("GetTextEditorModified: Element '{}' not found", element_id);
        return false;
    }

    // Try to cast to ElementTextEditor
    ElementTextEditor* editor = dynamic_cast<ElementTextEditor*>(element);
    if (!editor) {
        LOG_WARN("GetTextEditorModified: Element '{}' is not a texteditor", element_id);
        return false;
    }

    return editor->IsModified();
}

void DocumentManager::HandleRmlFileChanged(const std::string& normalized_path) {
    if (!context_) return;

    // Convert the changed file path to an absolute path for reliable comparison
    std::filesystem::path changed_path;
    try {
        changed_path = std::filesystem::absolute(normalized_path);
    } catch (const std::filesystem::filesystem_error& e) {
        LOG_WARN("Failed to convert path to absolute: {} - {}", normalized_path, e.what());
        // Fall back to using the normalized_path as-is
        changed_path = normalized_path;
    }

    // Iterate through ALL documents in context (not just tracked ones)
    int num_docs = context_->GetNumDocuments();
    for (int i = 0; i < num_docs; i++) {
        auto doc = context_->GetDocument(i);
        if (!doc) continue;

        std::string src = doc->GetSourceURL();

        // Try to match the document path with the changed file
        bool matches = false;
        try {
            std::filesystem::path doc_path = std::filesystem::absolute(src);
            // Use filesystem::equivalent for reliable comparison
            matches = std::filesystem::equivalent(changed_path, doc_path);
        } catch (const std::filesystem::filesystem_error&) {
            // If paths don't exist or can't be compared, fall back to string comparison
            matches = (src == normalized_path);
        }

        if (matches) {
            LOG_INFO("Auto-reloading document: {}", src);
            bool was_visible = doc->IsVisible();

            doc->Close();
            auto new_doc = context_->LoadDocument(src.c_str());

            // Update tracked documents map if this doc has an ID
            std::string reloaded_doc_id;
            for (auto& [doc_id, tracked_doc] : loaded_documents_) {
                if (tracked_doc == doc) {
                    loaded_documents_[doc_id] = new_doc;
                    if (new_doc) {
                        new_doc->SetId(doc_id.c_str());
                    }
                    reloaded_doc_id = doc_id;
                    break;
                }
            }

            if (new_doc && was_visible) {
                new_doc->Show();
            }

            // Force context update to rebind data models
            if (context_) {
                context_->Update();
            }

            // Notify owning thread that document was reloaded
            if (event_dispatcher_ && !reloaded_doc_id.empty()) {
                event_dispatcher_->DispatchEvent(reloaded_doc_id, "document_reloaded", {});
            }

            break;
        }
    }
}

void DocumentManager::HandleRcssFileChanged() {
    if (!context_) return;

    // Clear the stylesheet cache so RmlUi reloads the CSS
    Rml::Factory::ClearStyleSheetCache();

    // Reload all documents to apply new styles
    ReloadAllDocuments();
}

void DocumentManager::HandleLuaFileChanged(const std::string& normalized_path) {
    if (!context_) return;

    // Clear the Lua module cache so require() will reload the file
    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
    if (!L) {
        LOG_WARN("Cannot clear Lua cache: Lua state is null");
        return;
    }

    // Extract module name candidates from path
    // For "ui/canvas.test.lua", we want to try: "canvas.test", "canvas", and "ui.canvas.test"
    std::vector<std::string> module_candidates;

    size_t last_slash = normalized_path.find_last_of("/\\");
    std::string filename;
    std::string path_prefix;

    if (last_slash != std::string::npos) {
        filename = normalized_path.substr(last_slash + 1);
        path_prefix = normalized_path.substr(0, last_slash);
    } else {
        filename = normalized_path;
    }

    // Remove .lua extension if present
    if (filename.ends_with(".lua")) {
        filename = filename.substr(0, filename.length() - 4);
    }

    // Add the filename without path as first candidate (most common case)
    module_candidates.push_back(filename);

    // If filename has dots, also try without the last part (e.g., "canvas.test" -> "canvas")
    size_t last_dot = filename.find_last_of(".");
    if (last_dot != std::string::npos) {
        module_candidates.push_back(filename.substr(0, last_dot));
    }

    // If there was a path, also try path.filename (e.g., "ui.canvas.test")
    if (!path_prefix.empty()) {
        std::string path_as_module = path_prefix;
        std::replace(path_as_module.begin(), path_as_module.end(), '/', '.');
        std::replace(path_as_module.begin(), path_as_module.end(), '\\', '.');
        module_candidates.push_back(path_as_module + "." + filename);
    }

    LOG_INFO("Clearing Lua cache for file: {}", normalized_path);

    // Clear package.loaded for all module candidates
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");

    for (const auto& module_name : module_candidates) {
        lua_pushnil(L);
        lua_setfield(L, -2, module_name.c_str());
        LOG_INFO("  Cleared module: {}", module_name);
    }

    lua_pop(L, 2); // pop loaded and package tables

    // Reload all documents to re-execute their <script> tags
    ReloadAllDocuments();
}

void DocumentManager::UnloadAllDocuments() {
    loaded_documents_.clear();
    if (context_) {
        context_->UnloadAllDocuments();
    }
}

void DocumentManager::ReloadAllDocuments() {
    if (!context_) return;

    int num_docs = context_->GetNumDocuments();
    for (int i = 0; i < num_docs; i++) {
        auto doc = context_->GetDocument(i);
        if (!doc) continue;

        // Skip debugger documents - they don't have file sources and shouldn't be reloaded
        if (doc->GetId().find("rmlui-debug-") == 0) {
            continue;
        }

        std::string src = doc->GetSourceURL();
        bool was_visible = doc->IsVisible();

        doc->Close();
        auto new_doc = context_->LoadDocument(src.c_str());

        // Update tracked documents
        std::string reloaded_doc_id;
        for (auto& [doc_id, tracked_doc] : loaded_documents_) {
            if (tracked_doc == doc) {
                loaded_documents_[doc_id] = new_doc;
                if (new_doc) {
                    new_doc->SetId(doc_id.c_str());
                }
                reloaded_doc_id = doc_id;
                break;
            }
        }

        if (new_doc && was_visible) {
            new_doc->Show();
        }

        // Notify owning thread that document was reloaded
        if (event_dispatcher_ && !reloaded_doc_id.empty()) {
            event_dispatcher_->DispatchEvent(reloaded_doc_id, "document_reloaded", {});
        }
    }

    // Force context update to rebind data models
    if (context_) {
        context_->Update();
    }
}

Rml::Element* DocumentManager::FindElementById(const std::string& element_id) {
    if (!context_) return nullptr;

    // Search all documents for the element
    for (int i = 0; i < context_->GetNumDocuments(); i++) {
        auto doc = context_->GetDocument(i);
        if (doc) {
            auto element = doc->GetElementById(element_id.c_str());
            if (element) {
                return element;
            }
        }
    }
    return nullptr;
}

DocumentManager::DocumentInfo DocumentManager::GetDocumentInfo(const std::string& document_id) const {
    DocumentInfo info;
    info.document_id = document_id;
    info.path = "";
    info.visible = false;
    info.element_count = 0;
    info.width = 0;
    info.height = 0;

    auto it = loaded_documents_.find(document_id);
    if (it != loaded_documents_.end() && it->second != nullptr) {
        auto doc = it->second;
        info.path = doc->GetSourceURL();
        info.visible = doc->IsVisible();

        // Count elements (recursively)
        std::function<int(Rml::Element*)> count_elements = [&](Rml::Element* elem) -> int {
            if (!elem) return 0;
            int count = 1;  // Count this element
            for (int i = 0; i < elem->GetNumChildren(); ++i) {
                count += count_elements(elem->GetChild(i));
            }
            return count;
        };
        info.element_count = count_elements(doc);

        // Get dimensions
        auto box = doc->GetBox();
        info.width = static_cast<int>(box.GetSize().x);
        info.height = static_cast<int>(box.GetSize().y);
    }

    return info;
}

std::vector<DocumentManager::DocumentInfo> DocumentManager::GetAllDocumentInfo() const {
    std::vector<DocumentInfo> result;

    for (const auto& [doc_id, doc] : loaded_documents_) {
        if (doc != nullptr) {
            result.push_back(GetDocumentInfo(doc_id));
        }
    }

    return result;
}
