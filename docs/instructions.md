# vah application development

we are building vah. this is a foundation to build manufold, a data organization eco system.

## important documents to read

please read these documents first:

- [idea](idea.md)
- [manufold-client.md](manufold-client.md)

## notes
- avoid using bash for project exploration, use the built in tools you have instead.
- do not create "timelines" as you're the only dev. just make documents that will help you get up to speed when the conversation starts over.
- do not think about how long something takes in "weeks" but instead think of how much context it takes in lines of code. 
- we are only trying to complete a task that fits in subagents context (2k lines of code is a good target). if the effort is more than that, say that so.
- - each subagent can work through 2k lines of code, including the time it takes them to earn project understanding.
- do not create "phases" for your work. plans should be about what you can do in the given context you have. 
- - avoid using timelines/phases terminology all together. 
- we don't want application logic in C++, it should all be in lua with C++ exposing the functionality.
- avoid using lua strings in c++. 
- do not retain "fallbacks" for things that are not working in the code.
- do not retain code for "compatability." we want a clean codebase without confusion.
- when using subagents, tell them to read the [subagent-instructions document](subagent-instructions.md) in your instructions to them.

## RmlUi

the application uses RmlUi for the UI. It supports a subset of CSS3. it's safer to build in css2 to avoid issues.

for assistance, please read the code directly or the documentation. they can be found in these directories:
- D:/projects/RmlUi
- D:/projects/RmlUiDoc

## current task
this task is small enough that you should not use subagents.

after understanding the long term goal (manufold-client), please review the [reactive data plan](reactive-data-plan.md). please explain it to me so that i know i've documented the problem well enough. you have implemented your first pass in DataBindings and DataStore. review your work and resolve issues present. the current example crashes when i press the delete button too many times. 

## current effort

PS D:\projects\vah> git status
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   CMakeLists.txt
        modified:   docs/instructions.md
        modified:   scripts/sqlite_demo.lua
        modified:   src/CommandQueue.h
        modified:   src/LuaThread.cpp
        modified:   src/LuaThread.h
        modified:   src/RmlUiBridge.cpp
        modified:   src/ThreadManager.cpp
        modified:   src/ThreadManager.h
        modified:   src/main.cpp
        modified:   ui/sqlite_demo.rml

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        docs/reactive-data-plan.md
        src/DataBindings.cpp
        src/DataBindings.h
        src/DataStore.cpp
        src/DataStore.h


