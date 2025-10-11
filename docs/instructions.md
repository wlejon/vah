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
this task is small enough that you should not use subagents.

currently we're doing this in main.cpp:

        // Load and show test UI
        auto doc = rml_context_->LoadDocument("ui/main.rml");
        if (doc) {
            doc->Show();
            LOG_INFO("Loaded test UI document");
        } else {
            LOG_WARN("Failed to load test UI document");
        }

what i'd like instead is to do that in lua. you can look at bb1 (../bb1 or D:/projects/bb1) to see how we exposed the rmlui api to lua. lua should load the ui documents through a command queue. after the application initializes, it loads the scripts/main.lua file in a thread. this thread should then ask the main thread to display the ui/main.rml file through a command queue (like the ones that exist already).

