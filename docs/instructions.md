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

the main visual purpose of this application will be to realtime populate a view within streaming data async. let's create a scenario for this to operate in lua scripts. please create a lua script that continously creates data of a varied kind that fits a format we're displaying. have this continously generated data represented in a high level view of the data in the UI. this will help us iron out imporant bugs and any memory leaks we may have. this will serve the purpose of demonstrating one facet of the visualizations we can provide. this will help solidify the threading architecture we're following. 

