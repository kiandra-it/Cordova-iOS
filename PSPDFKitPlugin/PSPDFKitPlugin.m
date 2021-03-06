//
//  PSPDFKit.m
//  PSPDFPlugin for Apache Cordova
//
//  Copyright 2013 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY AUSTRIAN COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import "PSPDFKitPlugin.h"
#import "IsourceAnnotationProvider.h"
#import <WebKit/WebKit.h>
#import <PSPDFKit/PSPDFKit.h>
#import "AnnotationAvatarView.h"
#import "AnnotationAvatarContainerView.h"
#import "PSPDFAnnotation+AssociatedObject.h"

@interface PSPDFKitPlugin () <PSPDFViewControllerDelegate>
    @property (nonatomic, strong) UINavigationController *navigationController;
    @property (nonatomic, strong) PSPDFViewController *pdfController;
    @property (nonatomic, strong) PSPDFDocument *pdfDocument;
    @property (nonatomic, strong) NSDictionary *defaultOptions;

    @property (nonatomic, strong) NSDictionary *avatarUrls;

    + (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *) script withInterpreter:(WKWebView *)webView;
@end

@implementation PSPDFKitPlugin

#pragma mark Document methods

// TODO: Move out
static NSInteger TAG_AVATAR_CONTAINER = 1001;


- (void)present:(CDVInvokedUrlCommand *)command {

    // SET UP THE DOCUMENT
    NSString *path = [command argumentAtIndex:0];
    NSURL *url = [self pdfFileURLWithPath:path];

    NSDictionary *options = [command argumentAtIndex:1] ?: [command argumentAtIndex:2];
    NSMutableDictionary *newOptions = [self.defaultOptions mutableCopy];
    [newOptions addEntriesFromDictionary:options];

    // Extract all the annotation file paths and document Data
    NSDictionary* annotationFileData = [options objectForKey: @"annotationFileData"];

    // Extract avatars for all people who have annotated this document
    NSDictionary* avatarUrlStrings = [options objectForKey: @"avatarUrls"];
    
    
    NSMutableDictionary* avatarUrls = [NSMutableDictionary dictionary];
    
    for(NSString* userId in avatarUrlStrings){
        [avatarUrls setObject: [NSURL URLWithString: [avatarUrlStrings objectForKey: userId]]
                       forKey: userId];
    }
    
    _avatarUrls = [NSDictionary dictionaryWithDictionary: avatarUrls];
    
    // Extract documentId
    long documentId = [[options objectForKey: @"id"] longValue];

    
    PSPDFDocument *document = [PSPDFDocument documentWithURL:url];
    [self setOptions:newOptions forObject:_pdfDocument animated:NO];
    
    document.title = [options objectForKey:@"title"];

    // Sets up the mechanism that handles our annotations
    [document setDidCreateDocumentProviderBlock:^(PSPDFDocumentProvider *documentProvider) {
        if(documentProvider.document.annotationsEnabled){
            IsourceAnnotationProvider *annotationProvider = [[IsourceAnnotationProvider alloc] initWithDocumentProvider:documentProvider
                                                                                                 withAnnotationFileData:annotationFileData
                                                                                                         withAvatarUrls:avatarUrls
                                                                                                         withDocumentId:documentId
                                                                                                                    and:(WKWebView*)self.webView];
            documentProvider.annotationManager.annotationProviders = @[annotationProvider, documentProvider.annotationManager.fileAnnotationProvider];
        } else {
            NSLog(@"Annotations disabled");
        }
    }];

    // CREATE THE UI THINGS
    _pdfController = [[PSPDFViewController alloc] init];
    _pdfController.delegate = self;
    _navigationController = [[UINavigationController alloc] initWithRootViewController:_pdfController];

    [self setOptions:newOptions forObject:_pdfController animated:NO];
    _pdfController.document = document;

    // The first time we open our application for writing annotations (when updated/installed), PSPDFKit defaults to asking for a
    //  author name. Lets stop that prompt because we programmatically handle setting this.
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.shouldAskForAnnotationUsername = NO;
    }];
    
    [self.viewController presentViewController:_navigationController animated:YES completion:^{
        [self.commandDelegate sendPluginResult: [CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:command.callbackId
         ];
    }];

}


-(void)pdfViewController:(PSPDFViewController *)pdfController didShowPageView:(PSPDFPageView *)pageView{

    //Ensure the pageView contains our overlay view to hold avatars.
    UIView *avatarContainerView = [pageView viewWithTag:TAG_AVATAR_CONTAINER];
    
    if(avatarContainerView == nil){
        avatarContainerView = [[AnnotationAvatarContainerView alloc]initWithFrame:CGRectMake(0, 0, pageView.bounds.size.width, pageView.bounds.size.height)];
        avatarContainerView.tag = TAG_AVATAR_CONTAINER;
        [pageView insertSubview:avatarContainerView aboveSubview:pageView.renderView];
    }
    
    [avatarContainerView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        for(PSPDFPageView* pageView in pdfController.visiblePageViews){
            NSArray* annotations = [_pdfController.document annotationsForPage:pageView.page type:PSPDFAnnotationTypeAll];
            
            for(PSPDFAnnotation* annotation in annotations){
                [self addAvatarViewForAnnotation:annotation pageView:pageView];
            }
        }
        
    });
}


-(void)addAvatarViewForAnnotation:(PSPDFAnnotation*)annotation pageView:(PSPDFPageView*) pageView{
    if (annotation.userId == nil) {
        //This is likely the current user's which don't have avatars.
        return;
    }
    
    UIView *avatarContainerView = [pageView viewWithTag:TAG_AVATAR_CONTAINER];
    
    if (annotation.avatarView == nil) {
        annotation.avatarView = [[AnnotationAvatarView alloc]initWithAnnotation:annotation withAvatarUrl: [_avatarUrls objectForKey: annotation.userId] ];
    } else {
        [annotation.avatarView removeFromSuperview];
    }
    
    [avatarContainerView addSubview:annotation.avatarView];
    
    CGRect bottom = annotation.boundingBox;
    if(annotation.rects){
        bottom = ((NSValue*)annotation.rects.lastObject).CGRectValue;
    }
    
    CGRect anchor = [pageView convertPDFRectToViewRect:bottom];
    [annotation.avatarView anchorToRect:anchor];
}

