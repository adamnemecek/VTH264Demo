//
//  H264ToMp4.m
//  VTToolbox
//
//  Created by MOON on 2018/7/17.
//  Copyright © 2018年 Ganvir, Manish. All rights reserved.
//

#import "H264ToMp4.h"
#import <AVFoundation/AVFoundation.h>
#include <mach/mach_time.h>
#import "NaluHelper.h"
#import "AACHelper.h"

#define AV_W8(p, v) *(p) = (v)

#ifndef AV_WB16
#   define AV_WB16(p, darg) do {                \
unsigned d = (darg);                    \
((uint8_t*)(p))[1] = (d);               \
((uint8_t*)(p))[0] = (d)>>8;            \
} while(0)
#endif

@interface H264ToMp4 ()
{
    CMFormatDescriptionRef videoFormat;
}

@property (nonatomic, strong) NSString *videoFilePath;
@property (nonatomic, strong) NSString *audioFilePath;
@property (nonatomic, strong) NSString *dstFilePath;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoWriteInput;
@property (nonatomic, strong) AVAssetWriterInput *audioWriteInput;
@property (nonatomic, assign) NSUInteger videoFrameIndex;
@property (nonatomic, assign) NSUInteger audioFrameIndex;
@property (nonatomic, assign) BOOL videoProcessFinish;
@property (nonatomic, assign) BOOL audioProcessFinish;
@property (nonatomic, assign) CMTime startTime;
@property (nonatomic, assign) NSUInteger timeScale;
@property (nonatomic, assign) NSUInteger videoFPS;
@property (nonatomic, strong) dispatch_queue_t dataProcesQueue;

@end

@implementation H264ToMp4

- (instancetype)initWithVideoSize:(CGSize)videoSize videoFilePath:(NSString *)videoFilePath dstFilePath:(NSString *)dstFilePath fps:(NSUInteger)fps
{
    if (self = [super init])
    {
        _videoSize = videoSize;
        _videoFilePath = videoFilePath;
        _audioFilePath = nil;
        _dstFilePath = dstFilePath;
        _timeScale = 1000;
        _videoFPS = fps;
        [self initAssetWriter];
    }
    
    return self;
}

- (instancetype)initWithVideoSize:(CGSize)videoSize videoFilePath:(NSString *)videoFilePath audioFilePath:(NSString *)audioFilePath dstFilePath:(NSString *)dstFilePath
{
    if (self = [super init])
    {
        _videoSize = videoSize;
        _videoFilePath = videoFilePath;
        _audioFilePath = audioFilePath;
        _dstFilePath = dstFilePath;
        _timeScale = 1000;
        _videoFPS = 24;
        [self initAssetWriter];
    }
    
    return self;
}

- (void)initAssetWriter
{
    if (!_assetWriter)
    {
        self.dataProcesQueue = dispatch_queue_create("com.pingan.mp4Proces.queue", DISPATCH_QUEUE_SERIAL);
        
        //删除该文件,c语言用法
        unlink([_dstFilePath UTF8String]);
        [[NSFileManager defaultManager] removeItemAtPath:_dstFilePath error:nil];
        NSError *error = nil;
        NSURL *outputUrl = [NSURL fileURLWithPath:_dstFilePath];
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputUrl fileType:AVFileTypeMPEG4 error:&error];
        //使其更适合在网络上播放
        _assetWriter.shouldOptimizeForNetworkUse = YES;
    }
    
    if (self.audioFilePath.length > 0)
    {
        //先获取aac中adts数据，用于创建音频输入
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.audioFilePath];
        NSData *allData = [fileHandle readDataToEndOfFile];
        if (allData.length == 0)
        {
            NSLog(@"找不到aac文件");
            return;
        }
        
        AdtsUnit adtsUnit;
        NSUInteger curPos = 0;
        if ([AACHelper readOneAtdsFromFormatAAC:&adtsUnit data:allData curPos:&curPos])
        {
            [self initAudioInputChannels:adtsUnit.channel samples:adtsUnit.frequencyInHz];
        }
    }
    else
    {
        self.audioProcessFinish = YES;
    }
    
