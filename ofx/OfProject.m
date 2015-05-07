//
//  OfProject.m
//  ofx
//
//  Created by Hansi on 03.05.15.
//  Copyright (c) 2015 hansi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OfProject.h"

// accessing some private properties so that
// we can create groups with relative locations (ie linking addons/abc to ../../../addons/abc)
@interface XCGroup(AccessPrivates)
- (void)addMemberWithKey:(NSString*)key;
- (NSDictionary*)asDictionary;
@end

// adding a custom method so we can clear out the file queue.
// we don't really want to modify the file system in any way.
@interface XCProject(ClearFileQueue)
- (void)clearFileOperationsQueue;
@end
@implementation XCProject(ClearFileQueue)
- (void)clearFileOperationsQueue{
	_fileOperationQueue = [[XCFileOperationQueue alloc] init];
}
@end


@implementation OfProject

- (id)initWithPath:(NSString*)path{
	NSLog(@"Opening project %@", [path lastPathComponent]);
	_project = [[XCProject alloc] initWithFilePath:path];
	_path = path;
	_projPath = [path stringByDeletingLastPathComponent];
	_ofPath = [[[self.projPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	_addonsPath = [self.ofPath stringByAppendingPathComponent:@"addons"];
	
	
	XCGroup* group = [self.project groupWithPathFromRoot:@"addons"];
	
	NSLog(@"Addons in project file: ");
	for( NSString * key in group.children ){
		XCGroup * addon = [self.project groupWithKey:key];
		NSLog(@"- %@", addon.displayName);
	}
	
	NSLog(@"\n\n");

	
	return self;
}

- (void) save{
	[self.project clearFileOperationsQueue];
	[self.project save];
}

- (void)removeAddon:(NSString*)addonName{
	NSLog(@"Removing addon %@", addonName );
	
	// great! now figure out what to add...
	NSString * addonPath = [self.addonsPath stringByAppendingPathComponent:addonName];
	
	// create a new group for the addon...
	XCGroup * addonGroup = [self.project groupWithPathFromRoot:[NSString stringWithFormat:@"addons/%@",addonName]];
	
	// =======================================
	// 1. remove the group addons/ofxMyAddon/src
	// 2. remove addons/ofxAddon/libs/*/include
	// in fact, just remove it all!
	// =======================================
	if( addonGroup != nil ){
		[addonGroup removeFromParentGroup];
	}
	
	// =======================================
	// 3. remove .a files from linker options
	// TODO: what about dylibs? --> remember and add to copy resources stage?
	// TODO: this currently changes the linker flags in the product config
	// would be much nicer if it was just set once in the project?
	// =======================================
	for( XCTarget * target in self.project.targets ){
		for( NSString * configName in target.configurations ){
			XCProjectBuildConfig * config = target.configurations[configName];
			
			NSArray * ldFlags = (NSArray*)[config valueForKey:@"OTHER_LDFLAGS"];
			// do we have flags?
			if( ldFlags != nil ){
				NSMutableArray * newLdFlags = [[NSMutableArray alloc] init];
				for( NSString * flag in ldFlags ){
					NSString * basePath = [NSString stringWithFormat:@"../../../addons/%@", addonName];
					if( [flag rangeOfString:basePath].length == 0 ){
						[newLdFlags addObject:flag];
					}
				}
				
				[config addOrReplaceSetting:newLdFlags forKey:@"OTHER_LDFLAGS"];
			}
		}
	}
	
	
	// =======================================
	// 4. remove from "run script" phase
	// TODO: losen regex? 
	// =======================================
	NSString * copyCommand = [NSString stringWithFormat:@"cp -rf ../../../addons/%@/bin/data/ \"$TARGET_BUILD_DIR/$PRODUCT_NAME.app/Contents/Resources\"", addonName];
	
	NSString * exprString = [NSString stringWithFormat:@"%@\n*", [NSRegularExpression escapedTemplateForString:copyCommand]];
	for( XCTarget * target in self.project.targets ){
		// walk through all build phases for this target ...
		for (NSString* buildPhaseKey in [[[self.project objects] objectForKey:target.key] objectForKey:@"buildPhases"]){
			NSDictionary* buildPhase = [[self.project objects] objectForKey:buildPhaseKey];
			// it's a "shell script" phase?
			// ok, so for simplicites sake we assume there's just one such phase.
			if ( [[buildPhase valueForKey:@"isa"] isEqualToString:@"PBXShellScriptBuildPhase"] ){
				NSString * script = [buildPhase valueForKey:@"shellScript"];
				if( [script rangeOfString:copyCommand].length > 0 ){
					// remove it !
					script = [script stringByReplacingOccurrencesOfString:exprString withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, script.length)];
					[buildPhase setValue:script forKey:@"shellScript"];
				}
			}
		}
	}
}

- (NSArray*)availableAddons{
	NSArray* addons = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.addonsPath
																		  error:NULL];
	NSMutableArray * addonNames = [[NSMutableArray alloc] initWithCapacity:addons.count];
	for( NSString * addon in addons ){
		NSString * addonPath = [self.addonsPath stringByAppendingPathComponent:addon];
		BOOL isDir = NO;
		[[NSFileManager defaultManager] fileExistsAtPath:addonPath
											 isDirectory:&isDir];
		if( isDir ){
			[addonNames addObject:addon];
		}
	}
	
	return addonNames;
}

- (void)addAddon:(NSString *)addonName{
	NSLog(@"Adding addon %@", addonName );
	// remove the addon first!
	// rly? nooo maybe just remove the group? idk...
	// [self removeAddon:addonName];
	
	// great! now figure out what to add...
	NSString * addonPath = [self.addonsPath stringByAppendingPathComponent:addonName];
	
	// create a new group for the addon...
	XCGroup * addonGroup = [self getOrCreateAddonGroup:addonName];
	
	// =======================================
	// 1. add the source folder recursively
	// =======================================
	NSString * srcPath = [addonPath stringByAppendingPathComponent:@"src"];
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
										 enumeratorAtURL:[NSURL URLWithString:srcPath]
										 includingPropertiesForKeys:nil
										 options:0
										 errorHandler:^(NSURL *url, NSError *error) {return YES;
										 }];
	
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		NSString * relativePath = [path substringFromIndex:addonPath.length+1];
		[self addFileWithPath:relativePath toGroup:addonGroup];
	}
	
	// =======================================
	// 2. add addons/ofxAddon/libs/*/include
	// =======================================
	NSString * libsPath = [addonPath stringByAppendingPathComponent:@"libs"];
	enumerator = [[NSFileManager defaultManager]
										 enumeratorAtURL:[NSURL URLWithString:libsPath]
										 includingPropertiesForKeys:nil
										 options:0
										 errorHandler:^(NSURL *url, NSError *error) {return YES;
										 }];
	
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		NSString * relativePath = [path substringFromIndex:addonPath.length+1];
		NSArray * components = [relativePath pathComponents];
		if( components.count >= 3 && [components[2] isEqualToString:@"include"] ){
			[self addFileWithPath:relativePath toGroup:addonGroup];
		}
	}
	
	// =======================================
	// 3. add addons/ofxAddon/libs/*/lib/*.a to other linker flags
	// TODO: what about dylibs? --> remember and add to copy resources stage?
	// TODO: what about platform directories? ie. there is sometimes libs/osx
	// should be fairly easy to find if the .a architectures matches the current OF
	// TODO: this currently changes the linker flags in the product config
	// would be much nicer if it was just set once in the project?
	// =======================================
	enumerator = [[NSFileManager defaultManager]
				  enumeratorAtURL:[NSURL URLWithString:libsPath]
				  includingPropertiesForKeys:nil
				  options:0
				  errorHandler:^(NSURL *url, NSError *error) {return YES;
				  }];
	
	NSMutableSet * staticLibs = [[NSMutableSet alloc] init];
	
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		NSString * relativePath = [path substringFromIndex:addonPath.length+1];
		if( [[path pathExtension] isEqualToString:@"a"] ){
			[staticLibs addObject:[NSString stringWithFormat:@"../../../addons/%@/libs/%@", addonName, relativePath]];
		}
	}
	
	if( staticLibs.count > 0 ){
		for( XCTarget * target in self.project.targets ){
			for( NSString * configName in target.configurations ){
				XCProjectBuildConfig * config = target.configurations[configName];
				
				NSArray * ldFlags = (NSArray*)[config valueForKey:@"OTHER_LDFLAGS"];
				// do we have flags?
				if( ldFlags == nil ){
					NSMutableArray * newLdFlags = [[NSMutableArray alloc] init];
					[newLdFlags addObject:@"$(OF_CORE_LIBS)"];
					[newLdFlags addObjectsFromArray:[staticLibs allObjects]];
					[config addOrReplaceSetting:newLdFlags forKey:@"OTHER_LDFLAGS"];
				}
				else{
					NSMutableArray * newLdFlags = [NSMutableArray arrayWithArray:ldFlags];
					NSMutableSet * missingStaticLibs = [staticLibs copy];
					for( NSString * archive in ldFlags ){
						[missingStaticLibs removeObject:archive];
					}
					for( NSString * staticLib in missingStaticLibs ){
						[newLdFlags addObject:staticLib];
					}
					[config addOrReplaceSetting:newLdFlags forKey:@"OTHER_LDFLAGS"];
				}
			}
		}
	}
	
	
	// =======================================
	// 4. add "run script" to copy data folder
	// =======================================
	
	// do we even have a data folder?
	NSString * dataPath = [addonPath stringByAppendingPathComponent:@"bin/data"];
	BOOL hasDataFolder = [[NSFileManager defaultManager] fileExistsAtPath:dataPath];
	if( hasDataFolder ){
		NSString * copyCommand = [NSString stringWithFormat:@"cp -rf ../../../addons/%@/bin/data/ \"$TARGET_BUILD_DIR/$PRODUCT_NAME.app/Contents/Resources\"", addonName];
		
		for( XCTarget * target in self.project.targets ){
			// walk through all build phases for this target ...
			for (NSString* buildPhaseKey in [[[self.project objects] objectForKey:target.key] objectForKey:@"buildPhases"]){
				NSDictionary* buildPhase = [[self.project objects] objectForKey:buildPhaseKey];
				// it's a "shell script" phase?
				// ok, so for simplicites sake we assume there's just one such phase.
				if ( [[buildPhase valueForKey:@"isa"] isEqualToString:@"PBXShellScriptBuildPhase"] ){
					NSString * script = [buildPhase valueForKey:@"shellScript"];
					if( [script rangeOfString:copyCommand].length > 0 ){
						// neat, no work. that's a good thing!
					}
					else{
						script = [script stringByAppendingFormat:@"\n%@", copyCommand];
						[buildPhase setValue:script forKey:@"shellScript"];
						break;
					}
				}
			}
		}
	}
}

