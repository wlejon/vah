# Code Review: NanoVG Graphics & Canvas Elements

## Component Overview

This component provides a comprehensive integration of the NanoVG 2D vector graphics library with the vah application's Lua scripting environment. The implementation consists of:

1. **NanoVG Lua Bindings** - Complete bindings for NanoVG drawing API exposed through a global `nvg` table
2. **Custom RmlUI Canvas Element** - A custom `<canvas>` element that provides an OpenGL/NanoVG rendering surface within RmlUI documents
3. **Modular Organization** - Bindings split across focused modules (core, paint, text, image, utils)

The canvas element allows Lua scripts in RML documents to perform custom 2D rendering via callback functions, with full access to paths, shapes, transforms, gradients, images, and text rendering.

## Files Reviewed

| File | Lines | Purpose |
|------|-------|---------|
| NanoVGBindings.h | 27 | Main bindings header |
| NanoVGBindings.cpp | 537 | Core drawing, paths, shapes, transforms, state |
| NanoVGPaint.h | 18 | Paint management header |
| NanoVGPaint.cpp | 184 | Gradient and image pattern management |
| NanoVGText.h | 17 | Text rendering header |
| NanoVGText.cpp | 235 | Font loading and text rendering |
| NanoVGImage.h | 17 | Image management header |
| NanoVGImage.cpp | 83 | Image loading and sizing |
| NanoVGUtils.h | 23 | Utility functions header |
| NanoVGUtils.cpp | 339 | Color utils, scissoring, compositing |
| ElementCanvas.h | 83 | Canvas element interface |
| ElementCanvas.cpp | 665 | Canvas element implementation |
| **Total** | **2,228** | |

## Architecture & Design

### Modular Binding Architecture

The NanoVG bindings follow a well-organized modular design:

```
NanoVGBindings (SetupBindings)
├── Core bindings (paths, shapes, transforms, state)
├── NanoVGPaint::SetupBindings (gradients, patterns)
├── NanoVGText::SetupBindings (fonts, text rendering)
├── NanoVGImage::SetupBindings (image loading)
└── NanoVGUtils::SetupBindings (colors, scissors, compositing)
```

All functions are exposed through a single global `nvg` table, creating a cohesive API surface for Lua.

### Canvas Element Integration

The `ElementCanvas` class extends `Rml::Element` to provide:
- NanoVG context management (creation/destruction tied to element lifecycle)
- OpenGL state preservation around NanoVG rendering
- Lua callback system for custom rendering (`renderfunction` attribute)
- Mouse and keyboard event forwarding to Lua handlers
- Proper integration with RmlUI's render pipeline

### Context Passing Pattern

All NanoVG functions receive the context as a light userdata (pointer) parameter:
```lua
nvg.beginPath(ctx)
nvg.rect(ctx, x, y, w, h)
nvg.fillColor(ctx, color)
nvg.fill(ctx)
```

This is clean, explicit, and thread-safe (each canvas owns its context).

### Resource Management

- **Paint Objects**: Managed as Lua userdata with metatable `"NVGpaint"`, includes `__gc` metamethod (though NVGpaint is POD and needs no cleanup)
- **Images**: Managed by integer handles returned from `nvgCreateImage()`, must be manually deleted with `nvgDeleteImage()`
- **Fonts**: Managed by integer handles, loaded once and reused
- **NanoVG Context**: Created in `InitializeNanoVG()`, destroyed in `ShutdownNanoVG()`, lifecycle tied to canvas element

## Code Quality Assessment

### Strengths

1. **Clean Modular Organization**: Bindings are logically separated into focused modules (paint, text, image, utils), making the codebase maintainable and easy to navigate.

2. **Consistent Binding Pattern**: All binding functions follow a consistent pattern:
   - Get context via `GetContext()`
   - Extract and validate Lua arguments
   - Call NanoVG API
   - Return results

3. **Comprehensive API Coverage**: Covers all major NanoVG features:
   - Path primitives (lines, curves, arcs)
   - Shapes (rect, circle, ellipse)
   - Transforms (translate, rotate, scale, skew)
   - State management (save/restore)
   - Gradients and patterns
   - Text rendering and measurement
   - Image loading and display
   - Scissoring and compositing

