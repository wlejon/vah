-- Syntax Highlighter Configuration
-- Maps file extensions to highlighter modules

return {
    -- Lua files
    lua = "highlighters.lua_highlighter",

    -- C/C++ files
    c = "highlighters.cpp_highlighter",
    cpp = "highlighters.cpp_highlighter",
    cc = "highlighters.cpp_highlighter",
    h = "highlighters.cpp_highlighter",
    hpp = "highlighters.cpp_highlighter",

    -- RML/XML/HTML files
    rml = "highlighters.rml_highlighter",
    xml = "highlighters.rml_highlighter",
    html = "highlighters.rml_highlighter",

    -- RCSS/CSS files
    rcss = "highlighters.rcss_highlighter",
    css = "highlighters.rcss_highlighter",
}
