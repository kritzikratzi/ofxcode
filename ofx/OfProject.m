//
//  OfProject.m
//  ofx
//
//  Created by Hansi on 03.05.15.
//  Copyright (c) 2015 hansi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OfProject.h"
#import <XcodeEditor/XcodeGroupMember.h>

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


@implementation OfProject{
	NSMutableDictionary * addons; // a map of nsstring->OfAddon
}

// http://stackoverflow.com/a/17581217/347508
- (NSString *)resolvePath:(NSString *)path {
	NSString *expandedPath = [path stringByStandardizingPath];
	const char *cpath = [expandedPath cStringUsingEncoding:NSUTF8StringEncoding];
	char *resolved = NULL;
	char *returnValue = realpath(cpath, resolved);
	
	if (returnValue == NULL && resolved != NULL) {
		printf("Error with path: %s\n", resolved);
		// if there is an error then resolved is set with the path which caused the issue
		// returning nil will prevent further action on this path
		return nil;
	}
	
	return [NSString stringWithCString:returnValue encoding:NSUTF8StringEncoding];
}

- (id)initWithPath:(NSString*)path{
	path = [self resolvePath:path];
	_project = [[XCProject alloc] initWithFilePath:path];
	_path = path;
	_projPath = [path stringByDeletingLastPathComponent];
	_ofPath = [[[self.projPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	_addonsPathGlobal = [self.ofPath stringByAppendingPathComponent:@"addons"];
	_addonsPathLocal = [self.projPath stringByAppendingPathComponent:@"addons"];
	
	
	//XCGroup* group = [self.project groupWithPathFromRoot:@"addons"];
	//NSLog(@"Addons in xcode file: ");
	//for( NSString * key in group.children ){
	//	XCGroup * addon = [self.project groupWithKey:key];
	//	NSLog(@"- %@", addon.displayName);
	//}
	//NSLog(@"\n\n");
	
	// scanForAddons returns global first, then local.
	// we process in the same order, so local addons will remain
	addons = [[NSMutableDictionary alloc] init]; 
	for( OfAddon * addon in [self scanForAddons]){
		[addons setObject:addon forKey:addon.name];
	}
	
	return self;
}

- (void) save{
	[self.project clearFileOperationsQueue];
	[self.project save];
}


- (void)removeAddonNamed:(NSString *)name{
	// great! now figure out what to add...
	OfAddon * addon = [addons objectForKey:name];
	if(addon == nil){
		NSLog(@"not removing addon %@, unknown addon. ", name); // addadadadadad
		return;
	}
	else{
		[self removeAddonLocallyAndGlobally:addon];
	}
}

- (void)removeAddonLocallyAndGlobally:(OfAddon*)addon{
	[self removeAddon:addon];
	OfAddon * other = [[OfAddon alloc] initWithName:addon.name isLocal:!addon.isLocal];
	[self removeAddon:other];
}


- (void)removeAddon:(OfAddon*)addon{
	NSString * groupPath = addon.isLocal?@"local_addons":@"addons";
	// create a new group for the addon...
	XCGroup * addonGroup = [self.project groupWithPathFromRoot:[NSString stringWithFormat:@"%@/%@",groupPath,addon.name]];
	
	// =======================================
	// 1. remove the group addons/ofxMyAddon/src
	// in fact, just remove it all!
	// =======================================
	if( addonGroup != nil ){
		[addonGroup removeFromParentGroup];
	}
	
	// ========================================
	// 2. remove addons/ofxAddon/libs/*/include
	// ========================================
	for( XCTarget * target in self.project.targets ){
		for( NSString * configName in target.configurations ){
			XCProjectBuildConfig * config = target.configurations[configName];
			
			NSArray * searchPaths = [self valueAsArray:[config valueForKey:@"USER_HEADER_SEARCH_PATHS"]];
			// do we have flags?
			if( searchPaths.count > 0 ){
				NSMutableArray * newSearchPaths = [[NSMutableArray alloc] init];
				for( NSString * path in searchPaths ){
					NSString * basePath = addon.relativePath;
					if( [path rangeOfString:basePath].length == 0 ){
						[newSearchPaths addObject:path];
					}
				}
				
				[config addOrReplaceSetting:newSearchPaths forKey:@"USER_HEADER_SEARCH_PATHS"];
			}
		}
	}
	
	
	
	// =======================================
	// 3. remove .a/.dylib files from linker options
	// TODO: this currently changes the linker flags in the product config
	// would be much nicer if it was just set once in the project?
	// =======================================
	for( XCTarget * target in self.project.targets ){
		for( NSString * configName in target.configurations ){
			XCProjectBuildConfig * config = target.configurations[configName];
			
			NSArray * ldFlags = [self valueAsArray:[config valueForKey:@"OTHER_LDFLAGS"]];
			
			// do we have flags?
			if( ldFlags.count > 0 ){
				NSMutableArray * newLdFlags = [[NSMutableArray alloc] init];
				for( NSString * flag in ldFlags ){
					NSString * basePath = addon.relativePath;
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
	// TODO: losen regex? --> done! ^^
	// =======================================
	
	void (^removeCmd)(NSString*) = ^void(NSString * cmd) {
		NSString * expr = [NSString stringWithFormat:@"%@.*\n*", [NSRegularExpression escapedTemplateForString:cmd]];
		for( XCTarget * target in self.project.targets ){
			// walk through all build phases for this target ...
			for (NSString* buildPhaseKey in [[[self.project objects] objectForKey:target.key] objectForKey:@"buildPhases"]){
				NSDictionary* buildPhase = [[self.project objects] objectForKey:buildPhaseKey];
				// it's a "shell script" phase?
				// ok, so for simplicites sake we assume there's just one such phase.
				if ( [[buildPhase valueForKey:@"isa"] isEqualToString:@"PBXShellScriptBuildPhase"] ){
					NSString * script = [buildPhase valueForKey:@"shellScript"];
					if( [script rangeOfString:cmd options:NSCaseInsensitiveSearch].length > 0 ){
						// remove it !
						script = [script stringByReplacingOccurrencesOfString:expr withString:@"" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch range:NSMakeRange(0, script.length)];
						[buildPhase setValue:script forKey:@"shellScript"];
					}
				}
			}
		}
	};
	
	removeCmd([NSString stringWithFormat:@"cp -rf %@/", addon.relativePath]);
	removeCmd([NSString stringWithFormat:@"cp -fr %@/", addon.relativePath]);
	removeCmd([NSString stringWithFormat:@"rsync -aved %@/", addon.relativePath]);
	
}

- (void)updateSources{
	XCGroup * srcGroup = [self.project groupWithPathFromRoot:@"src"];
	
	// in case we have group called "src", remove everything inside!
	if(srcGroup != nil){
/*		for(id src in srcGroup.members){
			if([src isKindOfClass:XCGroup.class]){
				NSLog(@"it's a group!");
				XCGroup * group = src;
				[group removeFromParentDeletingChildren:NO];
			}
			else{
				XCSourceFile * file = src;
				NSLog(@"f=%@", file); 
			}
		}*/
		[srcGroup removeFromParentDeletingChildren:NO];
	}

	XCGroup * root = [self.project rootGroup];
	[self addDirRecursively:@"src" addonPath:self.projPath toGroup:root];
}


- (NSArray*)valueAsArray:(id) value{
	if( value == nil ){
		return [[NSArray alloc] init];
	}
	else if( [value isKindOfClass:[NSArray class]]){
		return value;
	}
	else{
		return [(NSString*)value componentsSeparatedByString:@"\n"];
	}
}

- (NSArray*)availableAddonNames{
	NSMutableArray * keys = [NSMutableArray arrayWithArray:addons.allKeys];
	[keys sortUsingSelector:@selector(compare:)];
	return keys;
}

- (NSArray*)availableAddons{
	NSMutableArray * values = [NSMutableArray arrayWithArray:[addons allValues]];
	[values sortUsingComparator:^NSComparisonResult(OfAddon * addon, OfAddon * other) {
		return [addon.name compare:other.name];
	}];
	
	return values;
}

- (NSArray*)scanForAddons{
	
	NSArray * (^scan)(BOOL local) = ^NSArray*(BOOL local) {
		NSString * path = local?self.addonsPathLocal:self.addonsPathGlobal;
		NSArray* addonDirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path
																				 error:NULL];
		NSMutableArray * addonList = [[NSMutableArray alloc] initWithCapacity:addonDirs.count];
		for( NSString * addon in addonDirs ){
			NSString * addonPath = [path stringByAppendingPathComponent:addon];
			BOOL isDir = NO;
			[[NSFileManager defaultManager] fileExistsAtPath:addonPath
												 isDirectory:&isDir];
			if( isDir ){
				[addonList addObject:[[OfAddon alloc] initWithName:addon isLocal:local]];
			}
		}
		return addonList;
	};
	
	NSMutableArray * arr = [[NSMutableArray alloc] init];
	[arr addObjectsFromArray:scan(NO)];
	[arr addObjectsFromArray:scan(YES)];
	
	return arr;
}

- (void)addAddonNamed:(NSString *)name{
	// great! now figure out what to add...
	OfAddon * addon = [addons objectForKey:name];
	if(addon == nil){
		NSLog(@"not adding addon %@, unknown addon. ", name); // addadadadadad
		return;
	}
	else{
		[self addAddon:addon];
	}
}

- (void)addAddon:(OfAddon*)addon{
	NSString * addonPath = [self.projPath stringByAppendingPathComponent:addon.relativePath].stringByStandardizingPath;
	
	// create a new group for the addon...
	XCGroup * addonGroup = [self getOrCreateAddonGroup:addon];
	
	// =======================================
	// 1.1 add the source folder recursively
	// =======================================
	[self addDirRecursively:@"src" addonPath:addonPath toGroup:addonGroup];
	
	// =====================================================
	// 2. add addons/ofxAddon/libs/*/include to include path and libs/*/src to src path
	// =====================================================
	NSString * libsPath = [addonPath stringByAppendingPathComponent:@"libs"];
	NSDirectoryEnumerator * enumerator = [[NSFileManager defaultManager]
										 enumeratorAtURL:[NSURL URLWithString:libsPath]
										 includingPropertiesForKeys:nil
										 options:0
										 errorHandler:^(NSURL *url, NSError *error) {return YES;
										 }];
	
	// this is a bit wasteful, because we traverse everything, but only care about the include directory
	NSMutableSet * includePaths = [[NSMutableSet alloc] init];
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		NSString * relativePath = [path substringFromIndex:addonPath.length+1];
		NSArray * components = [relativePath pathComponents];
		if( components.count == 3 && [components[2] isEqualToString:@"include"] ){
			[includePaths addObject:[NSString stringWithFormat:@"%@/%@", addon.relativePath, relativePath]];
		}
		if( components.count == 3 && [components[2] isEqualToString:@"src"] ){
			[includePaths addObject:[NSString stringWithFormat:@"%@/%@", addon.relativePath, relativePath]];
			[self addDirRecursively:relativePath addonPath:addonPath toGroup:addonGroup];
		}
	}
	
	if( includePaths.count > 0 ){
		for( XCTarget * target in self.project.targets ){
			for( NSString * configName in target.configurations ){
				XCProjectBuildConfig * config = target.configurations[configName];
				
				NSArray * searchPaths = [self valueAsArray:[config valueForKey:@"USER_HEADER_SEARCH_PATHS"]];
				
				// do we have flags?
				if( searchPaths == nil ){
					NSArray * newSearchPaths = [includePaths allObjects];
					[config addOrReplaceSetting:newSearchPaths forKey:@"USER_HEADER_SEARCH_PATHS"];
				}
				else{
					NSMutableArray * newSearchPaths = [searchPaths mutableCopy];
					NSMutableSet * missingIncludePaths = [includePaths mutableCopy];
					for( NSString * path in searchPaths ){
						[missingIncludePaths removeObject:path];
					}
					for( NSString * path in missingIncludePaths ){
						[newSearchPaths addObject:path];
					}
					[config addOrReplaceSetting:newSearchPaths forKey:@"USER_HEADER_SEARCH_PATHS"];
				}
			}
		}
	}

	
	// =======================================
	// 3. add addons/ofxAddon/libs/*/lib/*.a and *.dylib to other linker flags
	// TODO: what about platform directories? ie. there is sometimes libs/osx
	//       --> YES, it's always called "osx" for osx!
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
	NSMutableSet * dyLibs = [[NSMutableSet alloc] init];
	
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		NSString * relativePath = [path substringFromIndex:addonPath.length+1];
		NSArray * components = [relativePath pathComponents];
		if( components.count < 4 || ![components[3] isEqualToString: @"osx"] ){
			// ignore, not inside the osx subfolder
		}
		else if( [[path pathExtension] isEqualToString:@"a"] ){
			[staticLibs addObject:[NSString stringWithFormat:@"%@/%@", addon.relativePath, relativePath]];
		}
		else if( [[path pathExtension] isEqualToString:@"dylib"] ){
			NSDictionary * attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
			if( [[attributes valueForKey:@"NSFileType"] isEqualToString:NSFileTypeSymbolicLink] ){
				// skip, those aren't needed?
				// actually: don't skip those, they seem to be important in some cases! 
				[dyLibs addObject:[NSString stringWithFormat:@"%@/%@", addon.relativePath, relativePath]];
			}
			else{
				[dyLibs addObject:[NSString stringWithFormat:@"%@/%@", addon.relativePath, relativePath]];
			}
		}
	}
	
	if( staticLibs.count > 0 || dyLibs.count > 0 ){
		for( XCTarget * target in self.project.targets ){
			for( NSString * configName in target.configurations ){
				XCProjectBuildConfig * config = target.configurations[configName];
				
				NSArray * ldFlags = [self valueAsArray:[config valueForKey:@"OTHER_LDFLAGS"]];
				// do we have flags?
				if( ldFlags == nil || ldFlags.count == 0 ){
					NSMutableArray * newLdFlags = [[NSMutableArray alloc] init];
					[newLdFlags addObject:@"$(OF_CORE_LIBS)"];
					[newLdFlags addObject:@"$(OF_CORE_FRAMEWORKS)"];
					[newLdFlags addObjectsFromArray:[staticLibs allObjects]];
					[newLdFlags addObjectsFromArray:[dyLibs allObjects]];
					[config addOrReplaceSetting:newLdFlags forKey:@"OTHER_LDFLAGS"];
				}
				else{
					NSMutableArray * newLdFlags = [NSMutableArray arrayWithArray:ldFlags];
					NSMutableSet * missingLibs = [[NSMutableSet alloc] init];
					[missingLibs addObjectsFromArray:[staticLibs allObjects]];
					[missingLibs addObjectsFromArray:[dyLibs allObjects]];
					
					for( NSString * archive in ldFlags ){
						[missingLibs removeObject:archive];
					}
					for( NSString * lib in missingLibs ){
						[newLdFlags addObject:lib];
					}
					[config addOrReplaceSetting:newLdFlags forKey:@"OTHER_LDFLAGS"];
				}
			}
		}
	}
	
	// copy dylibs to final product
	for( NSString * dyLib in dyLibs ){
		// the "R" stands for recursive. only using it because it happens to copy symlinks.
		// http://stackoverflow.com/a/221316/347508
		// the 2>/dev/null is only to surpress the error status of copy if the file exists already.
		// and echo -n is used to generate a 0-return code
		//TODO: this is not ideal, it masks actual errors!
		
		NSString * copyCommand = [NSString stringWithFormat:@"rsync -aved %@ \"$TARGET_BUILD_DIR/$PRODUCT_NAME.app/Contents/MacOS\"", dyLib];
		[self addToScriptsPhase:copyCommand];
	}
	
	
	// =======================================
	// 4. add "run script" to copy data folder
	// =======================================
	
	// do we even have a data folder?
	NSString * dataPath = [addonPath stringByAppendingPathComponent:@"bin/data"];
	BOOL hasDataFolder = [[NSFileManager defaultManager] fileExistsAtPath:dataPath];
	if( hasDataFolder ){
		NSString * copyCommand = [NSString stringWithFormat:@"rsync -aved %@/bin/data/ \"$TARGET_BUILD_DIR/$PRODUCT_NAME.app/Contents/Resources\"", addon.relativePath];
		[self addToScriptsPhase:copyCommand];
	}
}

- (void) addToScriptsPhase: (NSString *) command {
	for( XCTarget * target in self.project.targets ){
		// walk through all build phases for this target ...
		for (NSString* buildPhaseKey in [[[self.project objects] objectForKey:target.key] objectForKey:@"buildPhases"]){
			NSDictionary* buildPhase = [[self.project objects] objectForKey:buildPhaseKey];
			// it's a "shell script" phase?
			// ok, so for simplicites sake we assume there's just one such phase.
			if ( [[buildPhase valueForKey:@"isa"] isEqualToString:@"PBXShellScriptBuildPhase"] ){
				NSString * script = [buildPhase valueForKey:@"shellScript"];
				if( [script rangeOfString:command].length > 0 ){
					// neat, no work. that's a good thing!
				}
				else{
					script = [script stringByAppendingFormat:@"\n%@", command];
					[buildPhase setValue:script forKey:@"shellScript"];
					break;
				}
			}
		}
	}
}

- (XCGroup*) addDirRecursively:(NSString *)relativePath addonPath:(NSString*)addonPath toGroup:(XCGroup *)group{
	NSString * srcPath = [addonPath stringByAppendingPathComponent:relativePath];
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager]
										 enumeratorAtURL:[NSURL URLWithString:srcPath]
										 includingPropertiesForKeys:nil
										 options:0
										 errorHandler:^(NSURL *url, NSError *error) {return YES;
										 }];
	for( NSURL * url in enumerator ){
		NSString * path = [url path];
		NSString * relativePath = [path substringFromIndex:addonPath.length+1];
		[self addFileWithPath:relativePath toGroup:group];
	}
	
	return group; 
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

- (XCGroup*) getOrCreateAddonGroup: (OfAddon*)addon{
	NSString * groupName = addon.isLocal?@"local_addons":@"addons";
	NSString * groupKeyPath = [NSString stringWithFormat:@"%@/%@", groupName, addon.name];
	NSString* groupKey = [[XCKeyBuilder forItemNamed:groupKeyPath] build];
	
	XCGroup * group = [self.project groupWithPathFromRoot:groupKeyPath];
	if( group == nil ){
		XCGroup * addonGroup = [self.project groupWithPathFromRoot:groupName];
		if(addonGroup == nil){
			XCGroup * root = [self.project rootGroup];
			NSString * addonsKey = [[XCKeyBuilder forItemNamed:groupName] build]; 
			//NSString * relGroupPath = [addon.relativePath stringByDeletingLastPathComponent];
			addonGroup = [[XCGroup alloc] initWithProject:self.project key:addonsKey alias:groupName path:@"" children:nil];
			NSDictionary* groupDict = [addonGroup asDictionary];
			
			[self.project objects][addonsKey] = groupDict;
			[root addMemberWithKey:addonsKey];
			
			NSDictionary* dict = [root asDictionary];
			[self.project objects][root.key] = dict;
		}
		// we build this our selves,
		// because the XcodeEditor library is cool, but not as cool as us!
		NSString * relGroupPath = addon.relativePath;
		group = [[XCGroup alloc] initWithProject:self.project key:groupKey alias:addon.name path:relGroupPath children:nil];
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