4. **Good OpenGL State Management**: `ElementCanvas::OnRender()` carefully saves and restores OpenGL state around NanoVG rendering (viewport, scissor, blend, stencil, shader program).

5. **Comprehensive Event Handling**: Canvas element supports:
   - Mouse events (move, click, scroll)
   - Keyboard events with comprehensive key mapping
   - Proper mouse button state tracking
   - Mouse-out handling to prevent stuck drag states

6. **Well-Documented**: Good inline comments explaining key decisions (e.g., stencil buffer clearing, scissor test handling).

7. **Error Handling for Lua Callbacks**: All Lua callback invocations use `lua_pcall()` with proper error logging.

8. **Type Safety**: Uses appropriate C++ casts and Lua type checking (`luaL_checktype`, `luaL_checkstring`, etc.).

### Issues & Concerns

#### Critical Issues

None identified.

#### Major Issues

**1. No Image Resource Lifecycle Management** (Multiple files)

Images are created via `nvgCreateImage()` which returns an integer handle. There's no automatic cleanup mechanism:

```cpp
// NanoVGImage.cpp:28
int handle = nvgCreateImage(ctx, filename, imageFlags);
lua_pushinteger(L, handle);
return 1;
```

**Problem**: If Lua scripts create images but don't explicitly call `nvgDeleteImage()`, image resources will leak. NanoVG maintains an internal image pool that can overflow.

**Impact**: Memory leaks in long-running applications with dynamic image loading.

**Recommendation**: Consider one of these approaches:
- Wrap image handles in userdata with `__gc` metamethod to auto-delete
- Maintain a per-canvas image registry that cleans up on canvas destruction
- Document the requirement for manual cleanup clearly in Lua API documentation

**2. Font Resource Management** (NanoVGText.cpp)

Similar to images, fonts created via `nvgCreateFont()` return integer handles with no cleanup:

```cpp
// NanoVGText.cpp:28
int handle = nvgCreateFont(ctx, name, filename);
lua_pushinteger(L, handle);
```

**Problem**: No cleanup mechanism for fonts. However, fonts are typically loaded once and reused, so this is less critical than images.

**Recommendation**: Document that fonts persist for the lifetime of the NanoVG context.

**3. No Error Checking on NanoVG Resource Creation** (NanoVGImage.cpp, NanoVGText.cpp, ElementCanvas.cpp)

Resource creation functions don't validate the returned handles:

```cpp
// NanoVGImage.cpp:28
int handle = nvgCreateImage(ctx, filename, imageFlags);
lua_pushinteger(L, handle);  // Returns -1 on failure, no check
```

```cpp
// ElementCanvas.cpp:50
int font_handle = nvgCreateFont(nvg_context_, "roboto", "ui/fonts/...");
if (font_handle == -1) {
    LOG_WARN("Failed to load font...");  // Warns but continues
}
```

**Problem**: Failed resource creation returns -1, which Lua scripts might use, causing undefined behavior or rendering issues.

**Recommendation**:
- Return `nil` to Lua on failure instead of -1
- Or raise a Lua error on critical failures
- Document that -1 indicates failure

**4. Potential Lua State Thread Safety** (ElementCanvas.cpp:270, 428, 483, etc.)

All Lua callback functions retrieve the Lua state via:
```cpp
lua_State* L = Rml::Lua::Interpreter::GetLuaState();
```

**Problem**: If RmlUI can be rendered from different threads or if the Lua state can change, this could be unsafe. However, based on the threading review (02-threading-system.md), the main thread owns UI rendering.

**Recommendation**: Verify that `GetLuaState()` always returns the same state during rendering and that rendering always occurs on the main thread. Add an assertion if possible.

#### Minor Issues

**1. Hardcoded Font Path** (ElementCanvas.cpp:50)

```cpp
int font_handle = nvgCreateFont(nvg_context_, "roboto",
    "ui/fonts/roboto-static/Roboto-Regular.ttf");
```

**Issue**: Hardcoded relative path may fail depending on working directory.

