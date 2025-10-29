-- Document Type Definition
-- Provides views for loaded RML documents

-- Helper to get document list (now synchronous - blocks until ready)
local function ui_list_documents_sync()
    if not ui or not ui.list_documents then
        return {}  -- API not available
    end

    local result = ui.list_documents()  -- Blocks until response arrives
    if not result then
        return {}
    end

    -- Convert numeric-keyed table to array
    local documents = result.documents or {}
    local documents_array = {}
    for i = 1, 100 do  -- Assume max 100 documents
        local key = tostring(i)
        if documents[key] then
            table.insert(documents_array, documents[key])
        else
            break  -- No more documents
        end
    end

    return documents_array
end

-- Helper to get info for specific document (now synchronous - blocks until ready)
local function ui_get_document_info_sync(document_id)
    if not ui or not ui.get_document_info then
        return nil
    end

    return ui.get_document_info(document_id)  -- Blocks until response arrives
end

return {
    name = "Document",
    plural = "Documents",

    -- Query functions for each view type
    query = {
        -- List all loaded RML documents
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            local offset = (page - 1) * limit

            -- Get loaded documents
            local documents = {}
            local doc_list = ui_list_documents_sync()

            for _, doc in ipairs(doc_list) do
                table.insert(documents, {
                    document_id = doc.document_id or "",
                    name = doc.document_id or "Unknown",
                    path = doc.path or "",
                    visible = doc.visible or false,
                    element_count = tonumber(doc.element_count) or 0
                })
            end

            -- Sort by document_id
            table.sort(documents, function(a, b)
                return a.document_id < b.document_id
            end)

            -- Paginate
            local total = #documents
            local total_pages = math.max(1, math.ceil(total / limit))
            local items = {}

            local start_idx = offset + 1
            local end_idx = math.min(offset + limit, total)

            for i = start_idx, end_idx do
                table.insert(items, documents[i])
            end

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit
            }
        end,

        -- View document details
        detail = function(context)
            local document_id = context.id

            if not document_id then
                error("Missing document ID")
            end

            -- Get document info
            local info = ui_get_document_info_sync(document_id)

            if not info or info.error then
                error("Document not found: " .. document_id)
            end

            return {
                id = info.document_id or document_id,
                document_id = info.document_id or document_id,
                name = info.document_id or "Unknown",
                path = info.path or "",
                visible = info.visible or false,
                element_count = tonumber(info.element_count) or 0,
                width = tonumber(info.width) or 0,
                height = tonumber(info.height) or 0
            }
        end,

        -- Summary statistics for all documents
        summary = function(context)
            local doc_list = ui_list_documents_sync()

            local total = #doc_list
            local visible = 0
            local hidden = 0
            local total_elements = 0

            for _, doc in ipairs(doc_list) do
                if doc.visible then
                    visible = visible + 1
                else
                    hidden = hidden + 1
                end
                total_elements = total_elements + (tonumber(doc.element_count) or 0)
            end

            return {
                total = total,
                visible = visible,
                hidden = hidden,
                total_elements = total_elements
            }
        end,

        -- Search documents by ID or path
        search = function(context)
            local query = context.query or ""
            local doc_list = ui_list_documents_sync()

            local results = {}

            for _, doc in ipairs(doc_list) do
                local document_id = doc.document_id or ""
                local path = doc.path or ""

                if document_id:lower():find(query:lower(), 1, true) or
                   path:lower():find(query:lower(), 1, true) then
                    table.insert(results, {
                        document_id = document_id,
                        name = document_id,
                        path = path,
                        size = 0,  -- Documents don't have file size
                        visible = doc.visible or false,
                        element_count = tonumber(doc.element_count) or 0
                    })
                end
            end

            return {
                items = results,
                total_matches = #results,
                query = query
            }
        end,

        -- Diff view (not supported for documents)
        diff = function(context)
            return {
                supported = false,
                message = "Diff view is not supported for documents"
            }
        end,

        -- Status view (overall document system status)
        status = function(context)
            local doc_list = ui_list_documents_sync()

            return {
                system_status = "ok",
                total_documents = #doc_list,
                timestamp = os.time()
            }
        end
    },

    -- Action tools (future: load_document, show_document, hide_document, close_document)
    tools = {},

    -- Custom templates (uses generic templates for now)
    templates = {}
}