//    NSURL *url = [NSURL fileURLWithPath:self.audioFilePath];
//    NSDictionary *inputOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
//    AVURLAsset *inputAsset = [[AVURLAsset alloc] initWithURL:url options:inputOptions];
//
//    [inputAsset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObject:@"tracks"] completionHandler: ^{
//
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//
//            NSError *error = nil;
//            AVKeyValueStatus tracksStatus = [inputAsset statusOfValueForKey:@"tracks" error:&error];
//            if (tracksStatus != AVKeyValueStatusLoaded)
//            {
//                return;
//            }
//
//            AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:inputAsset error:&error];
//
//            NSArray *audioTracks = [inputAsset tracksWithMediaType:AVMediaTypeAudio];
//
//            AVAssetReaderTrackOutput *readerAudioTrackOutput = nil;
//
//            AVAssetTrack *audioTrack = [audioTracks objectAtIndex:0];
//            NSDictionary *audioOutputSetting = @{AVFormatIDKey: @(kAudioFormatMPEG4AAC)};
//            readerAudioTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:audioOutputSetting];
//            readerAudioTrackOutput.alwaysCopiesSampleData = NO;
//            [assetReader addOutput:readerAudioTrackOutput];
//
//            if ([assetReader startReading] == NO)
//            {
//                NSLog(@"Error reading from file at URL: %@", url);
//                return;
//            }
//
//            CMSampleBufferRef audioSampleBufferRef = [readerAudioTrackOutput copyNextSampleBuffer];
////            if (audioSampleBufferRef)
////            {
//////                [self.audioEncodingTarget processAudioBuffer:audioSampleBufferRef];
////                CFRelease(audioSampleBufferRef);
////                return;
////            }
//
//            _startTime = CMTimeMakeWithSeconds(0, (int32_t)self.timeScale);
//            if ([_assetWriter startWriting])
//            {
//                [_assetWriter startSessionAtSourceTime:_startTime];
//                NSLog(@"H264ToMp4 setup success");
//            }
//            else
//            {
//                NSLog(@"[Error] startWritinge error:%@", _assetWriter.error);
//            }
//
//            if ([_audioWriteInput isReadyForMoreMediaData])
//            {
//                [_audioWriteInput appendSampleBuffer:audioSampleBufferRef];
////                NSLog(@"append audio SampleBuffer frameIndex %@ success", @(decodeFrameCount));
//            }
//            else
//            {
//                NSLog(@"_sampleBuffer isReadyForMoreMediaData NO status:%ld", (long)_assetWriter.status);
//            }
//        });
//    }];
}

- (void)startWriteWithCompletionHandler:(void (^)(void))handler
{
    if (_videoFilePath.length > 0)
    {
        [self startWriteVideoWithCompletionHandler:handler];
    }

    if (_audioFilePath.length > 0)
    {
        [self startWriteAudioWithCompletionHandler:handler];
    }
}

- (void)endWritingCompletionHandler:(void (^)(void))handler
{
    if (!self.audioProcessFinish || !self.videoProcessFinish)
    {
        return;
    }
    
    CMTime time = [self timeWithFrame:_videoFrameIndex];
    
    [_videoWriteInput markAsFinished];
    [_audioWriteInput markAsFinished];
    
    if (!_assetWriter)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (handler)
            {
                handler();
            }
        });
        
        return;
    }
    
    [_assetWriter endSessionAtSourceTime:time];
    [_assetWriter finishWritingWithCompletionHandler:^{
        
        NSLog(@"finishWriting total frame %@ total play time %@", @(_videoFrameIndex), @(_videoFrameIndex * 1.0 / self.videoFPS));
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (handler)
            {
                handler();
            }
        });
    }];
}

#pragma - mark - H264 -> MP4

