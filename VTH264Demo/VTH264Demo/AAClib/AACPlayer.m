//
//  AACPlayer.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

#define CONST_BUFFER_COUNT      3               //缓冲区个数
#define CONST_BUFFER_SIZE       0x10000

@interface AACPlayer ()
{
    AudioFileID audioFileID;
    AudioStreamBasicDescription audioStreamBasicDescrpition;
    AudioStreamPacketDescription *audioStreamPacketDescrption;
    AudioQueueRef audioQueue;
    AudioQueueBufferRef audioBuffers[CONST_BUFFER_COUNT];
    SInt64 readedPacket;
    u_int32_t packetNums;
}

@property (nonatomic, strong) NSString *filePath;

@end

@implementation AACPlayer

- (instancetype)initWithFile:(NSString *)filePath
{
    if (self = [super init])
    {
        _filePath = filePath;
        [self customAudioConfig];
        return self;
    }
    
    return nil;
}

- (void)customAudioConfig
{
    NSURL *url = [NSURL fileURLWithPath:_filePath];
    
    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID);
    if (status != noErr)
    {
        NSLog(@"打开文件失败 %@", url);
        return;
    }
    
    uint32_t size = sizeof(audioStreamBasicDescrpition);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioStreamBasicDescrpition);
    if (status != noErr)
    {
        NSLog(@"Get Property status = %@", @(status));
        return;
    }

    status = AudioQueueNewOutput(&audioStreamBasicDescrpition, bufferReady, (__bridge void * _Nullable)(self), NULL, NULL, 0, &audioQueue);
    if (status != noErr)
    {
        NSLog(@"New Queue status = %@", @(status));
        return;
    }
    
    if (audioStreamBasicDescrpition.mBytesPerPacket == 0
        || audioStreamBasicDescrpition.mFramesPerPacket == 0)
    {
        uint32_t maxSize;
        size = sizeof(maxSize);
        AudioFileGetProperty(audioFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &maxSize);
        if (maxSize > CONST_BUFFER_SIZE)
        {
            maxSize = CONST_BUFFER_SIZE;
        }
        
        packetNums = CONST_BUFFER_SIZE / maxSize;
        NSLog(@"packetNums %@", @(packetNums));
        audioStreamPacketDescrption = malloc(sizeof(AudioStreamPacketDescription) * packetNums);
    }
    else
    {
        packetNums = CONST_BUFFER_SIZE / audioStreamBasicDescrpition.mBytesPerPacket;
        audioStreamPacketDescrption = nil;
    }
    
    char cookies[100] = {0};
    memset(cookies, 0, sizeof(cookies));
    
    // 这里的100 有问题
    AudioFileGetProperty(audioFileID, kAudioFilePropertyMagicCookieData, &size, cookies);
    if (size > 0)
    {
        AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookies, size);
    }
    
    AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, propertyListener, (__bridge void * _Nullable)(self));
    
    readedPacket = 0;
    for (int i = 0; i < CONST_BUFFER_COUNT; ++i)
    {
        AudioQueueAllocateBuffer(audioQueue, CONST_BUFFER_SIZE, &audioBuffers[i]);
        if ([self fillBuffer:audioBuffers[i]])
        {
            // full
            break;
        }
        
        NSLog(@"buffer %d full", i);
    }
    
    UInt32 value = kAudioQueueHardwareCodecPolicy_UseHardwareOnly;
    status = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_HardwareCodecPolicy, &value, sizeof(value));
    if (status != noErr)
    {
        NSLog(@"hardware code not use");
    }
}

- (void)play
{
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    AudioQueueStart(audioQueue, NULL);
}

- (void)stop
{
    AudioQueueStop(audioQueue, NO);
}

- (BOOL)fillBuffer:(AudioQueueBufferRef)buffer
{
    BOOL full = NO;
    uint32_t bytes = 0, packets = (uint32_t)packetNums;
    OSStatus status = AudioFileReadPackets(audioFileID, NO, &bytes, audioStreamPacketDescrption, readedPacket, &packets, buffer->mAudioData);
    if (status != noErr)
    {
        NSLog(@"New Queue status = %@", @(status));
        return full;
    }

    if (packets > 0)
    {
        buffer->mAudioDataByteSize = bytes;
        status = AudioQueueEnqueueBuffer(audioQueue, buffer, packets, audioStreamPacketDescrption);
        if (status != noErr)
        {
            NSLog(@"En Queue buffer status = %@", @(status));
        }
        readedPacket += packets;
    }
    else
    {
        AudioQueueStop(audioQueue, NO);
        full = YES;
    }
    
    return full;
}

- (Float64)getCurrentTime
{
    Float64 timeInterval = 0.0;
    if (audioQueue)
    {
        AudioQueueTimelineRef timeLine;
        AudioTimeStamp timeStamp;
        OSStatus status = AudioQueueCreateTimeline(audioQueue, &timeLine);
        if (status == noErr)
        {
            AudioQueueGetCurrentTime(audioQueue, timeLine, &timeStamp, NULL);
            timeInterval = timeStamp.mSampleTime * 1000000 / audioStreamBasicDescrpition.mSampleRate;
        }
    }
    
    return timeInterval;
}

#pragma - mark - AudioQueuePropertyListenerProc

void propertyListener(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    NSLog(@"propertyListener inID %@", @(inID));
    
    AACPlayer *player = (__bridge AACPlayer *)inUserData;
    if (!player)
    {
        NSLog(@"propertyListener player nil");
        return;
    }
}

#pragma - mark - AudioQueueOutputCallback

void bufferReady(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef buffer)
{
    NSLog(@"bufferReady refresh buffer");
    
    AACPlayer *player = (__bridge AACPlayer *)inUserData;
    if (!player)
    {
        NSLog(@"bufferReady player nil");
        return;
    }
    
    if ([player fillBuffer:buffer])
    {
        NSLog(@"bufferReady play end");
    }
}

@end
