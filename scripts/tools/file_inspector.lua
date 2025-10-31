-- File Inspector
-- Intelligent file inspection with automatic sampling, structure detection, and parsing hints

local FileInspector = {}

-- Detect file format from content
local function detect_format(content, extension)
    -- Normalize extension to lowercase
    if extension then
        extension = extension:lower()
    end

    -- Try JSON
    if extension == ".json" then
        local success, _ = pcall(json.decode, content)
        if success then
            return "json"
        end
    end

    -- Try CSV (check for commas in first line)
    local first_line = content:match("^([^\n]+)")
    if first_line then
        local comma_count = 0
        for _ in first_line:gmatch(",") do
            comma_count = comma_count + 1
        end
        if comma_count >= 2 then
            return "csv"
        end
    end

    -- Check for XML
    if content:match("^%s*<%?xml") or content:match("^%s*<!DOCTYPE") or content:match("^%s*<[a-zA-Z]") then
        return "xml"
    end

    return "plain"
end

-- Check if content has headers (for CSV/TSV)
local function detect_headers(content, format)
    if format ~= "csv" then
        return false
    end

    local lines = {}
    for line in content:gmatch("([^\n]+)") do
        table.insert(lines, line)
        if #lines >= 3 then break end
    end

    if #lines < 2 then
        return false
    end

    -- Check if first line looks like headers (no numbers, all text)
    local first_line = lines[1]
    local has_numbers = first_line:match("%d+%.%d+") or first_line:match("^%d+,")
    if has_numbers then
        return false
    end

    -- Check if subsequent lines look like data (has numbers)
    local second_line = lines[2]
    local has_data = second_line:match("%d")

    return not has_numbers and has_data
end

-- Count lines in content
local function count_lines(content)
    local count = 0
    for _ in content:gmatch("\n") do
        count = count + 1
    end
    return count + 1 -- Add one for last line
end

