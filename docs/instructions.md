# vah application development

we are building vah. this is a foundation to build manufold, a data organization eco system.

## important documents to read

[idea](idea.md)
[manufold-client.md](manufold-client.md)

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

## current task

i've brought in various parts that we've made in previous projects. we need to setup the foundation to build to include these things and also build what's below.

here's what should be present and working:

Lock Free Threads: The application lua state (separate from the RmlUi lua state) will only run on separate threads, not the main thread. Each entry point script that is run will be run on its own thread.
Command Queue: All interaction to the main thread from lua threads will be through a command queue. There will be multiple lua threads asking the main thread to do things.
Seqlock: Input should be read from the lua threads as needed (not all will read input) and it should be populated from the main thread as a state not individual inputs. A lua thread can just ask the data about what inputs were pressed in the last frame.
RmlUi Bridge: the main thread will run rmlui and it's lua state. When UI events happen, we need to inform lua threads as well. We'll include UI events in the seqlock information. We'll treat it as an input event the same as mouse and keyboard. it'll have a string name and a payload as needed. the rmlui lua code should remain idiomatic with events being simple to create. something like trigger('eventname', {payload}). 

The main thread will keep track of the lua threads spawned and have tools needed to manage them (pause, resume, save, exit).

Please review the code created so far to understand what i'm after. 

we need to define the lua interface a little better. 

a lua thread will have a lua entry script. the entry script can require and load as many other scripts as it wants, of course. the lua thread c++ side will send some calls into the lua state created:

startup: called after the lua state is ready (scripts load).
load: load from a saved state. called after startup
update: called at 30hz
event function: called for registered events at the given function
save: save state
shutdown: called before shutting down

i'm trying to think through lifecycle and interactions with the thread. 

an example usage would be an application agent. we'd give the agent tools and those tools would trigger events in the application. the application would then call back to the lua thread with whatever the agent asked for. this async process also means we can see all transactions and review and approve them. we'd give agent tools like "search" and we'd build the search results in the application based on what the agent is searching for. tools like "read" and "write" for scripts and the ability to run those scripts. the agent would be able to manage that running script as needed as well. all of this passing through the main thread and the user interface so the user can monitor the agent activity as needed. so the agent would setup in startup, load previous data it chose to save in load, perform processing when update is called, react to events it registers to, saves data it deems important, cleanly shutsdown on shutdown. the agent might "think" on "update" but i think a lot of the time it will be waiting. either wating for a remote api call to respond or waiting for user input. 

what else will an agent need? of course we'll give the agent a lot of tools (filesystem, http, api, ui, etc) but when working autonomously to understand the data contained in the environment, are there any other application level interfaces the agent should have?