- (void)editableAnnotationTypes:(CDVInvokedUrlCommand *)command
{
    NSArray* types = [command argumentAtIndex:0];


    if (![types isKindOfClass:[NSArray class]])
    {
        types = @[types];
    }

    NSMutableSet *qualified = [[NSMutableSet alloc] init];
    for (NSString *type in types)
    {
        NSString *prefix = @"PSPDFAnnotationType";
        if ([type hasPrefix:prefix]) {
            [qualified addObject:[type substringFromIndex:prefix.length]];
        }
        else if ([type length]) {
            [qualified addObject:[NSString stringWithFormat:@"%@%@", [[type substringToIndex:1] uppercaseString], [type substringFromIndex:1]]];
        }
    }

    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.editableAnnotationTypes = qualified;
    }];
}

- (void)dismiss:(CDVInvokedUrlCommand *)command
{
    [_navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{

        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:command.callbackId];
    }];
}

- (void)reload:(CDVInvokedUrlCommand *)command
{
    [_pdfController reloadData];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)search:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult = nil;
    NSString *query = [command argumentAtIndex:0];
    BOOL animated = [[command argumentAtIndex:1 withDefault:@NO] boolValue];
    BOOL headless = [[command argumentAtIndex:2 withDefault:@NO] boolValue];

    if (query) {
        [_pdfController searchForString:query options:@{PSPDFViewControllerSearchHeadlessKey: @(headless)} sender:nil animated:animated];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"'query' argument was null"];
    }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)saveAnnotations:(CDVInvokedUrlCommand *)command
{
    NSError *error = nil;
    [_pdfController.document saveAnnotationsWithError:&error];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self dictionaryWithError:error]] callbackId:command.callbackId];
}

#pragma mark Private methods

- (NSDictionary *)defaultOptions
{
    //this is an opportunity to provide
    //default options if we so choose
    if (!_defaultOptions) {
        _defaultOptions = @{};
    }
    return _defaultOptions;
}

- (void)setOptionsWithDictionary:(NSDictionary *)options animated:(BOOL)animated
{
    //merge with defaults
    NSMutableDictionary *newOptions = [self.defaultOptions mutableCopy];
    [newOptions addEntriesFromDictionary:options];
    self.defaultOptions = newOptions;

    //set document and controller values
    [self setOptions:options forObject:_pdfController.document animated:animated];
    [self setOptions:options forObject:_pdfController animated:animated];
}

- (void)setOptions:(NSDictionary *)options forObject:(id)object animated:(BOOL)animated
{
    if (object) {

        //merge with defaults
        NSMutableDictionary *newOptions = [self.defaultOptions mutableCopy];
        [newOptions addEntriesFromDictionary:options];

        for (NSString *key in newOptions) {
            //generate setter prefix
            NSString *prefix = [NSString stringWithFormat:@"set%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];

            //try custom animated setter
            NSString *setter = [prefix stringByAppendingFormat:@"AnimatedFor%@WithJSON:", [object class]];
            if (animated && [self respondsToSelector:NSSelectorFromString(setter)]) {
                [self setValue:newOptions[key] forKey:[key stringByAppendingFormat:@"AnimatedFor%@WithJSON", [object class]]];
            }
            else {
                //try custom setter
                setter = [prefix stringByAppendingFormat:@"For%@WithJSON:", [object class]];
                if ([self respondsToSelector:NSSelectorFromString(setter)]) {
                    [self setValue:newOptions[key] forKey:[key stringByAppendingFormat:@"For%@WithJSON", [object class]]];
                }
                else {
                    //use KVC
                    setter = [prefix stringByAppendingString:@":"];
                    if ([object respondsToSelector:NSSelectorFromString(setter)]) {
                        [object setValue:newOptions[key] forKey:key];
                    }
                }
            }
        }
    }
}

- (id)optionAsJSON:(NSString *)key
{
    id value = nil;
    NSString *getterString = [key stringByAppendingFormat:@"AsJSON"];
    if ([self respondsToSelector:NSSelectorFromString(getterString)]) {
        value = [self valueForKey:getterString];
    }
    else if ([_pdfDocument respondsToSelector:NSSelectorFromString(key)]) {
        value = [_pdfDocument valueForKey:key];
    }
    else if ([_pdfController respondsToSelector:NSSelectorFromString(key)]) {
        value = [_pdfController valueForKey:key];
    }

    //determine type
    if ([value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSDictionary class]] ||
        [value isKindOfClass:[NSArray class]]) {
        return value;
    }
    else if ([value isKindOfClass:[NSSet class]]) {
        return [value allObjects];
    }
    else {
        return [value description];
    }
}

- (NSDictionary *)dictionaryWithError:(NSError *)error
{
    if (error) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"code"] = @(error.code);
        if (error.domain) dict[@"domain"] = error.domain;
        if ([error localizedDescription]) dict[@"description"] = [error localizedDescription];
        if ([error localizedFailureReason]) dict[@"reason"] = [error localizedFailureReason];
        return dict;
    }
    return nil;
}

- (NSDictionary *)standardColors
{
    //TODO: should we support all the standard css color names here?
    static NSDictionary *colors = nil;
    if (colors == nil) {
        colors = [[NSDictionary alloc] initWithObjectsAndKeys:
                  [UIColor blackColor], @"black", // 0.0 white
                  [UIColor darkGrayColor], @"darkgray", // 0.333 white
                  [UIColor lightGrayColor], @"lightgray", // 0.667 white
                  [UIColor whiteColor], @"white", // 1.0 white
                  [UIColor grayColor], @"gray", // 0.5 white
                  [UIColor redColor], @"red", // 1.0, 0.0, 0.0 RGB
                  [UIColor greenColor], @"green", // 0.0, 1.0, 0.0 RGB
                  [UIColor blueColor], @"blue", // 0.0, 0.0, 1.0 RGB
                  [UIColor cyanColor], @"cyan", // 0.0, 1.0, 1.0 RGB
                  [UIColor yellowColor], @"yellow", // 1.0, 1.0, 0.0 RGB
                  [UIColor magentaColor], @"magenta", // 1.0, 0.0, 1.0 RGB
                  [UIColor orangeColor], @"orange", // 1.0, 0.5, 0.0 RGB
                  [UIColor purpleColor], @"purple", // 0.5, 0.0, 0.5 RGB
                  [UIColor brownColor], @"brown", // 0.6, 0.4, 0.2 RGB
                  [UIColor clearColor], @"clear", // 0.0 white, 0.0 alpha
                  nil];
    }
    return colors;
}

