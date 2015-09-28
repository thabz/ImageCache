//
//  ImageCacheTests.m
//  Peopls
//
//  Created by Jesper Christensen on 14/07/14.
//
//

#import <XCTest/XCTest.h>
#import "Future.h"

#define FASTTEST true

@interface ImageCacheTests : XCTestCase

@end

@implementation ImageCacheTests
/*
// This will load a bunch of images through the ImageCache.
// 5% will fail.
// About 50% will be cache hits.
// We check that both the returned (normal and highlighted) versions of an image have the same center color.
- (void)testThumbnailForSearchResultItemWithImageURL
{
    ImageDownloader* imageDownloader = [ImageDownloader uniqueInstance];
    
    NSInteger iterations = FASTTEST ? 50 : 1200;
    NSInteger differentImagesCount = iterations / 2; // The cache size is 300 and 1200/2 gives us a 50% hit-miss-ratio.
    
    // Create random URLs
    NSMutableArray* urls = [NSMutableArray new];
    for(NSInteger i = 0; i < differentImagesCount; i++) {
        NSInteger imageId = arc4random() % 1000;
        NSString* badness = @"";
        if (i < (iterations/20)) {
            // Introduce 5% bad URLs to test that errors gets passed through.
            badness = @"bad";
        }
        
        NSString* url = [NSString stringWithFormat:@"http://erato.kalliope.org/random-images/%03ld%@.png",(long)imageId,badness];
        [urls addObject:url];
    }
    
    // Fetch them
    NSMutableArray* futuresForNormalImages = [NSMutableArray new];
    NSMutableArray* futuresForHighlightedImages = [NSMutableArray new];
    __block NSInteger cacheHits = 0;
    for (NSInteger i = 0; i < iterations; i++) {
        NSString* url = urls[i % urls.count];
        
        Future* futureNormal = [Future new];
        Future* futureHighlighted = [Future new];
        [futuresForNormalImages addObject:futureNormal];
        [futuresForHighlightedImages addObject:futureHighlighted];
        [imageDownloader thumbnailForSearchResultItemWithImageURL:url avatarStyle:SearchResultItemAvatarStyleWhite callback:^(UIImage *image, NSString *returnedUrl, ImageCacheScheme *scheme, BOOL fromCache, NSError *error) {
            if (error != nil) {
                NSLog(@"Got error for %@", url);
            } else {
                NSLog(@"Got image for %@", url);
            }
            if (fromCache) {
                cacheHits++;
            }
            XCTAssertEqualObjects(url, returnedUrl);
            if (scheme.identifier == ImageDownloaderAvatarStyleWhite35) {
                [futureNormal setObject:image error:error];
            } else if (scheme.identifier == ImageDownloaderAvatarStyleTransparent30) {
                [futureHighlighted setObject:image error:error];
            }
        }];
    }
    
    NSInteger errorsFound = 0;
    
    // Wait for all the futures
    for (NSInteger i = 0; i < iterations; i++) {
        __block UIImage* normalImage;
        __block UIImage* highlightedImage;
        __block NSError* normalError;
        __block NSError* highlightedError;
        Future* future = futuresForNormalImages[i];
        [future then:^(id object, NSError *error) {
            normalImage = object;
            normalError = error;
        }];
        future = futuresForHighlightedImages[i];
        [future then:^(id object, NSError *error) {
            highlightedImage = object;
            highlightedError = error;
        }];
        
        if (normalError == nil && highlightedError == nil) {
            
            XCTAssertTrue(normalImage.size.height > 20, @"Sanity check");
            XCTAssertTrue(normalImage.size.width > 20, @"Sanity check");
            
            UIColor* normalCenterColor = [self getCenterColorFromImage:normalImage];
            UIColor* highlightedCenterColor = [self getCenterColorFromImage:highlightedImage];
            
            CGFloat nr,ng,nb,na,hr,hg,hb,ha;
            [normalCenterColor getRed:&nr green:&ng blue:&nb alpha:&na];
            [highlightedCenterColor getRed:&hr green:&hg blue:&hb alpha:&ha];
            
            CGFloat redDifference = fabs(nr-hr);
            CGFloat greenDifference = fabs(ng-hg);
            CGFloat blueDifference = fabs(nb-hb);
            
            if (redDifference > 0.01) {
                NSLog(@"Red difference %f too large. Set break point here to investigate.", redDifference);
            }
            if (greenDifference > 0.01) {
                NSLog(@"Green difference %f too large. Set break point here to investigate.", greenDifference);
            }
            if (blueDifference > 0.01) {
                NSLog(@"Blue difference %f too large. Set break point here to investigate.", blueDifference);
            }
            
            XCTAssertTrue(redDifference < 0.01, @"Color mismatch");
            XCTAssertTrue(greenDifference < 0.01, @"Color mismatch");
            XCTAssertTrue(blueDifference < 0.01, @"Color mismatch");
        } else {
            XCTAssertNotNil(normalError, @"Both must fail if one fails.");
            XCTAssertNotNil(highlightedError, @"Both must fail if one fails.");
            errorsFound++;
        }
    }
    XCTAssertTrue(errorsFound > 0);
    XCTAssertTrue(errorsFound < differentImagesCount);
    NSLog(@"Cache hits %ld on %ld image returns.", (long)cacheHits, (long)iterations*2);
    NSLog(@"Errors found: %ld", (long)errorsFound);
}


- (void)testGenereateTestImages
{
    //    [self generateTestImages];
}

// Generates a bunch of solid color images. This has been run once, and the resulting images has been uploaded to http://erato.kalliope.org/random-images/[000-999].png

- (void)generateTestImages
{
    NSInteger count = 1000;
    CGSize size = CGSizeMake(100, 100);
    for (NSInteger i = 0; i < count; i++) {
        CGFloat r = (float)rand() / RAND_MAX;
        CGFloat g = (float)rand() / RAND_MAX;
        CGFloat b = (float)rand() / RAND_MAX;
        
        UIColor* fill = [UIColor colorWithRed:r green:g blue:b alpha:1];
        NSLog(@"%ld: %@", (long)i, fill);
        
        CGRect bounds = CGRectMake(0, 0, size.width, size.height);
        
        UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(context, fill.CGColor);
        CGContextFillRect(context, bounds);
        
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        // Write image in documents folder
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* path = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"RandomImages"];
        
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        
        BOOL directoryExists = [fileManager fileExistsAtPath:path];
        if (directoryExists == NO) {
            [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString* filename = [NSString stringWithFormat:@"%03ld.png", (long)i];
        NSString* filePath = [path stringByAppendingPathComponent:filename];
        NSData *imageData = UIImagePNGRepresentation(image);
        [imageData writeToFile:filePath atomically:YES];
        NSLog(@"Wrote file %@", filePath);
    }
}

// Adaptation of http://stackoverflow.com/a/1262893/1514022
- (UIColor*)getCenterColorFromImage:(UIImage*)image
{
    // First get the image into your data buffer
    CGImageRef imageRef = [image CGImage];
    NSUInteger width = CGImageGetWidth(imageRef);
    NSUInteger height = CGImageGetHeight(imageRef);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);
    
    NSInteger xx = width / 2;
    NSInteger yy = height / 2;
    // Now your rawData contains the image data in the RGBA8888 pixel format.
    NSInteger byteIndex = (bytesPerRow * yy) + xx * bytesPerPixel;
    
    CGFloat red   = (rawData[byteIndex]     * 1.0) / 255.0;
    CGFloat green = (rawData[byteIndex + 1] * 1.0) / 255.0;
    CGFloat blue  = (rawData[byteIndex + 2] * 1.0) / 255.0;
    CGFloat alpha = (rawData[byteIndex + 3] * 1.0) / 255.0;
    
    UIColor *acolor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
    
    free(rawData);
    
    return acolor;
}
*/
@end