**Recommendation**: Use an absolute path or resolve relative to executable/resource directory. Consider making default font configurable.

**2. Duplicate GetContext() Helper** (All binding files)

Each binding file has an identical `GetContext()` helper function in its anonymous namespace:

```cpp
NVGcontext* GetContext(lua_State* L, int idx) {
    if (!lua_islightuserdata(L, idx)) {
        luaL_error(L, "Expected NVGcontext (light userdata)");
        return nullptr;
    }
    return static_cast<NVGcontext*>(lua_touserdata(L, idx));
}
```

**Issue**: Code duplication across 5 files.

**Recommendation**: Move to a shared internal header or NanoVGUtils namespace.

**3. Color Table Format Inconsistency**

Colors are represented as Lua tables with 4 numeric elements `{r, g, b, a}`, but there's no validation of table contents:

```cpp
// NanoVGUtils.cpp:197
NVGcolor NanoVGUtils::TableToColor(lua_State* L, int idx) {
    NVGcolor color;
    lua_rawgeti(L, idx, 1);
    color.r = static_cast<float>(lua_tonumber(L, -1));  // No error checking
    lua_pop(L, 1);
    // ...
}
```

**Issue**: If Lua passes incomplete or malformed color table, results are undefined.

**Recommendation**: Add validation that table has 4 numeric elements, or use `lua_tonumberx()` to detect conversion failures.

**4. Transform Matrix Not Exposed** (NanoVGBindings.cpp)

NanoVG has functions to get the current transform (`nvgCurrentTransform()`), but these aren't exposed to Lua.

**Issue**: Lua scripts can't query the current transform state for advanced rendering.

**Recommendation**: Consider exposing `nvgCurrentTransform()` if needed for advanced use cases.

**5. Text Metrics Limited** (NanoVGText.cpp)

Only `nvgTextBounds()` is exposed for text measurement. NanoVG also provides `nvgTextMetrics()` for font metrics and `nvgTextGlyphPositions()` for glyph-level layout.

**Issue**: Limited text measurement capabilities for advanced text layout.

**Recommendation**: Consider exposing additional text measurement functions if needed.

**6. Path Hit Testing Not Exposed**

NanoVG doesn't provide built-in hit testing for paths. Applications must implement their own.

**Issue**: Lua scripts can't determine if a point is inside a drawn path.

**Recommendation**: This is a NanoVG limitation. Consider implementing CPU-side path hit testing if needed, or document this limitation.

**7. Excessive Key Mapping Boilerplate** (ElementCanvas.cpp:313-423)

The `MapKeyToString()` function is a large switch statement with 110+ cases mapping RmlUI key identifiers to string names.

**Issue**: Very verbose, difficult to maintain.

**Recommendation**: Consider using a lookup table (array or map) instead of a switch statement. However, the switch is efficient and the compiler can optimize it, so this is low priority.

**8. Mouse Position Stored in Canvas** (ElementCanvas.h:80)

```cpp
Rml::Vector2f mouse_pos_;
bool mouse_buttons_[3];
```

**Issue**: Redundant storage - RmlUI events already contain mouse position.

**Impact**: Minimal - only 12 bytes per canvas.

**Recommendation**: Consider passing mouse position directly from events rather than storing state, but current approach is acceptable for simplicity.

**9. Document Registry Manipulation** (ElementCanvas.cpp:456-477, etc.)

Canvas temporarily sets `_owner_document` in Lua registry during callbacks:

```cpp
Rml::Lua::LuaType<Rml::ElementDocument>::push(L, document, false);
lua_setfield(L, LUA_REGISTRYINDEX, "_owner_document");
// ... call Lua function ...
lua_pushnil(L);
lua_setfield(L, LUA_REGISTRYINDEX, "_owner_document");
```

**Issue**: Global state manipulation that could conflict if nested calls occur or if multiple canvases render simultaneously.

**Recommendation**:
- Verify this pattern is used by RmlUi's own event handlers
- Consider using a unique key per canvas instance
- Document why this is needed (likely for `trigger()` to work in Lua)

**10. No Framebuffer Object Support**

