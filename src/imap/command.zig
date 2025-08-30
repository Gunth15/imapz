//Command is prefixed with identifier A001, A002, etc called tag
//Should generate tag for every command, but server MUST accept reuse

//NOTE: Only two cases when a command in not finished in one line
//1. Command Require server feedback
//2. Command is quoted with octet count
//In both cases, a command continuation request is made by the server and prefixed with "+"
//If an error happens, BAS is sent and no mor eof the command is can be sent.

//Serer -> Client
//Repsonses that do not indicate command completions are prefixed with a "*" and are called untagged
//MAY be sent as client or MAY be sent unilaterally by server
//Completion result indocates success or failure. Tagged with same tag as command
//If multiple commands in progress, tag can be used to identify which command goes to what.
//
//NOTE: Clinet must be prepared to accept server repsonse at all times.
//Including unrequested data and all of it SHOUlD be cached.
