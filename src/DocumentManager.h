#pragma once

#include <RmlUi/Core.h>
#include <string>
#include <unordered_map>
#include "DataStore.h"  // For DynamicTable and DynamicValue types

class RmlUiBridge;  // Forward declaration
class EventDispatcher;  // Forward declaration

class DocumentManager {
public:
    DocumentManager(Rml::Context* context, RmlUiBridge* rmlui_bridge = nullptr, EventDispatcher* event_dispatcher = nullptr);
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
    void TextEditorCopy(const std::string& element_id);
    void TextEditorPaste(const std::string& element_id);
    void TextEditorCut(const std::string& element_id);
    void TextEditorSelectAll(const std::string& element_id);
    void TextEditorUndo(const std::string& element_id);
    void TextEditorRedo(const std::string& element_id);
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

    // Check and reset the document changed flag
    bool GetAndClearDocumentChangedFlag();

    // Query document information (for MCP API)
    struct DocumentInfo {
        std::string document_id;
        std::string path;
        bool visible;
        int element_count;
        int width;
        int height;
    };

    DocumentInfo GetDocumentInfo(const std::string& document_id) const;
    std::vector<DocumentInfo> GetAllDocumentInfo() const;

private:
    Rml::Context* context_;
    RmlUiBridge* rmlui_bridge_;
    EventDispatcher* event_dispatcher_;
    std::unordered_map<std::string, Rml::ElementDocument*> loaded_documents_;

    // Flag to track if documents changed this frame
    bool document_changed_this_frame_ = false;

    // Helper to find element by ID across all documents
    Rml::Element* FindElementById(const std::string& element_id);
};