NanoVG can render to framebuffer objects (FBOs) for off-screen rendering, but this isn't exposed.

**Issue**: Lua scripts can't render to textures for effects or caching.

**Recommendation**: Consider exposing FBO support if advanced rendering features are needed.

### Resource Management

#### Image Lifecycle

**Current State**: Manual management via handles
- Created: `nvg.createImage(ctx, filename, flags)` → returns integer handle
- Used: Pass handle to `nvg.imagePattern()` or `nvg.deleteImage()`
- Deleted: `nvg.deleteImage(ctx, handle)` - manual only

**Issues**: No automatic cleanup, potential for leaks

**Recommendation**: Implement automatic cleanup via userdata wrapper:

```lua
-- Proposed API:
local img = nvg.createImage(ctx, "texture.png")  -- returns userdata
local pattern = nvg.imagePattern(ctx, 0, 0, w, h, 0, img, 1.0)
-- img auto-deleted when garbage collected
```

#### Font Lifecycle

**Current State**: Manual management via handles
- Created: `nvg.createFont(ctx, name, filename)` → returns integer handle or name lookup
- Used: `nvg.fontFace(ctx, name)` or `nvg.fontFaceId(ctx, handle)`
- Deleted: Never (fonts persist for context lifetime)

**Issues**: No cleanup mechanism, but fonts are typically loaded once

**Status**: Acceptable - document that fonts persist

#### Paint Lifecycle

**Current State**: Userdata with metatable
- Created: Gradient/pattern functions return `NVGpaint` userdata
- Used: `nvg.fillPaint(ctx, paint)` or `nvg.strokePaint(ctx, paint)`
- Deleted: Automatic via `__gc` metamethod (though NVGpaint is POD)

**Status**: Well-designed, no issues

#### NanoVG Context Lifecycle

**Current State**: Per-canvas singleton
- Created: `InitializeNanoVG()` called when canvas added to document
- Used: Passed to Lua render function as light userdata
- Deleted: `ShutdownNanoVG()` called in destructor

**Issues**:
- Context not recreated if canvas is removed and re-added multiple times
- `InitializeNanoVG()` early-returns if context already exists

**Status**: Acceptable for typical usage patterns

### Performance Considerations

#### OpenGL State Thrashing

**Observation**: Canvas saves/restores extensive GL state every frame (lines 192-257 in ElementCanvas.cpp)

```cpp
GLint viewport[4], scissor_box[4], blend_src, blend_dst, ...;
GLboolean blend_enabled, cull_enabled, ...;
// ... save 15+ state values ...
// ... NanoVG rendering ...
// ... restore all state ...
```

**Impact**: State queries and changes can be expensive if done every frame per canvas

**Recommendation**:
- Profile to verify if this is a bottleneck
- Consider caching state if profiling shows impact
- However, correctness is critical here, so current approach is safe

#### Frame Time Available to Lua

**Observation**: Lua render function called every frame in `OnRender()`

**Consideration**: Complex Lua rendering code could impact frame rate

**Recommendation**: Document that render functions should be optimized for 60fps (16ms budget)

#### Stencil Buffer Clearing

**Observation**: Stencil buffer cleared every frame (line 222):

```cpp
glClearStencil(0);
glClear(GL_STENCIL_BUFFER_BIT);
```

**Justification**: NanoVG uses stencil for antialiasing and strokes, must start clean

**Status**: Necessary, no optimization possible

#### Font Loading on Initialization

**Observation**: Default font loaded in `InitializeNanoVG()` (line 50)

**Issue**: Synchronous file I/O on main thread during canvas initialization

**Impact**: Potential frame hitch when canvas first appears

**Recommendation**: Consider pre-loading fonts during application startup or loading asynchronously

### API Design

#### Lua API Usability

**Strengths**:
1. Clean, explicit context passing
2. Consistent naming matching NanoVG C API (camelCase)
3. Well-organized namespace under `nvg` table
4. All NanoVG constants exposed (NVG_CCW, NVG_ALIGN_LEFT, etc.)

