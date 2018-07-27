//
//  AACAudioPlayer.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioFile.h>

typedef NS_ENUM(NSUInteger, AACAPStatus)
{
    AACAPStatusStopped = 0,
    AACAPStatusPlaying = 1,
    AACAPStatusWaiting = 2,
    AACAPStatusPaused = 3,
    AACAPStatusFlushing = 4,
};

@interface AACAudioPlayer : NSObject

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) AudioFileTypeID fileType;
@property (nonatomic, assign) AACAPStatus status;
@property (nonatomic, assign) BOOL isPlayingOrWaiting;
@property (nonatomic, assign) BOOL failed;
@property (nonatomic, assign) NSTimeInterval progress;
@property (nonatomic, assign) NSTimeInterval duration;

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType;
- (void)play;
- (void)pause;
- (void)stop;

@end
