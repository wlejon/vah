#include "DocumentManager.h"
#include "Logger.h"
#include <algorithm>
#include <RmlUi/Lua/Interpreter.h>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

DocumentManager::DocumentManager(Rml::Context* context)
    : context_(context)
{
}

void DocumentManager::LoadDocument(const std::string& document_path, bool show, const std::string& document_id) {
    if (!context_) {
        LOG_WARN("Cannot load document: context is null");
        return;
    }

    auto doc = context_->LoadDocument(document_path.c_str());
    if (doc) {
        // Store document if ID provided
        if (!document_id.empty()) {
            loaded_documents_[document_id] = doc;
            LOG_INFO("Stored document with ID: {}", document_id);
        }

        if (show) {
            doc->Show();
        } else {
            doc->Hide();
        }
        LOG_INFO("Loaded UI document: {}", document_path);
    } else {
        LOG_WARN("Failed to load UI document: {}", document_path);
    }
}

void DocumentManager::ShowDocument(const std::string& document_id) {
    auto it = loaded_documents_.find(document_id);
    if (it != loaded_documents_.end()) {
        it->second->Show();
        LOG_INFO("Showing document: {}", document_id);
    } else {
        LOG_WARN("Document not found: {}", document_id);
    }
}

void DocumentManager::HideDocument(const std::string& document_id) {
    auto it = loaded_documents_.find(document_id);
    if (it != loaded_documents_.end()) {
        it->second->Hide();
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

void DocumentManager::HandleRmlFileChanged(const std::string& normalized_path) {
    if (!context_) return;

    // Iterate through ALL documents in context (not just tracked ones)
    int num_docs = context_->GetNumDocuments();
    for (int i = 0; i < num_docs; i++) {
        auto doc = context_->GetDocument(i);
        if (!doc) continue;

        std::string src = doc->GetSourceURL();

        // Check if the changed file matches this document
        // Compare with both absolute and relative paths
        if (src == normalized_path ||
            normalized_path.ends_with(src) ||
            src.ends_with(normalized_path)) {

            LOG_INFO("Auto-reloading document: {}", src);
            bool was_visible = doc->IsVisible();

            doc->Close();
            auto new_doc = context_->LoadDocument(src.c_str());
            if (new_doc && was_visible) {
                new_doc->Show();
            }

            // Update tracked documents map if this doc has an ID
            for (auto& [doc_id, tracked_doc] : loaded_documents_) {
                if (tracked_doc == doc) {
                    loaded_documents_[doc_id] = new_doc;
                    break;
                }
            }
            break;
        }
    }
}

void DocumentManager::HandleRcssFileChanged() {
    if (!context_) return;

    // Clear the stylesheet cache so RmlUi reloads the CSS
    Rml::Factory::ClearStyleSheetCache();

    int num_docs = context_->GetNumDocuments();
    for (int i = 0; i < num_docs; i++) {
        auto doc = context_->GetDocument(i);
        if (!doc) continue;

        std::string src = doc->GetSourceURL();
        bool was_visible = doc->IsVisible();

        doc->Close();
        auto new_doc = context_->LoadDocument(src.c_str());

        // Update tracked documents
        for (auto& [doc_id, tracked_doc] : loaded_documents_) {
            if (tracked_doc == doc) {
                loaded_documents_[doc_id] = new_doc;
                break;
            }
        }

        if (new_doc && was_visible) {
            new_doc->Show();
        }
    }
}

void DocumentManager::HandleLuaFileChanged(const std::string& normalized_path) {
    if (!context_) return;

    // Clear the Lua module cache so require() will reload the file
    lua_State* L = Rml::Lua::Interpreter::GetLuaState();
    if (!L) {
        LOG_WARN("Cannot clear Lua cache: Lua state is null");
        return;
    }

    // Extract module name from path (e.g., "ui/canvas_test.lua" -> "canvas_test")
    std::string module_name;
    size_t last_slash = normalized_path.find_last_of("/\\");
    size_t last_dot = normalized_path.find_last_of(".");

    if (last_slash != std::string::npos && last_dot != std::string::npos && last_dot > last_slash) {
        module_name = normalized_path.substr(last_slash + 1, last_dot - last_slash - 1);
    } else if (last_dot != std::string::npos) {
        module_name = normalized_path.substr(0, last_dot);
    } else {
        module_name = normalized_path;
    }

    LOG_INFO("Clearing Lua cache for module: {}", module_name);

    // Clear package.loaded[module_name]
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_pushnil(L);
    lua_setfield(L, -2, module_name.c_str());
    lua_pop(L, 2); // pop loaded and package tables

    // Reload all documents to re-execute their <script> tags
    int num_docs = context_->GetNumDocuments();
    for (int i = 0; i < num_docs; i++) {
        auto doc = context_->GetDocument(i);
        if (!doc) continue;

        std::string src = doc->GetSourceURL();
        bool was_visible = doc->IsVisible();

        doc->Close();
        auto new_doc = context_->LoadDocument(src.c_str());

        // Update tracked documents
        for (auto& [doc_id, tracked_doc] : loaded_documents_) {
            if (tracked_doc == doc) {
                loaded_documents_[doc_id] = new_doc;
                break;
            }
        }

        if (new_doc && was_visible) {
            new_doc->Show();
        }
    }
}

void DocumentManager::UnloadAllDocuments() {
    loaded_documents_.clear();
    if (context_) {
        context_->UnloadAllDocuments();
    }
}

void DocumentManager::UpdateTrackedDocument(Rml::ElementDocument* old_doc, Rml::ElementDocument* new_doc) {
    for (auto& [doc_id, tracked_doc] : loaded_documents_) {
        if (tracked_doc == old_doc) {
            loaded_documents_[doc_id] = new_doc;
            break;
        }
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