- (XCGroup*) addFileWithPath: (NSString*) relativePath toGroup:(XCGroup*)group{
	XcodeSourceFileType type = XCSourceFileTypeFromFileName(relativePath);
	if( type == FileTypeNil ){
		// we don't need this crap in our project!
		return nil;
	}
	
	// get all directories
	NSArray * groupNames = [[relativePath stringByDeletingLastPathComponent] pathComponents];
	for( NSString * groupName in groupNames ){
		id subGroup = [group memberWithDisplayName:groupName];
		if( subGroup == nil ){
			group = [group addGroupWithPath:groupName];
		}
		else{
			group = subGroup;
		}
	}
	
	// ok, we should have the group now!
	// time to add the source file
	NSString * filename = [relativePath lastPathComponent];
	XCSourceFileDefinition * srcDefinition = [XCSourceFileDefinition sourceDefinitionWithName:filename data:nil type:type];
	[srcDefinition setFileOperationType:XCFileOperationTypeReferenceOnly];
	[group addSourceFile:srcDefinition];
	
	// neato. now add the file to the compile stage
	if( type == SourceCodeObjC ||
		type == SourceCodeObjCPlusPlus ||
		type == SourceCodeCPlusPlus ||
		type == XibFile ){
		
		// grab the source file again
		XCSourceFile * src = (XCSourceFile*)[group memberWithDisplayName:filename];
		for( XCTarget * target in self.project.targets ){
			[target addMember:src];
		}
	}
	
	return group;
}

