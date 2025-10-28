-- Directory Type Definition
-- Provides views for directories in the file system

return {
    name = "Directory",
    plural = "Directories",

    -- Query functions for each view type
    query = {
        -- List subdirectories within a directory
        list = function(context)
            local page = tonumber(context.page) or 1
            local limit = tonumber(context.limit) or 10
            local parent_directory = context.directory or "."

            -- Ensure page is at least 1
            if page < 1 then page = 1 end
            if limit < 1 then limit = 10 end

            local offset = (page - 1) * limit

            -- List directory
            local entries, err = fs.list_dir(parent_directory)

            if err ~= "" then
                return {
                    items = {},
                    total = 0,
                    page = page,
                    total_pages = 0,
                    limit = limit,
                    parent_directory = parent_directory
                }
            end

            -- Filter for directories only
            local directories = {}
            for _, entry in ipairs(entries) do
                if entry.is_dir then
                    local path = parent_directory .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)

                    local modified = ""
                    if stat_err == "" and stats then
                        modified = stats.modified or ""
                    end

                    -- Count items in subdirectory
                    local sub_entries, sub_err = fs.list_dir(path)
                    local item_count = 0
                    local file_count = 0
                    local dir_count = 0

                    if sub_err == "" and sub_entries then
                        item_count = #sub_entries
                        for _, sub_entry in ipairs(sub_entries) do
                            if sub_entry.is_dir then
                                dir_count = dir_count + 1
                            else
                                file_count = file_count + 1
                            end
                        end
                    end

                    table.insert(directories, {
                        name = entry.name,
                        path = path,
                        modified = modified,
                        item_count = item_count,
                        file_count = file_count,
                        dir_count = dir_count
                    })
                end
            end

            -- Sort by name
            table.sort(directories, function(a, b)
                return a.name < b.name
            end)

            -- Paginate
            local total = #directories
            local total_pages = math.max(1, math.ceil(total / limit))
            local items = {}

            local start_idx = offset + 1
            local end_idx = math.min(offset + limit, total)

            for i = start_idx, end_idx do
                table.insert(items, directories[i])
            end

            return {
                items = items,
                total = total,
                page = page,
                total_pages = total_pages,
                limit = limit,
                parent_directory = parent_directory
            }
        end,

        -- View directory details
        detail = function(context)
            local dir_path = context.id

            if not dir_path then
                error("Missing directory path")
            end

            -- Get directory stats
            local stats, err = fs.stat(dir_path)
            if err ~= "" then
                error("Directory not found: " .. dir_path)
            end

            if not stats.is_dir then
                error("Not a directory: " .. dir_path)
            end

            -- List directory contents
            local entries, list_err = fs.list_dir(dir_path)

            local total_items = 0
            local file_count = 0
            local dir_count = 0
            local total_size = 0

            if list_err == "" and entries then
                total_items = #entries

                for _, entry in ipairs(entries) do
                    if entry.is_dir then
                        dir_count = dir_count + 1
                    else
                        file_count = file_count + 1

                        -- Get file size
                        local file_path = dir_path .. "/" .. entry.name
                        local file_stats, file_err = fs.stat(file_path)
                        if file_err == "" and file_stats then
                            total_size = total_size + (file_stats.size or 0)
                        end
                    end
                end
            end

            -- Get parent directory
            local parent = dir_path:match("^(.+)[/\\][^/\\]+$") or ""

            return {
                id = dir_path,
                name = dir_path:match("([^/\\]+)$") or dir_path,
                path = dir_path,
                parent = parent,
                modified = stats.modified or "",
                total_items = total_items,
                file_count = file_count,
                dir_count = dir_count,
                total_size = total_size
            }
        end,

        -- Directory summary statistics
        summary = function(context)
            local directory = context.directory or "."

            local entries, err = fs.list_dir(directory)

            if err ~= "" then
                return {
                    total_directories = 0,
                    total_files = 0,
                    total_size = 0,
                    directory = directory
                }
            end

            local total_directories = 0
            local total_files = 0
            local total_size = 0

            for _, entry in ipairs(entries) do
                if entry.is_dir then
                    total_directories = total_directories + 1
                else
                    total_files = total_files + 1
                    local path = directory .. "/" .. entry.name
                    local stats, stat_err = fs.stat(path)
                    if stat_err == "" and stats then
                        total_size = total_size + (stats.size or 0)
                    end
                end
            end

            return {
                total_directories = total_directories,
                total_files = total_files,
                total_items = total_directories + total_files,
                total_size = total_size,
                average_file_size = total_files > 0 and (total_size / total_files) or 0,
                directory = directory
            }
        end,

        -- Search directories
        search = function(context)
            local search_query = context.query or ""
            local parent_directory = context.directory or "."

            if search_query == "" then
                return {
                    query = search_query,
                    items = {},
                    total_matches = 0
                }
            end

            local entries, err = fs.list_dir(parent_directory)

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
                if entry.is_dir and entry.name:lower():find(search_lower, 1, true) then
                    local path = parent_directory .. "/" .. entry.name

                    -- Count items in subdirectory
                    local sub_entries, sub_err = fs.list_dir(path)
                    local item_count = 0
                    if sub_err == "" and sub_entries then
                        item_count = #sub_entries
                    end

                    table.insert(matches, {
                        name = entry.name,
                        path = path,
                        item_count = item_count
                    })
                end
            end

            return {
                query = search_query,
                items = matches,
                total_matches = #matches,
                directory = parent_directory
            }
        end,

        -- Diff view (not supported for directories)
        diff = function(context)
            return {
                id = context.id or "",
                supported = false,
                not_supported = true,
                message = "Diff view is not supported for directories"
            }
        end,

        -- Directory system status
        status = function(context)
            return {
                status = "ready",
                message = "Directory system operational"
            }
        end
    },

    -- No action tools yet (read-only)
    tools = {},

    -- No custom templates (use generic ones)
    templates = {}
}