## current log 
[2025-10-11 20:28:23.184] [info] Initializing Vah Engine...
[2025-10-11 20:28:23.381] [info] RmlGL3: 
[2025-10-11 20:28:23.389] [info] [RmlUi] Loaded font face 'Roboto' [regular] from 'ui/fonts/roboto-static/Roboto-Regular.ttf'.
[2025-10-11 20:28:23.389] [info] [RmlUi] Loaded font face 'Roboto' [bold] from 'ui/fonts/roboto-static/Roboto-Bold.ttf'.
[2025-10-11 20:28:23.389] [info] [RmlUi] Loaded font face 'Roboto' [italic] from 'ui/fonts/roboto-static/Roboto-Italic.ttf'.
[2025-10-11 20:28:23.389] [info] [RmlUi] Loaded font face 'Roboto' [weight=300] from 'ui/fonts/roboto-static/Roboto-Light.ttf'.
[2025-10-11 20:28:23.389] [info] [RmlUi] Loaded font face 'Roboto' [weight=500] from 'ui/fonts/roboto-static/Roboto-Medium.ttf'.
[2025-10-11 20:28:23.390] [info] [RmlUi] Loading Lua plugin using a new Lua state.
[2025-10-11 20:28:23.390] [info] [RmlUi] Loaded font face 'rmlui-debugger-font' [regular] from 'memory'.
[2025-10-11 20:28:23.390] [info] [RmlUi] Loaded font face 'rmlui-debugger-font' [italic] from 'memory'.
[2025-10-11 20:28:23.395] [info] RmlUiBridge: Registered trigger(), trigger_delete() and update_data_model() functions in RmlUI lua state
[2025-10-11 20:28:23.396] [info] ThreadManager: Spawned thread 1 for script 'scripts/main.lua'
[2025-10-11 20:28:23.396] [info] Vah Engine initialized successfully
[2025-10-11 20:28:23.396] [info] FileSystem bindings initialized
[2025-10-11 20:28:23.396] [info] JSON bindings initialized
[2025-10-11 20:28:23.396] [info] SQLite bindings initialized
[2025-10-11 20:28:23.397] [info] Lua thread 1 running
[2025-10-11 20:28:23.401] [info] [Lua Thread 1] Main Lua thread started
[2025-10-11 20:28:23.401] [info] Processing SpawnThread command: scripts/sqlite_demo.lua (parent: 1)
[2025-10-11 20:28:23.401] [info] ThreadManager: Spawned thread 2 for script 'scripts/sqlite_demo.lua' (parent: 1)
[2025-10-11 20:28:23.401] [info] [Lua Thread 1] Demo initialized
[2025-10-11 20:28:23.401] [info] FileSystem bindings initialized
[2025-10-11 20:28:23.401] [info] JSON bindings initialized
[2025-10-11 20:28:23.401] [info] SQLite bindings initialized
[2025-10-11 20:28:23.403] [debug] Lua thread 2 registered handler for event 'add_contact'
[2025-10-11 20:28:23.403] [debug] Lua thread 2 registered handler for event 'delete_contact'
[2025-10-11 20:28:23.407] [debug] DataStore: Set model 'contacts' with 74 rows
[2025-10-11 20:28:23.407] [debug] LuaThread 2: Bound data model 'contacts' with 74 rows
[2025-10-11 20:28:23.407] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:23.407] [debug] Lua thread 2 queued LoadUIDocument: ui/sqlite_demo.rml
[2025-10-11 20:28:23.407] [info] Lua thread 2 running
[2025-10-11 20:28:23.420] [info] [Lua Thread 2] SQLite demo started (thread_id: 2)
[2025-10-11 20:28:23.420] [info] [Lua Thread 2] Database opened successfully
[2025-10-11 20:28:23.420] [info] [Lua Thread 2] Loaded 74 contacts
[2025-10-11 20:28:23.420] [info] Processing BindDataModel command: contacts
[2025-10-11 20:28:23.420] [info] Successfully bound data model 'contacts'
[2025-10-11 20:28:23.420] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:23.420] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:23.420] [info] Processing LoadUIDocument command: ui/sqlite_demo.rml
[2025-10-11 20:28:23.426] [warning] [RmlUi] Syntax error parsing property declaration 'border: none;' in ui/sqlite_demo.rml: 66.
[2025-10-11 20:28:23.774] [info] Loaded UI document: ui/sqlite_demo.rml
[2025-10-11 20:28:25.519] [debug] RmlUiBridge: Triggered event 'delete_contact' with 1 payload items
[2025-10-11 20:28:25.524] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:25.528] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:25.528] [info] [Lua Thread 2] Loaded 73 contacts
[2025-10-11 20:28:25.528] [debug] DataStore: Set model 'contacts' with 73 rows
[2025-10-11 20:28:25.528] [debug] LuaThread 2: Updated data model 'contacts' with 73 rows
[2025-10-11 20:28:25.529] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:25.531] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:25.532] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:25.568] [debug] DataStore: Set model 'contacts' with 73 rows
[2025-10-11 20:28:25.568] [debug] LuaThread 2: Updated data model 'contacts' with 73 rows
[2025-10-11 20:28:25.569] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:25.893] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:25.893] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:25.893] [info] [Lua Thread 2] Loaded 73 contacts
[2025-10-11 20:28:25.893] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:25.893] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:25.934] [debug] DataStore: Set model 'contacts' with 73 rows
[2025-10-11 20:28:25.934] [debug] LuaThread 2: Updated data model 'contacts' with 73 rows
[2025-10-11 20:28:25.934] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.187] [debug] RmlUiBridge: Triggered event 'delete_contact' with 1 payload items
[2025-10-11 20:28:26.188] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:26.188] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:26.188] [info] [Lua Thread 2] Loaded 73 contacts
[2025-10-11 20:28:26.188] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:26.188] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.220] [debug] DataStore: Set model 'contacts' with 73 rows
[2025-10-11 20:28:26.220] [debug] LuaThread 2: Updated data model 'contacts' with 73 rows
[2025-10-11 20:28:26.221] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.234] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:26.234] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:26.234] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.456] [warning] DataBindings: Row index 72 out of bounds for model 'contacts'
[2025-10-11 20:28:26.456] [warning] [RmlUi] Could not get value from data variable 'contacts[72].name'.
[2025-10-11 20:28:26.457] [warning] DataBindings: Row index 72 out of bounds for model 'contacts'
[2025-10-11 20:28:26.457] [warning] [RmlUi] Could not get value from data variable 'contacts[72].email'.
[2025-10-11 20:28:26.457] [warning] DataBindings: Row index 72 out of bounds for model 'contacts'
[2025-10-11 20:28:26.457] [warning] [RmlUi] Could not get value from data variable 'contacts[72].company'.
[2025-10-11 20:28:26.458] [warning] DataBindings: Row index 72 out of bounds for model 'contacts'
[2025-10-11 20:28:26.458] [warning] [RmlUi] Could not get value from data variable 'contacts[72].phone'.
[2025-10-11 20:28:26.535] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:26.535] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:26.535] [info] [Lua Thread 2] Loaded 73 contacts
[2025-10-11 20:28:26.535] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:26.535] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.535] [info] [Lua Thread 2] Deleting contact ID: 13
[2025-10-11 20:28:26.535] [info] [Lua Thread 2] Deleted contact with id: 13
[2025-10-11 20:28:26.535] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:26.535] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:26.535] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.558] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:26.558] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:26.558] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.565] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:26.565] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:26.565] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.891] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:26.891] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:26.891] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:26.891] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:26.891] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.891] [info] [Lua Thread 2] Deleting contact ID: 13
[2025-10-11 20:28:26.891] [info] [Lua Thread 2] Deleted contact with id: 13
[2025-10-11 20:28:26.891] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:26.891] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:26.891] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.913] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:26.913] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:26.913] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:26.920] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:26.920] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:26.920] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.168] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:27.168] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:27.168] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:27.168] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:27.168] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.168] [info] [Lua Thread 2] Deleting contact ID: 13
[2025-10-11 20:28:27.168] [info] [Lua Thread 2] Deleted contact with id: 13
[2025-10-11 20:28:27.168] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:27.168] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:27.168] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.189] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:27.189] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:27.189] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.205] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:27.205] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:27.205] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.467] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:27.467] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:27.467] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:27.467] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:27.467] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.467] [info] [Lua Thread 2] Deleting contact ID: 13
[2025-10-11 20:28:27.467] [info] [Lua Thread 2] Deleted contact with id: 13
[2025-10-11 20:28:27.467] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:27.467] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:27.467] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.485] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:27.485] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:27.486] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.499] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:27.499] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:27.499] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.762] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:27.762] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:27.762] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:27.762] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:27.762] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.762] [info] [Lua Thread 2] Deleting contact ID: 13
[2025-10-11 20:28:27.762] [info] [Lua Thread 2] Deleted contact with id: 13
[2025-10-11 20:28:27.762] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:27.762] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:27.762] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.771] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:27.771] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:27.771] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:27.777] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:27.777] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:27.778] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:28.039] [debug] RmlUiBridge: Triggered event 'delete_contact' with 1 payload items
[2025-10-11 20:28:28.039] [info] [Lua Thread 2] Deleting contact ID: 2
[2025-10-11 20:28:28.039] [info] [Lua Thread 2] Deleted contact with id: 2
[2025-10-11 20:28:28.039] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:28.039] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:28.039] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:28.039] [info] [Lua Thread 2] Deleting contact ID: 13
[2025-10-11 20:28:28.039] [info] [Lua Thread 2] Deleted contact with id: 13
[2025-10-11 20:28:28.039] [info] [Lua Thread 2] Loaded 72 contacts
[2025-10-11 20:28:28.039] [debug] Processing DirtyDataModel command: contacts
[2025-10-11 20:28:28.039] [debug] Marked data model 'contacts' as dirty
[2025-10-11 20:28:28.068] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:28.068] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:28.069] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:28.075] [debug] DataStore: Set model 'contacts' with 72 rows
[2025-10-11 20:28:28.075] [debug] LuaThread 2: Updated data model 'contacts' with 72 rows
[2025-10-11 20:28:28.075] [debug] LuaThread 2: Marked data model 'contacts' as dirty
[2025-10-11 20:28:28.088] [debug] DataStore: Set model 'contacts' with 71 rows
[2025-10-11 20:28:28.088] [debug] LuaThread 2: Updated data model 'contacts' with 71 rows
[2025-10-11 20:28:28.088] [debug] LuaThread 2: Marked data model 'contacts' as dirty
