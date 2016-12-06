//
//  OfAddon.h
//  ofx
//
//  Created by Hansi on 06.12.16.
//  Copyright © 2016 hansi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OfAddon : NSObject

@property (readonly) NSString * name; // name of the addon
@property (readonly) BOOL isLocal; // is it a local, or a global addon?
@property (readonly,getter=getPathRelativeToProject) NSString * relativePath;

- (id) initWithName:(NSString*)name isLocal:(BOOL)isLocal;
- (NSString*) getPathRelativeToProject; // returns the path to the addon, relative to the project directory
@end
