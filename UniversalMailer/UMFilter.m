//
//  UMFilter.m
//  UniversalMailer
//
//  Created by luca on 25/05/16.
//  Copyright © 2016 noware. All rights reserved.
//

#import "UMFilter.h"

#import <Cocoa/Cocoa.h>

#import "UMConstants.h"
#import "UMLog.h"
#import "NSString+UMExtensions.h"
#import "UMMIMEEntity.h"

@interface UMFilter ()
@property (nonatomic, strong) NSData *data;
@end

@implementation UMFilter

- (id)initWithData: (NSData*)data {
    if( self = [super init] ){
        self.inlineAttachments = ![[NSUserDefaults standardUserDefaults] boolForKey: UMDisableImageInlining];
        self.data = data;
    }
    
    return self;
}

- (NSData*)filteredData {
    UMMIMEEntity *entity = [[UMMIMEEntity alloc] initWithData: self.data];
    NSArray *plain = [entity findSubentitiesOfType: @"text/plain" avoidAttachments: YES invertMatches: NO];
    NSArray *html = [entity findSubentitiesOfType: @"text/html" avoidAttachments: YES invertMatches: NO];
    NSArray *atts = [entity findSubentitiesOfType: @"text/" avoidAttachments: NO invertMatches: YES];
    
    UMLog(@"%s - plain[%@]", __PRETTY_FUNCTION__, plain);
    UMLog(@"%s - html[%@]", __PRETTY_FUNCTION__, html);
    UMLog(@"%s - atts[%@]", __PRETTY_FUNCTION__, atts);
    
    NSMutableArray *avoidCids = [@[] mutableCopy];
    
    if( plain.count > 1 ){
        NSMutableString *final = [@"" mutableCopy];
        for( UMMIMEEntity *e in plain ){
            if( e.body.string.length > 0 )
                [final appendString: e.body.string];
        }
        
        UMMIMEEntity *ne = [[UMMIMEEntity alloc] initWithContentType: @"Content-Type: text/plain"];
        [ne parseHeadersFromString: [plain[0] originalHeaders]];
        ne.body = [[UMMIMEBody alloc] initWithString: final];
        plain = @[ne];
    }
    if( html.count > 0 ){
        NSMutableString *final = [@"" mutableCopy];
        for( UMMIMEEntity *e in html ){
            if( e.body.string.length > 0 )
                [final appendString: e.body.string];
        }
        
        if( self.inlineAttachments ){
            NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern: @"<img[^>]*src=[\"']cid:[^>]*>" options: 0 error: nil];
            [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: UMAttachmentPlaceholder];
        }
        else {
            NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern: @"<img[^>]*src=[\"']cid:[^>]*>" options: 0 error: nil];
            NSRange r1 = [final rangeOfString: UMSignatureMarkerBegin];
            if( r1.location != NSNotFound ){
                [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, r1.location) withTemplate: @""];
                NSRange r2 = [final rangeOfString: UMSignatureMarkerEnd];
                [regex replaceMatchesInString: final options: 0 range: NSMakeRange(r2.location+r2.length, final.length-(r2.location+r2.length)) withTemplate: @""];
                
                r1 = [final rangeOfString: UMSignatureMarkerBegin];
                r2 = [final rangeOfString: UMSignatureMarkerEnd];
                NSArray *matches = [regex matchesInString: final options: 0 range: NSMakeRange(r1.location, r2.location+r2.length-r1.location)];
                for( NSTextCheckingResult *m in matches ){
                    NSString *s = [final substringWithRange: [m rangeAtIndex: 0]];
                    NSRegularExpression *regex2 = [[NSRegularExpression alloc] initWithPattern: @"cid:([^\" ]*)" options: 0 error: nil];
                    NSArray *matches2 = [regex2 matchesInString: s options: 0 range: NSMakeRange(0, s.length)];
                    for( NSTextCheckingResult *m2 in matches2 ){
                        NSString *ss = [[s substringWithRange: [m2 rangeAtIndex: 0]] stringByReplacingOccurrencesOfString: @"cid:" withString: @""];
                        [avoidCids addObject: ss];
                    }
                }
            }
            else {
                [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: @""];
            }
        }
        
        if( self.inlineAttachments && atts.count > 0 ){
            NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern: @"</html><html[^>]*>" options: 0 error: nil];
            [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: UMAttachmentPlaceholder];
        }
        
        NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern: @"<[/]?html[^>]*>" options: 0 error: nil];
        [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: @""];
        regex = [[NSRegularExpression alloc] initWithPattern: @"<head[^>]*>.*?</head>" options: 0 error: nil];
        [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: @""];
        regex = [[NSRegularExpression alloc] initWithPattern: @"<body" options: 0 error: nil];
        [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: @"<div"];
        regex = [[NSRegularExpression alloc] initWithPattern: @"</body>" options: 0 error: nil];
        [regex replaceMatchesInString: final options: 0 range: NSMakeRange(0, final.length) withTemplate: @"</div>"];
        
        NSString *finalHtml = [NSString stringWithFormat: @"<html><head></head><body>%@</body></html>", final];
        if( self.inlineAttachments && atts.count > 0 ){
            NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern: UMAttachmentPlaceholder options: 0 error: nil];
            NSArray *matches = [regex matchesInString: finalHtml options: 0 range: NSMakeRange(0, finalHtml.length)];
            int i = 0;
            while( matches.count > 0 ){
                NSRange r = [matches[0] rangeAtIndex: 0];
                if( atts.count > i ){
                    if( [[atts[i] contentID] length] > 0 ){
                        NSString *cid = [atts[i] contentID];
                        if( [avoidCids containsObject: cid] )
                            continue;
                        finalHtml = [finalHtml stringByReplacingCharactersInRange: r withString: [NSString stringWithFormat: @"<img src=\"cid:%@\">", cid]];
                    }
                    else {
                        NSString *ct = [atts[i] contentType];
                        if( [ct hasPrefix: @"image/"] ){
                            NSString *cid = [@"abcdefABCDEF0123456789" randomizeWithLength: 32];;
                            [atts[i] setContentID: cid];
                            finalHtml = [finalHtml stringByReplacingCharactersInRange: r withString: [NSString stringWithFormat: @"<img src=\"cid:%@\">", cid]];
                        }
                    }
                }
                else {
                    finalHtml = [finalHtml stringByReplacingCharactersInRange: r withString: @""];
                }
                i++;
                matches = [regex matchesInString: finalHtml options: 0 range: NSMakeRange(0, finalHtml.length)];
            }
        }

        if( [[NSUserDefaults standardUserDefaults] boolForKey: UMOverrideInjectedCSS] &&
           [[[NSUserDefaults standardUserDefaults] stringForKey: UMInjectedCSS] length] > 0 ){
            NSString *injectedCSS = [[NSUserDefaults standardUserDefaults] stringForKey: UMInjectedCSS];
            finalHtml = [finalHtml stringByReplacingOccurrencesOfString: @"<head></head>" withString: [NSString stringWithFormat: @"<head><style>\n%@\n</style></head>", injectedCSS]];
        }
        else {
            NSString *fontName = [[NSUserDefaults standardUserDefaults] stringForKey: UMOutgoingFontName];
            CGFloat fontSize = [[NSUserDefaults standardUserDefaults] floatForKey: UMOutgoingFontSize];
            NSFont *sfont = [NSFont fontWithName: fontName size: fontSize];
            BOOL usePoints = [[NSUserDefaults standardUserDefaults] boolForKey: UMUsePointsInsteadOfPixels];
            
            NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey: UMOutgoingFontColor];
            NSColor *color = [[NSColor blackColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
            color = [[NSUnarchiver unarchiveObjectWithData: colorData] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
            NSString *css = [NSString stringWithFormat: @"body{\n\tfont-family: '%@', '%@';\n\tfont-size: %.0f%@;\n\tcolor: rgba(%.0f, %.0f, %.0f, %.1f)\n}",
                             sfont.fontName, sfont.familyName, sfont.pointSize, usePoints?@"pt":@"px",
                             color.redComponent*255, color.greenComponent*255, color.blueComponent*255, color.alphaComponent];
            finalHtml = [finalHtml stringByReplacingOccurrencesOfString: @"<head></head>" withString: [NSString stringWithFormat: @"<head><style>\n%@\n</style></head>", css]];
        }
        
        UMMIMEEntity *ne = [[UMMIMEEntity alloc] initWithContentType: @"Content-Type: text/plain"];
        [ne parseHeadersFromString: [html[0] originalHeaders]];
        ne.body = [[UMMIMEBody alloc] initWithString: finalHtml];
        html = @[ne];
    }
    
    UMMIMEEntity *alts = [[UMMIMEEntity alloc] initWithContentType: @"Content-Type: multipart/alternative"];
    alts.body = [[UMMIMEBody alloc] initWithSubentities: [plain arrayByAddingObjectsFromArray: html]];
    
    NSMutableArray *attachments = [@[] mutableCopy];
    NSMutableArray *inlines = [@[] mutableCopy];
    
    if( atts.count > 0 ){
        for( UMMIMEEntity *a in atts ){
            a.contentDisposition = @"attachment";
            if( a.contentType.length > 0 ){
                if( [a.contentType hasPrefix: @"image/"] && self.inlineAttachments ){
                    [inlines addObject: a];
                    a.contentDisposition = @"inline";
                }
            }
            if( [avoidCids containsObject: a.contentID] ){
                [inlines addObject: a];
                a.contentDisposition = @"inline";
            }
            if( ![inlines containsObject: a] )
                [attachments addObject: a];
        }
    }
    
    UMMIMEEntity *ret = nil;
    if( attachments.count > 0 ){
        UMLog(@"%s - multipart/mixed path", __PRETTY_FUNCTION__);
        UMMIMEEntity *mid = nil;
        if( inlines.count > 0 ){
            UMLog(@"%s - multipart/mixed path: adding inlines", __PRETTY_FUNCTION__);
            UMMIMEEntity *ne = [[UMMIMEEntity alloc] initWithContentType: @"Content-Type: multipart/related"];
            [ne setContentTypeParameterWithKey: @"type" value: @"multipart/alternative"];
            ne.body = [[UMMIMEBody alloc] initWithSubentities: [@[alts] arrayByAddingObjectsFromArray: inlines]];
            mid = ne;
        }
        else {
            mid = alts;
        }
        ret = [[UMMIMEEntity alloc] initWithContentType: @"Content-Type: multipart/mixed"];
        [ret parseHeadersFromString: entity.originalHeaders];
        ret.contentType = @"multipart/mixed";
        ret.body = [[UMMIMEBody alloc] initWithSubentities: [@[mid] arrayByAddingObjectsFromArray: attachments]];
    }
    else {
        UMLog(@"%s - multipart/related path", __PRETTY_FUNCTION__);
        NSArray *alle = [attachments arrayByAddingObjectsFromArray: inlines];
        UMMIMEEntity *ne = [[UMMIMEEntity alloc] initWithContentType: @"Content-Type: multipart/related"];
        [ne parseHeadersFromString: entity.originalHeaders];
        ne.contentType = @"multipart/related";
        [ne setContentTypeParameterWithKey: @"type" value: @"multipart/alternative"];
        ne.body = [[UMMIMEBody alloc] initWithSubentities: [@[alts] arrayByAddingObjectsFromArray: alle]];
        ret = ne;
    }
    
    return [ret.encodedBodyString dataUsingEncoding: NSUTF8StringEncoding];
}

@end
