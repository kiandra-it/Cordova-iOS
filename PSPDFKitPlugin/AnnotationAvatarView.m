//
//  AnnotationAvatarView.m
//  iSource
//
//  Created by Administrator on 21/07/2014.
//  Copyright (c) 2014 Administrator. All rights reserved.
//

#import <PSPDFKit/PSPDFNoteAnnotationView.h>
#import "PSPDFAnnotation+AssociatedObject.h"
#import "AnnotationAvatarView.h"

@implementation AnnotationAvatarView{
    BOOL _isExpanded;
    UIView<PSPDFAnnotationViewProtocol>* _anchorAnnotationView;
    CGRect _anchorRect;
    CGFloat _originalWidth;
    NSArray* _collapsingConstraints;
}


-(id)initWithAnnotation:(PSPDFAnnotation *)annotation
          withAvatarUrl:(NSURL *)avatarUrl
{
    self = [[NSBundle mainBundle] loadNibNamed:@"AnnotationAvatarView" owner:nil options:nil][0];
    
    if (self) {
        _anchorRect = CGRectNull;
        
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOffset = CGSizeMake(0,1);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 3;
        self.layer.anchorPoint = CGPointMake(0, 0);
        self.fullname.text = annotation.user;
        
        _collapsingConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"[fullname(0)]-0-|" options:0 metrics:nil views:@{@"fullname": self.fullname}];
        
        if(annotation.userId != nil){
            // [self.avatar sd_setImageWithURL:avatarUrl placeholderImage:[UIImage imageNamed:@"unknownAvatar.png"]];
            // [self.avatar]
        
            UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL: avatarUrl]];

            self.avatar.image = image;
        }
        [self.fullname sizeToFit];
        _originalWidth = self.fullname.frame.size.width + 50;
        
        [self collapseAnimate:false];
    }
    
    return self;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(object == self && [@"bounce"isEqualToString:keyPath]){
        [self layoutShadowAnimate:self.layer.shadowPath!=nil];
    }
}

-(void)expand{
    if(!_isExpanded){
        _isExpanded = true;
        [UIView animateWithDuration:0.2 animations:^{
            self.alpha = 1;
            [self removeConstraints:_collapsingConstraints];
            
            self.frame = CGRectMake(self.frame.origin.x,
                                    self.frame.origin.y,
                                    _originalWidth,
                                    self.frame.size.height);
            
            [self layoutIfNeeded];
            [self reposition];
        }];
    }
}

- (void)layoutShadowAnimate:(BOOL)animate {
    CGPathRef shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.layer.cornerRadius].CGPath;
    
    if(animate){
        CABasicAnimation *shadowAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
        shadowAnimation.duration = 0.2;
        shadowAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]; // Match the easing of the UIView block animation
        
        // Animate from current shadowPath to the new shadow path that follows the current bounds
        shadowAnimation.fromValue = (id)self.layer.shadowPath;
        shadowAnimation.toValue = (__bridge id)shadowPath;
        [self.layer addAnimation:shadowAnimation forKey:@"shadowPath"];
        
        // Set shadowPath to current shadow path, using the non-animate version of this method
        [self layoutShadowAnimate:false];
    }
    else{
        self.layer.shadowPath = shadowPath;
    }
}

-(void)collapseAnimate:(BOOL)animate{
        if(animate){
            if(_isExpanded){
                [UIView animateWithDuration:0.2 animations:^{
                    [self collapseAnimate:false];
                }];
            }
        }
        else {
            _isExpanded = false;
            self.alpha = 0.9;
            [self addConstraints:_collapsingConstraints];
            self.frame = CGRectMake(self.frame.origin.x,
                                    self.frame.origin.y,
                                    36,
                                    self.frame.size.height);
            [self layoutIfNeeded];
            [self reposition];
        }
}

-(BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{
    return [super pointInside:point withEvent:event];
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
    if(_isExpanded){
        [self collapseAnimate:true];
    }
    else{
        [self expand];
    }
}

-(UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{
    UIView* result = [super hitTest:point withEvent:event];
    if(result == nil){
        [self collapseAnimate:true];
    }
    return result;
}

-(void)setTransform:(CGAffineTransform)transform{
    [super setTransform:transform];
    [self reposition];
}

-(void)layoutIfNeeded{
    [super layoutIfNeeded];
}

-(void)anchorToAnnotationView:(UIView<PSPDFAnnotationViewProtocol> *)annotationView{
    _anchorAnnotationView = annotationView;
    _anchorRect = CGRectNull;
    [self collapseAnimate:false];
}

-(void)anchorToRect: (CGRect)rect{
    _anchorAnnotationView = nil;
    _anchorRect = rect;
    [self collapseAnimate:false];
}

- (IBAction)onPanned:(UIPanGestureRecognizer*) recognizer {
    CGPoint translation = [recognizer translationInView:self];
    
    self.frame = CGRectMake(self.frame.origin.x + translation.x * self.transform.a,
                             self.frame.origin.y + translation.y * self.transform.d,
                             self.frame.size.width,
                             self.frame.size.height);
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        
        [UIView animateWithDuration:0.4 delay:0
             usingSpringWithDamping:0.6 initialSpringVelocity:0.0f
                            options:0 animations:^{
                                [self reposition];
                            } completion:nil];
    }
    
    
    [recognizer setTranslation:CGPointMake(0, 0) inView:self];
}

-(void)reposition{
    CGRect anchorBounds = _anchorRect;
    UIView* anchor;
    CGFloat xpad;
    CGFloat ypad;
    
    if(_anchorAnnotationView != nil){
        if([_anchorAnnotationView isKindOfClass:PSPDFNoteAnnotationView.class]){
            PSPDFNoteAnnotationView* noteView = (PSPDFNoteAnnotationView*) _anchorAnnotationView;
            anchor = noteView.annotationImageView;
        }
        else{
            anchor = _anchorAnnotationView;
        }
        xpad = -10 * self.transform.a;
        ypad = -20 * self.transform.d;
        anchorBounds = [self.superview convertRect:anchor.bounds fromView:anchor];
    }
    else{
        xpad = 5 * self.transform.a;
        ypad = _anchorRect.size.height - self.bounds.size.height * self.transform.d;
    }
    
    if(!CGRectIsNull(anchorBounds)){
        CGFloat maxX = self.superview.bounds.size.width - self.frame.size.width - 3;
        
        CGRect frame = self.frame;
        frame.origin.x = MIN(anchorBounds.origin.x + anchorBounds.size.width + xpad, maxX);
        frame.origin.y = anchorBounds.origin.y + ypad;
        self.frame = frame;
    }
}

@end