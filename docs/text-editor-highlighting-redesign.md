# Text Editor Syntax Highlighting Redesign

## Problem

Current implementation uses callbacks from main thread to Lua threads, violating the lock-free architecture. This causes crashes when rapidly opening files.

## Solution

Use data binding for syntax highlighting tokens, following the established pattern.

## Architecture

### Data Flow

```
Lua Thread (file_editor.lua)
    ↓ (compute tokens)
    ↓ data.bind("editor_tokens_[id]", tokens)
    ↓
Command Queue
    ↓
Main Thread (DataStore)
    ↓
ElementTextEditor (reads bound data during render)
```

### Data Model Format

```lua
-- Lua thread binds syntax tokens
data.bind("editor_tokens_code_editor", {
    {line = 0, start_col = 0, end_col = 5, r = 255, g = 100, b = 100, a = 255},
    {line = 0, start_col = 6, end_col = 7, r = 100, g = 255, b = 100, a = 255},
    {line = 1, start_col = 0, end_col = 5, r = 100, g = 100, b = 255, a = 255},
    -- ...
})
```

### Implementation Changes

1. **Remove from ElementTextEditor**:
   - Remove `SyntaxHighlighter` member
   - Remove `SetSyntaxHighlighter()` / `SetReferenceHighlighter()`
   - Remove callback infrastructure

2. **ElementTextEditor reads bound data**:
   - In `GenerateTextGeometry()`, check DataStore for token model
   - Model name: `"editor_tokens_" + element_id`
   - If model exists, use it; otherwise render with default color

3. **Lua side** (file_editor.lua):
   - When file opens, set text via `ui.set_texteditor_content(id, content)`
   - Compute syntax tokens (can be incremental)
   - Bind tokens via `data.bind("editor_tokens_" .. id, tokens)`
   - Can update incrementally as more tokens are computed

4. **Commands**:
   - Remove `highlighter_callback` from `SetTextEditorContent` command
   - Keep command simple: just set text content

### Benefits

- ✓ No cross-thread Lua calls
- ✓ Lock-free architecture maintained
- ✓ Incremental updates supported
- ✓ Large files can display immediately with highlighting appearing progressively
- ✓ Follows established data binding pattern

### Incremental Highlighting Example

```lua
-- Open file immediately with no highlighting
ui.set_texteditor_content("code_editor", file_content)

-- Start computing tokens in background
local tokens = {}
local lines = split_lines(file_content)

for i, line in ipairs(lines) do
    -- Tokenize this line
    local line_tokens = tokenize_line(line, i - 1)
    for _, token in ipairs(line_tokens) do
        table.insert(tokens, token)
    end

    -- Bind incrementally every N lines
    if i % 100 == 0 then
        data.bind("editor_tokens_code_editor", tokens)
    end
end

-- Final bind with all tokens
data.bind("editor_tokens_code_editor", tokens)
```

## Migration Path

1. Update ElementTextEditor to read from DataStore instead of callbacks
2. Update ui.set_texteditor_content to not accept highlighter parameter
3. Update file_editor.lua to compute and bind tokens separately
4. Remove SyntaxHighlighter class entirely
5. Remove callback infrastructure from LuaThread
