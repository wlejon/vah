# Canvas Scene Architecture Design

## Problem Statement

The current canvas implementation has Lua building drawing commands frame-by-frame. This creates two issues:
1. **Flickering**: Lua (30Hz) can't keep up with rendering (60Hz)
2. **Poor Interaction**: Any user interaction (dragging nodes, panning) requires Lua to rebuild the entire scene, causing lag

## Solution: Scene Graph Architecture

C++ owns a **scene graph** that Lua declaratively modifies. C++ handles all rendering and interactions without waiting on Lua.

---

## Architecture Overview

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│ Lua Thread  │────────▶│ Scene Graph  │────────▶│ Renderer    │
│  (30 Hz)    │ Modify  │   (C++)      │ Render  │  (60 Hz)    │
└─────────────┘         └──────────────┘         └─────────────┘
       ▲                        │
       │                        │ Events
       └────────────────────────┘
       (on_node_clicked, on_connection_made, etc.)
```

**Data Flow:**
- **Lua → Scene**: Declares nodes, edges, groups (infrequent updates)
- **Scene → Renderer**: C++ renders scene graph at 60Hz
- **User Input → Scene**: C++ handles drag/pan/zoom immediately
- **Scene → Lua**: Events for logical actions (connections, clicks)

---

## Scene Graph Structure

### Core Classes

#### `WorkflowScene`
The root container for all workflow elements.

```cpp
class WorkflowScene {
    std::unordered_map<std::string, std::unique_ptr<WorkflowNode>> nodes_;
    std::unordered_map<std::string, std::unique_ptr<WorkflowEdge>> edges_;
    std::unordered_map<std::string, std::unique_ptr<WorkflowGroup>> groups_;

    ViewportState viewport_;  // Pan, zoom
    SelectionState selection_;  // Selected nodes/edges

    // Modifications (called from Lua thread)
    void AddNode(const std::string& id, const NodeDefinition& def);
    void RemoveNode(const std::string& id);
    void AddEdge(const std::string& id, const std::string& from_port, const std::string& to_port);
    void RemoveEdge(const std::string& id);

    // Rendering (called from main thread)
    void Render(Canvas2D* canvas);

    // Interactions (called from main thread)
    void OnMouseDown(float x, float y);
    void OnMouseMove(float x, float y);
    void OnMouseUp(float x, float y);
    void OnMouseWheel(float delta);
};
```

#### `WorkflowNode`
Represents a single node in the workflow.

```cpp
struct WorkflowNode {
    std::string id;
    std::string type;  // "transform", "ingest", "export", etc.

    glm::vec2 position;
    glm::vec2 size;

    std::string title;
    std::string description;

    NodeStyle style;  // Colors, border radius, etc.
    std::vector<Port> input_ports;
    std::vector<Port> output_ports;

    NodeState state;  // Normal, Selected, Hovered, Executing, Error
};
```

#### `WorkflowEdge`
Represents a connection between ports.

```cpp
struct WorkflowEdge {
    std::string id;
    std::string from_node;
    std::string from_port;
    std::string to_node;
    std::string to_port;

    EdgeStyle style;  // Color, width, pattern
    EdgeState state;  // Normal, Selected, Hovered, Active (data flowing)
};
```

#### `WorkflowGroup`
Container for organizing multiple nodes.

```cpp
struct WorkflowGroup {
    std::string id;
    std::string title;

    std::vector<std::string> node_ids;

    glm::vec2 position;
    glm::vec2 size;

