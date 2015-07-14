//
//  main.m
//  ofx
//
//  Created by Hansi on 03.05.15.
//  Copyright (c) 2015 hansi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OfProject.h"


@interface CLI : NSObject
+(void) printUsage;
+(NSString*) findXcodeProjectFile;
@end

int main(int argc, const char * argv[]) {
	
	/*
	 neat for testing: 
	 NSString * projectFile = @"/Users/hansi/Documents/OF/of_v0084_osx_release/apps/myApps/OsciStudio/OsciStudio.xcodeproj";
	 OfProject * proj = [[OfProject alloc] initWithPath:projectFile];
	 [proj addAddon:@"ofxAssimpModelLoader"];
	 [proj save];
	 exit(0);
	*/
	
	NSString * projectFile;
	NSString * command;
	NSString * addonName;
	
	// maybe its time for an argument parsing library?
	if( argc == 2 ){
		command = [NSString stringWithUTF8String:argv[1]];
		if( [command isEqualToString:@"version"] ){
			printf( "ofxcode version 1.01\n" );
			exit(0);
		}

	}
	
	
	if( argc == 3 ){
		// use first .xcodeproj we can find
		projectFile = [CLI findXcodeProjectFile];
		if( projectFile == nil ){
			printf("No .xcodeproject file found in the current directory" );
			exit(1);
		}
		
		command = [NSString stringWithUTF8String:argv[1]];
		addonName = [NSString stringWithUTF8String:argv[2]];
	}
	else if( argc == 4 ){
		projectFile = [NSString stringWithUTF8String:argv[1]];
		command = [NSString stringWithUTF8String:argv[2]];
		addonName = [NSString stringWithUTF8String:argv[3]];
	}
	else{
		[CLI printUsage];
		exit(0);
	}
	
	OfProject * proj = [[OfProject alloc] initWithPath:projectFile];

	if( [addonName isEqualToString:@"-"] ){
		NSArray * addons = proj.availableAddons;
		for( int i = 0; i < addons.count; i++ ){
			printf( "%d. %s\n", i+1, [addons[i] UTF8String] );
		}
		
		int choice;
		scanf ("%d", &choice);
		choice --;
		if( choice >= 0 && choice < addons.count ){
			addonName = addons[choice];
		}
		else{
			printf( "tooo much" );
			exit(1);
		}
	}
	
	if( addonName == nil || projectFile == nil ){
		[CLI printUsage];
		exit(1);
	}
	else if( [command isEqualToString:@"add"] || [command isEqualToString:@"update"] ){
		// we _have_ to remove it first anyways. so... add is actually an alias for update, i guess!
		[proj removeAddon:addonName];
		[proj addAddon:addonName];
	}
	else if( [command isEqualToString:@"remove"]){
		[proj removeAddon:addonName];
	}
	else{
		[CLI printUsage];
		exit(1);
	}
	
	printf( "\n\nWriting changes to %s, sure?\n", projectFile.lastPathComponent.UTF8String);
	printf( "y/n? "); 
	char ch;
	scanf(" %c", &ch);
	if( ch == 'y' ){
		[proj save];
	}
	else{
		printf( "Didn't save!" );
	}
    return 0;
}


@implementation CLI
+(void) printUsage{
	printf("Usage: ofxcode [project-file] (add|remove|update) addonName\n\n");
	printf("  project-file: Name of project file, e.g. emptyExample.xcodeproj\n" );
	printf("                If not provided the first xcodeproject in the directory will be used.\n\n" );
	printf("  \n" );
	printf("  add|remove|update: Adds/removes an addon. Update first calls remove, then add. \n" );
	printf("  \n" );
	printf("  addonName:    Name of an addon. Use a dash (-) to pick from a list of available addons. \n" );
}

+(NSString*) findXcodeProjectFile{
	NSString * path = NSFileManager.defaultManager.currentDirectoryPath;
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
										 enumeratorAtURL:[NSURL URLWithString:path]
										 includingPropertiesForKeys:nil
										 options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
										 errorHandler:^(NSURL *url, NSError *error) {return YES;}];
	
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		if( [[path pathExtension] isEqualToString:@"xcodeproj"] ){
			return path;
		}
	}
	
	return nil;
}
@end