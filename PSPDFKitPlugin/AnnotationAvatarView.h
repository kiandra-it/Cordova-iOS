//
//  AnnotationAvatarView.h
//  iSource
//
//  Created by Administrator on 21/07/2014.
//  Copyright (c) 2014 Administrator. All rights reserved.
//

#import <PSPDFKit/PSPDFKit.h>

@interface AnnotationAvatarView : UIControl<PSPDFAnnotationViewProtocol>

@property (weak, nonatomic) IBOutlet UIImageView *avatar;
@property (weak, nonatomic) IBOutlet UILabel *fullname;

-(id)initWithAnnotation:(PSPDFAnnotation *)annotation
          withAvatarUrl:(NSURL *)avatarUrl;

-(void)expand;
-(void)collapseAnimate:(BOOL)animate;

-(void)anchorToAnnotationView: (UIView<PSPDFAnnotationViewProtocol>*)annotationView;
-(void)anchorToRect: (CGRect)rect;

@end