- (UIColor *)colorWithString:(NSString *)string
{
    //convert to lowercase
    string = [string lowercaseString];

    //try standard colors first
    UIColor *color = [self standardColors][string];
    if (color) return color;

    //try rgb(a)
    if ([string hasPrefix:@"rgb"]) {
        string = [string substringToIndex:[string length] - 1];
        if ([string hasPrefix:@"rgb("]) {
            string = [string substringFromIndex:4];
        }
        else if ([string hasPrefix:@"rgba("]) {
            string = [string substringFromIndex:5];
        }
        CGFloat alpha = 1.0f;
        NSArray *components = [string componentsSeparatedByString:@","];
        if ([components count] > 3) {
            alpha = [[components[3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] floatValue];
        }
        if ([components count] > 2) {
            NSString *red = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *green = [components[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *blue = [components[2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [UIColor colorWithRed:[red floatValue] / 255.0f
                                   green:[green floatValue] / 255.0f
                                    blue:[blue floatValue] / 255.0f
                                   alpha:alpha];
        }
        return nil;
    }

    //try hex
    string = [string stringByReplacingOccurrencesOfString:@"#" withString:@""];
    switch ([string length])
    {
        case 0:
        {
            string = @"00000000";
            break;
        }
        case 3:
        {
            NSString *red = [string substringWithRange:NSMakeRange(0, 1)];
            NSString *green = [string substringWithRange:NSMakeRange(1, 1)];
            NSString *blue = [string substringWithRange:NSMakeRange(2, 1)];
            string = [NSString stringWithFormat:@"%1$@%1$@%2$@%2$@%3$@%3$@ff", red, green, blue];
            break;
        }
        case 6:
        {
            string = [string stringByAppendingString:@"ff"];
            break;
        }
        default:
        {
            return nil;
        }
    }
    uint32_t rgba;
    NSScanner *scanner = [NSScanner scannerWithString:string];
    [scanner scanHexInt:&rgba];
    CGFloat red = ((rgba & 0xFF000000) >> 24) / 255.0f;
    CGFloat green = ((rgba & 0x00FF0000) >> 16) / 255.0f;
    CGFloat blue = ((rgba & 0x0000FF00) >> 8) / 255.0f;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.0f];
}

- (void)getComponents:(CGFloat *)rgba ofColor:(UIColor *)color
{
    CGColorSpaceModel model = CGColorSpaceGetModel(CGColorGetColorSpace(color.CGColor));
    const CGFloat *components = CGColorGetComponents(color.CGColor);
    switch (model)
    {
        case kCGColorSpaceModelMonochrome:
        {
            rgba[0] = components[0];
            rgba[1] = components[0];
            rgba[2] = components[0];
            rgba[3] = components[1];
            break;
        }
        case kCGColorSpaceModelRGB:
        {
            rgba[0] = components[0];
            rgba[1] = components[1];
            rgba[2] = components[2];
            rgba[3] = components[3];
            break;
        }
        default:
        {
            rgba[0] = 0.0f;
            rgba[1] = 0.0f;
            rgba[2] = 0.0f;
            rgba[3] = 1.0f;
            break;
        }
    }
}

- (NSString *)colorAsString:(UIColor *)color
{
    //get components
    CGFloat rgba[4];
    [self getComponents:rgba ofColor:color];
    return [NSString stringWithFormat:@"rgba(%i,%i,%i,%g)",
            (int)round(rgba[0]*255), (int)round(rgba[1]*255),
            (int)round(rgba[2]*255), rgba[3]];
}

+ (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script withInterpreter:(WKWebView *)webView{
    __block NSString *result;
    if ([webView isKindOfClass:UIWebView.class]) {
        result = [(UIWebView *)webView stringByEvaluatingJavaScriptFromString:script];
    } else {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [((WKWebView *)webView) evaluateJavaScript:script completionHandler:^(id resultID, NSError *error) {
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

- (BOOL)sendEventWithJSON:(id)JSON
{
    if ([JSON isKindOfClass:[NSDictionary class]]) {
        JSON = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:JSON options:0 error:NULL] encoding:NSUTF8StringEncoding];
    }
    NSString *script = [NSString stringWithFormat:@"PSPDFKitPlugin.dispatchEvent(%@)", JSON];
    NSString *result = [PSPDFKitPlugin stringByEvaluatingJavaScriptFromString:script withInterpreter:(WKWebView *)self.webView];
    return [result length]? [result boolValue]: YES;
}

- (BOOL)isNumeric:(id)value
{
    if ([value isKindOfClass:[NSNumber class]]) return YES;
    static NSNumberFormatter *formatter = nil;
    if (formatter == nil)
    {
        formatter = [[NSNumberFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    }
    return [formatter numberFromString:value] != nil;
}

- (UIBarButtonItem *)standardBarButtonWithName:(NSString *)name
{
    NSString *selectorString = [name stringByAppendingString:@"ButtonItem"];
    if ([_pdfController respondsToSelector:NSSelectorFromString(selectorString)]) {
        return [_pdfController valueForKey:selectorString];
    }
    return nil;
}

- (UIBarButtonItem *)barButtonItemWithJSON:(id)JSON
{
    if ([JSON isKindOfClass:[NSString class]]) {
        return [self standardBarButtonWithName:JSON];
    }
    else if ([JSON isKindOfClass:[NSDictionary class]]) {

        UIImage *image = nil;
        NSString *imagePath = JSON[@"image"];
        if (imagePath) {
            imagePath = [@"www" stringByAppendingPathComponent:imagePath];
            image = [UIImage imageNamed:imagePath];
        }

        UIImage *landscapeImage = image;
        imagePath = JSON[@"landscapeImage"];
        if (imagePath) {
            imagePath = [@"www" stringByAppendingPathComponent:imagePath];
            landscapeImage = [UIImage imageNamed:imagePath] ?: landscapeImage;
        }

        UIBarButtonItemStyle style = [self enumValueForKey:JSON[@"style"]
                                                    ofType:@"UIBarButtonItemStyle"
                                               withDefault:UIBarButtonItemStylePlain];

        UIBarButtonItem *item = nil;
        if (image) {
            item = [[UIBarButtonItem alloc] initWithImage:image landscapeImagePhone:landscapeImage style:style target:self action:@selector(customBarButtonItemAction:)];
        }
        else {
            item = [[UIBarButtonItem alloc] initWithTitle:JSON[@"title"] style:style target:self action:@selector(customBarButtonItemAction:)];
        }

        item.tintColor = JSON[@"tintColor"]? [self colorWithString:JSON[@"tintColor"]]: item.tintColor;
        return item;
    }
    return nil;
}

- (NSArray *)barButtonItemsWithArray:(NSArray *)array
{
    NSMutableArray *items = [NSMutableArray array];
    for (id JSON in array) {
        UIBarButtonItem *item = [self barButtonItemWithJSON:JSON];
        if (item) {
            [items addObject:item];
        }
        else {
            NSLog(@"Unrecognised toolbar button name or format: %@", JSON);
        }
    }
    return items;
}

- (void)customBarButtonItemAction:(UIBarButtonItem *)sender
{
    NSInteger index = [_pdfController.leftBarButtonItems indexOfObject:sender];
    if (index == NSNotFound) {
        index = [_pdfController.rightBarButtonItems indexOfObject:sender];
        if (index != NSNotFound) {
            NSString *script = [NSString stringWithFormat:@"PSPDFKitPlugin.dispatchRightBarButtonAction(%ld)", (long)index];

            [PSPDFKitPlugin stringByEvaluatingJavaScriptFromString:script withInterpreter:(WKWebView *)self.webView];
        }
    }
    else {
        NSString *script = [NSString stringWithFormat:@"PSPDFKitPlugin.dispatchLeftBarButtonAction(%ld)", (long)index];

        [PSPDFKitPlugin stringByEvaluatingJavaScriptFromString:script withInterpreter:(WKWebView *)self.webView];
    }
}

- (NSURL *)pdfFileURLWithPath:(NSString *)path
{
    if (path) {
        path = [path stringByExpandingTildeInPath];
        if (![path isAbsolutePath]) {
            path = [[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"] stringByAppendingPathComponent:path];
        }
        return [NSURL fileURLWithPath:path];
    }
    return nil;
}

- (NSInteger)enumValueForKey:(NSString *)key ofType:(NSString *)type withDefault:(int)defaultValue
{
    NSNumber *number = key? [self enumValuesOfType:type][key]: nil;
    if (number) return [number integerValue];
    if ([self isNumeric:key]) return [key integerValue];
    return defaultValue;
}

- (NSString *)enumKeyForValue:(int)value ofType:(NSString *)type
{
    NSDictionary *dict = [self enumValuesOfType:type];
    NSInteger index = [[dict allValues] indexOfObject:@(value)];
    if (index != NSNotFound) {
        return [[dict allKeys] objectAtIndex:index];
    }
    return nil;
}

- (NSInteger)optionsValueForKeys:(NSArray *)keys ofType:(NSString *)type withDefault:(NSInteger)defaultValue
{
    if (!keys)
    {
        return 0;
    }
    if ([keys isKindOfClass:NSNumber.class]) {
        if (((NSNumber *)keys).integerValue == 0) {
            return 0;
        }
    }
    if (![keys isKindOfClass:[NSArray class]])
    {
        keys = @[keys];
    }
    if ([keys count] == 0)
    {
        return defaultValue;
    }
    NSInteger value = 0;
    for (id key in keys)
    {
        NSNumber *number = [self enumValuesOfType:type][key];
        if (number)
        {
            value += [number integerValue];
        }
        else
        {
            if ([key isKindOfClass:NSString.class])
            {
                // Try to find with uppercase first letter
                NSString *keyStr = [NSString stringWithFormat:@"%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
                number = [self enumValuesOfType:type][keyStr];
                if (number) {
                    value += [number integerValue];
                }
            }
            else if ([self isNumeric:key])
            {
                value += [key integerValue];
            }
        }
    }
    return value;
}

- (NSArray *)optionKeysForValue:(NSUInteger)value ofType:(NSString *)type
{
    NSDictionary *dict = [self enumValuesOfType:type];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in dict)
    {
        NSNumber *number = dict[key];
        if (number) {
            if ([number unsignedIntegerValue] == NSUIntegerMax)
            {
                if (value == NSUIntegerMax)
                {
                    return @[key];
                }
            } else {
                if (value & [number unsignedIntegerValue])
                {
                    [keys addObject:key];
                }
            }
        }
    }
    return keys;
}

#pragma mark Enums and options

- (NSDictionary *)enumValuesOfType:(NSString *)type
{
    static NSDictionary *enumsByType = nil;
    if (!enumsByType) {
        enumsByType = @{

        @"UIBarButtonItemStyle":

  @{@"plain": @(UIBarButtonItemStylePlain),
    @"done": @(UIBarButtonItemStyleDone)},

        @"PSPDFAnnotationSaveMode":

  @{@"disabled": @(PSPDFAnnotationSaveModeDisabled),
    @"externalFile": @(PSPDFAnnotationSaveModeExternalFile),
    @"embedded": @(PSPDFAnnotationSaveModeEmbedded),
    @"embeddedWithExternalFileAsFallback": @(PSPDFAnnotationSaveModeEmbeddedWithExternalFileAsFallback)},

        @"PSPDFTextCheckingType":

  @{@"link": @(PSPDFTextCheckingTypeLink),
    @"phoneNumber": @(PSPDFTextCheckingTypePhoneNumber),
    @"all": @(PSPDFTextCheckingTypeAll)},

        @"PSPDFTextSelectionMenuAction":

  @{@"search": @(PSPDFTextSelectionMenuActionSearch),
    @"define": @(PSPDFTextSelectionMenuActionDefine),
    @"wikipedia": @(PSPDFTextSelectionMenuActionWikipedia),
    @"speak": @(PSPDFTextSelectionMenuActionSpeak),
    @"all": @(PSPDFTextSelectionMenuActionAll)},

        @"PSPDFPageTransition":

  @{@"scrollPerPage": @(PSPDFPageTransitionScrollPerPage),
    @"scrollContinuous": @(PSPDFPageTransitionScrollContinuous),
    @"curl": @(PSPDFPageTransitionCurl)},

        @"PSPDFViewMode":

  @{@"document": @(PSPDFViewModeDocument),
    @"thumbnails": @(PSPDFViewModeThumbnails)},

        @"PSPDFPageMode":

  @{@"single": @(PSPDFPageModeSingle),
    @"double": @(PSPDFPageModeDouble),
    @"automatic": @(PSPDFPageModeAutomatic)},

        @"PSPDFScrollDirection":

  @{@"single": @(PSPDFScrollDirectionHorizontal),
    @"double": @(PSPDFScrollDirectionVertical)},

        @"PSPDFLinkAction":

  @{@"none": @(PSPDFLinkActionNone),
    @"alertView": @(PSPDFLinkActionAlertView),
    @"openSafari": @(PSPDFLinkActionOpenSafari),
    @"inlineBrowser": @(PSPDFLinkActionInlineBrowser)},

        @"PSPDFHUDViewMode":

  @{@"always": @(PSPDFHUDViewModeAlways),
    @"automatic": @(PSPDFHUDViewModeAutomatic),
    @"automaticNoFirstLastPage": @(PSPDFHUDViewModeAutomaticNoFirstLastPage),
    @"never": @(PSPDFHUDViewModeNever)},

        @"PSPDFHUDViewAnimation":

  @{@"none": @(PSPDFHUDViewAnimationNone),
    @"fade": @(PSPDFHUDViewAnimationFade),
    @"slide": @(PSPDFHUDViewAnimationSlide)},

        @"PSPDFThumbnailBarMode":

  @{@"none": @(PSPDFThumbnailBarModeNone),
    @"scrobbleBar": @(PSPDFThumbnailBarModeScrubberBar),
    @"scrollable": @(PSPDFThumbnailBarModeScrollable)},

        @"PSPDFAnnotationType":

  @{@"None": @(PSPDFAnnotationTypeNone),
    @"Undefined": @(PSPDFAnnotationTypeUndefined),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeLink): @(PSPDFAnnotationTypeLink),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeHighlight): @(PSPDFAnnotationTypeHighlight),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeStrikeOut): @(PSPDFAnnotationTypeStrikeOut),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeUnderline): @(PSPDFAnnotationTypeUnderline),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeSquiggly): @(PSPDFAnnotationTypeSquiggly),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeFreeText): @(PSPDFAnnotationTypeFreeText),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeInk): @(PSPDFAnnotationTypeInk),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeSquare): @(PSPDFAnnotationTypeSquare),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeCircle): @(PSPDFAnnotationTypeCircle),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeLine): @(PSPDFAnnotationTypeLine),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeNote): @(PSPDFAnnotationTypeNote),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeStamp): @(PSPDFAnnotationTypeStamp),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeCaret): @(PSPDFAnnotationTypeCaret),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeRichMedia): @(PSPDFAnnotationTypeRichMedia),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeScreen): @(PSPDFAnnotationTypeScreen),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeWidget): @(PSPDFAnnotationTypeWidget),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeSound): @(PSPDFAnnotationTypeSound),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeFile): @(PSPDFAnnotationTypeFile),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypePolygon): @(PSPDFAnnotationTypePolygon),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypePolyLine): @(PSPDFAnnotationTypePolyLine),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypePopup): @(PSPDFAnnotationTypePopup),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeWatermark): @(PSPDFAnnotationTypeWatermark),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeTrapNet): @(PSPDFAnnotationTypeTrapNet),
    PSPDFStringFromAnnotationType(PSPDFAnnotationType3D): @(PSPDFAnnotationType3D),
    PSPDFStringFromAnnotationType(PSPDFAnnotationTypeRedact): @(PSPDFAnnotationTypeRedact),
    @"All": @(PSPDFAnnotationTypeAll)}
        };

        //Note: this method crashes the second time a
        //PDF is opened if the dictionary is not copied.
        //Somehow the enumsByType dictionary is released
        //and becomes a dangling pointer, which really
        //shouldn't be possible since we are using ARC
        enumsByType = [enumsByType copy];
    }
    return enumsByType[type];
}

