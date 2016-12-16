//
//  PSPDFAnnotation+AssociatedObjects.h
//  iSource
//
//  Created by Naz Taylor on 29/09/2015.
//  Copyright © 2015 Administrator. All rights reserved.
//

#import <PSPDFKit/PSPDFKit.h>
#import <objc/runtime.h>
#import "AnnotationAvatarView.h"

@interface PSPDFAnnotation (AssociatedObject)

- (void)setAssociatedObject:(id)value withKey:(void *)key;
- (id)associatedObjectForKey:(void *)key;

@property (nonatomic) NSString *userId;
@property (nonatomic) NSString *userFullname;
@property (nonatomic) AnnotationAvatarView *avatarView;

@end