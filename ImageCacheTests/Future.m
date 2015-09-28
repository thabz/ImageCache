//
//  Future.m
//  Peopls
//
//  Created by Jesper Christensen on 13/08/13.
//
//

#import "Future.h"

@interface Future ()
@property NSCondition* lock;
@property (nonatomic) id object;
@property (nonatomic) NSError* error;
@property BOOL resolved;
@end

// TOOD: Reimplement using NSCondition à la http://www.mikeash.com/pyblog/friday-qa-2010-02-26-futures.html
@implementation Future

- (id)init
{
    self = [super init];
    if (self) {
        self.resolved = NO;
        self.lock = [[NSCondition alloc] init];
    }
    return self;
}

- (void)setObject:(id)object error:(NSError*)error
{
    self.object = object;
    self.error = error;
    self.resolved = YES;
    [self.lock broadcast];
}

- (id)object
{
    [self.lock lock];
    while (!self.resolved) {
        // Non-blocking wait.
        NSDate *oneSecond = [NSDate dateWithTimeIntervalSinceNow:1];
        [self.lock waitUntilDate:oneSecond];
        oneSecond = [NSDate dateWithTimeIntervalSinceNow:1];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:oneSecond];
    }
    [self.lock unlock];
    return _object;
}

- (NSError*)error
{
    [self.lock lock];
    while (!self.resolved) {
        // Non-blocking wait.
        NSDate *oneSecond = [NSDate dateWithTimeIntervalSinceNow:1];
        [self.lock waitUntilDate:oneSecond];
        oneSecond = [NSDate dateWithTimeIntervalSinceNow:1];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:oneSecond];
    }
    [self.lock unlock];
    return _error;
}

- (void)then:(void (^)(id object, NSError *error))then
{
    then(self.object, self.error);
}

+ (NSArray*)objectsFromFutures:(NSArray*)futures
{
    NSMutableArray* result = [NSMutableArray new];
    for(Future* future in futures) {
        if (future.object && !future.error) {
            [result addObject:future.object];
        }
    }
    return result;
}

@end
