//
//  IsourceAnnotationProvider.m
//  iSource
//
//  Created by Dale Salter on 10/03/2016.
//
//

#import "IsourceAnnotationProvider.h"


static NSString *const XmlDeclaration = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>";

@interface IsourceAnnotationProvider()
    @property (nonatomic) long documentId;

    @property (nonatomic) NSDictionary* annotationFileData;

    @property (nonatomic) NSString* myAnnotationFilePath;
    @property (nonatomic) NSMutableArray* otherAnnotationFilePaths;

    @property (nonatomic, copy) NSMutableArray<__kindof PSPDFAnnotation *>* allAnnotations;
    @property (nonatomic, copy) NSMutableArray<__kindof PSPDFAnnotation *>* myAnnotations;
    @property (nonatomic, copy) NSMutableArray<__kindof PSPDFAnnotation *>* otherAnnotations;

    @property (nonatomic) WKWebView* webView;
@end

@implementation IsourceAnnotationProvider
{}

- (instancetype)initWithDocumentProvider:(PSPDFDocumentProvider *) documentProvider
                  withAnnotationFileData:annotationFileData
                          withDocumentId:(long)documentId
                                     and:(WKWebView *) webView
{
    if ((self = [super initWithDocumentProvider:documentProvider])) {
        _documentId = documentId;
        _annotationFileData = annotationFileData;
        
        _allAnnotations = [NSMutableArray new];

        NSString* myAnnotationFilePath = [annotationFileData objectForKey: @"annotationFilePath"];
        _myAnnotationFilePath = ![myAnnotationFilePath isEqualToString: @""] ? myAnnotationFilePath : NULL;
        _myAnnotations = [NSMutableArray new];
        
        _otherAnnotations = [NSMutableArray new];
        _otherAnnotationFilePaths = [NSMutableArray new];

        for (NSDictionary* otherAnnotationFilePath in [annotationFileData objectForKey: @"otherUsersAnnotations"]){
            [_otherAnnotationFilePaths addObject: [otherAnnotationFilePath objectForKey: @"annotationFilePath"]];
        }
        
        _webView = webView;

        // Load in the annotations off of disk
        [self initalizeAnnotations:_annotationFileData
                  myAnnotationPath:_myAnnotationFilePath
          andOtherAnnotationsPaths:_otherAnnotationFilePaths
               toMyAnnotationStore:_myAnnotations
            toOtherAnnotationStore:_otherAnnotations
                     toGlobalStore:_allAnnotations];
    }

    return self;
}

/* HOOK: Called when an annotation has been added */
- (NSArray<__kindof PSPDFAnnotation *> *) addAnnotations:(NSArray<__kindof PSPDFAnnotation *> *)annotations options:(NSDictionary<NSString *, id> *)options {
    if (annotations.count == 0) return annotations;

    NSLog(@"addAnnotations called");
    
    // Update our annotations store to reflect new changes
    [_allAnnotations addObjectsFromArray:annotations];
    [_myAnnotations addObjectsFromArray:annotations];
    
    [self persistAnnotations: _myAnnotations];
    
    return [super addAnnotations:annotations options:options];
}

/* HOOK: Called when an annotation has been removed */
- (NSArray<__kindof PSPDFAnnotation *> *) removeAnnotations:(NSArray<__kindof PSPDFAnnotation *> *)annotations options:(NSDictionary<NSString *, id> *)options {
    if (annotations.count == 0) return annotations;

    NSLog(@"removeAnnotations called");
    
    [_allAnnotations enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(PSPDFAnnotation* annotation, NSUInteger index, BOOL* stop) {
        if (annotations[0] == annotation) // TODO: Check if there can be multiple annotations
            [_allAnnotations removeObjectAtIndex:index];
    }];
    
    [_myAnnotations enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(PSPDFAnnotation* annotation, NSUInteger index, BOOL* stop) {
        if (annotations[0] == annotation) // TODO: Check if there can be multiple annotations
            [_myAnnotations removeObjectAtIndex:index];
    }];
    
    [self persistAnnotations: _myAnnotations];
    
    return [super removeAnnotations:annotations options:options];
}

/* 
 HOOK: Called when a fine gained change happens to the annotations (typically called when addAnnotations isn't)
 NOTE: Annotations in the collections (_myAnnotation and _allAnnotations) are updated automatically by PSPDFKit to reflect the changes to those annotations
        and as a result they can just be parsed to get an up to date FDF.
 */
