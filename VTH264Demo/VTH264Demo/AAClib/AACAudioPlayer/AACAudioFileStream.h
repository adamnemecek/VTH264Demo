//
//  AACAudioFileStream.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AACParsedAudioData.h"

@class AACAudioFileStream;

@protocol AACAudioFileStreamDelegate <NSObject>

@optional
- (void)audioFileStream:(AACAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData;
- (void)audioFileStreamReadyToProducePackets:(AACAudioFileStream *)audioFileStream;

@end

@interface AACAudioFileStream : NSObject

@property (nonatomic, assign) AudioFileTypeID fileType;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL readyToProducePackets;
@property (nonatomic, weak) id<AACAudioFileStreamDelegate> delegate;
@property (nonatomic, assign) AudioStreamBasicDescription format;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) UInt32 bitRate;
@property (nonatomic, assign) UInt32 maxPacketSize;
@property (nonatomic, assign) UInt64 audioDataByteCount;

- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error;
- (BOOL)parseData:(NSData *)data error:(NSError **)error;
- (SInt64)seekToTime:(NSTimeInterval *)time;
- (NSData *)fetchMagicCookie;
- (void)close;

@end
