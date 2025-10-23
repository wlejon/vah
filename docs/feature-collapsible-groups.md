# Feature: Collapsible Groups with Group-Level Ports

## Overview

Add support for hierarchical grouping in the workflow editor where multiple nodes can be contained within a collapsible group node. Groups have their own input/output ports that route connections to contained nodes, allowing workflows to be organized into logical subsystems while maintaining a clean high-level view.

## Goals

- **Visual Organization**: Allow complex workflows to be organized into semantic groups (e.g., "C++ Initialization", "Lua Thread Operations", "Rendering Pipeline")
- **Hierarchical Abstraction**: Enable collapse/expand to show either high-level system architecture or detailed implementation
- **Connection Routing**: Support connections at both group level and node level, with automatic routing from group ports to appropriate internal nodes
- **Reusable Subsystems**: Groups can represent reusable workflow patterns that can be collapsed into a single visual unit

## Data Model Changes

### Group Entity Structure

Groups are first-class entities alongside nodes in the workflow data model. Each group contains:

**Identity and Metadata**
- Unique group identifier separate from node IDs
- Group name displayed in the collapsed header
- Optional description for documentation
- Color theming to visually distinguish group types
- Z-order or layer information for rendering order

**Containment Information**
- List of member node IDs that belong to this group
- Nesting level if groups can contain other groups (consider starting with flat groups only)
- Original positions of nodes before grouping (for restoration on ungroup)

**Visual State**
- Collapsed/expanded boolean state
- Collapsed position and dimensions on canvas
- Expanded bounding box that encompasses all member nodes
- Padding around contained nodes when expanded

**Port Definitions**
- Array of input port definitions with names and internal routing
- Array of output port definitions with names and internal routing
- Each port maps to one or more internal node ports that it represents

### Port Routing Mappings

Each group port needs routing information to connect to internal nodes:

**Input Port Routing**
- Which internal node(s) receive data when external connections come to this group input
- Support for fan-out where one group input routes to multiple internal nodes
- Validation rules for compatible port types

**Output Port Routing**
- Which internal node port(s) provide data for this group output
- Support for fan-in where multiple internal outputs merge to one group output
- Aggregation strategy if multiple internal sources exist

### Connection Model Updates

Connections can now target three types of endpoints:

**Standard Node-to-Node**
- Existing behavior: direct connection between two node ports
- No changes to existing connection logic

**External-to-Group**
- Source is a regular node or another group
- Target is a group's input port
- Connection visually terminates at group boundary
- Routing table determines which internal node(s) receive the data

**Group-to-External**
- Source is a group's output port
- Target is a regular node or another group
- Connection visually originates from group boundary
- Routing table determines which internal node(s) provide the data

**Internal Connections Within Groups**
- Connections between nodes that are both members of the same group
- These connections are hidden when group is collapsed
- Preserved in data model regardless of collapse state

## State Management Architecture

### Editor State Extensions

The workflow editor state module needs new fields:

**Group Collection**
- Map of group ID to group data structures
- Maintained alongside the existing nodes array
- Updated when groups are created, modified, or deleted

**Group Interaction State**
- Currently selected group (for editing ports or properties)
- Currently hovered group (for visual feedback)
- Group being dragged (if dragging entire groups is supported)
- Resize handles if groups can be manually sized

**Collapse State Tracking**
- Which groups are currently collapsed vs expanded
- Cached dimensions for collapsed groups (to avoid recalculation)
- Animation state if collapse/expand should be animated

### Data Synchronization

Groups must be synchronized between:

**Lua Thread State**
- workflow_app.lua manages groups in SQLite database
- Groups loaded and bound via data.bind similar to nodes
- Group modifications trigger database updates

**Main Thread State**
- workflow_editor reads group data via data.get
- Maintains local state for interaction (hover, drag, etc.)
- Does not directly modify data (triggers events to Lua thread)

**Database Schema**
- New table for groups with ID, name, metadata
- Junction table for group membership (group_id, node_id)
- Table for group ports with routing information
- Collapse state can be stored per-workflow or per-user preference

## Visual Representation

### Collapsed Group Appearance

When collapsed, a group appears as a special node type:

**Visual Elements**
- Rounded rectangle larger than standard nodes
- Header area with group name and expand/collapse icon
- Left edge shows input ports with names
- Right edge shows output ports with names
- Distinctive visual treatment (thicker border, different background pattern)
- Optional icon or badge indicating number of contained nodes

**Size Calculation**
- Width based on longest port name plus padding
- Height based on max of input port count and output port count
- Minimum size to ensure readability
- Consistent sizing within same group type for visual harmony

### Expanded Group Appearance

When expanded, a group shows its internal structure:

**Visual Elements**
- Semi-transparent bounding box around all contained nodes
- Rounded rectangle outline with group name in header
- Member nodes rendered normally within the group boundary
- Connections between internal nodes rendered normally
- Connections crossing group boundary route to edge ports

**Boundary Behavior**
- Group boundary expands automatically to fit all member nodes
- Manual resize handles if user wants to override auto-sizing
- Padding around member nodes for visual breathing room
- Minimum size constraints to prevent collapse-like appearance

