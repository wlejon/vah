# vah application development

we are working in vah. this is a foundation for supporting the manufold data organization and display eco system.

## build
- build with "cmake --build build" and avoid using cd. 
- - the user runs the application, instruct them, don't run it yourself.

## notes
- avoid using bash for project exploration, use the built in tools you have instead.
- - as a subagent, when i decline a request it stops the subagent all together, ending your process. using the pre-approved tools prevents this. don't try to be clever with bash as the commands fail and i decline them, halting your process.
- do not think about how long something takes in "weeks" but instead think of how much context it takes in lines of code. 
- we are only trying to complete a task that fits in your context (2k lines of code is a good target).
- we don't want application logic in C++, it should all be in lua with C++ exposing the functionality to lua.
- avoid using lua strings in c++. 
- do not retain "fallbacks" for things that are not working in the code. remove the old code.
- do not retain code for "compatability." we want a clean codebase without confusion.
- do not create simplifications. you are the primary programmer. complete the effort properly.
- go into c++ as needed. don't be shy.

## RmlUi

the application uses RmlUi for the UI. It does supports a subset of CSS3.

for assistance, please read the code directly or the documentation. they can be found in these directories:
- D:/projects/RmlUi
- D:/projects/RmlUiDoc

## current task

the current task given to you is the only thing you should work on. do not create additional documentation/documents, tests, or examples. this excess causes confusion in the codebase, especially with other coding agents. keep it clean.

do not create scripts meant to test other parts of the code. it's the users job to test.