- (void)startWriteVideoWithCompletionHandler:(void (^)(void))handler
{
    dispatch_async(self.dataProcesQueue, ^{
        
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.videoFilePath];
        NSData *allData = [fileHandle readDataToEndOfFile];
        if (allData.length == 0)
        {
            NSLog(@"找不到h264文件");
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if (handler)
                {
                    handler();
                }
            });
            return;
        }
        
        NaluUnit naluUnit;
        NSData *sps = nil;
        NSData *pps = nil;
        int frame_size = 0;
        NSUInteger curPos = 0;
        NSUInteger frameIndex = 0;
        
        while ([NaluHelper readOneNaluFromAnnexBFormatH264:&naluUnit data:allData curPos:&curPos])
        {
            frameIndex++;
            NSLog(@"naluUnit.type :%d, frameIndex:%@", naluUnit.type, @(frameIndex));
            
            if (naluUnit.type == NAL_SPS || naluUnit.type == NAL_PPS || naluUnit.type == NAL_SEI)
            {
                if (naluUnit.type == NAL_SPS)
                {
                    sps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
                }
                else if (naluUnit.type == NAL_PPS)
                {
                    pps = [NSData dataWithBytes:naluUnit.data length:naluUnit.size];
                }
                
                if (sps && pps)
                {
                    [self initVideoInputWithSPS:sps PPS:pps];
                }
                
                continue;
            }
            
            if (sps == nil || pps == nil)
            {
                continue;
            }
            
            //获取NALUS的长度，开辟内存
            frame_size += naluUnit.size;
            BOOL isIFrame = NO;
            if (naluUnit.type == NAL_SLICE_IDR)
            {
                isIFrame = YES;
            }
            
            frame_size = naluUnit.size + 4;
            uint8_t *frame_data = (uint8_t *)calloc(1, naluUnit.size + 4);//avcc header 占用4个字节
            uint32_t littleLength = CFSwapInt32HostToBig(naluUnit.size);
            uint8_t *lengthAddress = (uint8_t *)&littleLength;
            memcpy(frame_data, lengthAddress, 4);
            memcpy(frame_data + 4, naluUnit.data, naluUnit.size);
            
            NSLog(@"frame_data:%d, %d, %d, %d", *frame_data, *(frame_data + 1), *(frame_data + 3), *(frame_data + 3));
            [self pushH264Data:frame_data length:frame_size isIFrame:isIFrame timeOffset:0];
            free(frame_data);
        }
        
        self.videoProcessFinish = YES;
        [self.videoWriteInput markAsFinished];
        [self endWritingCompletionHandler:handler];
    });
}

- (void)initVideoInputWithSPS:(NSData *)sps PPS:(NSData *)pps
{
    if (!_videoWriteInput)
    {
        NSLog(@"H264ToMp4 setup start");

        const CFStringRef avcCKey = CFSTR("avcC");
        const CFDataRef avcCValue = [self avccExtradataCreate:sps PPS:pps];
        const void *atomDictKeys[] = {avcCKey};
        const void *atomDictValues[] = {avcCValue};
        CFDictionaryRef atomsDict = CFDictionaryCreate(kCFAllocatorDefault, atomDictKeys, atomDictValues, 1, nil, nil);
        
        const void *extensionDictKeys[] = {kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms};
        const void *extensionDictValues[] = {atomsDict};
        CFDictionaryRef extensionDict = CFDictionaryCreate(kCFAllocatorDefault, extensionDictKeys, extensionDictValues, 1, nil, nil);
        
        CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_H264, self.videoSize.width, self.videoSize.height, extensionDict, &videoFormat);
        _videoWriteInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:videoFormat];
        
        if ([_assetWriter canAddInput:_videoWriteInput])
        {
            [_assetWriter addInput:_videoWriteInput];
        }
        else
        {
            NSLog(@"assetWriter cannot add videoWriteInput");
        }
        
        //expectsMediaDataInRealTime = true 必须设为 true，否则，视频会丢帧
        _videoWriteInput.expectsMediaDataInRealTime = YES;
        
        _startTime = CMTimeMakeWithSeconds(0, (int32_t)self.timeScale);
        if ([_assetWriter startWriting])
        {
            [_assetWriter startSessionAtSourceTime:_startTime];
            NSLog(@"H264ToMp4 setup success");
        }
        else
        {
            NSLog(@"[Error] startWritinge error:%@", _assetWriter.error);
        }
    }
}

