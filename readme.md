ofxcode
--

Tiny little command line tool for mac users of OF to quickly add addons. 


	Usage: ofxcode [project-file] (add|remove|update) addonName
	
	  project-file: Name of project file, e.g. emptyExample.xcodeproj
	                If not provided the first xcodeproject in the directory will be used.
	
	  
	  add|remove|update: Adds/removes an addon. Update first calls remove, then add. 
	  
	  addonName:    Name of an addon. Use a dash (-) to pick from a list of available addons. 
