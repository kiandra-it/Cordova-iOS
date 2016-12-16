//
//  PSPDFAnnotation+AssociatedObjects.m
//  iSource
//
//  Created by Naz Taylor on 29/09/2015.
//  Copyright © 2015 Administrator. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PSPDFAnnotation+AssociatedObject.h"

@implementation PSPDFAnnotation (AssociatedObject)

- (void)setAssociatedObject:(id)object withKey:(void *)key {
     objc_setAssociatedObject(self, key, object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)associatedObjectForKey:(void *)key {
    return objc_getAssociatedObject(self, key);
}

-(void)setUserId:(NSString *)userId{
    [self setAssociatedObject:userId withKey:@selector(userId)];
}

-(NSString *)userId{
    return [self associatedObjectForKey:@selector(userId)];
}

-(void)setUserFullname:(NSString *)userFullname{
    [self setAssociatedObject:userFullname withKey:@selector(userFullname)];
}

-(NSString *)userFullname{
    return [self associatedObjectForKey:@selector(userFullname)];
}

-(void)setAvatarView:(AnnotationAvatarView *)avatarView{
    [self setAssociatedObject:avatarView withKey:@selector(avatarView)];
}

-(AnnotationAvatarView *)avatarView{
    return [self associatedObjectForKey:@selector(avatarView)];
}

@end