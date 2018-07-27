//
//  AACAudioOutputQueue.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface AACAudioOutputQueue : NSObject

@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) AudioStreamBasicDescription format;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSTimeInterval playedTime;

- (instancetype)initWithFormat:(AudioStreamBasicDescription)format bufferSize:(UInt32)bufferSize macgicCookie:(NSData *)macgicCookie;

- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof;

- (BOOL)pause;
- (BOOL)resume;
- (BOOL)stop:(BOOL)immediately;
- (BOOL)reset;
- (BOOL)flush;

- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError **)outError;
- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError **)outError;
- (BOOL)setParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue)value error:(NSError **)outError;
- (BOOL)getParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue *)value error:(NSError **)outError;

@end
