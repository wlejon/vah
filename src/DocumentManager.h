#pragma once

#include <RmlUi/Core.h>
#include <string>
#include <unordered_map>
#include "DataStore.h"  // For DynamicTable and DynamicValue types

class DocumentManager {
public:
    DocumentManager(Rml::Context* context);
    ~DocumentManager() = default;

    // Document lifecycle
    void LoadDocument(const std::string& document_path, bool show, const std::string& document_id);
    void ShowDocument(const std::string& document_id);
    void HideDocument(const std::string& document_id);
    void ReloadDocument(const std::string& document_id);

    // Element manipulation
    void SetElementText(const std::string& element_id, const std::string& text);
    void SetElementAttribute(const std::string& element_id, const std::string& attribute_name, const std::string& value);
    void SetElementStyle(const std::string& element_id, const std::string& property, const std::string& value);
    void AddElementClass(const std::string& element_id, const std::string& class_name);
    void RemoveElementClass(const std::string& element_id, const std::string& class_name);
    void SetTextEditorContent(const std::string& element_id, const std::string& content);
    void SetTextEditorTokens(const std::string& element_id, const DynamicTable& tokens);
    void SetTextEditorEditable(const std::string& element_id, bool editable);
    void SetTextEditorModified(const std::string& element_id, bool modified);
    void SetTextEditorConfig(const std::string& element_id, const std::string& config_key, const DynamicValue& value);
    std::string GetTextEditorContent(const std::string& element_id);
    bool GetTextEditorModified(const std::string& element_id);

    // File change handling (for hot reload)
    void HandleRmlFileChanged(const std::string& normalized_path);
    void HandleRcssFileChanged();
    void HandleLuaFileChanged(const std::string& normalized_path);

    // Cleanup
    void UnloadAllDocuments();

    // Access tracked document (for hot reload update)
    void UpdateTrackedDocument(Rml::ElementDocument* old_doc, Rml::ElementDocument* new_doc);

private:
    Rml::Context* context_;
    std::unordered_map<std::string, Rml::ElementDocument*> loaded_documents_;

    // Helper to find element by ID across all documents
    Rml::Element* FindElementById(const std::string& element_id);
};
