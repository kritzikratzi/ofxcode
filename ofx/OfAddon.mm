//
//  OfAddon.m
//  ofx
//
//  Created by Hansi on 06.12.16.
//  Copyright © 2016 hansi. All rights reserved.
//

#import "OfAddon.h"

@implementation OfAddon

- (id) initWithName:(NSString*)name isLocal:(BOOL)isLocal{
	self = [super init];
	if(self){
		_name = name;
		_isLocal = isLocal;
	}
	
	return self;
}

- (NSString*) getPathRelativeToProject{
	if(self.isLocal){
		return [NSString stringWithFormat:@"addons/%@", self.name ];
	}
	else{
		return [NSString stringWithFormat:@"../../../addons/%@", self.name ];
	}
}

@end
