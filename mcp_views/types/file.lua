-- File Type Definition
-- Provides views for files in the file system

return {
    name = "File",
    plural = "Files",

    -- Query functions for each view type
    query = {
        -- List files in a directory
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10
            local directory = context.directory or "."

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            local offset = (page - 1) * limit

            -- List directory
            local entries, err = fs.list_dir(directory)

            if err ~= "" then
                return {
                    items = {},
                    total = 0,
                    page = page,
                    total_pages = 0,
                    limit = limit
                }
            end

            -- Filter for files only (not directories)
            local files = {}
            for _, entry in ipairs(entries) do
                if not entry.is_dir then
                    local path = directory .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)

                    local size = 0
                    local modified = ""
                    local extension = ""
                    if stat_err == "" and stats then
                        size = stats.size or 0
                        modified = stats.modified or ""
                    end

                    -- Get extension
                    extension = entry.name:match("%.([^%.]+)$") or ""

                    table.insert(files, {
                        name = entry.name,
                        path = path,
                        size = size,
                        modified = modified,
                        extension = extension
                    })
                end
            end

            -- Sort by name
            table.sort(files, function(a, b)
                return a.name < b.name
            end)

            -- Paginate
            local total = #files
            local total_pages = math.ceil(total / limit)
            local items = {}

            for i = offset + 1, math.min(offset + limit, total) do
                table.insert(items, files[i])
            end

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit,
                directory = directory
            }
        end,

        -- View file details
        detail = function(context)
            local file_path = context.id

            if not file_path then
                error("Missing file path")
            end

            -- Get file stats
            local stats, err = fs.stat(file_path)
            if err ~= "" then
                error("File not found: " .. file_path)
            end

            -- Read file content (if text file and not too large)
            local content = nil
            local is_text = false
            local extension = file_path:match("%.([^%.]+)$") or ""

            local text_extensions = {
                txt = true, md = true, lua = true, cpp = true, h = true, hpp = true,
                js = true, py = true, json = true, xml = true, yaml = true, yml = true,
                css = true, html = true, sql = true, csv = true
            }

            if text_extensions[extension:lower()] and stats.size < 100000 then
                is_text = true
                local file_content, read_err = fs.read_file(file_path)
                if read_err == "" then
                    content = file_content
                end
            end

            return {
                id = file_path,
                name = file_path:match("([^/\\]+)$") or file_path,
                path = file_path,
                size = stats.size or 0,
                modified = stats.modified or "",
                extension = extension,
                is_text = is_text,
                content = content,
                content_preview = content and content:sub(1, 500) or nil
            }
        end,

        -- File summary statistics
        summary = function(context)
            local directory = context.directory or "."

            local entries, err = fs.list_dir(directory)

            if err ~= "" then
                return {
                    total_files = 0,
                    total_size = 0,
                    directory = directory
                }
            end

            local total_files = 0
            local total_size = 0
            local extensions = {}

            for _, entry in ipairs(entries) do
                if not entry.is_dir then
                    total_files = total_files + 1
                    local path = directory .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)
                    if stat_err == "" and stats then
                        total_size = total_size + (stats.size or 0)
                    end

                    local ext = entry.name:match("%.([^%.]+)$") or "none"
                    extensions[ext] = (extensions[ext] or 0) + 1
                end
            end

            return {
                total_files = total_files,
                total_size = total_size,
                average_size = total_files > 0 and (total_size / total_files) or 0,
                directory = directory,
                extensions = extensions
            }
        end,

        -- Search files
        search = function(context)
            local search_query = context.query or ""
            local directory = context.directory or "."

            if search_query == "" then
                return {
                    query = search_query,
                    items = {},
                    total_matches = 0
                }
            end

            local entries, err = fs.list_dir(directory)

            if err ~= "" then
                return {
                    query = search_query,
                    items = {},
                    total_matches = 0
                }
            end

            local matches = {}
            local search_lower = search_query:lower()

            for _, entry in ipairs(entries) do
                if not entry.is_dir and entry.name:lower():find(search_lower, 1, true) then
                    local path = directory .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)

                    table.insert(matches, {
                        name = entry.name,
                        path = path,
                        size = (stat_err == "" and stats) and stats.size or 0
                    })
                end
            end

            return {
                query = search_query,
                items = matches,
                total_matches = #matches
            }
        end,

        -- Diff view (compare file versions)
        diff = function(context)
            -- For now, not supported
            return {
                id = context.id or "",
                supported = false,
                not_supported = true,
                message = "Diff view is not yet implemented for files"
            }
        end,

        -- File system status
        status = function(context)
            return {
                status = "ready",
                message = "File system operational"
            }
        end
    },

    -- No action tools yet (read-only)
    tools = {},

    -- No custom templates (use generic ones)
    templates = {}
}