**Example Usage**:
```lua
function myRenderFunction(ctx, x, y, w, h, time)
    local color = nvg.rgba(255, 100, 100, 255)

    nvg.beginPath(ctx)
    nvg.rect(ctx, x, y, w, h)
    nvg.fillColor(ctx, color)
    nvg.fill(ctx)

    nvg.fontSize(ctx, 24)
    nvg.fontFace(ctx, "roboto")
    nvg.fillColor(ctx, nvg.rgba(255, 255, 255, 255))
    nvg.text(ctx, x + 10, y + 30, "Hello NanoVG!")
end
```

**Observations**:
- API is verbose but clear
- Color creation separate from usage (intentional - colors can be reused)
- Transform state managed via save/restore

#### Canvas Element Attributes

**Supported Attributes**:
- `renderfunction="functionName"` - Lua function called each frame
  - Signature: `function(nvg, x, y, w, h, time)`
- `keyhandler="functionName"` - Keyboard event handler
  - Signature: `function(key_name, key_down)`
- `mouseclickhandler="functionName"` - Mouse click handler
  - Signature: `function(button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)`
- `mousemovehandler="functionName"` - Mouse move handler
  - Signature: `function(mouse_x, mouse_y, canvas_x, canvas_y, button_left, button_middle, button_right)`
- `mousescrollhandler="functionName"` - Mouse wheel handler
  - Signature: `function(wheel_x, wheel_y)`

**Strengths**:
- Clean separation of concerns (one handler per event type)
- Comprehensive event coverage
- Canvas position provided for coordinate conversion

**Issues**:
- All handlers are global function names (strings)
- No support for anonymous functions or closures
- No way to pass custom data to handlers

**Recommendation**: Consider supporting table-based handlers:
```lua
<canvas renderfunction="MyCanvas.render" />

MyCanvas = {
    data = {...},
    render = function(self, ctx, x, y, w, h, time)
        -- can access self.data
    end
}
```

#### Error Handling

**Current Approach**:
- Invalid context: `luaL_error()` - aborts Lua with error message
- Invalid function in callback: `LOG_WARN()` - logs and continues
- Lua runtime errors in callbacks: `LOG_ERROR()` - logs and continues
- Failed resource creation: Returns -1 handle, no error

**Strengths**: Callbacks use `lua_pcall()` to catch Lua errors gracefully

**Issues**:
- Failed resource creation doesn't signal error clearly to Lua
- No way for Lua to detect and handle failures

**Recommendation**: Return nil on resource creation failure

## Recommendations

### High Priority

1. **Implement Automatic Image Cleanup**
   - Wrap image handles in userdata with `__gc` metamethod
   - Or maintain per-canvas image registry with automatic cleanup
   - Prevents resource leaks in long-running applications

2. **Improve Error Handling for Resource Creation**
   - Return `nil` to Lua on failed image/font loading instead of -1
   - Document the error handling behavior
   - Consider raising Lua errors for critical failures

3. **Validate Color Table Format**
   - Check that color tables have 4 numeric elements
   - Provide better error messages when format is wrong
   - Consider optional color validation function

### Medium Priority

4. **Fix Hardcoded Font Path**
   - Use absolute path or resolve relative to resource directory
   - Make default font configurable (e.g., via attribute or config)

5. **Consolidate Duplicate GetContext() Helper**
   - Move to shared header or NanoVGUtils
   - Reduces code duplication and maintenance burden

6. **Document Resource Lifecycle**
   - Create clear documentation for image, font, and paint lifecycles
   - Explain when resources are cleaned up
   - Provide examples of proper resource management

7. **Expose Additional Text Measurement Functions**
   - `nvgTextMetrics()` for font metrics
   - `nvgTextGlyphPositions()` for advanced layout
   - Only if needed by application requirements

### Low Priority

8. **Refactor Key Mapping to Use Lookup Table**
   - Replace large switch statement with static array/map
   - Improves maintainability
   - Current switch is functional and efficient

9. **Consider Table-Based Canvas Handlers**
   - Allow handlers to be table methods with state
   - Improves encapsulation for complex canvas logic
   - Current string-based approach works but is limited

10. **Profile OpenGL State Save/Restore**
    - Measure performance impact of state queries
    - Optimize only if profiling shows it's a bottleneck
    - Current approach prioritizes correctness

