//
//  OfProject.h
//  ofx
//
//  Created by Hansi on 03.05.15.
//  Copyright (c) 2015 hansi. All rights reserved.
//

#pragma once

#import <XcodeEditor/XCProject.h>
#import <XcodeEditor/XCGroup.h>
#import <XcodeEditor/XcodeGroupMember.h>
#import <XcodeEditor/XCSourceFileDefinition.h>
#import <XcodeEditor/XCKeyBuilder.h>
#import <XcodeEditor/XCFileOperationQueue.h>
#import <XcodeEditor/XCTarget.h>
#import <XcodeEditor/XCProjectBuildConfig.h>

#import "OfAddon.h"

@interface OfProject : NSObject

@property (readonly) NSString * path; // path to project file
@property (readonly) NSString * ofPath; // path to OF
@property (readonly) NSString * projPath; // path to project
@property (readonly) NSString * addonsPathGlobal; // path to addons
@property (readonly) NSString * addonsPathLocal; // path to addons

@property (readonly) XCProject * project;

- (id)initWithPath:(NSString*)path;
- (void)save;

// returns a list of addon names installed in OF.x.x/addons/ (cached)
- (NSArray*)availableAddons;
- (NSArray*)availableAddonNames;

// scans for local/global addons, returns an array of OfAddon
- (NSArray*)scanForAddons;

// add a specific addon to the project.
// if it was already added, it will be removed and re-added.
// this will:
// +1. create the group addons/ofxAddonName
// +2. create groups for header search paths to include addons/ofxAddonName/libs/*/include (if that folder exists)
// ~3. update the linker settings to add addons/ofxAddonName/libs/*/lib (missing dylib files, not checking arch yet)
// +4. create a new "run script" stage to copy the data folder during the build process
// -5. add addon specific frameworks to the linker stage
// -6. create a new "copy bundle resources" stage for addon specific frameworks
//
// can't be bothered about (5) and (6) for now.
- (void)addAddonNamed:(NSString*)name;
- (void)addAddon:(OfAddon*)addon;

// removes an addon from the project.
// ruins all the hard work that addAddon performed.
- (void)removeAddonNamed:(NSString*)name;
- (void)removeAddon:(OfAddon*)addon;
- (void)removeAddonLocallyAndGlobally:(OfAddon*)addon;

// removes and re-adds the sources folder, rebuilding all the groups in the project file
- (void)updateSources; 


// from here on it's private methods
- (XCGroup*) addFileWithPath: (NSString*)relativePath toGroup:(XCGroup*)group;
- (BOOL) addDirRecursively: (NSString*)relativePath addonPath:(NSString*)addonPath toGroup:(XCGroup*)group;
- (XCGroup*) getOrCreateAddonGroup: (OfAddon*)addon;

- (BOOL) isDirectory:(NSString*)path;

@end
