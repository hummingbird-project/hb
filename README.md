# HB

The Hummingbird command line tool

## Create a new project

```
hb init my-project
```
And answer the questions
```
✔︎ What kind of application are you building: Server 
✔︎ What would you like your executable to be named?: MyProject 
✔︎ Which features would you like to enable?: OpenAPI 
```

## Background compilation

Watch for project changes to your project source tree. 

```
hb watch
```
Whenever there are any changes it will rebuild your application and run.
```
Building for debugging...
[1/1] Write swift-version--2BC00F076F73B7CD.txt
Build of product 'MyProject' complete! (2.66s)
PID: 96830
2026-06-09T08:06:06+0100 info my-project: [HummingbirdCore] Server started and listening on 127.0.0.1:8080
File changed /Users/adamfowler/Developer/server/my-project/Sources/App/APIImplementation.swift
File changed /Users/adamfowler/Developer/server/my-project/Sources/App/APIImplementation.swift
Building for debugging...
[7/7] Applying MyProject
Build of product 'MyProject' complete! (8.39s)
PID: 98221
2026-06-09T08:06:44+0100 info my-project: [HummingbirdCore] Server started and listening on 127.0.0.1:8080
```