11. **Expose Transform Query Functions**
    - `nvgCurrentTransform()` for reading current matrix
    - Only needed for advanced rendering scenarios

12. **Consider Framebuffer Object Support**
    - Enable off-screen rendering for effects
    - Only if advanced rendering features are needed

## Dependencies & Integration

### External Dependencies

1. **NanoVG Library**
   - Version: Unknown (standard NanoVG)
   - Backend: OpenGL 3 (`nanovg_gl.h` with `NANOVG_GL3_IMPLEMENTATION`)
   - Features used: Antialiasing, stencil strokes

2. **RmlUI**
   - Custom element integration via `Rml::Element` base class
   - Event system via `Rml::EventListener`
   - Lua integration via `Rml::Lua::Interpreter`
   - Box model for layout (`GetBox()`, `GetAbsoluteOffset()`)

3. **Lua**
   - Version: Assumed 5.x (uses Lua C API)
   - Features used: C functions, userdata, metatables, pcall

4. **OpenGL**
   - Version: 3.x (via GLAD loader)
   - State management: Extensive state save/restore

### Integration Points

#### With Lua Bindings System

```
Application::InitializeScripting()
  └─> NanoVGBindings::SetupBindings(L)
        ├─> Creates global 'nvg' table
        ├─> Registers all drawing functions
        └─> Calls sub-module SetupBindings()
```

**Status**: Clean, single entry point

#### With RmlUI Document System

```
RML Document Parse
  └─> <canvas> tag encountered
        └─> ElementCanvas::ElementCanvas() constructor
              └─> OnChildAdd() called when added to tree
                    └─> InitializeNanoVG()
                    └─> Register event listeners
```

**Status**: Proper lifecycle integration with RmlUI

#### With Rendering Pipeline

```
RmlUI Render Loop
  └─> Document::Render()
        └─> Element::OnRender() for each element
              └─> ElementCanvas::OnRender()
                    ├─> Save GL state
                    ├─> Clear stencil
                    ├─> nvgBeginFrame()
                    ├─> CallLuaRenderFunction()
                    ├─> nvgEndFrame()
                    └─> Restore GL state
```

**Status**: Well-integrated, minimal coupling

#### Thread Safety

**Observation**: Based on threading review (02-threading-system.md):
- Main thread owns UI rendering
- Worker threads don't access UI

**Conclusion**: NanoVG integration is single-threaded, which is appropriate. NanoVG contexts are not thread-safe, so each canvas must be rendered on the same thread.

**Status**: Thread-safe by design (main thread only)

### Potential Conflicts

1. **OpenGL State Conflicts**: NanoVG modifies GL state extensively. Canvas carefully saves/restores state, but other OpenGL code must also be state-aware.

2. **Lua Registry Conflicts**: Canvas uses `_owner_document` key in Lua registry. If other code uses the same key or if nested rendering occurs, conflicts could arise.

3. **Stencil Buffer Conflicts**: Canvas clears stencil buffer before use. If RmlUI or other code relies on stencil buffer persistence, this could cause issues.

**Current Status**: No conflicts observed in reviewed code, but these are potential areas for future issues.

## Summary

The NanoVG graphics integration is **well-designed and implemented**, with clean modular organization, comprehensive API coverage, and proper integration with RmlUI. The code quality is high, with good error handling, documentation, and consistent patterns.

**Key Strengths**:
- Modular, maintainable binding architecture
- Comprehensive coverage of NanoVG features
- Clean Lua API design
- Robust OpenGL state management
- Comprehensive event handling

**Key Concerns**:
- Resource lifecycle management (images, fonts) needs improvement
- Error handling for resource creation could be clearer
- Some minor code duplication and hardcoded paths

**Overall Assessment**: Production-ready with recommended improvements for resource management and error handling. The component provides a solid foundation for custom 2D rendering in Lua scripts.

**Priority Recommendations**:
1. Implement automatic image cleanup mechanism
2. Improve error signaling for resource creation failures
3. Validate color table format in TableToColor()
4. Fix hardcoded font path
5. Document resource lifecycle clearly
