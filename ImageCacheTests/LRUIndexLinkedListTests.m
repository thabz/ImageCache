//
//  LRUIndexLinkedListTests.m
//  Peopls
//
//  Created by Jesper Christensen on 30/05/14.
//
//

#import <XCTest/XCTest.h>
#import "LRUIndexLinkedList.h"
#import "LRUIndexLinkedList_Testing.h"

@interface LRUIndexLinkedListTests : XCTestCase

@end

@implementation LRUIndexLinkedListTests

- (void)testInitialServings
{
    LRUIndexLinkedList* list = [[LRUIndexLinkedList alloc] initWithCapacity:5];
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertEqual(1, [list getLRUValue]);
    XCTAssertEqual(2, [list getLRUValue]);
    XCTAssertEqual(3, [list getLRUValue]);
    XCTAssertEqual(4, [list getLRUValue]);
    XCTAssertTrue([list sanityCheck]);
}

- (void)testWhenFull
{
    LRUIndexLinkedList* list = [[LRUIndexLinkedList alloc] initWithCapacity:5];
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertEqual(1, [list getLRUValue]);
    XCTAssertEqual(2, [list getLRUValue]);
    XCTAssertEqual(3, [list getLRUValue]);
    XCTAssertEqual(4, [list getLRUValue]);
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertTrue([list sanityCheck]);
}

- (void)testMakingLRUtoMRU
{
    LRUIndexLinkedList* list = [[LRUIndexLinkedList alloc] initWithCapacity:5];
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertEqual(1, [list getLRUValue]);
    XCTAssertEqual(2, [list getLRUValue]);
    XCTAssertEqual(3, [list getLRUValue]);
    XCTAssertEqual(4, [list getLRUValue]);
    XCTAssertEqual(0, [list getLRUValue]);
    [list markValueAsMRU:0];
    XCTAssertEqual(1, [list getLRUValue]);
    [list markValueAsMRU:1];
    XCTAssertEqual(2, [list getLRUValue]);
    [list markValueAsMRU:2];
    XCTAssertEqual(3, [list getLRUValue]);
    [list markValueAsMRU:3];
    XCTAssertEqual(4, [list getLRUValue]);
    [list markValueAsMRU:4];
    XCTAssertEqual(0, [list getLRUValue]);
    [list markValueAsMRU:4];
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertTrue([list sanityCheck]);
}

- (void)testMarkingMRUasMRU
{
    LRUIndexLinkedList* list = [[LRUIndexLinkedList alloc] initWithCapacity:5];
    XCTAssertEqual(0, [list getLRUValue]);
    [list markValueAsMRU:0];
    XCTAssertEqual(1, [list getLRUValue]);
    XCTAssertEqual(2, [list getLRUValue]);
    XCTAssertEqual(3, [list getLRUValue]);
    XCTAssertEqual(4, [list getLRUValue]);
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertEqual(0, [list getLRUValue]);
    XCTAssertTrue([list sanityCheck]);
}

- (void)testInitPrepopulatedWithCapacity
{
    LRUIndexLinkedList* list = [[LRUIndexLinkedList alloc] initPrepopulatedWithCapacity:100];
    XCTAssertEqual(list.count, 100);
    XCTAssertTrue([list sanityCheck]);
}

- (void)testStress
{
    NSInteger capacity = 300;
    NSInteger markedAsMRU = 0;
    LRUIndexLinkedList* lruList = [[LRUIndexLinkedList alloc] initWithCapacity:capacity];
    NSInteger runIterations[8] = {300,300,400,1000,1000,5000,10000,50000};
    for (int i = 0; i < 8; i++) {
        NSInteger iterations = runIterations[i];
        for (int j = 0; j < iterations; j++) {
            NSUInteger lruValue = [lruList getLRUValue];
            [lruList markValueAsMRU:lruValue];
            for(int k = 0; k < 10; k++) {
                NSInteger rnd = random() % lruList.count;
                XCTAssertTrue(rnd >= 0 && rnd < lruList.count);
                [lruList markValueAsMRU:rnd];
                markedAsMRU++;
            }
            [lruList markValueAsMRU:j % lruList.count];
            [lruList markValueAsMRU:lruList.count-1];
        }
        XCTAssertEqual(lruList.count, capacity);
        XCTAssertTrue([lruList sanityCheck]);
    }
    NSLog(@"Marked as MRU: %ld", (long)markedAsMRU);
}

@end
