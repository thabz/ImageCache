//
//  ImageCache.m
//  Kalliope
//
//  Created by Jesper Christensen on 25/05/14.
//
//  Design notes.
//  We only persist the metadata urlToCacheIndex when a new image is rendered into the mmap'ed pixelstore. We don't persist the LRU cache, it changes far too often, ie. on each lookup. It doesn't really matter whether the LRU cache gets saved, as long as the icons used on the MasterViewController are available on launch, which they almost alway are.

#import "ImageCache.h"
#import "LRUIndexLinkedList.h"
#import <sys/mman.h>

@interface ImageCacheScheme ()
@property size_t sizeInBytes;
@property size_t bytesPerRow;
@property size_t offsetInGroup;
@property CGBitmapInfo bitmapInfo;
@property size_t bytesPerPixel;
@end

@implementation ImageCacheScheme

- (instancetype)initWithIdentifier:(NSInteger)identifier opaque:(BOOL)opaque renderer:(void (^)(CGContextRef context, CGSize contextSize, UIImage* image))renderer
{
    self = [self init];
    if (self) {
        self.identifier = identifier;
        self.opaque = opaque;
        self.renderer = renderer;
    }
    return self;
}

@end

typedef void (^RequestsCallback)(UIImage* renderedImage, ImageCacheScheme* scheme, NSError* error);

@interface ImageCache ()
@property (nonatomic, copy) NSString* identifier;
@property (nonatomic) CGSize size;
@property (nonatomic) NSUInteger capacity;
@property (nonatomic, copy) NSArray* schemes;
@property (nonatomic) CGFloat screenScale;
@property (nonatomic) NSMutableDictionary* urlToCacheIndex; // Keys are url, values are integer indices into cache. This values need to be multiplied by the number of schemes to get to the entries in the cache.
@property (nonatomic) NSMutableArray* cacheIndexToUrl; // Values are urls.
@property (nonatomic) NSLock* urlToCacheLock;
@property (nonatomic) NSMutableArray* imageCache; // maxCount * schemes.count entries of UIImage
@property (nonatomic) LRUIndexLinkedList* lruList;
@property int pixelCacheFileDescriptor;
@property (nonatomic) void* bytes;
@property (nonatomic) size_t bytes_length;
@property (nonatomic) size_t groupSizeInBytes;
@property (nonatomic) NSMutableDictionary* requests; // Keys are urls, values are arrays of callback-blocks.
@property (nonatomic) NSOperationQueue* operationQueue;
@property (nonatomic) NSURLSession* urlSession;
@property (nonatomic) NSInteger version;
@property dispatch_queue_t saving_queue;
@end

@implementation ImageCache