///// Status bar style. (old status will be restored regardless of the style chosen)
//typedef NS_ENUM(NSInteger, PSPDFStatusBarStyleSetting) {
//    PSPDFStatusBarInherit,             // Don't change status bar style, but show/hide statusbar on HUD events.
//    PSPDFStatusBarSmartBlack,          // UIStatusBarStyleBlackOpaque on iPad, UIStatusBarStyleBlackTranslucent on iPhone.
//    PSPDFStatusBarSmartBlackHideOnIpad,// Similar to PSPDFStatusBarSmartBlack, but also hides statusBar on iPad.
//    PSPDFStatusBarBlackOpaque,         // Opaque Black everywhere.
//    PSPDFStatusBarDefault,             // Default statusbar (white on iPhone/black on iPad).
//    PSPDFStatusBarDisable,             // Never show status bar.
//};

//// Customize how a single page should be displayed.
//typedef NS_ENUM(NSInteger, PSPDFPageRenderingMode) {
//    PSPDFPageRenderingModeThumbnailThenFullPage, // Load cached page async.
//    PSPDFPageRenderingModeFullPage,              // Load cached page async, no upscaled thumb.
//    PSPDFPageRenderingModeFullPageBlocking,      // Load cached page directly.
//    PSPDFPageRenderingModeThumbnailThenRender,   // Don't use cached page but thumb.
//    PSPDFPageRenderingModeRender                 // Don't use cached page nor thumb.
//};