    GroupStyle style;
    bool collapsed;
};
```

---

## Visual Primitives

### Node Rendering
Standard visual representation for all nodes:

```
┌──────────────────────────────────┐
│ ● ● ●  Node Title         [icon] │ ← Header (colored by type)
├──────────────────────────────────┤
│                                  │
│  ○ Input 1      Output 1 ○      │ ← Ports
│  ○ Input 2      Output 2 ○      │
│                                  │
│  Status: Ready                   │ ← Optional status
└──────────────────────────────────┘
```

**Node Types & Colors:**
- `ingest`: Blue (#89B4FA)
- `transform`: Green (#A6E3A1)
- `export`: Purple (#CBA6F7)
- `agent`: Pink (#F5C2E7)
- `data`: Teal (#94E2D5)

### Edge Rendering
Bezier curves connecting ports:
- **Normal**: Thin line, type-colored
- **Selected**: Thicker, bright color
- **Active (data flowing)**: Animated dash pattern
- **Error**: Red with warning icon

### Group Rendering
Rounded rectangle container with collapse/expand:
```
┌─ Group Name ────────────────[−]─┐
│  ┌─────┐      ┌─────┐           │
│  │Node1│─────▶│Node2│           │
│  └─────┘      └─────┘           │
└──────────────────────────────────┘
```

---

## Scene File Format (JSON)

```json
{
  "version": "1.0",
  "viewport": {
    "pan": [0, 0],
    "zoom": 1.0
  },
  "nodes": [
    {
      "id": "ingest_csv",
      "type": "ingest",
      "position": [100, 200],
      "size": [220, 150],
      "title": "Parse CSV",
      "description": "Reads and parses CSV files",
      "input_ports": [],
      "output_ports": [
        {"id": "data", "label": "Data", "type": "table"}
      ],
      "state": "ready"
    },
    {
      "id": "transform_cols",
      "type": "transform",
      "position": [400, 200],
      "size": [220, 150],
      "title": "Select Columns",
      "input_ports": [
        {"id": "input", "label": "Input", "type": "table"}
      ],
      "output_ports": [
        {"id": "output", "label": "Output", "type": "table"}
      ]
    }
  ],
  "edges": [
    {
      "id": "e1",
      "from": "ingest_csv.data",
      "to": "transform_cols.input"
    }
  ],
  "groups": []
}
```

---

## Lua API

### Scene Building

```lua
-- Create a new workflow scene
local scene = workflow.create_scene()

-- Add nodes
scene.add_node({
    id = "parse_csv",
    type = "ingest",
    title = "Parse CSV Files",
    position = {100, 200},
    output_ports = {
        {id = "data", label = "Data", type = "table"}
    }
})

scene.add_node({
    id = "transform",
    type = "transform",
    title = "Transform Data",
    position = {400, 200},
    input_ports = {
        {id = "input", label = "Input", type = "table"}
    },
    output_ports = {
        {id = "output", label = "Output", type = "table"}
    }
})

-- Connect nodes
scene.add_edge({
    id = "e1",
    from = "parse_csv.data",
    to = "transform.input"
})

-- Create a group
scene.add_group({
    id = "ingestion",
    title = "Data Ingestion",
    nodes = {"parse_csv"}
})

-- Update the active scene (atomic)
workflow.set_active_scene(scene)
```

### Events (C++ → Lua)

```lua
-- Node interactions
function on_node_clicked(node_id)
    print("Clicked node: " .. node_id)
end

function on_node_double_clicked(node_id)
    -- Open node editor
end

function on_node_dragged(node_id, new_position)
    -- Optionally save position to persistent state
end

-- Edge interactions
function on_connection_created(from_port, to_port)
    print("Connected " .. from_port .. " to " .. to_port)
    -- Update workflow logic
end

function on_connection_deleted(edge_id)
    -- Update workflow logic
end

-- Selection
function on_selection_changed(selected_nodes, selected_edges)
    -- Update UI state
