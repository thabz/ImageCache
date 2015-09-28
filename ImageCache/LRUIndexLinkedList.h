//
//  LRUIndexLinkedList.h
//  Kalliope
//
//  Created by Jesper Christensen on 30/05/14.
//
//

#import <Foundation/Foundation.h>

// This is thread-safe
@interface LRUIndexLinkedList : NSObject<NSCoding>
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initPrepopulatedWithCapacity:(NSUInteger)capacity;
- (NSUInteger)getLRUValue;
- (void)markValueAsMRU:(NSUInteger)value;
@end