#pragma mark License Key

- (void)setLicenseKey:(CDVInvokedUrlCommand *)command {
    NSString *key = [command argumentAtIndex:0];
    if (key.length > 0) {
        [PSPDFKit setLicenseKey:key];
    }
}

#pragma mark PSPDFDocument setters and getters

- (void)setFileURLForPSPDFDocumentWithJSON:(NSString *)path
{
    // Brute-Force-Set.
    [_pdfDocument setValue:[self pdfFileURLWithPath:path] forKey:@"fileURL"];
}

- (NSString *)fileURLAsJSON
{
    return _pdfDocument.fileURL.path;
}

- (void)setEditableAnnotationTypesWithJSON:(NSArray *)types
{
    if (![types isKindOfClass:[NSArray class]])
    {
        types = @[types];
    }

    NSMutableSet *qualified = [[NSMutableSet alloc] init];
    for (NSString *type in types)
    {
        NSString *prefix = @"PSPDFAnnotationType";
        if ([type hasPrefix:prefix]) {
            [qualified addObject:[type substringFromIndex:prefix.length]];
        }
        else if ([type length]) {
            [qualified addObject:[NSString stringWithFormat:@"%@%@", [[type substringToIndex:1] uppercaseString], [type substringFromIndex:1]]];
        }
    }

    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.editableAnnotationTypes = qualified;
    }];
}

- (NSArray *)editableAnnotationTypesAsJSON
{
    return _pdfController.configuration.editableAnnotationTypes.allObjects;
}

- (void)setAnnotationSaveModeForPSPDFDocumentWithJSON:(NSString *)option
{
    _pdfDocument.annotationSaveMode = [self enumValueForKey:option ofType:@"PSPDFAnnotationSaveMode" withDefault:PSPDFAnnotationSaveModeEmbeddedWithExternalFileAsFallback];
}

- (NSString *)annotationSaveModeAsJSON
{
    return [self enumKeyForValue:_pdfDocument.annotationSaveMode ofType:@"PSPDFAnnotationSaveMode"];
}

