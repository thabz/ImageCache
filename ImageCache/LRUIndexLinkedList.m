//
//  LRUIndexLinkedList.m
//  Kalliope
//
//  Created by Jesper Christensen on 30/05/14.
//
//

#import "LRUIndexLinkedList.h"

@interface LRUIndexLinkedList ()
@property uint16_t capacity;
@property uint16_t *next, *prev;  // Our linked nodes
@property (nonatomic) uint16_t count;
@property uint16_t firstNodeIndex;
@property uint16_t lastNodeIndex;
@end

/// Last node is the index of the least recently used cache entry. Each time a cache item gets used its index is moved to the top of this array. Each a time an item is created, its index is taken from the last object in the array and then moved to the top.
@implementation LRUIndexLinkedList

- (instancetype)initWithCapacity:(NSUInteger)capacity
{
    self = [super init];
    if (self) {
        NSAssert(capacity < 65536, @"Unsupported capacity (%lu). Should be < 65536.", (unsigned long)capacity);
        _capacity = capacity;
        _next = malloc(sizeof(uint16_t)*capacity);
        _prev = malloc(sizeof(uint16_t)*capacity);
        _count = 0;
    }
    return self;
}

- (instancetype)initPrepopulatedWithCapacity:(NSUInteger)capacity
{
    self = [self initWithCapacity:capacity];
    for(NSInteger i = 0; i < capacity; i++) {
        [self getLRUValue];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _next = (uint16_t*)[coder decodeBytesForKey:@"next" returnedLength:nil];
        _prev = (uint16_t*)[coder decodeBytesForKey:@"next" returnedLength:nil];
        _firstNodeIndex = [coder decodeIntForKey:@"firstNodeIndex"];
        _lastNodeIndex = [coder decodeIntForKey:@"lastNodeIndex"];
        _capacity = [coder decodeIntForKey:@"capacity"];
        _count = [coder decodeIntForKey:@"count"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBytes:(void*)_next length:sizeof(uint16_t)*_capacity forKey:@"next"];
    [coder encodeBytes:(void*)_prev length:sizeof(uint16_t)*_capacity forKey:@"prev"];
    [coder encodeInt:_firstNodeIndex forKey:@"firstNodeIndex"];
    [coder encodeInt:_lastNodeIndex forKey:@"lastNodeIndex"];
    [coder encodeInt:_capacity forKey:@"capacity"];
    [coder encodeInt:_count forKey:@"count"];
}

- (NSUInteger)getLRUValue
{
    if (_count < _capacity) {
        uint16_t new_val = _count;
        if (new_val == 0) {
            _firstNodeIndex = new_val;
            _lastNodeIndex = new_val;
        } else {
            // Put the new_val in front.
            _next[new_val] = _firstNodeIndex;
            _prev[_firstNodeIndex] = new_val;
            _firstNodeIndex = new_val;
        }
        _count++;
        return new_val;
    } else {
        return _lastNodeIndex;
    }
}

- (void)markValueAsMRU:(NSUInteger)value
{
    NSAssert(value < _count, @"value (%ld) out of bounds (%d)",(long)value, _count);
    uint16_t nodeIndex = value;
    if (nodeIndex == _firstNodeIndex) {
        return;
    }
    if (nodeIndex == _lastNodeIndex) {
        // We've pulled the last node. No glueing necessary, but we need to update lastNodeIndex to point to the new last node.
        _lastNodeIndex = _prev[_lastNodeIndex];
    } else {
        // Glue up the hole we'll leave
        uint16_t prev_node = _prev[nodeIndex];
        uint16_t next_node = _next[nodeIndex];
        _next[prev_node] = next_node;
        _prev[next_node] = prev_node;
    }

    // Move it into first position
    _prev[_firstNodeIndex] = nodeIndex;
    _next[nodeIndex] = _firstNodeIndex;
    _firstNodeIndex = nodeIndex;
}

// Only used for testing.
- (BOOL)sanityCheck
{
    BOOL ok = true;

    NSMutableIndexSet* foundViaNextChain = [NSMutableIndexSet new];
    NSMutableIndexSet* foundViaPrevChain = [NSMutableIndexSet new];
    NSInteger i = 0;
    NSInteger index = _firstNodeIndex;
    NSInteger lastIndex = -1, firstIndex = -1;
    // Iterate through the chain from the beginning and record the indices we found.
    while (i < _count && i < _capacity) {
        ok &= (![foundViaNextChain containsIndex:index]);
        [foundViaNextChain addIndex:index];
        lastIndex = index;
        index = _next[index];
        i++;
    }
    ok &= (lastIndex == _lastNodeIndex);  // Check that we reached _lastNodeIndex
    
    index = _lastNodeIndex;
    i = 0;
    // Iterate through the chain from the end and record the indices we found.
    while (i < _count && i < _capacity) {
        ok &= (![foundViaPrevChain containsIndex:index]);
        [foundViaPrevChain addIndex:index];
        firstIndex = index;
        index = _prev[index];
        i++;
    }
    ok &= (firstIndex == _firstNodeIndex); // Check that we reached _firstNodeIndex
    
    // Check that we found all indices when following both the next chain and the prev chain.
    // This ensures that we have no holes or loops in the chain.
    for(NSInteger i = 0; i < _count && i < _capacity; i++) {
        ok &= [foundViaNextChain containsIndex:i];
        ok &= [foundViaPrevChain containsIndex:i];
    }
    return ok;
}

- (uint16_t)count {
    return _count;
}

@end
