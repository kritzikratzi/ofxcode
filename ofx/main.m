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
+(NSMutableSet*) readAddonsMake: (NSString*) path;
+(void) writeAddonsMake: (NSString*) path addonNames:(NSSet*)addonNames;
+(NSString*) askForAddonName: (NSArray*) availableAddonNames;
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
	
	NSMutableArray * args = [[NSMutableArray alloc] init];
	for( int i = 1; i < argc; i++ ){
		[args addObject:[NSString stringWithUTF8String:argv[i]]];
	}
	
	// The first argument is an optional xcodeproject path
	if( [[args.firstObject pathExtension] isEqualToString:@".xcodeproj"] ){
		// It is!
		projectFile = args.firstObject;
		[args removeObjectAtIndex:0];
	}
	else{
		projectFile = [CLI findXcodeProjectFile];
	}
	
	
	if( args.count == 0 ){
		[CLI printUsage];
		exit(0);
	}
	else{
		// Now we must have a command
		command = args.firstObject;
		[args removeObjectAtIndex:0];
	}
	
	
	if( [command isEqualToString:@"version"] ){
		printf( "ofxcode version 1.07\n" );
		exit(0);
	}
	
	if( ![NSFileManager.defaultManager fileExistsAtPath:projectFile] ){
		printf("XCode project file could not be loaded\n");
		exit(1);
	}
	OfProject * proj = [[OfProject alloc] initWithPath:projectFile];
	NSString * addonsMakeFile = [[projectFile stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"addons.make"];
	NSMutableSet * projAddons = [CLI readAddonsMake:addonsMakeFile];

	if( [command isEqualToString:@"sync"] ){
		// update all addons as set by addons.make
		for( NSString * addonName in projAddons ){
			[proj removeAddon:addonName];
			[proj addAddon:addonName];
		}
	}
	else if( [command isEqualToString:@"add"] || [command isEqualToString:@"update"] ){
		// we _have_ to remove it first anyways. so... add is actually an alias for update, i guess!
		NSArray * addonNames;
		if( args.count == 0 || [args.firstObject isEqualToString:@"-"] ){
			addonNames = @[ [CLI askForAddonName:proj.availableAddons] ];
		}
		else{
			addonNames = args; // only addons from here on
		}
		
		for( NSString * addonName in addonNames ){
			[proj removeAddon:addonName];
			[proj addAddon:addonName];
			[projAddons addObject:addonName];
		}
	}
	else if( [command isEqualToString:@"remove"]){
		NSArray * addonNames;
		if( args.count == 0 || [args.firstObject isEqualToString:@"-"] ){
			addonNames = @[ [CLI askForAddonName:proj.availableAddons] ];
		}
		else{
			addonNames = args; // only addons from here on
		}
		
		for( NSString * addonName in addonNames ){
			[proj removeAddon:addonName];
			[projAddons removeObject:addonName];
		}
	}
	else{
		[CLI printUsage];
		exit(1);
	}
	
	[proj save];
	[CLI writeAddonsMake:addonsMakeFile addonNames:projAddons];

	return 0;
}


@implementation CLI
+(void) printUsage{
	printf("Usage: ofxcode [project-file] (add|remove|update) addonName\n");
	printf("or     ofxcode [project-file] sync\n\n");
	
	printf("  project-file: Name of project file, e.g. emptyExample.xcodeproj\n" );
	printf("                Optional. You'll be prompted to select the project file if there is more than one in the current folder. \n\n" );
	printf("  \n" );
	printf("  add|remove|update: Adds/removes an addon. This also changes addons.make\n" );
	printf("  If no addon name is provided you will be asked to pick from a list. \n");
	printf("  \n" );
	printf("  sync: Remove all addons, and re-adds them based on addons.make\n\n");
}

+(NSString*) findXcodeProjectFile{
	NSString * path = NSFileManager.defaultManager.currentDirectoryPath;
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
										 enumeratorAtURL:[NSURL URLWithString:path]
										 includingPropertiesForKeys:nil
										 options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
										 errorHandler:^(NSURL *url, NSError *error) {return YES;}];
	
	NSMutableArray * paths = [[NSMutableArray alloc] init];
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		if( [[path pathExtension] isEqualToString:@"xcodeproj"] ){
			[paths addObject:path];
		}
	}
	
	if( paths.count == 0 ){
		return nil;
	}
	else if( paths.count == 1 ){
		return paths.firstObject;
	}
	else{
		for( int i = 0; i < paths.count; i++ ){
			printf( "%d. %s\n", i+1, [paths[i] UTF8String] );
		}
		
		int choice;
		scanf ("%d", &choice);
		choice --;
		if( choice >= 0 && choice < paths.count ){
			return paths[choice];
		}
		else{
			printf( "tooo much" );
			exit(3);
		}
	}
	
	
	return nil;
}

+(NSMutableSet*) readAddonsMake: (NSString*) path{
	NSString * contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	NSArray * names = [contents componentsSeparatedByString:@"\n"];
	NSMutableSet * result = [[NSMutableSet alloc] init];
	for( NSString * addonName in names ){
		if( ![addonName isEqualToString:@""] ){
			[result addObject:addonName];
		}
	}
	return result;
}

+(void) writeAddonsMake: (NSString*) path addonNames:(NSSet*)addonNames{
	NSString * contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	
	if( [addonNames isEqualToSet:[CLI readAddonsMake:path]] ){
		// addons didn't change. no need to write anything
	}
	else{
		// old addons ordered
		NSArray * oldNames = [contents componentsSeparatedByString:@"\n"];
		// new addons unordered
		NSMutableSet * remaining = [NSMutableSet setWithSet:addonNames];
		

		// new addons ordered
		NSString * result = @"";
		BOOL first = YES;
		
		// first add in all addons that were already there, preserve their order
		for( NSString * addonName in oldNames ){
			if( [remaining containsObject:addonName] ){
				if(!first) result = [result stringByAppendingString:@"\n"];
				else first = NO;
				result = [result stringByAppendingString:addonName];
				[remaining removeObject:addonName];
			}
		}
		
		for( NSString * addonName in remaining ){
				if(!first) result = [result stringByAppendingString:@"\n"];
				else first = NO;
				result = [result stringByAppendingString:addonName];
		}
		
		[result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
	}
}

+(NSString*) askForAddonName: (NSArray*) availableAddonNames{
	for( int i = 0; i < availableAddonNames.count; i++ ){
		printf( "%d. %s\n", i+1, [availableAddonNames[i] UTF8String] );
	}
	
	int choice;
	scanf ("%d", &choice);
	choice --;
	if( choice >= 0 && choice < availableAddonNames.count ){
		return availableAddonNames[choice];
	}
	else{
		printf( "tooo much" );
		exit(1);
	}
}

@end