- (void)setPageBackgroundColorForPSPDFDocumentWithJSON:(NSString *)color
{
    NSMutableDictionary *renderOptions = [_pdfDocument.renderOptions mutableCopy];
    renderOptions[PSPDFRenderBackgroundFillColorKey] = [self colorWithString:color];
    _pdfDocument.renderOptions = renderOptions;
}

- (NSString *)pageBackgroundColorAsJSON
{
    return [self colorAsString:_pdfDocument.renderOptions[PSPDFRenderBackgroundFillColorKey]];
}

- (void)setBackgroundColorForPSPDFDocumentWithJSON:(NSString *)color
{
    //not supported, use pageBackgroundColor instead
}

- (NSArray *)renderAnnotationTypesAsJSON
{
    NSArray *types = [self optionKeysForValue:_pdfDocument.renderAnnotationTypes ofType:@"PSPDFAnnotationType"];
    return types;
}

- (void)setRenderAnnotationTypesForPSPDFDocumentWithJSON:(NSArray *)options
{
    PSPDFAnnotationType types = (PSPDFAnnotationType) [self optionsValueForKeys:options ofType:@"PSPDFAnnotationType" withDefault:PSPDFAnnotationTypeAll];
    _pdfDocument.renderAnnotationTypes = types;
}

#pragma mark PSPDFViewController setters and getters

- (void)setPageTransitionForPSPDFViewControllerWithJSON:(NSString *)transition
{
    PSPDFPageTransition pageTransition = (PSPDFPageTransition) [self enumValueForKey:transition ofType:@"PSPDFPageTransition" withDefault:PSPDFPageTransitionScrollPerPage];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.pageTransition = pageTransition;
    }];
}

- (NSString *)pageTransitionAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.pageTransition ofType:@"PSPDFPageTransition"];
}

- (void)setViewModeAnimatedForPSPDFViewControllerWithJSON:(NSString *)mode
{
    [_pdfController setViewMode:[self enumValueForKey:mode ofType:@"PSPDFViewMode" withDefault:PSPDFViewModeDocument] animated:YES];
}

- (void)setViewModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    _pdfController.viewMode = [self enumValueForKey:mode ofType:@"PSPDFViewMode" withDefault:PSPDFViewModeDocument];
}

- (NSString *)viewModeAsJSON
{
    return [self enumKeyForValue:_pdfController.viewMode ofType:@"PSPDFViewMode"];
}

- (void)setThumbnailBarModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFThumbnailBarMode thumbnailBarMode = (PSPDFThumbnailBarMode) [self enumValueForKey:mode ofType:@"PSPDFThumbnailBarMode" withDefault:PSPDFThumbnailBarModeScrubberBar];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.thumbnailBarMode = thumbnailBarMode;
    }];
}

- (NSString *)thumbnailBarMode
{
    return [self enumKeyForValue:_pdfController.configuration.thumbnailBarMode ofType:@"PSPDFThumbnailBarMode"];
}

- (void)setPageModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFPageMode pageMode = (PSPDFPageMode) [self enumValueForKey:mode ofType:@"PSPDFPageMode" withDefault:PSPDFPageModeAutomatic];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.pageMode = pageMode;
    }];
}

- (NSString *)pageModeAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.pageMode ofType:@"PSPDFPageMode"];
}

- (void)setScrollDirectionForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFScrollDirection scrollDirection = (PSPDFScrollDirection) [self enumValueForKey:mode ofType:@"PSPDFScrollDirection" withDefault:PSPDFScrollDirectionHorizontal];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.scrollDirection = scrollDirection;
    }];
}

- (NSString *)scrollDirectionAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.scrollDirection ofType:@"PSPDFScrollDirection"];
}

- (void)setLinkActionForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFLinkAction linkAction = (PSPDFLinkAction) [self enumValueForKey:mode ofType:@"PSPDFLinkAction" withDefault:PSPDFLinkActionInlineBrowser];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.linkAction = linkAction;
    }];
}

- (NSString *)linkActionAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.linkAction ofType:@"PSPDFLinkAction"];
}

- (void)setHUDViewModeForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFHUDViewMode HUDViewMode = (PSPDFHUDViewMode) [self enumValueForKey:mode ofType:@"PSPDFHUDViewMode" withDefault:PSPDFHUDViewModeAutomatic];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.HUDViewMode = HUDViewMode;
    }];
}

- (NSString *)HUDViewModeAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.HUDViewMode ofType:@"PSPDFHUDViewMode"];
}

- (void)setHUDViewAnimationForPSPDFViewControllerWithJSON:(NSString *)mode
{
    PSPDFHUDViewAnimation HUDViewAnimation = (PSPDFHUDViewAnimation) [self enumValueForKey:mode ofType:@"HUDViewAnimation" withDefault:PSPDFHUDViewAnimationFade];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.HUDViewAnimation = HUDViewAnimation;
    }];
}

- (NSString *)HUDViewAnimationAsJSON
{
    return [self enumKeyForValue:_pdfController.configuration.HUDViewAnimation ofType:@"PSPDFHUDViewAnimation"];
}

- (void)setHUDVisibleAnimatedForPSPDFViewControllerWithJSON:(NSNumber *)visible
{
    [_pdfController setHUDVisible:[visible boolValue] animated:YES];
}

- (void)setPageAnimatedForPSPDFViewControllerWithJSON:(NSNumber *)page
{
    [_pdfController setPage:[page integerValue] animated:YES];
}

- (void)setLeftBarButtonItemsForPSPDFViewControllerWithJSON:(NSArray *)items
{
    _pdfController.leftBarButtonItems = [self barButtonItemsWithArray:items] ?: _pdfController.leftBarButtonItems;
}

- (void)setRightBarButtonItemsForPSPDFViewControllerWithJSON:(NSArray *)items
{
    _pdfController.rightBarButtonItems = [self barButtonItemsWithArray:items] ?: _pdfController.rightBarButtonItems;
}

- (void)setTintColorForPSPDFViewControllerWithJSON:(NSString *)color
{
    _pdfController.view.tintColor = [self colorWithString:color];
}

- (NSString *)tintColorAsJSON
{
    return [self colorAsString:_pdfController.view.tintColor];
}

- (void)setBackgroundColorForPSPDFViewControllerWithJSON:(NSString *)color
{
    UIColor *backgroundColor = [self colorWithString:color];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.backgroundColor = backgroundColor;
    }];
}

- (NSString *)backgroundColorAsJSON
{
    return [self colorAsString:_pdfController.configuration.backgroundColor];
}