- (instancetype)initWithCacheWithIdentifier:(nonnull NSString*)identifier size:(CGSize)size capacity:(NSUInteger)capacity schemes:(nonnull NSArray*)schemes
{
    self = [self init];
    if (self) {
        self.version = 3;
        self.identifier = identifier;
        self.size = size;
        self.capacity = capacity;
        self.schemes = schemes;
        self.requests = [NSMutableDictionary dictionary];
        // Is 2 for Retina displays, 1 for non-Retina and even 3 for iPhone 6 plus.
        self.screenScale = [[UIScreen mainScreen] scale];
        
        NSURLSessionConfiguration* conf = [NSURLSessionConfiguration defaultSessionConfiguration];
        conf.HTTPMaximumConnectionsPerHost = 5;
        conf.timeoutIntervalForRequest = 10;
        self.operationQueue = [[NSOperationQueue alloc] init];
        self.operationQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
        self.urlSession = [NSURLSession sessionWithConfiguration:conf delegate:nil delegateQueue:self.operationQueue];
        
        self.saving_queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL);
        self.urlToCacheLock = [NSLock new];
        _groupSizeInBytes = 0;
        int page_size = getpagesize();
        [schemes enumerateObjectsUsingBlock:^(ImageCacheScheme* scheme, NSUInteger idx, BOOL *stop) {
            if (scheme.opaque) {
                scheme.bitmapInfo = kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host;
            } else {
                scheme.bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
            }
            
            NSUInteger bytesPerPixel = 4;
            NSUInteger bytesPerRow = bytesPerPixel * _size.width * _screenScale;
            // Core Animation will make a copy of any image that a client application provides whose backing store isn't properly byte-aligned. This copy operation can be prohibitively expensive, so we want to avoid this by properly aligning any UIImages we're working with. To produce a UIImage that is properly aligned, we need to ensure that the backing store's bytes per row is a multiple of 64.
            bytesPerRow =  [self byteAlignSize:bytesPerRow alignment:64];
            scheme.bytesPerRow = bytesPerRow;
            
            NSUInteger sizeInBytes = bytesPerRow * _size.height * _screenScale;
            // The size of each entry in the table needs to be page-aligned. This will cause each entry to have a page-aligned base address, which will help us avoid Core Animation having to copy our images when we eventually set them on layers.
            sizeInBytes = [self byteAlignSize:sizeInBytes alignment:page_size];
            scheme.sizeInBytes = sizeInBytes;
            if (idx == 0) {
                scheme.offsetInGroup = 0;
            } else {
                ImageCacheScheme* prevScheme = schemes[idx-1];
                scheme.offsetInGroup = prevScheme.offsetInGroup + prevScheme.sizeInBytes;
            }
            _groupSizeInBytes += sizeInBytes;
        }];
        
        self.imageCache = [NSMutableArray new];
        for(NSUInteger i = 0; i < self.capacity*self.schemes.count; i++) {
            [self.imageCache addObject:[NSNull null]];
        }
        
        BOOL initFromFileSuccess = [self loadFromFile];
        //initFromFileSuccess = NO;
        if (!initFromFileSuccess) {
            NSLog(@"Starting a new ImageCache for %@", self.identifier);
            // Starting a new cache.
            self.lruList = [[LRUIndexLinkedList alloc] initWithCapacity:capacity];
            self.cacheIndexToUrl = [NSMutableArray array];
            for(NSUInteger i = 0; i < self.capacity; i++) {
                [self.cacheIndexToUrl addObject:@""];
            }
            self.urlToCacheIndex = [NSMutableDictionary new];
            BOOL result = [self loadPixelCacheByCreatingNew:YES];
            if (!result) {
                // We couldn't create a pixel buffer file, so we'll hump along with no caching.
                self.capacity = 0;
            }
        }
    }
    return self;
}

+ (ImageCache*)imageCacheWithIdentifier:(nonnull NSString*)identifier size:(CGSize)size capacity:(NSUInteger)capacity schemes:(nonnull NSArray*)schemes
{
    return [[ImageCache alloc] initWithCacheWithIdentifier:identifier size:size capacity:capacity schemes:schemes];
}

- (void)dealloc
{
    [self saveMetadata];
    if (_bytes != NULL) {
        munmap(_bytes, _bytes_length);
    }
}

- (void)imageWithURL:(nonnull NSString*)url completionHandler:(void (^)(UIImage* __nullable renderedImage, NSString* __nonnull url, ImageCacheScheme* __nonnull scheme, BOOL fromCache, NSError* __nullable error))completionHandler;
{
    NSAssert([NSThread isMainThread], @"Called %s from outside of main_queue.",__PRETTY_FUNCTION__);
    if (self.capacity > 0 && self.urlToCacheIndex[url]) {
        // Call completionHandler for each scheme immediately and while still on the main thread
        NSNumber* indexNumber = self.urlToCacheIndex[url];
        NSUInteger index = indexNumber.unsignedIntegerValue;
        [self.lruList markValueAsMRU:index];
        for(NSUInteger i = 0; i < self.schemes.count; i++) {
            ImageCacheScheme* scheme = self.schemes[i];
            NSUInteger cacheIndex = i+index*self.schemes.count;
            UIImage* cachedImage = (UIImage*)self.imageCache[cacheIndex];
            if (cachedImage == nil || cachedImage == (UIImage*)[NSNull null]) {
                // We got the binary data, but not the UIImage. This is the case when the app starts up with a cache on disk from a previous run.
                cachedImage = [self getImageEntryAtIndex:index schemeIndex:i];
                self.imageCache[cacheIndex] = cachedImage;
            }
            completionHandler(cachedImage, url, scheme, YES, nil);
        }
    } else {
        [self _downloadUrl:url completionHandler:^(UIImage *renderedImage, ImageCacheScheme *scheme, NSError *error) {
            NSAssert([NSThread isMainThread], @"Called %s from outside of main_queue.",__PRETTY_FUNCTION__);
            completionHandler(renderedImage, url, scheme, NO, error);
        }];
    }
}

