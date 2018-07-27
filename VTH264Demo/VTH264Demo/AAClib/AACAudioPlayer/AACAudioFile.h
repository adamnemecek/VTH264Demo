//
//  AACAudioFile.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AACParsedAudioData.h"

@interface AACAudioFile : NSObject

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) AudioFileTypeID fileType;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) AudioStreamBasicDescription format;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) UInt32 bitRate;
@property (nonatomic, assign) UInt32 maxPacketSize;
@property (nonatomic, assign) UInt64 audioDataByteCount;

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType;
- (NSArray *)parseData:(BOOL *)isEof;
- (NSData *)fetchMagicCookie;
- (void)seekToTime:(NSTimeInterval)time;
- (void)close;

@end