- (void)setAllowedMenuActionsForPSPDFViewControllerWithJSON:(NSArray *)options
{
    PSPDFTextSelectionMenuAction menuActions = (PSPDFTextSelectionMenuAction) [self optionsValueForKeys:options ofType:@"PSPDFTextSelectionMenuAction" withDefault:PSPDFTextSelectionMenuActionAll];
    [_pdfController updateConfigurationWithBuilder:^(PSPDFConfigurationBuilder *builder) {
        builder.allowedMenuActions = menuActions;
    }];
}

- (NSArray *)allowedMenuActionsAsJSON
{
    return [self optionKeysForValue:_pdfController.configuration.allowedMenuActions ofType:@"PSPDFTextSelectionMenuAction"];
}

- (void)generatePDFFromHTMLString:(NSString *)html outputFile:(NSString *)filePath options:(NSDictionary *)options completionBlock:(void (^)(NSError *error))completionBlock
{
    [[PSPDFProcessor defaultProcessor] generatePDFFromHTMLString:html
                                                   outputFileURL:[NSURL fileURLWithPath:filePath]
                                                         options:options
                                                 completionBlock:completionBlock];
}

#pragma mark PDFProcessing methods

- (void)convertPDFFromHTMLString:(CDVInvokedUrlCommand *)command
{
    NSString *decodeHTMLString = [[[command argumentAtIndex:0] stringByReplacingOccurrencesOfString:@"+" withString:@""]stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *fileName = [command argumentAtIndex:1 withDefault:@"Sample"];
    NSDictionary *options = [command argumentAtIndex:2 withDefault:nil];
    NSString *outputFilePath = [NSTemporaryDirectory()
                                stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"pdf"]];

    void (^completionBlock)(NSError *error) = ^(NSError *error) {
        CDVPluginResult *pluginResult;

        if (error)
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsDictionary:@{@"localizedDescription": error.localizedDescription, @"domin": error.domain}];
        }
        else
        {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsDictionary:@{@"filePath":outputFilePath}];
        }

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    [self generatePDFFromHTMLString:decodeHTMLString outputFile:outputFilePath options:options completionBlock:completionBlock];
}



#pragma mark Configuration

- (void)setOptions:(CDVInvokedUrlCommand *)command
{
    NSDictionary *options = [command argumentAtIndex:0];
    BOOL animated = [[command argumentAtIndex:1 withDefault:@NO] boolValue];
    [self setOptionsWithDictionary:options animated:animated];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)setOption:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult = nil;
    NSString *key = [command argumentAtIndex:0];
    id value = [command argumentAtIndex:1];
    BOOL animated = [[command argumentAtIndex:2 withDefault:@NO] boolValue];

    if (key && value) {
        [self setOptionsWithDictionary:@{key: value} animated:animated];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
    else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"'key' and/or 'value' argument was null"];
    }

    [self.commandDelegate sendPluginResult:pluginResult
                                callbackId:command.callbackId];
}

- (void)getOptions:(CDVInvokedUrlCommand *)command
{
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSArray *names = [command argumentAtIndex:0];
    for (NSString *name in names) {
        id value = [self optionAsJSON:name];
        if (value) values[name] = value;
    }

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:values] callbackId:command.callbackId];
}

- (void)getOption:(CDVInvokedUrlCommand *)command
{
    NSString *key = [command argumentAtIndex:0];
    if (key)
    {
        id value = [self optionAsJSON:key];

        //determine type
        if ([value isKindOfClass:[NSNumber class]]) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:[value doubleValue]] callbackId:command.callbackId];
        }
        else if ([value isKindOfClass:[NSDictionary class]]) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:value] callbackId:command.callbackId];
        }
        else if ([value isKindOfClass:[NSArray class]]) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:value] callbackId:command.callbackId];
        }
        else if (value) {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:value] callbackId:command.callbackId];
        }
        else {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
        }
    }
}

#pragma mark Paging

- (void)setPage:(CDVInvokedUrlCommand *)command
{
    NSInteger page = [[command argumentAtIndex:0 withDefault:@(NSNotFound)] integerValue];
    BOOL animated = [[command argumentAtIndex:1 withDefault:@NO] boolValue];

    if (page != NSNotFound) {
        [_pdfController setPage:page animated:animated];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:command.callbackId];
    }
    else {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"'page' argument was null"] callbackId:command.callbackId];
    }
}

- (void)getPage:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)_pdfController.page] callbackId:command.callbackId];
}

- (void)getScreenPage:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)_pdfController.screenPage] callbackId:command.callbackId];
}

- (void)getPageCount:(CDVInvokedUrlCommand *)command
{
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)_pdfDocument.pageCount] callbackId:command.callbackId];
}