- (CFDataRef)avccExtradataCreate:(NSData *)sps PPS:(NSData *)pps
{
    CFDataRef data = NULL;
    uint8_t *sps_data = (uint8_t *)[sps bytes];
    uint8_t *pps_data = (uint8_t *)[pps bytes];
    int sps_data_size = (int)sps.length;
    int pps_data_size = (int)pps.length;
    uint8_t *p;
    int extradata_size = 6 + 2 + sps_data_size + 3 + pps_data_size;
    uint8_t *extradata = calloc(1, extradata_size);
    if (!extradata)
    {
        return NULL;
    }
    
    p = extradata;
    
    AV_W8(p + 0, 1); /* version */
    AV_W8(p + 1, sps_data[1]); /* profile */
    AV_W8(p + 2, sps_data[2]); /* profile compat */
    AV_W8(p + 3, sps_data[3]); /* level */
    AV_W8(p + 4, 0xff); /* 6 bits reserved (111111) + 2 bits nal size length - 3 (11) */
    AV_W8(p + 5, 0xe1); /* 3 bits reserved (111) + 5 bits number of sps (00001) */
    AV_WB16(p + 6, sps_data_size);
    memcpy(p + 8, sps_data, sps_data_size);
    p += 8 + sps_data_size;
    AV_W8(p + 0, 1); /* number of pps */
    AV_WB16(p + 1, pps_data_size);
    memcpy(p + 3, pps_data, pps_data_size);
    
    p += 3 + pps_data_size;
    assert(p - extradata == extradata_size);
    
    data = CFDataCreate(kCFAllocatorDefault, extradata, extradata_size);
    free(extradata);
    
    return data;
}

- (void)pushH264Data:(unsigned char *)dataBuffer length:(uint32_t)len isIFrame:(BOOL)isIFrame timeOffset:(int64_t)timestamp
{
    if (_assetWriter.status == AVAssetWriterStatusUnknown)
    {
        NSLog(@"_assetWriter status not ready");
        return;
    }
    
    NSData *h264Data = [NSData dataWithBytes:dataBuffer length:len];
    CMSampleBufferRef h264Sample = [self sampleBufferWithData:h264Data formatDescriptor:videoFormat];
    if ([_videoWriteInput isReadyForMoreMediaData])
    {
        [_videoWriteInput appendSampleBuffer:h264Sample];
        NSLog(@"append video SampleBuffer frameIndex %@ success", @(_videoFrameIndex));
    }
    else
    {
        NSLog(@"_videoWriteInput isReadyForMoreMediaData NO status:%ld", (long)_assetWriter.status);
    }
    
    CFRelease(h264Sample);
}

- (CMSampleBufferRef)sampleBufferWithData:(NSData*)data formatDescriptor:(CMFormatDescriptionRef)formatDescription
{
    OSStatus result;
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    size_t data_len = data.length;

    if (!blockBuffer)
    {
        size_t blockLength = 100 * 1024;
        result = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, blockLength, kCFAllocatorDefault, NULL, 0, data_len, kCMBlockBufferAssureMemoryNowFlag, &blockBuffer);
    }
    
    result = CMBlockBufferReplaceDataBytes([data bytes], blockBuffer, 0, [data length]);
    
    const size_t sampleSizes[] = {[data length]};
    CMTime pts = [self timeWithFrame:_videoFrameIndex];

    CMSampleTimingInfo timeInfoArray[1] = {{
        .presentationTimeStamp = pts,
        .duration = CMTimeMakeWithSeconds(1.0 / self.videoFPS, (int32_t)self.timeScale),
        .decodeTimeStamp = kCMTimeInvalid
    }};
    
    result = CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, YES, NULL, NULL, formatDescription, 1, 1, timeInfoArray, 1, sampleSizes, &sampleBuffer);
    if (result != noErr)
    {
        NSLog(@"CMSampleBufferCreate result:%d", (int)result);
        return NULL;
    }

    _videoFrameIndex++;
    
    return sampleBuffer;
}

- (CMTime)timeWithFrame:(NSUInteger)frameIndex
{
    CMTime pts = CMTimeMakeWithSeconds(CMTimeGetSeconds(_startTime) + (1.0 / self.videoFPS) * _videoFrameIndex, (int32_t)self.timeScale);

    NSLog(@"timeWithFrame %@ timing pts value %@ pts timescale %@", @(frameIndex), @(pts.value), @(pts.timescale));
    
    return pts;
}

#pragma - mark - AAC -> MP4

