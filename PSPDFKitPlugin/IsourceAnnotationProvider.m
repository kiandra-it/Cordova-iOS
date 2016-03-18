//
//  IsourceAnnotationProvider.m
//  iSource
//
//  Created by Dale Salter on 10/03/2016.
//
//

#import "IsourceAnnotationProvider.h"

@interface IsourceAnnotationProvider()
    @property (nonatomic) NSArray* annotationFilePaths;
    @property (nonatomic, copy) NSMutableArray *annotations;
    @property (nonatomic) WKWebView* webView;

    // @property (nonatomic) int documentId;
    // @property (nonatomic, copy) NSManagedObjectContext *managedContext;
    // @property (nonatomic, copy) NSString* annotationsUrl;
    // @property (nonatomic, copy) NSString* postUrl;
@end

@implementation IsourceAnnotationProvider
{
    // BOOL _ignoreAnnotationChanges;   // ?: Not sure yet
    // BOOL _hasInitialised;            // ?: Not sure yet
}

- (instancetype)initWithDocumentProvider:(PSPDFDocumentProvider *)documentProvider with:(NSArray *) annotationFilePaths and:(WKWebView *)webView
{
    if ((self = [super initWithDocumentProvider:documentProvider])) {

        // _documentId = documentId;
        _annotationFilePaths = annotationFilePaths;
        _annotations = [NSMutableArray new];
        _webView = webView;

        // _managedContext = [NSManagedObjectContext MR_defaultContext];

        // Should be passed in
        //_annotationsUrl = [UrlConstants getAnnotationsForFileId:_documentId];
        //_postUrl = [UrlConstants getPostAnnotationForFileId:_documentId];

        [self setupAnnotationStore]; // ?: Do we need to worry about this yet?
    }

    return self;
}



-(NSArray *)parseAnnotations:(NSString *)filePath {
    if(self.documentProvider == nil || self.documentProvider.document == nil) {
        return @[];
    }

    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:filePath];

    PSPDFXFDFParser *parser = [[PSPDFXFDFParser alloc] initWithInputStream:stream documentProvider:self.documentProvider];

    NSError *error = nil;
    NSArray *annotations;

    @try {
        annotations = [parser parseWithError:&error]; // Completing this causes PSPDFKit to launch
    }
    @catch (NSException *exception){
        NSLog(@"%@", exception.reason);
    }
    @finally{
        [stream close];
    }

    return annotations;
}

- (void)setAnnotationsFromStorage{
    [_annotations removeAllObjects];

    if (_annotationFilePaths.count > 0) {
        NSArray *myAnnotations = [self parseAnnotations:  _annotationFilePaths[0]];

        // Associate the annotations that we have gotten from out mine.fdf to ourselves
        for (PSPDFAnnotation *annotation in myAnnotations) {
            annotation.user = @"You";
        }

        for (int i = 1; i < _annotationFilePaths.count; ++i) {
            [_annotations addObjectsFromArray: [self parseAnnotations:  _annotationFilePaths[i]] ];
        }

        // Lets add the annotations to the global annotations store
        [_annotations addObjectsFromArray:myAnnotations];


        [super addAnnotations:_annotations options:nil];           // We apply the annotations to the base class (PSPDFContainerAnnotationProvider)

        NSLog(@"setAnnotationsFromStorage: Loaded annotation data");
    }
    else {
        NSLog(@"setAnnotationsFromStorage: No annotation data");
    }

}

- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script {
    __block NSString *result;
    if ([_webView isKindOfClass:UIWebView.class]) {
        result = [(UIWebView *)_webView stringByEvaluatingJavaScriptFromString:script];
    } else {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [((WKWebView *)_webView) evaluateJavaScript:script completionHandler:^(id resultID, NSError *error) {
            result = [resultID description];
        }];

        // Ugly way to convert the async call into a sync call.
        // Since WKWebView calls back on the main thread we can't block.
        while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW)) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:10]];
        }
    }
    return result;
}

- (NSArray *)addAnnotations:(NSArray *)annotations options:(NSDictionary *)options {
    if (annotations.count == 0) return annotations;

    NSLog(@"addAnnotations Called!");

    [self stringByEvaluatingJavaScriptFromString: @"window.PSPDFKitEvents.logger('TEXT')"];

    return [super addAnnotations:annotations options:options];

    /*
     for (PSPDFAnnotation *annotation in annotations) {
     annotation.user = @"You";
     }

     //Parse the new annotations to an fdf xml.
     PSPDFXFDFWriter *writer = [PSPDFXFDFWriter new];
     NSOutputStream *stream = [[NSOutputStream alloc] initToMemory];

     NSError *error;
     if(![writer writeAnnotations:annotations toOutputStream:stream documentProvider:self.documentProvider error:&error]){
     NSLog(@"Failed to write XFDF file: %@", error.localizedDescription);
     }

     NSData *data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
     NSDictionary *addedAnnotationsXml = [NSDictionary dictionaryWithXMLData:data];
     [stream close];

     //If we currently have no annotations, just simply store and push the new ones.
     NSDictionary *currentAnnotationSet = [NSDictionary dictionaryWithXMLFile:_annotationStore.myFileUrl.path];

     if (currentAnnotationSet == nil) {
     [self storeAnnotationFdf: [XmlDeclaration stringByAppendingString: addedAnnotationsXml.XMLString] fileUrl:_annotationStore.myFileUrl];
     [self sendAnnotationsToServer];
     [Intercom logEventWithName:@"annotation-created"];
     return [super addAnnotations:annotations options:options];
     }

     //Stringify the currently stored annotations.
     NSString *currentAnnotations = [[currentAnnotationSet dictionaryValueForKeyPath:@"annots"] innerXML] ? : @"";

     //Append the new annotations.
     NSString *addedAnnotations = [[addedAnnotationsXml valueForKeyPath:@"annots"] innerXML];
     currentAnnotations = [currentAnnotations stringByAppendingString:addedAnnotations];

     NSDictionary *joinedAnnotations = [NSDictionary dictionaryWithXMLString:[NSString stringWithFormat:@"<root>%@</root>", currentAnnotations]];

     [currentAnnotationSet setValue:joinedAnnotations forKeyPath:@"annots"];

     //Save to storage.
     [self storeAnnotationFdf: [XmlDeclaration stringByAppendingString: [currentAnnotationSet XMLString]] fileUrl:_annotationStore.myFileUrl];

     NSArray *result = [super addAnnotations:annotations options:options];

     [self sendAnnotationsToServer];
     [Intercom logEventWithName:@"annotation-created"];
     */
}

- (BOOL)setupAnnotationStore {

    dispatch_async(dispatch_get_main_queue(), ^{
       [self setAnnotationsFromStorage];
    });

    return YES;
}

@end
