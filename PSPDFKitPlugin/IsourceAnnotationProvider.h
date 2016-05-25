//
//  IsourceAnnotationProvider.h
//  iSource
//
//  Created by Dale Salter on 10/03/2016.
//
//

#ifndef IsourceAnnotationProvider_h
#define IsourceAnnotationProvider_h

#import <PSPDFKit/PSPDFKit.h>
#import <CoreData/CoreData.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "PSPDFKitPlugin.h"

@interface IsourceAnnotationProvider : PSPDFContainerAnnotationProvider

    - (instancetype)initWithDocumentProvider:(PSPDFDocumentProvider *) documentProvider
                      withAnnotationFileData:(NSDictionary *)annotationFileData
                              withDocumentId:(long)documentId
                                         and:(WKWebView *) webView;

    //- (void)setSharing:(BOOL)sharing;
    //- (BOOL)isSharing;
    //- (void)startPolling;
    //- (void)stopPolling;
    //- (void)refresh;
    //
    //@property (nonatomic, copy) void (^sharingChanged)(BOOL);
    //@property (nonatomic, copy) void (^updatesReceived)();
    //@property (nonatomic, copy) void (^beforeAnnotationsSet)();
    //@property (nonatomic, copy) void (^annotationsSet)(NSArray*);

@end

#endif /* IsourceAnnotationProvider_h */