- (void) didChangeAnnotation:(PSPDFAnnotation *)annotation keyPaths:(NSArray<NSString *> *)keyPaths options:(nullable NSDictionary<NSString *, id> *)options {
    NSLog(@"didChangeAnnotation called");
    
    [self persistAnnotations: _myAnnotations];
}

// Turns the collection of annotations into FDF, and sends that off to the JavaScript to be persisted
- (void) persistAnnotations:(NSMutableArray *)myAnnotations {
    // Lets extract the FDF as a string
    PSPDFXFDFWriter *writer = [PSPDFXFDFWriter new];
    NSOutputStream *stream = [[NSOutputStream alloc] initToMemory]; // Specifies we want it to buffer otuput to memory
    
    NSError *error;
    if(![writer writeAnnotations:myAnnotations toOutputStream:stream documentProvider:self.documentProvider error:&error]){
        NSLog(@"Failed to write XFDF file: %@", error.localizedDescription);
    }
    
    NSData *fdfData = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    [stream close];
    
    NSString* newFdfXML = [[NSString alloc] initWithData:fdfData encoding:NSUTF8StringEncoding];
    
    // String contains new lines which need to be stripped to be passed as an argument
    newFdfXML = [newFdfXML stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    
    NSString* script = [NSString stringWithFormat:@"window.PSPDFKitEvents.persistAnnotations(%ld, '%@')", _documentId, newFdfXML];
    
    [PSPDFKitPlugin stringByEvaluatingJavaScriptFromString:script withInterpreter:(WKWebView *)self.webView];
    // [PSPDFKitPlugin stringByEvaluatingJavaScriptFromString:script withInterpreter:self.webView];
}

// Extract annotations from disk, initialize the stores, then draw them
- (BOOL)initalizeAnnotations:(NSDictionary *)annotationFileData
            myAnnotationPath:(NSString *)myAnnotationFilePath
    andOtherAnnotationsPaths:(NSArray *)otherAnnotationFilePaths
         toMyAnnotationStore:(NSMutableArray<__kindof PSPDFAnnotation *> *)myAnnotationStore
      toOtherAnnotationStore:(NSMutableArray<__kindof PSPDFAnnotation *> *)otherAnnotationsStore
               toGlobalStore:(NSMutableArray<__kindof PSPDFAnnotation *> *)allAnnotationsStore
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [allAnnotationsStore removeAllObjects];
        
        // Extract out the annotations that I have created from the disk
        if (myAnnotationFilePath != NULL) {
           [myAnnotationStore addObjectsFromArray: [self parseAnnotations: myAnnotationFilePath]];
            
            for (PSPDFAnnotation *myAnnotation in myAnnotationStore){
                myAnnotation.user = @"You";
            }
            
            NSLog(@"Added: %lu annotations from %@", (unsigned long)myAnnotationStore.count, myAnnotationFilePath);
        }
        
        // Extra out all the other annotations that other people have made from the disk
        for (NSDictionary* otherUsersAnnotationData in [annotationFileData objectForKey: @"otherUsersAnnotations"]) {
            NSArray* tempAnnotationsStore = [self parseAnnotations: [otherUsersAnnotationData objectForKey: @"annotationFilePath"]];
            
            for (PSPDFAnnotation *otherAnnotation in tempAnnotationsStore){
                otherAnnotation.user = [otherUsersAnnotationData objectForKey: @"fullName"];
                otherAnnotation.editable = NO;  // Stop other people from editing annotations that arent theirs.
            }
            
            [otherAnnotationsStore addObjectsFromArray:tempAnnotationsStore];
            
            NSLog(@"Added: %lu annotations from %@", (unsigned long)tempAnnotationsStore.count, [otherUsersAnnotationData objectForKey: @"annotationFilePath"]);
        }
        
        // Update the global store so that it can be shown
        [allAnnotationsStore addObjectsFromArray:myAnnotationStore];
        [allAnnotationsStore addObjectsFromArray:otherAnnotationsStore];
        
        [super addAnnotations:allAnnotationsStore options:nil]; // After parsing the annotations we must pass them through to be added to the document
    });

    return YES;
}

// Parse the file at filePath, then return those annotations
- (NSArray<__kindof PSPDFAnnotation *> *)parseAnnotations:(NSString *)filePath {
    if(self.documentProvider == nil || self.documentProvider.document == nil) {
        return @[];
    }
    
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:filePath];
    
    // Parses the documentProvider in, must use this to apply annotations
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

@end