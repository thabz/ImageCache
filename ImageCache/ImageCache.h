//
//  ImageCache.h
//  Kalliope
//
//  Created by Jesper Christensen on 25/05/14.
//
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@interface ImageCacheScheme : NSObject

- (nonnull instancetype)initWithIdentifier:(NSInteger)identifier opaque:(BOOL)opaque renderer:(nonnull void (^)(CGContextRef __nonnull context, CGSize contextSize, UIImage* __nonnull image))renderer;
/// Is the rendered image opaque?
@property (nonatomic) BOOL opaque;
/// An id you supply to distinquish between your schemes.
@property (nonatomic) NSInteger identifier;
/// You supply a block that renders the downloaded image into a supplied context with contextSize.
@property (copy,nonatomic, nonnull) void (^renderer)(CGContextRef __nonnull context, CGSize contextSize, UIImage* __nonnull image);
@end

@interface ImageCache : NSObject
/*!
 @info Create a new image cache.
 @param identifier Your own identifier.
 @param size We only support square images
 @param maxCount max items in the cache. Shared between all schemes.
 @param schemes the schemes or rendering styles for this cache.
 */
+ (nonnull ImageCache*)imageCacheWithIdentifier:(nonnull NSString*)identifier size:(CGSize)size capacity:(NSUInteger)capacity schemes:(nonnull NSArray*)schemes;

/*!
 @info Get an image from the cache.
 @param url the URL to download.
 @param completionHandler this will get called once for each scheme in this cache. If a cache-hit the completion handler will be called on the same thread as we got called on. If a cache miss, the completion handler will be called on the main thread.
 */
- (void)imageWithURL:(nonnull NSString*)url completionHandler:(nonnull void (^)(UIImage* __nullable renderedImage, NSString* __nonnull url, ImageCacheScheme* __nonnull scheme, BOOL fromCache, NSError* __nullable error))completionHandler ;

@end