- (void)startWriteAudioWithCompletionHandler:(void (^)(void))handler
{
    dispatch_async(self.dataProcesQueue, ^{
        
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.audioFilePath];
        NSData *allData = [fileHandle readDataToEndOfFile];
        if (allData.length == 0)
        {
            NSLog(@"找不到aac文件");
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if (handler)
                {
                    handler();
                }
            });
            return;
        }
        
        AdtsUnit adtsUnit;
        NSUInteger curPos = 0;
        NSUInteger decodeFrameCount = 0;
        
        while ([AACHelper readOneAtdsFromFormatAAC:&adtsUnit data:allData curPos:&curPos])
        {
            decodeFrameCount++;
            NSLog(@"aacdata frameIndex:%@", @(decodeFrameCount));
            
            AudioStreamBasicDescription audioFormat;
            audioFormat.mSampleRate = adtsUnit.frequencyInHz;
            audioFormat.mFormatID = kAudioFormatMPEG4AAC;
            audioFormat.mFormatFlags = adtsUnit.profile;
            audioFormat.mBytesPerPacket = 0;
            audioFormat.mFramesPerPacket = 1024;
            audioFormat.mBytesPerFrame = 0;
            audioFormat.mChannelsPerFrame = adtsUnit.channel;
            audioFormat.mBitsPerChannel = 0;
            audioFormat.mReserved = 0;
            
            CMFormatDescriptionRef format = NULL;
            OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &audioFormat, 0, nil, 0, nil, nil, &format);
            
            CMBlockBufferRef frameBuffer;
            status = CMBlockBufferCreateWithMemoryBlock(NULL, (void *)adtsUnit.data, adtsUnit.size, kCFAllocatorNull, NULL, 0, adtsUnit.size, 0, &frameBuffer);
            
            CMSampleTimingInfo timing = {CMTimeMake(1, adtsUnit.frequencyInHz), kCMTimeZero, kCMTimeInvalid};
            
            CMSampleBufferRef sampleBuffer = NULL;
            const size_t sampleSizes[] = {adtsUnit.size};
            
            status = CMSampleBufferCreate(kCFAllocatorDefault, frameBuffer, false, NULL, NULL, format, 1, 1, &timing, 0, sampleSizes, &sampleBuffer);
            if (status)
            {
                NSLog(@"CMSampleBufferCreate status %@", @(status));
            }
        
            if ([_audioWriteInput isReadyForMoreMediaData])
            {
                [_audioWriteInput appendSampleBuffer:sampleBuffer];
                NSLog(@"append audio SampleBuffer frameIndex %@ success", @(decodeFrameCount));
            }
            else
            {
                NSLog(@"_audioWriteInput isReadyForMoreMediaData NO status:%ld", (long)_assetWriter.status);
            }

            CFRelease(sampleBuffer);
        }
        
        self.audioProcessFinish = YES;
        [self.audioWriteInput markAsFinished];
        [self endWritingCompletionHandler:handler];
    });
}

- (void)initAudioInputChannels:(int)ch samples:(Float64)rate
{
    if (!_audioWriteInput)
    {
        //音频的一些配置包括音频各种这里为AAC, 音频通道、采样率和音频的比特率
        AudioChannelLayout acl;
        memset(&acl, 0, sizeof(acl));
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
        if (ch == 2)
        {
            acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
        }
        
        NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt: kAudioFormatMPEG4AAC], AVFormatIDKey, [NSNumber numberWithInt: ch], AVNumberOfChannelsKey, [NSNumber numberWithFloat: rate], AVSampleRateKey, [NSNumber numberWithInt: 64000], AVEncoderBitRateKey, [ NSData dataWithBytes:&acl length: sizeof(acl)], AVChannelLayoutKey, nil];
        //初始化音频写入类
        _audioWriteInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:settings];

        //表明输入是否应该调整其处理为实时数据源的数据
        _audioWriteInput.expectsMediaDataInRealTime = YES;

        if ([_assetWriter canAddInput:_audioWriteInput])
        {
            [_assetWriter addInput:_audioWriteInput];
        }
        else
        {
            NSLog(@"assetWriter cannot add audioWriteInput");
        }
    }
}

@end