end
```

---

## Interaction Model

### Mouse Interactions (handled by C++)

**Node Dragging:**
1. MouseDown on node → Begin drag
2. MouseMove → Update node position in scene graph
3. MouseUp → Commit final position, send `on_node_dragged` event to Lua

**Panning:**
1. MouseDown on background + drag → Update viewport pan
2. Smooth 60Hz feedback

**Zooming:**
1. MouseWheel → Update viewport zoom
2. Zoom centered on mouse position

**Connection Creation:**
1. MouseDown on output port → Begin connection
2. MouseMove → Draw temporary edge
3. MouseUp on input port → Create edge, send `on_connection_created` to Lua
4. MouseUp elsewhere → Cancel

**Selection:**
1. Click node → Select (Ctrl+Click for multi-select)
2. Click background → Clear selection
3. Drag background → Box selection

All these happen at 60Hz without Lua involvement!


You've hit on a critical point. Mixing UI rendering frameworks is often undesirable as it can lead to inconsistencies in style, input handling, and performance. Wanting a library that handles the "plumbing" (the scene graph data model and interaction logic) but leaves the rendering to you is the ideal scenario for deep integration.

The challenge is that most popular node editor libraries are tightly coupled with their rendering framework (like ImGui) because that's their main selling point—a complete, drop-in solution. Truly headless, renderer-agnostic node graph libraries are much rarer and often less feature-complete.

Given your constraints, your original plan to **build it yourself is the correct path**. You're not just building a renderer; you're building a state management system that happens to be for a node graph.

Here’s a slight refinement of your architecture that makes this separation crystal clear:

-----

### Refined Architecture: Model-View-Controller (MVC)

Think of your design not as one monolithic `WorkflowScene` class, but as three distinct components. This structure ensures your rendering is completely decoupled from your state and logic.

#### 1\. The Model: `WorkflowScene` (The "Headless Library")

This is the core data structure, just as you designed. It should have **zero rendering code**. It knows nothing about `RmlUi`, `Canvas2D`, or OpenGL. It's pure data and state.

  * **Responsibilities**:
      * Stores nodes, edges, and groups.
      * Contains the viewport state (pan, zoom).
      * Provides methods to modify the graph (`AddNode`, `RemoveEdge`, etc.), which are called from your command queue.

This component **is** the headless plumbing you're looking for.

-----

#### 2\. The Controller: `WorkflowInteractionManager`

This class handles all input and translates it into modifications on the `WorkflowScene` model. It also lives entirely in C++ and runs on the main thread at 60Hz.

  * **Responsibilities**:
      * Receives raw mouse events (`OnMouseDown`, `OnMouseMove`).
      * Performs hit-testing against the `WorkflowScene` model.
      * Manages interaction states (e.g., "dragging node X", "creating connection from port Y").
      * Directly updates the model (e.g., `node->position = new_pos`).
      * Queues high-level events for Lua (`on_node_drag_finished`, `on_connection_created`).

-----

#### 3\. The View: `WorkflowSceneRenderer`

This is the bridge to your rendering engine. It's a "dumb" component that simply knows how to draw the current state of the `WorkflowScene`.

```cpp
// WorkflowSceneRenderer.h

class WorkflowSceneRenderer {
public:
    // The renderer takes the model and a canvas to draw on.
    void Render(const WorkflowScene& scene, Canvas2D* canvas);

private:
    void DrawNode(const WorkflowNode& node, const WorkflowScene& scene, Canvas2D* canvas);
    void DrawEdge(const WorkflowEdge& edge, const WorkflowScene& scene, Canvas2D* canvas);
    // ... etc ...
};
```

  * **Responsibilities**:
      * Iterates through the nodes and edges of the `WorkflowScene`.
      * Translates the scene data into `Canvas2D` draw calls (e.g., `canvas->DrawRect`, `canvas->DrawBezier`).
      * Applies viewport transformations (pan/zoom) to all coordinates.
      * Renders different states visually (e.g., draws a glowing border around selected nodes).

### Why This is the Right Approach for You

  * **No Unwanted Dependencies**: You avoid pulling in ImGui or any other framework that clashes with `RmlUi`.
  * **Perfect Integration**: The `WorkflowSceneRenderer` will be perfectly tailored to your `Canvas2D` API and your engine's rendering pipeline.
  * **You're in Control**: You get to implement the look, feel, and interaction logic exactly as you've envisioned in your design document.

You were on the right track from the start. Instead of looking for an external library to provide the plumbing, you can confidently build that plumbing yourself, knowing it's the cleanest and most integrated solution for your existing architecture.