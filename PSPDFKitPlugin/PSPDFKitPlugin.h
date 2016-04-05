//
//  PSPDFKit.h
//  PSPDFPlugin for Apache Cordova
//
//  Copyright 2013 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY AUSTRIAN COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import <Foundation/Foundation.h>
#import <Cordova/CDV.h>

@class WKWebView; // This is a class provided by PSPDFKit which allows us to execute arbitrary JavaScript

@interface PSPDFKitPlugin : CDVPlugin
    + (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *) script withInterpreter:(WKWebView *)webView;
@end