/// Download, render and store an image in the cache.
/// Do this is a thread somehow, so that each url only gets downloaded once and rendered once per scheme.
/// The completion handler should get called once for each scheme.
/// This method also handles the adding to the cache.
- (void)_downloadUrl:(NSString*)url completionHandler:(RequestsCallback)doneCallback;
{
    NSAssert([NSThread isMainThread], @"Called %s from outside of main_queue.",__PRETTY_FUNCTION__);
    NSMutableArray* callbacks = self.requests[url];
    if (callbacks) {
        [callbacks addObject:doneCallback];
    } else {
        self.requests[url] = [NSMutableArray arrayWithObject:doneCallback];
        [self _downloadAndRenderUrl:url];
    }
}

// Download the image, render it using the schemes and call the callbacks in the requests dictionary once for each scheme.
- (void)_downloadAndRenderUrl:(NSString*)url
{
    [self _downloadDataWithUrl:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // This completion handler is called off the main thread.
        NSHTTPURLResponse* httpResponse = nil;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            httpResponse = (NSHTTPURLResponse*)response;
        }
        if (data == nil || error || (httpResponse != nil && httpResponse.statusCode != 200)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // By doing the callbacks on the main thread, we assure that no other callbacks are added to the requests dictionary.
                NSArray* callbacks = self.requests[url];
                for (RequestsCallback callback in callbacks) {
                    for (ImageCacheScheme* scheme in self.schemes) {
                        callback(nil, scheme, [NSError errorWithDomain:@"Some network error happened" code:0 userInfo:nil]);
                    }
                }
                [self.requests removeObjectForKey:url];
            });
        } else {
            // We're off the main thread here, so OK to do slow rendering but not OK to access our data structures.
            UIImage* downloadedImage = [UIImage imageWithData:data];
            // Find the new image locations using the LRU linked list
            __block NSUInteger index;
            dispatch_sync(dispatch_get_main_queue(), ^{
                index = [self.lruList getLRUValue];
                [self.lruList markValueAsMRU:index];
            });
            NSMutableArray* renderedImages = [NSMutableArray new];
            [self.schemes enumerateObjectsUsingBlock:^(ImageCacheScheme* scheme, NSUInteger i, BOOL *stop) {
                // Create or reuse CGContextRefs) in the memcache
                CGContextRef context = [self newCGContextAtEntryIndex:index schemeIndex:i];
                CGContextTranslateCTM(context, 0, _size.height*_screenScale);
                CGContextScaleCTM(context, _screenScale, -_screenScale);
                
                // Render the icons for each scheme in the contexts.
                scheme.renderer(context, self.size, downloadedImage);
                CGContextRelease(context);
                // Convert the contexts to CGImages and then UIImages.
                UIImage* renderedImage = [self getImageEntryAtIndex:index schemeIndex:i];
                [renderedImages addObject:renderedImage];
            }];
            // Flush the changed bytes
            msync(_bytes + index * _groupSizeInBytes, _groupSizeInBytes, MS_SYNC);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Modify the data structures and do the callbacks on the main-thread
                NSAssert(index < self.capacity, nil);
                NSString* oldUrl = self.cacheIndexToUrl[index];
                
                [self.urlToCacheLock lock];
                self.urlToCacheIndex[url] = @(index);
                self.cacheIndexToUrl[index] = url;
                if (oldUrl) {
                    [self.urlToCacheIndex removeObjectForKey:oldUrl];
                }
                [self.urlToCacheLock unlock];
                [self saveMetadata];
                
                // Register rendered images in cache
                for(NSUInteger i = 0; i < self.schemes.count; i++) {
                    self.imageCache[i + index*self.schemes.count] = renderedImages[i];
                }
                // Handle callbacks to those waiting for the rendered images.
                NSArray* callbacks = self.requests[url];
                for (RequestsCallback callback in callbacks) {
                    [self.schemes enumerateObjectsUsingBlock:^(ImageCacheScheme* scheme, NSUInteger i, BOOL *stop) {
                        callback(renderedImages[i], scheme, nil);
                    }];
                }
                [self.requests removeObjectForKey:url];
            });
        }
    }];
}

