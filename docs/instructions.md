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

## current task
this task is small enough that you should not use subagents.

we're having issues with how the scrollbar renders on streaming.rml. i need you to read the documentation for how scrollbars are used and also read the code for how it's rendered. 

D:/projects/RmlUi
D:/projects/RmlUiDoc

please explore these two folders to figure out exactly how you're meant to use the scrollbar and then compare to how we're using it. our current implementation, as a whole, is incorrect and the scrollbar renders comically large. adjusting the size in css has had no impact. 

