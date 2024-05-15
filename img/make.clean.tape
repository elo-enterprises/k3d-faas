# creates terminal videos with vhs
# https://github.com/charmbracelet/vhs

Output img/make.clean.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 1000
Set TypingSpeed 100ms
Hide 
Type "make clean"
Show
Sleep 500ms
Enter
Sleep 10s
Hide 
Type "make bootstrap"
Show
Sleep 500ms
Enter
Sleep 20s
Type "clear"
