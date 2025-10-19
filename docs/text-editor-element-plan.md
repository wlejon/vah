# Text Editor Element - Implementation Plan

## Goal
Build a custom RmlUi element (`<texteditor>`) for viewing and editing text with character-level selection and syntax highlighting.

## Architecture

### File Structure (~2000 lines total, split across files)

**src/TextBuffer.h** (~150 lines)
- Line-based text storage (vector of strings)
- Insert/delete by line and column
- Get line, get line count, get character at position
- Undo/redo stack structure

**src/TextBuffer.cpp** (~200 lines)
- Implementation of text operations
- Undo/redo logic

**src/TextLayout.h** (~100 lines)
- Monospace font metrics (character width, line height)
- Screen position ↔ text position conversion
- Glyph geometry generation using RmlUi's FontEngineInterface

**src/TextLayout.cpp** (~300 lines)
- Position calculations (trivial math with fixed character width)
- Call RmlUi font system to generate glyph meshes
- Return geometry for rendering

**src/SelectionManager.h** (~80 lines)
- Selection state (anchor and cursor positions)
- Get selected range (normalized start/end)
- Extract text from buffer given selection

**src/SelectionManager.cpp** (~100 lines)
- Selection normalization logic
- Text extraction from buffer

**src/SyntaxHighlighter.h** (~60 lines)
- Lua callback interface
- Token structure (line, start_col, end_col, color)
- Cache invalidation

**src/SyntaxHighlighter.cpp** (~120 lines)
- Call Lua function with text
- Parse returned token array
- Manage token cache per line

**src/ElementTextEditor.h** (~150 lines)
- RmlUi::Element subclass
- EventListener interface
- Private members for all components above
- Lua binding interface declarations

**src/ElementTextEditor.cpp** (~800 lines)
- RmlUi lifecycle (OnChildAdd, OnChildRemove, OnUpdate, OnRender)
- Mouse event handling (down/move/up → update selection)
- Keyboard handling (Ctrl+C → copy)
- Geometry generation (call TextLayout, combine with selection quads)
- Lua bindings (SetText, GetText, GetSelectedText, SetSyntaxHighlighter)
- Dirty tracking and regeneration logic

**src/ElementTextEditorInstancer.h** (~40 lines)
- RmlUi element instancer (factory pattern)

**src/ElementTextEditorInstancer.cpp** (~50 lines)
- Create ElementTextEditor instances

**src/main.cpp modifications** (~10 lines added)
- Register ElementTextEditor factory with RmlUi
- Load JetBrains Mono font

## Implementation Constraints

**Font:** JetBrains Mono (monospace) at `ui/fonts/jetbrains-mono-static/`
- Fixed character width makes position calculation: `col * char_width`
- Fixed line height makes line calculation: `y / line_height`

**Coordinate System:**
- Screen coords: pixels from element top-left
- Text coords: (line, column) where line=0-based, column=0-based
- Conversion is direct arithmetic with font metrics

**Selection Rendering:**
- Draw colored quads behind text for selected ranges
- One quad per line in selection
- Generated as simple Geometry with 6 vertices per quad

**Text Rendering:**
- Use RmlUi's FontEngineInterface to generate glyph geometry
- Apply syntax colors per token during geometry generation
- Batch by color for efficiency

**Dirty Tracking:**
- text_dirty_ flag → regenerate all text geometry
- selection_dirty_ flag → regenerate selection quads only
- Only regenerate what changed

## Lua Interface

```lua
local editor = document:GetElementById('my_editor')

-- Set content
editor:SetText("local x = 5\nprint(x)")

-- Set highlighter (returns array of {line, start_col, end_col, r, g, b, a})
editor:SetSyntaxHighlighter(function(text)
    -- tokenize and return colors
    return tokens
end)

-- Get selection
local selected = editor:GetSelectedText()
clipboard.set(selected)
```

## RML Usage

```xml
<texteditor id="code_view" style="width: 800px; height: 600px;" />
```

## What Works Out of the Box

- Mouse drag selection (all handled in C++)
- Ctrl+C to copy (uses ClipboardBindings already in codebase)
- Syntax highlighting via Lua callback
- Efficient rendering (only regenerate geometry when needed)

## Build Integration

Add to CMakeLists.txt:
- TextBuffer.cpp
- TextLayout.cpp
- SelectionManager.cpp
- SyntaxHighlighter.cpp
- ElementTextEditor.cpp
- ElementTextEditorInstancer.cpp

## Rendering Flow

1. Element receives text via SetText()
2. Text stored in TextBuffer
3. Mark text_dirty = true
4. OnUpdate() checks dirty flags
5. If text_dirty: call TextLayout to generate geometry for all lines
6. If selection_dirty: generate selection quad geometry
7. OnRender() draws selection geometry, then text geometry

## Mouse Selection Flow

1. MouseDown → get mouse position → TextLayout converts to (line, col) → SelectionManager stores anchor
2. MouseMove → convert position → SelectionManager updates cursor
3. MouseUp → selection complete
4. Selection range used to generate highlight geometry

## File Viewer Integration

Create new RML file `ui/text_editor_viewer.rml`:
```xml
<texteditor id="editor" style="width:100%; height:100%;" />
```

Lua sets content and syntax highlighter when file opens.