- (XCGroup*) getOrCreateAddonGroup: (NSString*) addonName{
	NSString * groupKeyPath = [NSString stringWithFormat:@"addons/%@", addonName];
	NSString* groupKey = [[XCKeyBuilder forItemNamed:groupKeyPath] build];
	
	XCGroup * group = [self.project groupWithPathFromRoot:groupKeyPath];
	if( group == nil ){
		XCGroup * addonGroup = [self.project groupWithPathFromRoot:@"addons"];
		// we build this our selves,
		// because the XcodeEditor library is cool, but not as cool as us!
		NSString * relGroupPath = [NSString stringWithFormat:@"../../../addons/%@", addonName];
		group = [[XCGroup alloc] initWithProject:self.project key:groupKey alias:addonName path:relGroupPath children:nil];
		NSDictionary* groupDict = [group asDictionary];
		
		[self.project objects][groupKey] = groupDict;
		[addonGroup addMemberWithKey:groupKey];
		
		NSDictionary* dict = [addonGroup asDictionary];
		[self.project objects][addonGroup.key] = dict;

		return group;
	}
	else{
		return group;
	}
}

- (BOOL) isDirectory:(NSString*)path{
	BOOL isDir = NO;
	[[NSFileManager defaultManager] fileExistsAtPath:path
										 isDirectory:&isDir];

	return isDir;
}

@end