- (void)scrollToNextPage:(CDVInvokedUrlCommand *)command
{
    BOOL animated = [[command argumentAtIndex:0 withDefault:@NO] boolValue];
    [_pdfController scrollToNextPageAnimated:animated];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)scrollToPreviousPage:(CDVInvokedUrlCommand *)command
{
    BOOL animated = [[command argumentAtIndex:0 withDefault:@NO] boolValue];
    [_pdfController scrollToPreviousPageAnimated:animated];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

#pragma mark Toolbar Items

- (void)setLeftBarButtonItems:(CDVInvokedUrlCommand *)command
{
    NSArray *items = [command argumentAtIndex:0 withDefault:@[]];
    [self setOptionsWithDictionary:@{@"leftBarButtonItems": items} animated:NO];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

- (void)setRightBarButtonItems:(CDVInvokedUrlCommand *)command
{
    NSArray *items = [command argumentAtIndex:0 withDefault:@[]];
    [self setOptionsWithDictionary:@{@"rightBarButtonItems": items} animated:NO];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

#pragma mark Delegate methods

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldScrollToPage:(NSUInteger)page
{
    return [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'shouldScrollToPage',page:%ld}", (long)page]];
}

/* - (void)pdfViewController:(PSPDFViewController *)pdfController didShowPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didShowPageView',page:%ld}", (long) pageView.page]];
}*/

- (void)pdfViewController:(PSPDFViewController *)pdfController didRenderPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didRenderPageView',page:%ld}", (long) pageView.page]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didLoadPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didLoadPageView',page:%ld}", (long) pageView.page]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController willUnloadPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'willUnloadPageView',page:%ld}", (long) pageView.page]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didBeginPageDragging:(UIScrollView *)scrollView
{
    [self sendEventWithJSON:@"{type:'didBeginPageDragging'}"];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didEndPageDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didBeginPageDragging',willDecelerate:%@,velocity:{%g,%g}}", decelerate? @"true": @"false", velocity.x, velocity.y]];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didEndPageScrollingAnimation:(UIScrollView *)scrollView
{
    [self sendEventWithJSON:@"{type:'didEndPageScrollingAnimation'}"];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didBeginPageZooming:(UIScrollView *)scrollView
{
    [self sendEventWithJSON:@"{type:'didBeginPageZooming'}"];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didEndPageZooming:(UIScrollView *)scrollView atScale:(CGFloat)scale
{
    [self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didEndPageZooming',scale:%g}", scale]];
}

//- (PSPDFDocument *)pdfViewController:(PSPDFViewController *)pdfController documentForRelativePath:(NSString *)relativePath
//{
//
//}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController didTapOnPageView:(PSPDFPageView *)pageView atPoint:(CGPoint)viewPoint
{
    // inverted because it's almost always YES (due to handling JS eval calls).
    // in order to set this event as handled use explicit "return false;" in JS callback.
    return ![self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didTapOnPageView',viewPoint:[%g,%g]}", viewPoint.x, viewPoint.y]];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController didLongPressOnPageView:(PSPDFPageView *)pageView atPoint:(CGPoint)viewPoint gestureRecognizer:(UILongPressGestureRecognizer *)gestureRecognizer
{
    // inverted because it's almost always YES (due to handling JS eval calls).
    // in order to set this event as handled use explicit "return false;" in JS callback.
    return ![self sendEventWithJSON:[NSString stringWithFormat:@"{type:'didLongPressOnPageView',viewPoint:[%g,%g]}", viewPoint.x, viewPoint.y]];
}

static NSString *PSPDFStringFromCGRect(CGRect rect) {
    return [NSString stringWithFormat:@"[%g,%g,%g,%g]", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldSelectText:(NSString *)text withGlyphs:(NSArray *)glyphs atRect:(CGRect)rect onPageView:(PSPDFPageView *)pageView
{
    return [self sendEventWithJSON:@{@"type": @"shouldSelectText", @"text": text, @"rect": PSPDFStringFromCGRect(rect)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didSelectText:(NSString *)text withGlyphs:(NSArray *)glyphs atRect:(CGRect)rect onPageView:(PSPDFPageView *)pageView
{
    [self sendEventWithJSON:@{@"type": @"didSelectText", @"text": text, @"rect": PSPDFStringFromCGRect(rect)}];
}

//- (NSArray *)pdfViewController:(PSPDFViewController *)pdfController shouldShowMenuItems:(NSArray *)menuItems atSuggestedTargetRect:(CGRect)rect forSelectedText:(NSString *)selectedText inRect:(CGRect)textRect onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (NSArray *)pdfViewController:(PSPDFViewController *)pdfController shouldShowMenuItems:(NSArray *)menuItems atSuggestedTargetRect:(CGRect)rect forSelectedImage:(PSPDFImageInfo *)selectedImage inRect:(CGRect)textRect onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (NSArray *)pdfViewController:(PSPDFViewController *)pdfController shouldShowMenuItems:(NSArray *)menuItems atSuggestedTargetRect:(CGRect)rect forAnnotation:(PSPDFAnnotation *)annotation inRect:(CGRect)annotationRect onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldDisplayAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (BOOL)pdfViewController:(PSPDFViewController *)pdfController didTapOnAnnotation:(PSPDFAnnotation *)annotation annotationPoint:(CGPoint)annotationPoint annotationView:(UIView <PSPDFAnnotationViewProtocol> *)annotationView pageView:(PSPDFPageView *)pageView viewPoint:(CGPoint)viewPoint
//{
//
//}

//- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldSelectAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (void)pdfViewController:(PSPDFViewController *)pdfController didSelectAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (UIView <PSPDFAnnotationViewProtocol> *)pdfViewController:(PSPDFViewController *)pdfController annotationView:(UIView <PSPDFAnnotationViewProtocol> *)annotationView forAnnotation:(PSPDFAnnotation *)annotation onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (void)pdfViewController:(PSPDFViewController *)pdfController willShowAnnotationView:(UIView <PSPDFAnnotationViewProtocol> *)annotationView onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (void)pdfViewController:(PSPDFViewController *)pdfController didShowAnnotationView:(UIView <PSPDFAnnotationViewProtocol> *)annotationView onPageView:(PSPDFPageView *)pageView
//{
//
//}

//- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldShowController:(id)viewController embeddedInController:(id)controller animated:(BOOL)animated
//{
//
//}

//- (void)pdfViewController:(PSPDFViewController *)pdfController didShowController:(id)viewController embeddedInController:(id)controller animated:(BOOL)animated
//{
//
//}

//- (void)pdfViewController:(PSPDFViewController *)pdfController requestsUpdateForBarButtonItem:(UIBarButtonItem *)barButtonItem animated:(BOOL)animated
//{
//
//}

//- (void)pdfViewController:(PSPDFViewController *)pdfController didChangeViewMode:(PSPDFViewMode)viewMode
//{
//
//}

- (void)pdfViewControllerWillDismiss:(PSPDFViewController *)pdfController
{
    [self sendEventWithJSON:@"{type:'willDismiss'}"];
}

- (void)pdfViewControllerDidDismiss:(PSPDFViewController *)pdfController
{
    //release the pdf document and controller
    _pdfDocument = nil;
    _pdfController = nil;
    _navigationController = nil;

    //send event
    [self sendEventWithJSON:@"{type:'didDismiss'}"];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldShowHUD:(BOOL)animated
{
    return [self sendEventWithJSON:@{@"type": @"shouldShowHUD", @"animated": @(animated)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController willShowHUD:(BOOL)animated
{
    [self sendEventWithJSON:@{@"type": @"willShowHUD", @"animated": @(animated)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didShowHUD:(BOOL)animated
{
    [self sendEventWithJSON:@{@"type": @"didShowHUD", @"animated": @(animated)}];
}

- (BOOL)pdfViewController:(PSPDFViewController *)pdfController shouldHideHUD:(BOOL)animated
{
    return [self sendEventWithJSON:@{@"type": @"shouldHideHUD", @"animated": @(animated)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController willHideHUD:(BOOL)animated
{
    [self sendEventWithJSON:@{@"type": @"willHideHUD", @"animated": @(animated)}];
}

- (void)pdfViewController:(PSPDFViewController *)pdfController didHideHUD:(BOOL)animated
{
    [self sendEventWithJSON:@{@"type": @"didHideHUD", @"animated": @(animated)}];
}



@end
