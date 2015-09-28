//
//  Future.h
//  Peopls
//
//  Created by Jesper Christensen on 13/08/13.
//
//

#import <Foundation/Foundation.h>

@interface Future : NSObject

/// Sets the object and release the mutex
- (void)setObject:(id)object error:(NSError*)error;

/// Blocking getter
@property (readonly, nonatomic) id object;

/// Blocking getter
@property (readonly, nonatomic) NSError* error;

/// Blocks until the object is set and then calls then
- (void)then:(void (^)(id object, NSError *error))then;

/// Pulls the non-nil objects with no errors. This will block until futures are ready.
+ (NSArray*)objectsFromFutures:(NSArray*)futures;

@end
