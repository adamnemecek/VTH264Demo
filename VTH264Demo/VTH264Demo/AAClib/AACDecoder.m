//
//  AACDecoder.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACDecoder.h"

typedef struct _passthroughUserData
{
    UInt32 mChannels;
    UInt32 mDataSize;
    const void *mData;
    AudioStreamPacketDescription mPacket;
} PassthroughUserData;

@interface AACDecoder ()

@property (nonatomic, assign) AudioConverterRef audioConverter;

@end

@implementation AACDecoder

- (BOOL)createAudioConvert:(AdtsUnit)adtsUnit
{
    // 根据输入样本初始化一个编码转换器
    if (self.audioConverter != nil)
    {
        return TRUE;
    }

    // 输入音频格式
    AudioStreamBasicDescription inputFormat;
    memset(&inputFormat, 0, sizeof(inputFormat));
    inputFormat.mSampleRate = adtsUnit.frequencyInHz;
    inputFormat.mFormatID = kAudioFormatMPEG4AAC;
    inputFormat.mFormatFlags = adtsUnit.profile;
    inputFormat.mBytesPerPacket = 0;
    inputFormat.mFramesPerPacket = 1024;
    inputFormat.mBytesPerFrame = 0;
    inputFormat.mChannelsPerFrame = adtsUnit.channel;
    inputFormat.mBitsPerChannel = 0;
    inputFormat.mReserved = 0;
    
    // 这里开始是输出音频格式
    AudioStreamBasicDescription outputFormat;
    memset(&outputFormat, 0, sizeof(outputFormat));
    outputFormat.mSampleRate = inputFormat.mSampleRate; // 采样率保持一致
    outputFormat.mFormatID = kAudioFormatLinearPCM; // PCM编码
    outputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    outputFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame; // 1:单声道；2:立体声
    outputFormat.mFramesPerPacket = 1;
    outputFormat.mBitsPerChannel = 16;
    outputFormat.mBytesPerFrame = outputFormat.mBitsPerChannel / 8 * outputFormat.mChannelsPerFrame;
    outputFormat.mBytesPerPacket = outputFormat.mBytesPerFrame * outputFormat.mFramesPerPacket;
    outputFormat.mReserved = 0;
    
    // 硬编码
    AudioClassDescription *desc = [self getAudioClassDescriptionWithType:kAudioFormatLinearPCM fromManufacturer:kAppleHardwareAudioCodecManufacturer];
    OSStatus result = AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, desc, &_audioConverter);
    if (result != noErr)
    {
        NSLog(@"AudioConverterNewSpecific failed %@", @(result));
        return NO;
    }

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

- (CMSampleBufferRef)startDecode:(AdtsUnit)adtsUnit
{
    if (!_audioConverter)
    {
        [self createAudioConvert:adtsUnit];
    }

    //AAC需要先解码还原到PCM才能创建CMSampleBufferRef
    PassthroughUserData userData = {1, adtsUnit.size, adtsUnit.data};
    NSMutableData *decodedData = [NSMutableData new];
    
    const uint32_t MAX_AUDIO_FRAMES = 128;
    const uint32_t maxDecodedSamples = MAX_AUDIO_FRAMES * 1;
    
    do
    {
        uint8_t *buffer = (uint8_t *)malloc(maxDecodedSamples * sizeof(short int));
        AudioBufferList decBuffer;
        decBuffer.mNumberBuffers = 1;
        decBuffer.mBuffers[0].mNumberChannels = adtsUnit.channel;
        decBuffer.mBuffers[0].mDataByteSize = maxDecodedSamples * sizeof(short int);
        decBuffer.mBuffers[0].mData = buffer;
        
        UInt32 numFrames = MAX_AUDIO_FRAMES;
        
        AudioStreamPacketDescription outPacketDescription;
        memset(&outPacketDescription, 0, sizeof(AudioStreamPacketDescription));
        outPacketDescription.mDataByteSize = MAX_AUDIO_FRAMES;
        outPacketDescription.mStartOffset = 0;
        outPacketDescription.mVariableFramesInPacket = 0;
        
        OSStatus rv = AudioConverterFillComplexBuffer(_audioConverter, inputInDataProc, &userData, &numFrames, &decBuffer, &outPacketDescription);
        if (rv && rv != noErr)
        {
            NSLog(@"Error decoding audio stream: %d\n", rv);
            break;
        }
        
        if (numFrames)
        {
            [decodedData appendBytes:decBuffer.mBuffers[0].mData length:decBuffer.mBuffers[0].mDataByteSize];
        }
        
        if (rv == noErr)
        {
            break;
        }
        
    } while (true);

    AudioStreamBasicDescription audioFormat;
    memset(&audioFormat, 0, sizeof(audioFormat));
    audioFormat.mSampleRate = adtsUnit.frequencyInHz; // 采样率保持一致
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    audioFormat.mChannelsPerFrame = adtsUnit.channel; // 1:单声道；2:立体声
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerFrame = audioFormat.mBitsPerChannel / 8 * audioFormat.mChannelsPerFrame;
    audioFormat.mBytesPerPacket = audioFormat.mBytesPerFrame * audioFormat.mFramesPerPacket;
    audioFormat.mReserved = 0;
    
    CMFormatDescriptionRef format = NULL;
    OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &audioFormat, 0, nil, 0, nil, nil, &format);
    
    CMBlockBufferRef frameBuffer;
    status = CMBlockBufferCreateWithMemoryBlock(NULL, (void *)[decodedData bytes], decodedData.length, kCFAllocatorNull, NULL, 0, decodedData.length, 0, &frameBuffer);
    
    CMSampleTimingInfo timing = {CMTimeMake(1, audioFormat.mSampleRate), kCMTimeZero, kCMTimeInvalid};
    
    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSizes[] = {decodedData.length};
    
    status = CMSampleBufferCreate(kCFAllocatorDefault, frameBuffer, false, NULL, NULL, format, 1, 1, &timing, 0, sampleSizes, &sampleBuffer);
    if (status)
    {
        NSLog(@"CMSampleBufferCreate status %@", @(status));
    }

//    if (self.delegate && [self.delegate respondsToSelector:@selector(getDecodedAudioData:)])
//    {
//        dispatch_async(self.dataCallbackQueue, ^{
//
//            [self.delegate getDecodedAudioData:sampleBuffer];
//        });
//    }
    
    return sampleBuffer;
}

- (void)endDecode
{
    self.audioConverter = nil;
}

#pragma - mark - AudioConverterComplexInputDataProc

OSStatus inputInDataProc(AudioConverterRef aAudioConverter, UInt32 *aNumDataPackets, AudioBufferList *aData, AudioStreamPacketDescription **aPacketDesc, void *aUserData)
{
    PassthroughUserData *userData = (PassthroughUserData *)aUserData;
    if (!userData->mDataSize)
    {
        *aNumDataPackets = 0;
        return noErr;
    }
    
    if (aPacketDesc)
    {
        userData->mPacket.mStartOffset = 0;
        userData->mPacket.mVariableFramesInPacket = 0;
        userData->mPacket.mDataByteSize = userData->mDataSize;
        *aPacketDesc = &userData->mPacket;
    }
    
    aData->mBuffers[0].mNumberChannels = userData->mChannels;
    aData->mBuffers[0].mDataByteSize = userData->mDataSize;
    aData->mBuffers[0].mData = (void *)(userData->mData);
    
    // No more data to provide following this run.
    userData->mDataSize = 0;
    
    return noErr;
}

@end
