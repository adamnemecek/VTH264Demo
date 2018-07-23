//
//  AACEncoder.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACEncoder.h"

@interface AACEncoder ()

@property (nonatomic, assign) AudioConverterRef audioConverter;

@end

@implementation AACEncoder

- (void)startEncode:(CMSampleBufferRef)sampleBuffer
{
    char aacData[4096] = {0};
    int aacLen = sizeof(aacData);
    
    if ([self encoderAAC:sampleBuffer aacData:aacData aacLen:&aacLen] == YES)
    {
        NSData *data = [NSData dataWithBytes:aacData length:aacLen];
        if (self.delegate && [self.delegate respondsToSelector:@selector(getEncodedAudioData:)])
        {
            dispatch_async(self.dataCallbackQueue, ^{
                
                [self.delegate getEncodedAudioData:data];
            });
        }
    }
}

- (BOOL)createAudioConvert:(CMSampleBufferRef)sampleBuffer
{
    //根据输入样本初始化一个编码转换器
    if (self.audioConverter != nil)
    {
        return TRUE;
    }
    
    // 输入音频格式
    AudioStreamBasicDescription inputFormat = *(CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)));
    AudioStreamBasicDescription outputFormat; // 这里开始是输出音频格式
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate = inputFormat.mSampleRate; // 采样率保持一致
    outputFormat.mFormatID = kAudioFormatMPEG4AAC; // AAC编码
    outputFormat.mChannelsPerFrame = 2;
    outputFormat.mFramesPerPacket = 1024; // AAC一帧是1024个字节
    
    AudioClassDescription *desc = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    if (AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, desc, &_audioConverter) != noErr)
    {
        NSLog(@"AudioConverterNewSpecific failed");
        return NO;
    }
    
    return YES;
}

- (BOOL)encoderAAC:(CMSampleBufferRef)sampleBuffer aacData:(char *)aacData aacLen:(int *)aacLen
{
    // 编码PCM成AAC
    if ([self createAudioConvert:sampleBuffer] != YES)
    {
        return NO;
    }
    
    CMBlockBufferRef blockBuffer = nil;
    AudioBufferList inBufferList;
    if (CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, &inBufferList, sizeof(inBufferList), NULL, NULL, 0, &blockBuffer) != noErr)
    {
        NSLog(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed");
        return NO;
    }
    
    // 初始化一个输出缓冲列表
    AudioBufferList outBufferList;
    outBufferList.mNumberBuffers = 1;
    outBufferList.mBuffers[0].mNumberChannels = 2;
    outBufferList.mBuffers[0].mDataByteSize = *aacLen; // 设置缓冲区大小
    outBufferList.mBuffers[0].mData = aacData; // 设置AAC缓冲区
    UInt32 outputDataPacketSize = 1;
    if (AudioConverterFillComplexBuffer(self.audioConverter, inputDataProc, &inBufferList, &outputDataPacketSize, &outBufferList, NULL) != noErr)
    {
        NSLog(@"AudioConverterFillComplexBuffer failed");
        return NO;
    }
    
    *aacLen = outBufferList.mBuffers[0].mDataByteSize; //设置编码后的AAC大小
    CFRelease(blockBuffer);
    return YES;
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type fromManufacturer:(UInt32)manufacturer
{
    // 获得相应的编码器
    static AudioClassDescription audioDesc;
    
    UInt32 encoderSpecifier = type, size = 0;
    OSStatus status;
    
    memset(&audioDesc, 0, sizeof(audioDesc));
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    if (status)
    {
        return nil;
    }
    
    uint32_t count = size / sizeof(AudioClassDescription);
    AudioClassDescription descs[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, descs);
    for (uint32_t i = 0; i < count; i++)
    {
        if ((type == descs[i].mSubType) && (manufacturer == descs[i].mManufacturer))
        {
            memcpy(&audioDesc, &descs[i], sizeof(audioDesc));
            break;
        }
    }
    
    return &audioDesc;
}

- (void)endEncode
{
    
}

#pragma - mark - AudioConverterComplexInputDataProc

OSStatus inputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    //AudioConverterFillComplexBuffer 编码过程中，会要求这个函数来填充输入数据，也就是原始PCM数据
    AudioBufferList inBufferList = *(AudioBufferList *)inUserData;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mData = inBufferList.mBuffers[0].mData;
    ioData->mBuffers[0].mDataByteSize = inBufferList.mBuffers[0].mDataByteSize;

    return noErr;
}

@end