-- Get sample lines (first N and last N)
local function get_sample_lines(content, first_n, last_n)
    local lines = {}
    for line in content:gmatch("([^\n]+)") do
        table.insert(lines, line)
    end

    local samples = {}

    -- First N lines
    for i = 1, math.min(first_n, #lines) do
        table.insert(samples, lines[i])
    end

    -- Last N lines (if file was long enough to be interesting)
    if #lines > first_n + last_n then
        samples.separator = "... (" .. (#lines - first_n - last_n) .. " lines omitted) ..."
        for i = math.max(#lines - last_n + 1, first_n + 1), #lines do
            table.insert(samples, lines[i])
        end
    end

    return samples
end

-- Calculate average line length
local function avg_line_length(content)
    local total = 0
    local count = 0
    for line in content:gmatch("([^\n]+)") do
        total = total + #line
        count = count + 1
    end
    return count > 0 and (total / count) or 0
end

-- Inspect a file with intelligent sampling
function FileInspector.inspect_file(path, max_bytes)
    -- Get file metadata
    local stat_result, stat_err = fs.stat(path)
    if not stat_result then
        return {
            error = "File not found: " .. path
        }
    end

    local extension = fs.extension(path)
    local is_binary = false -- We'll determine this from content

    -- Determine max bytes based on file type hint
    if not max_bytes then
        if extension == ".jpg" or extension == ".png" or extension == ".gif" or
           extension == ".pdf" or extension == ".zip" or extension == ".exe" then
            max_bytes = 1024 -- Binary files: just peek
            is_binary = true
        else
            max_bytes = 32768 -- Text files: read more
        end
    end

    -- Read file content (limited)
    local content, read_err = fs.read_file(path)
    if not content then
        return {
            metadata = {
                path = path,
                name = fs.basename(path),
                extension = extension,
                size = stat_result.size,
                is_binary = is_binary
            },
            error = "Failed to read file: " .. (read_err or "unknown error")
        }
    end

    local was_truncated = false
    local truncated_at_bytes = #content

    if #content > max_bytes then
        content = content:sub(1, max_bytes)
        was_truncated = true
        truncated_at_bytes = max_bytes
    end

    -- Detect if actually binary by checking for null bytes or high percentage of non-printable chars
    local null_bytes = 0
    local non_printable = 0
    local sample_size = math.min(512, #content)
    for i = 1, sample_size do
        local byte = content:byte(i)
        if byte == 0 then
            null_bytes = null_bytes + 1
        elseif byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then
            non_printable = non_printable + 1
        end
    end

    if null_bytes > 0 or (non_printable / sample_size) > 0.3 then
        is_binary = true
    end

    -- If binary, return limited info
    if is_binary then
        return {
            metadata = {
                path = path,
                name = fs.basename(path),
                extension = extension,
                size = stat_result.size,
                mime_type = "application/octet-stream",
                is_binary = true
            },
            content = nil,
            structure_hints = {
                detected_format = "binary"
            },
            parsing_suggestions = {
                "This is a binary file",
                "Binary files typically cannot be parsed as text",
                "Consider excluding binary files from text-based imports"
            }
        }
    end

    -- Analyze text content
    local detected_format = detect_format(content, extension)
    local has_headers = detect_headers(content, detected_format)
    local line_count = count_lines(content)
    local avg_line_len = avg_line_length(content)
    local sample_lines = get_sample_lines(content, 5, 5)

    -- Generate parsing suggestions
    local parsing_suggestions = {}

    if detected_format == "json" then
        table.insert(parsing_suggestions, "Parse as JSON using json.decode()")
        table.insert(parsing_suggestions, "JSON structure appears valid")

        -- Try to detect if it's an array of objects
        local success, parsed = pcall(json.decode, content)
        if success and type(parsed) == "table" then
            if #parsed > 0 then
                table.insert(parsing_suggestions, "Contains array of " .. #parsed .. " objects")
                table.insert(parsing_suggestions, "Each object can map to a database row")
            else
                table.insert(parsing_suggestions, "Contains single object - use for configuration or metadata")
            end
        end

    elseif detected_format == "csv" then
        if has_headers then
            table.insert(parsing_suggestions, "CSV with headers detected")
            table.insert(parsing_suggestions, "First line contains column names")
            table.insert(parsing_suggestions, "Use headers to map to database columns")
        else
            table.insert(parsing_suggestions, "CSV without headers - will need to define column names")
        end
        table.insert(parsing_suggestions, "Split lines by comma, handle quoted values")
        table.insert(parsing_suggestions, "Consider using a CSV parsing library")

    elseif detected_format == "xml" then
        table.insert(parsing_suggestions, "XML format detected")
        table.insert(parsing_suggestions, "Will need XML parser to extract structured data")
        table.insert(parsing_suggestions, "Map XML elements to database tables")

    else
        table.insert(parsing_suggestions, "Plain text format")
        table.insert(parsing_suggestions, "Look for patterns in line structure")
        if avg_line_len > 100 then
            table.insert(parsing_suggestions, "Long lines - might be unstructured prose or logs")
        else
            table.insert(parsing_suggestions, "Short lines - might be list or simple records")
        end
    end

    return {
        metadata = {
            path = path,
            name = fs.basename(path),
            extension = extension,
            size = stat_result.size,
            mime_type = "text/plain",
            is_binary = false
        },
        content = content,
        was_truncated = was_truncated,
        truncated_at_bytes = truncated_at_bytes,
        structure_hints = {
            has_headers = has_headers,
            line_count = line_count,
            avg_line_length = math.floor(avg_line_len),
            detected_format = detected_format,
            detected_encoding = "utf-8", -- Assume UTF-8 for now
            sample_lines = sample_lines
        },
        parsing_suggestions = parsing_suggestions
    }
end

-- Analyze a collection of files for patterns and relationships
function FileInspector.analyze_collection(files)
    -- Build directory structure
    local dir_tree = {}
    for _, file in ipairs(files) do
        local dir = fs.dirname(file.path)
        if not dir_tree[dir] then
            dir_tree[dir] = {}
        end
        table.insert(dir_tree[dir], file.name)
    end

    -- Detect naming patterns
    local naming_patterns = {}
    local extensions = {}

    for _, file in ipairs(files) do
        -- Track extensions
        local ext = file.type or ""
        extensions[ext] = (extensions[ext] or 0) + 1

        -- Look for date patterns in filename
        if file.name:match("%d%d%d%d%-%d%d%-%d%d") then
            table.insert(naming_patterns, {
                pattern = "Date-stamped files (YYYY-MM-DD)",
                example = file.name
            })
        end

        -- Look for numbered sequences
        if file.name:match("%d+") then
            table.insert(naming_patterns, {
                pattern = "Numbered sequence",
                example = file.name
            })
        end
    end

    -- Deduplicate naming patterns
    local unique_patterns = {}
    local seen = {}
    for _, pattern in ipairs(naming_patterns) do
        if not seen[pattern.pattern] then
            table.insert(unique_patterns, pattern)
            seen[pattern.pattern] = true
        end
    end

    -- Detect probable relationships
    local relationships = {}

    -- Files with same base name but different extensions might be related
    local base_names = {}
    for _, file in ipairs(files) do
        local base = fs.stem(file.path)
        if not base_names[base] then
            base_names[base] = {}
        end
        table.insert(base_names[base], file.name)
    end

    for base, file_list in pairs(base_names) do
        if #file_list > 1 then
            table.insert(relationships, {
                relationship_type = "Same base name, different formats",
                files = file_list,
                confidence = "high"
            })
        end
    end

    -- Format consistency check
    local format_consistency = {}
    local format_files = {}

    for _, file in ipairs(files) do
        local ext = file.type or "unknown"
        if not format_files[ext] then
            format_files[ext] = {}
        end
        table.insert(format_files[ext], file.name)
    end

    for ext, file_list in pairs(format_files) do
        local consistency_score = "consistent"
        if #file_list < #files / 2 then
            consistency_score = "mixed"
        end

        format_consistency[ext] = {
            files = file_list,
            count = #file_list,
            consistency_score = consistency_score
        }
    end

    -- Generate recommendations
    local recommendations = {}

    local ext_count = 0
    for _ in pairs(extensions) do
        ext_count = ext_count + 1
    end

    if ext_count == 1 then
        table.insert(recommendations, "All files are same format - single parser can handle all")
    elseif ext_count <= 3 then
        table.insert(recommendations, "Few file formats - create a parser for each type")
    else
        table.insert(recommendations, "Many file formats - prioritize most common types first")
    end

    if #files > 100 then
        table.insert(recommendations, "Large file collection - consider batch processing")
        table.insert(recommendations, "May want to sample subset for schema design")
    end

    return {
        directory_structure = dir_tree,
        naming_patterns = unique_patterns,
        probable_relationships = relationships,
        format_consistency = format_consistency,
        recommendations = recommendations
    }
end

-- List files with rich metadata and statistics
function FileInspector.list_files(files)
    -- Calculate statistics
    local by_extension = {}
    local by_mime = {}
    local total_size = 0
    local largest_file = nil
    local largest_size = 0
    local binary_count = 0
    local text_count = 0

    for _, file in ipairs(files) do
        local ext = file.type or "unknown"
        by_extension[ext] = (by_extension[ext] or 0) + 1

        local mime = file.mime_type or "unknown"
        by_mime[mime] = (by_mime[mime] or 0) + 1

        local size = file.size or 0
        total_size = total_size + size

        if size > largest_size then
            largest_size = size
            largest_file = file.name
        end

        if file.is_binary then
            binary_count = binary_count + 1
        else
            text_count = text_count + 1
        end
    end

    local avg_size = #files > 0 and (total_size / #files) or 0

    -- Sample files (up to 10)
    local sample_files = {}
    for i = 1, math.min(10, #files) do
        table.insert(sample_files, {
            path = files[i].path,
            name = files[i].name,
            extension = files[i].type,
            size = files[i].size,
            mime_type = files[i].mime_type
        })
    end

    return {
        total_count = #files,
        by_extension = by_extension,
        by_mime_type = by_mime,
        size_stats = {
            total_bytes = total_size,
            avg_bytes = math.floor(avg_size),
            largest_file = largest_file,
            largest_bytes = largest_size
        },
        sample_files = sample_files,
        binary_vs_text = {
            binary_count = binary_count,
            text_count = text_count
        }
    }
end

return FileInspector
