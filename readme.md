# ofxcode
--

Tiny little command line tool for mac users of OF to quickly add addons. 


## Installation

Download the latest binary release and drop it in `/usr/local/bin`

## Usage
	
	
	ofxcode version 1.09
	Usage: ofxcode [project-file] (add|remove|update) addonName
	or     ofxcode [project-file] sync [src|addons]
	
	  project-file: Name of project file, e.g. emptyExample.xcodeproj
	                Optional. You'll be prompted to select the project file if there is more than one in the current folder. 
	
	  
	  add|remove|update: Adds/removes an addon. This also changes addons.make
	  If no addon name is provided you will be asked to pick from a list. 
	  
	  sync: Synchronizes source folder and/or addons
	        src: Only synchrones the src folder of the project
	        addons: Only synchronizes addons (same as calling 'update' for each addon)
	        Providing no extra argument synchronizes both sources and addons
