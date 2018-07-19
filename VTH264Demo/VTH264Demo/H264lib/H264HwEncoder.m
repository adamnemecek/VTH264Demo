//
//  H264HwEncoder.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "H264HwEncoder.h"

@interface H264HwEncoder ()
{
    VTCompressionSessionRef encodingSession;
}

@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, strong) NSData *sps;
@property (nonatomic, strong) NSData *pps;

@end

@implementation H264HwEncoder

- (void)initWithConfiguration
{    
    encodingSession = nil;
    self.frameCount = 0;
    self.sps = nil;
    self.pps = nil;
}

- (void)initEncode:(int)width height:(int)height
{
    OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self), &encodingSession);
    if (status != 0)
    {
        NSLog(@"Error by VTCompressionSessionCreate");
        return ;
    }
    
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    
    //越高效果越好, 帧数据越大
    SInt32 bitRate = width * height * 50;
    CFNumberRef ref = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AverageBitRate, ref);
    CFRelease(ref);

    //关键帧间隔, 越低效果越好, 帧数据越大
    int frameInterval = 10;
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    CFRelease(frameIntervalRef);
    
    VTCompressionSessionPrepareToEncodeFrames(encodingSession);
}

- (void)startEncode:(CMSampleBufferRef)sampleBuffer
{
    if (encodingSession == nil)
    {
        return;
    }

    self.frameCount++;
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    CMTime presentationTimeStamp = CMTimeMake(self.frameCount, 1000);
    
    //硬编码系统缺省都是异步执行
    VTEncodeInfoFlags flags;
    OSStatus statusCode = VTCompressionSessionEncodeFrame(encodingSession, imageBuffer, presentationTimeStamp, kCMTimeInvalid, NULL, NULL, &flags);
    if (statusCode != noErr)
    {
        [self endEncode];
    }
}

- (void)endEncode
{
    if (encodingSession)
    {
        VTCompressionSessionInvalidate(encodingSession);
        CFRelease(encodingSession);
        encodingSession = nil;
        return;
    }
}

#pragma - mark - VTCompressionOutputCallback

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
    if (status != noErr || !sampleBuffer)
    {
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready");
        return;
    }
    
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if (!array)
    {
        return;
    }
    
    CFDictionaryRef dic = (CFDictionaryRef)CFArrayGetValueAtIndex(array, 0);
    if (!dic)
    {
        return;
    }
    
    NSLog(@"\r\n%@", dic);

    H264HwEncoder *encoder = (__bridge H264HwEncoder *)outputCallbackRefCon;
    
    BOOL keyframe = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0);
        if (statusCode == noErr)
        {
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0);
            if (statusCode == noErr)
            {
                encoder.sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                encoder.pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder.delegate && [encoder.delegate respondsToSelector:@selector(getSpsPps:pps:)])
                {
                    dispatch_async(encoder.dataCallbackQueue, ^{
                        
                        [encoder.delegate getSpsPps:encoder.sps pps:encoder.pps];
                    });
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr)
    {
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength)
        {
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            NSData *data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            if (encoder.delegate && [encoder.delegate respondsToSelector:@selector(getEncodedData:isKeyFrame:)])
            {
                dispatch_async(encoder.dataCallbackQueue, ^{
                    
                    [encoder.delegate getEncodedData:data isKeyFrame:keyframe];
                });
            }
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

@end
