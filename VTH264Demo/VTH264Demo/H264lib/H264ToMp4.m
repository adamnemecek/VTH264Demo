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

@property (nonatomic, strong) NSString *srcFilePath;
@property (nonatomic, strong) NSString *dstFilePath;
@property (nonatomic, assign) CGSize videoSize;
@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoWriteInput;
@property (nonatomic, assign) CMTime startTime;
@property (nonatomic, assign) int frameIndex;

@end

const int32_t TIME_SCALE = 1000000000l;    // 1s = 1e10^9 ns
const int32_t fps = 25;

@implementation H264ToMp4

- (instancetype)initWithVideoSize:(CGSize)videoSize srcFilePath:(NSString *)srcFilePath dstFilePath:(NSString *)dstFilePath
{
    if (self = [super init])
    {
        _videoSize = videoSize;
        _srcFilePath = srcFilePath;
        _dstFilePath = dstFilePath;
    }
    
    return self;
}

- (void)startWriteWithCompletionHandler:(void (^)(void))handler
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.srcFilePath];
        NSData *allData = [fileHandle readDataToEndOfFile];
        if (allData.length == 0)
        {
            NSLog(@"找不到mp4文件");
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
                    [self setupWithSPS:sps PPS:pps];
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
        
        [self endWritingCompletionHandler:handler];
    });
}

- (void)setupWithSPS:(NSData *)sps PPS:(NSData *)pps
{
    NSLog(@"H264ToMp4 setup start");
    
    unlink([_dstFilePath UTF8String]);//删除该文件,c语言用法
    [[NSFileManager defaultManager] removeItemAtPath:_dstFilePath error:nil];
    NSError *error = nil;
    NSURL *outputUrl = [NSURL fileURLWithPath:_dstFilePath];
    _assetWriter = [[AVAssetWriter alloc] initWithURL:outputUrl fileType:AVFileTypeMPEG4 error:&error];

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
    
    //expectsMediaDataInRealTime = true 必须设为 true，否则，视频会丢帧
    _videoWriteInput.expectsMediaDataInRealTime = YES;
    _startTime = CMTimeMake(0, TIME_SCALE);
    if ([_assetWriter startWriting])
    {
        [_assetWriter startSessionAtSourceTime:_startTime];
        NSLog(@"H264ToMp4 setup success");
    }
    else
    {
        NSLog(@"[Error] startWritinge error:%@", _assetWriter.error);
    };
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
        NSLog(@"appendSampleBuffer frameIndex %@ success", @(_frameIndex));
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
    CMTime pts = [self timeWithFrame:_frameIndex];
    
    CMSampleTimingInfo timeInfoArray[1] = { {
        .duration = CMTimeMake(0, 0),
        .presentationTimeStamp = pts,
        .decodeTimeStamp = CMTimeMake(0, 0),
    } };
    
    result = CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, YES, NULL, NULL, formatDescription, 1, 1, timeInfoArray, 1, sampleSizes, &sampleBuffer);
    if (result != noErr)
    {
        NSLog(@"CMSampleBufferCreate result:%d", (int)result);
        return NULL;
    }

    _frameIndex++;
    
    return sampleBuffer;
}

- (void)endWritingCompletionHandler:(void (^)(void))handler
{
    CMTime time = [self timeWithFrame:_frameIndex];
    [_videoWriteInput markAsFinished];
    
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
        
        NSLog(@"finishWriting");
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (handler)
            {
                handler();
            }
        });        
    }];
}

- (CMTime)timeWithFrame:(int)frameIndex
{
    int64_t pts = (frameIndex * (1000.0 / 40)) * (TIME_SCALE / 1000);
    CMTime time = CMTimeMake(pts, TIME_SCALE);
    
    NSLog(@"frameIndex %@, pts %@", @(frameIndex), @(pts));
    
    return time;
}

@end