**Port Rendering**
- Group ports appear as connection points on the group boundary
- Visual indicators showing which internal nodes are routed to which group ports
- Highlight routing on hover to show data flow

### Connection Rendering

Connections involving groups need special rendering:

**To/From Collapsed Groups**
- Connection endpoints attach to group port positions on boundary
- Bezier curves route naturally to group edges
- Port positions calculated based on port index and group dimensions

**To/From Expanded Groups**
- Connection crosses group boundary
- Visual routing from external node to group port on boundary
- Continuation from group port to internal routed node
- Possibly render as two separate visual segments with connection point at boundary

**Hover and Selection**
- Hovering group port highlights all routed internal connections
- Hovering internal node shows which group ports it connects through
- Selection shows full routing path for debugging

## Interaction Design

### Creating Groups

**Selection-Based Grouping**
- User selects multiple nodes using existing selection mechanism
- Right-click menu or keyboard shortcut to "Group Selected Nodes"
- System creates new group containing selected nodes
- User prompted to name group and define ports

**Empty Group Creation**
- User creates empty group first via menu or node creation palette
- Nodes can be dragged into group boundary to add them
- Provides more control over group structure before adding nodes

### Defining Group Ports

**Automatic Port Detection**
- System analyzes connections entering/leaving selected nodes
- Suggests group ports based on external connections
- User can accept, modify, or supplement suggested ports

**Manual Port Definition**
- UI panel for editing group properties when group selected
- Add input port: specify name, routing to internal node(s)
- Add output port: specify name, routing from internal node(s)
- Reorder ports to match logical flow
- Delete unused ports

**Port Routing Interface**
- Visual routing editor showing group boundary and internal nodes
- Click internal node port to assign it to a group port
- Support multi-select for fan-in or fan-out scenarios
- Validation prevents incompatible routings

### Collapse and Expand

**Collapse Interaction**
- Click collapse icon in group header
- Smooth transition animation (optional, can start without)
- Member nodes become hidden from view
- Connections reroute to group ports
- Group state saved to database or local preference

**Expand Interaction**
- Click expand icon on collapsed group
- Member nodes fade in or pop into view
- Group boundary appears around members
- Internal connections become visible
- Full workflow context restored

