//
//  AnnotationAvatarContainerView.m
//  iSource
//
//  Created by Administrator on 21/07/2014.
//  Copyright (c) 2014 Administrator. All rights reserved.
//

#import "AnnotationAvatarContainerView.h"

@implementation AnnotationAvatarContainerView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = true;
    }
    return self;
}

-(id)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    id hitView = [super hitTest:point withEvent:event];
    if (hitView == self) return nil;
    else return hitView;
}

@end