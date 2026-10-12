In `/home/GoogleDrive/Projekty/meeting-scheduler` i created a web app that pulls from shared calendars of my team members and builds a common panel that allows to display multiple of them together to see when people are busy. it works and is hosted on github pages. every team member has a checkbox to display their calendar, so i can see only selected subsets of people. read the original project to see how it's done currently.

now i want to take this idea and build a plugin for omarchy, that will have the same functionality. 

i already started building the plugin, and i already have something working. you can see it in action if you run the `Preview.qml` file. it already renders the mockup events defined in the preview file, and it is theme-aware in terms of coloring, so this aspect might be ready.

the idea for team configuration is that one user builds a `team.json` file with the team info. then, other team members can import this file into the plugin, and the plugin will build the team configuration based on this file. 

the assumption is that the calendar ids are public / accessible to anyone who has the id, so you don't need any special permissions to access them. see in what state this project is and assess if the next step should be to implement the actual pulling the data from calendars or something else related to the plugin architecture, that is needed first.