**State Persistence**
- Collapse state can be per-workflow (everyone sees same state)
- Or per-user preference (user's personal view)
- Reasonable default: collapsed for large groups, expanded for new groups

### Moving and Editing Groups

**Dragging Collapsed Groups**
- Click and drag group header or body
- Entire group moves as unit
- Connected edges update dynamically
- No changes to internal node positions

**Dragging Expanded Groups**
- Dragging group header moves entire group including members
- Member nodes maintain relative positions within group
- Internal connections move with nodes
- External connections update endpoints

**Dragging Individual Members**
- When group is expanded, can drag individual nodes
- Node stays within group boundary
- Group boundary auto-resizes to accommodate
- Or boundary is manually sized and nodes constrained

**Ungrouping**
- Select group and choose "Ungroup" action
- Group ports are removed
- Connections from group ports are deleted (with warning)
- Or connections attempt to preserve routing to internal nodes
- Member nodes remain at current positions

## Implementation Modules

### State Module Extensions

The state.lua module needs to track group entities:

**Group State Structure**
- Add groups table to editor state
- Each group has ID, name, metadata, member IDs, port definitions
- Collapse state per group
- Next group ID counter for unique IDs

**Group Membership Tracking**
- Maintain reverse mapping: node ID to containing group ID
- Enable fast lookups for "which group does this node belong to"
- Support validation (node can only belong to one group in flat hierarchy)

### Node Module Extensions

The node.lua module needs group-aware operations:

**Node Creation Within Groups**
- When creating node, check if creation point is within a group boundary
- Automatically add node to group membership
- Validate group capacity limits if any

**Node Deletion**
- When deleting node, remove from group membership
- If last node in group, prompt to delete group or leave empty
- Update group ports that route to deleted node

**Group Boundary Checking**
- Function to test if point or node is inside group boundary
- Hit testing for expanded groups
- Collision detection for overlap prevention

### Render Module Extensions

The render.lua module needs to draw groups:

**Group Rendering Order**
- Render expanded groups first (background layer)
- Then render nodes (some may be inside groups)
- Then render collapsed groups (foreground layer)
- Then render connections (may cross group boundaries)

**Group Drawing Functions**
- Draw expanded group: boundary box, header, ports
- Draw collapsed group: compact representation, ports
- Draw group ports: circles on boundary with labels
- Draw routing hints: visual connection from group port to internal nodes

**Connection Drawing Updates**
- Detect if connection involves group
- Calculate connection endpoints based on group port positions
- Render connection routing through group boundary
- Handle visual layering for group-crossing connections

### Input Module Extensions

The input.lua module needs group interaction:

**Click Handling**
- Distinguish between clicking group header, body, ports, members
- Collapse/expand on header icon click
- Select group on body click
- Port connection drag from group ports
- Node selection within expanded groups

**Drag Handling**
- Drag entire collapsed group
- Drag expanded group by header
- Drag individual members within group
- Constrain dragging to group boundaries if configured

**Hover Handling**
- Hover on group highlights boundary
- Hover on group port shows routing connections
- Hover on internal node shows group membership
- Hover feedback distinguishes groups from nodes

### Connection Module

New module or extensions for connection routing:

**Route Calculation**
- Given connection from external to group port, determine internal endpoint
- Given connection from group port to external, determine internal source
- Validate routing compatibility
- Detect routing conflicts

**Connection Creation**
- Support creating connections to/from group ports
- UI shows available ports when dragging near group
- Snap to group port on release
- Prompt for routing if multiple internal targets possible

**Connection Validation**
- Prevent connections that would create invalid states
- No direct external connections to grouped nodes
- All external traffic must go through group ports
- Internal connections within group are unrestricted

## Data Binding and Persistence

### Lua Thread Management

The workflow_app.lua manages groups through database:

**Group CRUD Operations**
- create_group: insert group record, return group ID
- update_group: modify name, ports, metadata
- delete_group: remove group and membership records
- add_node_to_group: update membership table
- remove_node_from_group: update membership table

**Port Management**
- add_group_port: create port with routing information
- update_group_port_routing: modify which nodes connect to port
- delete_group_port: remove port definition
- reorder_group_ports: change visual port order

**Data Binding to UI**
- Bind groups array via data.bind similar to nodes and connections
- Include membership information in bound data
- Include port definitions and routing in bound data
- Main thread reads via data.get and reconstructs group state

### Database Schema

New tables needed in SQLite:

**Groups Table**
- group_id: unique identifier
- workflow_id: which workflow this group belongs to
- name: display name
- description: optional documentation
- color_r, color_g, color_b, color_a: theming
- is_collapsed: default state
- created_at, updated_at: timestamps

**Group Membership Table**
- membership_id: unique identifier
- group_id: which group
- node_id: which node is a member
- joined_at: timestamp
- Unique constraint on (group_id, node_id)

**Group Ports Table**
- port_id: unique identifier
- group_id: which group
- port_name: display name
- is_input: true for input, false for output
- port_index: ordering for visual display
- created_at: timestamp

**Port Routing Table**
- routing_id: unique identifier
- port_id: which group port
- node_id: which internal node
- node_port_index: which port on the internal node
- is_node_output: direction of internal port
- Supports multiple rows per port_id for fan-in/fan-out

## Edge Cases and Considerations

### Nesting Groups

**Initial Implementation: Flat Only**
- Groups cannot contain other groups
- Simplifies implementation and mental model
- Most use cases satisfied with single-level grouping

**Future Enhancement: Nested Groups**
- Groups can contain other groups
- Requires recursive rendering and interaction logic
- Collision detection becomes more complex
- Port routing can cross multiple group boundaries

### Connection Conflicts

**External Connection to Grouped Node**
- If node is grouped, existing external connections should be converted
- Prompt user to create appropriate group port
- Or automatically create group port with sensible routing
- Migration path when grouping existing workflows

**Deleting Routed Nodes**
- If internal node is deleted and group port routes to it, warn user
- Offer to delete group port or reroute to different node
- Prevent orphaned port routing references

**Modifying Group Membership**
- When removing node from group, check if any group ports route to it
- Update or delete affected port routings
- Maintain connection integrity

### Performance Optimization

**Rendering Optimization**
- Collapsed groups render as single node-like entity
- Don't render internal nodes when group is collapsed
- Cache collapsed group visual representation
- Render only visible groups when canvas is panned/zoomed

**Hit Testing Optimization**
- Bounding box tests before detailed group boundary checks
- Collapsed groups use simple rectangle hit test
- Expanded groups test boundary then members

**Data Synchronization**
- Batch group updates to avoid frequent data.bind calls
- Debounce collapse/expand state changes
- Only sync modified groups, not entire group collection

### User Experience Refinements

**Visual Feedback**
- Animate collapse/expand transitions smoothly
- Highlight group boundary on hover
- Show connection routing on port hover
- Indicate group membership with subtle border or shading

**Keyboard Shortcuts**
- Ctrl+G to group selected nodes
- Ctrl+Shift+G to ungroup
- Space or Enter to toggle collapse on selected group
- Arrow keys to navigate between groups

**Context Menus**
- Right-click group for group-specific actions
- Edit ports, rename, delete, ungroup
- Quick collapse/expand all groups
- Auto-arrange nodes within group

## Success Criteria

**Functional**
- Can create groups from selected nodes
- Can collapse and expand groups
- Can define input/output ports on groups
- Connections to group ports route correctly to internal nodes
- Can move, edit, and delete groups
- All state persists to database

**Visual**
- Groups are visually distinct from regular nodes
- Collapsed and expanded states are clear
- Port routing is intuitive and visible
- Connection flow through groups is understandable

**Performance**
- No noticeable lag when collapsing/expanding
- Large workflows with many groups remain responsive
- Rendering scales to 10+ groups with 50+ nodes each

**Usability**
- Creating groups requires minimal clicks
- Port configuration is straightforward
- Collapse/expand is instant and predictable
- Workflow organization is significantly improved