- (void)_downloadDataWithUrl:(NSString*)urlString completionHandler:(void(^)(NSData* data, NSURLResponse* response, NSError* error))completionHandler
{
    NSURL* url = [NSURL URLWithString:urlString];
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"image/*" forHTTPHeaderField:@"Accept"];
    __block NSURLSessionDataTask* task = [self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        completionHandler(data, response, error);
    }];
    [task resume];
}

// Creates a context to draw on.
// @param index index in the binary cache.
- (CGContextRef)newCGContextAtEntryIndex:(NSUInteger)index schemeIndex:(NSUInteger)schemeIndex
{
    ImageCacheScheme* scheme = self.schemes[schemeIndex];
    NSUInteger bitsPerComponent = 8;
    void* bytes_address = _bytes + index * _groupSizeInBytes + scheme.offsetInGroup;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = scheme.bitmapInfo;
    CGContextRef context = CGBitmapContextCreate(bytes_address, _size.width*_screenScale, _size.height*_screenScale, bitsPerComponent, scheme.bytesPerRow, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    return context;
}

// @param index index in the binary cache.
- (UIImage*)getImageEntryAtIndex:(NSUInteger)index schemeIndex:(NSUInteger)schemeIndex
{
    ImageCacheScheme* scheme = self.schemes[schemeIndex];
    NSUInteger bitsPerComponent = 8;
    NSUInteger bitsPerPixel = 4 * bitsPerComponent;
    void* bytes_address = _bytes + index * _groupSizeInBytes + scheme.offsetInGroup;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, bytes_address, scheme.sizeInBytes, NULL);
    CGSize pixelSize = CGSizeMake(_size.width*_screenScale, _size.height*_screenScale);
    CGImageRef imageRef = CGImageCreate(pixelSize.width, pixelSize.height, bitsPerComponent, bitsPerPixel, scheme.bytesPerRow, colorSpace, scheme.bitmapInfo, dataProvider, NULL, false, (CGColorRenderingIntent)0);
    CGDataProviderRelease(dataProvider);
    CGColorSpaceRelease(colorSpace);
    UIImage* image = [[UIImage alloc] initWithCGImage:imageRef scale:_screenScale orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    return image;
}

- (size_t)byteAlignSize:(NSUInteger)size alignment:(NSUInteger)alignment
{
    return ((size + (alignment-1)) / alignment) * alignment;
}


#pragma mark - Filehandling

+ (NSString*)directoryPath
{
    static dispatch_once_t onceToken;
    static NSString* path = nil;
    dispatch_once(&onceToken, ^{
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        path = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"ImageCache"];
        
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        
        
        BOOL directoryExists = [fileManager fileExistsAtPath:path];
        if (directoryExists == NO) {
            [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
    });
    return path;
}

- (NSString*)pixelCacheFilename
{
    NSString* filename = [self.identifier stringByAppendingPathExtension:@"pixels"];
    return [[ImageCache directoryPath] stringByAppendingPathComponent:filename];
}

- (NSString*)metadataFilename
{
    NSString* filename = [self.identifier stringByAppendingPathExtension:@"metadata"];
    return [[ImageCache directoryPath] stringByAppendingPathComponent:filename];
}

- (void)saveMetadata
{
    dispatch_async(self.saving_queue, ^{
        [self.urlToCacheLock lock];
        NSDictionary* dict = @{@"urlToCacheIndex": self.urlToCacheIndex,
                               @"capacity": @(self.capacity),
                               @"screenScale": @(self.screenScale),
                               @"version": @(self.version)};
        
        NSError* error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        [self.urlToCacheLock unlock];
        if (error == nil) {
            if ([data writeToFile:[self metadataFilename] atomically:YES] == NO) {
                NSLog(@"%s: Couldn't persist metadata for ImageCache (%@)", __PRETTY_FUNCTION__, self.identifier);
            }
        } else {
            NSLog(@"%s: Got an error (%@) when serializing metadata (%@) for ImageCache (%@)", __PRETTY_FUNCTION__, error, dict, self.identifier);
        }
    });
}

- (BOOL)loadMetaData
{
    //NSData* data = [NSData dataWithContentsOfMappedFile:[self metadataFilename]];
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfFile:[self metadataFilename] options:NSDataReadingMappedAlways error:&error];
    if (data == nil || error != nil) {
        return NO;
    }
    
    NSDictionary* dict = (NSDictionary *)[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    if (dict == nil) {
        return NO;
    }
    NSNumber* version = dict[@"version"];
    if (version == nil || version.integerValue != self.version) {
        // The filedata is from an earlier version, so ditch it.
        return NO;
    }
    NSNumber* capacity = dict[@"capacity"];
    if (capacity == nil || capacity.integerValue != self.capacity) {
        // The filedata is from an earlier version, so ditch it.
        return NO;
    }
    NSNumber* screenScale = dict[@"screenScale"];
    if (screenScale == nil || screenScale.integerValue != self.screenScale) {
        // The filedata is from another simulator, so ditch it.
        return NO;
    }
    
    self.urlToCacheIndex = [dict[@"urlToCacheIndex"] mutableCopy];
    self.cacheIndexToUrl = [NSMutableArray array];
    for(NSUInteger i = 0; i < self.capacity; i++) {
        [self.cacheIndexToUrl addObject:@""];
    }
    [self.urlToCacheIndex enumerateKeysAndObjectsUsingBlock:^(NSString* url, NSNumber* indexNumber, BOOL *stop) {
        NSUInteger index = indexNumber.unsignedIntegerValue;
        if (index < self.cacheIndexToUrl.count) {
            self.cacheIndexToUrl[index] = url;
        }
    }];
    self.lruList = [[LRUIndexLinkedList alloc] initPrepopulatedWithCapacity:self.capacity];
    
    return YES;
}

- (BOOL)loadPixelCacheByCreatingNew:(BOOL)forceNew
{
    _bytes_length = self.capacity * self.groupSizeInBytes;
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSString* filePath = [self pixelCacheFilename];
    if ([fileManager fileExistsAtPath:filePath] == NO) {
        NSDictionary* attributes = @{NSFileProtectionKey: NSFileProtectionNone};
        [fileManager createFileAtPath:filePath contents:nil attributes:attributes];
    } else {
        NSDictionary* attributes = [fileManager attributesOfItemAtPath:filePath error:NULL];
        NSUInteger fileSize = [attributes[NSFileSize] unsignedIntegerValue];
        if (fileSize < _bytes_length) {
            NSLog(@"Filesize (%llu) not matching %zu", attributes.fileSize, _bytes_length);
        } else {
            //NSString* length_string = [NSByteCountFormatter stringFromByteCount:fileSize countStyle:NSByteCountFormatterCountStyleFile];
            //NSLog(@"Found mmap file for cache (%@) where file size (%@) is correct", self.identifier, length_string);
        }
    }
    _pixelCacheFileDescriptor = open([filePath fileSystemRepresentation], O_RDWR|O_CREAT, 0666);
    
    // Make sure that we are big enough
    lseek(_pixelCacheFileDescriptor, _bytes_length + 1, SEEK_SET);
    write(_pixelCacheFileDescriptor, "", 1);
    lseek(_pixelCacheFileDescriptor, 0, SEEK_SET);
    
    if (_pixelCacheFileDescriptor >= 0) {
        _bytes_length = self.capacity * self.groupSizeInBytes;
        //NSString* length_string = [NSByteCountFormatter stringFromByteCount:_bytes_length countStyle:NSByteCountFormatterCountStyleFile];
        
        _bytes = mmap(NULL, _bytes_length, (PROT_READ|PROT_WRITE), (MAP_FILE|MAP_SHARED), _pixelCacheFileDescriptor, 0);
        if (_bytes == MAP_FAILED) {
            NSLog(@"File (%@) for (%@) mmap failed", filePath, self.identifier);
        } else {
            //NSLog(@"File (%@) for (%@) with length (%@) mmapped successfully", filePath, self.identifier, length_string);
        }
        close(_pixelCacheFileDescriptor);
        return _bytes != MAP_FAILED;
    } else {
        NSLog(@"Creation of mmap for (%@) failed", self.identifier);
        return NO;
    }
}

/// @return YES on success; NO otherwise.
- (BOOL)loadFromFile
{
    return [self loadMetaData] && [self loadPixelCacheByCreatingNew:NO];
}

@end
