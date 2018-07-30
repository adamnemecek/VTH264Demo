//
//  AACAudioFileStream.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACAudioFileStream.h"

#define BitRateEstimationMaxPackets         5000
#define BitRateEstimationMinPackets         10

@interface AACAudioFileStream ()

@property (nonatomic, assign) BOOL discontinuous;
@property (nonatomic, assign) AudioFileStreamID audioFileStreamID;
@property (nonatomic, assign) SInt64 dataOffset;
@property (nonatomic, assign) NSTimeInterval packetDuration;
@property (nonatomic, assign) UInt64 processedPacketsCount;
@property (nonatomic, assign) UInt64 processedPacketsSizeTotal;

@end

@implementation AACAudioFileStream

#pragma - init & dealloc

- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error
{
    self  = [super init];
    if (self)
    {
        _discontinuous = NO;
        _fileType = fileType;
        _fileSize = fileSize;
        [self openAudioFileStreamWithFileTypeHint:_fileType error:error];
    }
    
    return self;
}

- (void)dealloc
{
    [self closeAudioFileStream];
}

- (void)errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL)
    {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"errorForOSStatus %@", *outError);
    }
}

#pragma - mark - open & close

- (BOOL)openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint error:(NSError *__autoreleasing *)error
{
    OSStatus status = AudioFileStreamOpen((__bridge void *)self, AACAudioFileStreamPropertyListener, AACAudioFileStreamPacketsCallBack, fileTypeHint, &_audioFileStreamID);
    if (status != noErr)
    {
        _audioFileStreamID = NULL;
    }
    
    NSLog(@"AudioFileStreamOpen status %@", @(status));
    
    [self errorForOSStatus:status error:error];
    
    return status == noErr;
}

- (void)closeAudioFileStream
{
    if (self.available)
    {
        AudioFileStreamClose(_audioFileStreamID);
        _audioFileStreamID = NULL;
    }
}

- (void)close
{
    [self closeAudioFileStream];
}

- (BOOL)available
{
    return _audioFileStreamID != NULL;
}

#pragma - mark - actions

- (NSData *)fetchMagicCookie
{
    UInt32 cookieSize;
	Boolean writable;
	OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
	if (status != noErr)
	{
		return nil;
	}
    
	void *cookieData = malloc(cookieSize);
	status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
	if (status != noErr)
	{
		return nil;
	}
    
    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);
    
    return cookie;
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error
{
    if (self.readyToProducePackets && _packetDuration == 0)
    {
        [self errorForOSStatus:-1 error:error];
        return NO;
    }
    
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)[data length], [data bytes], _discontinuous ? kAudioFileStreamParseFlag_Discontinuity : 0);
    [self errorForOSStatus:status error:error];
    
    return status == noErr;
}

- (SInt64)seekToTime:(NSTimeInterval *)time
{
    SInt64 approximateSeekOffset = _dataOffset + (*time / _duration) * _audioDataByteCount;
    SInt64 seekToPacket = floor(*time / _packetDuration);
    SInt64 seekByteOffset;
    UInt32 ioFlags = 0;
    SInt64 outDataByteOffset;
    OSStatus status = AudioFileStreamSeek(_audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
    if (status == noErr && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated))
    {
        *time -= ((approximateSeekOffset - _dataOffset) - outDataByteOffset) * 8.0 / _bitRate;
        seekByteOffset = outDataByteOffset + _dataOffset;
    }
    else
    {
        _discontinuous = YES;
        seekByteOffset = approximateSeekOffset;
    }
    
    return seekByteOffset;
}

#pragma - mark - callbacks

- (void)calculateBitRate
{
    if (_packetDuration && _processedPacketsCount > BitRateEstimationMinPackets
        && _processedPacketsCount <= BitRateEstimationMaxPackets)
    {
        double averagePacketByteSize = _processedPacketsSizeTotal / _processedPacketsCount;
        _bitRate = 8.0 * averagePacketByteSize / _packetDuration;
        NSLog(@"calculateBitRate %@", @(_bitRate));
    }
}

- (void)calculateDuration
{
    if (_fileSize > 0 && _bitRate > 0)
    {
        _duration = ((_fileSize - _dataOffset) * 8.0) / _bitRate;
        NSLog(@"calculateDuration %@", @(_duration));
    }
}

- (void)calculatepPacketDuration
{
    if (_format.mSampleRate > 0)
    {
        _packetDuration = _format.mFramesPerPacket / _format.mSampleRate;
        NSLog(@"calculatepPacketDuration %@ ms", @(_packetDuration * 1000));
    }
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    if (propertyID == kAudioFileStreamProperty_BitRate)
    {
        // 表示音频数据的码率，获取这个Property是为了计算音频的总时长Duration（因为AudioFileStream没有这样的接口)
        UInt32 bitRate;
        UInt32 bitRateSize = sizeof(bitRate);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_BitRate, &bitRateSize, &bitRate);
        if (status != noErr)
        {
            //错误处理
        }
        
        NSLog(@"kAudioFileStreamProperty_BitRate %@", @(bitRate));
    }
    else if (propertyID == kAudioFileStreamProperty_AudioDataByteCount)
    {
        // 音频文件中音频数据的总量。这个Property的作用一是用来计算音频的总时长，二是可以在seek时用来计算时间对应的字节offset。
        UInt64 audioDataByteCount;
        UInt32 byteCountSize = sizeof(audioDataByteCount);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
        if (status != noErr)
        {
            //错误处理
        }
        
        NSLog(@"kAudioFileStreamProperty_AudioDataByteCount %@", @(audioDataByteCount));
    }
    else if (propertyID == kAudioFileStreamProperty_AudioDataPacketCount)
    {
        UInt64 audioDataPacketCount;
        UInt32 byteCountSize = sizeof(audioDataPacketCount);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_AudioDataPacketCount, &byteCountSize, &audioDataPacketCount);
        if (status != noErr)
        {
            //错误处理
        }
        
        NSLog(@"kAudioFileStreamProperty_AudioDataPacketCount %@", @(audioDataPacketCount));
    }
    else if (propertyID == kAudioFileStreamProperty_FileFormat)
    {
        UInt32 fileFormat;
        UInt32 byteCountSize = sizeof(fileFormat);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FileFormat, &byteCountSize, &fileFormat);
        if (status != noErr)
        {
            //错误处理
        }
        
        Byte byte[4] = {};
        byte[0] = (Byte)((fileFormat >> 24) & 0xFF);
        byte[1] = (Byte)((fileFormat >> 16) & 0xFF);
        byte[2] = (Byte)((fileFormat >> 8) & 0xFF);
        byte[3] = (Byte)(fileFormat & 0xFF);
        
        NSString *string = [NSString stringWithFormat:@"%c%c%c%c", byte[0], byte[1], byte[2], byte[3]];
        NSLog(@"kAudioFileStreamProperty_FileFormat %@", string);
    }
    else if (propertyID == kAudioFileStreamProperty_DataOffset)
    {
        // 表示音频数据在整个音频文件中的offset
        // 因为大多数音频文件都会有一个文件头之后才使真正的音频数据），这个值在seek时会发挥比较大的作用，音频的seek并不是直接seek文件位置而seek时间（比如seek到2分10秒的位置），seek时会根据时间计算出音频数据的字节offset然后需要再加上音频数据的offset才能得到在文件中的真正offset

        UInt32 offsetSize = sizeof(_dataOffset);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &_dataOffset);
        _audioDataByteCount = _fileSize - _dataOffset;
        [self calculateDuration];
    }
    else if (propertyID == kAudioFileStreamProperty_DataFormat)
    {
        // 表示音频文件结构信息，是一个AudioStreamBasicDescription的结构
        UInt32 asbdSize = sizeof(_format);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_format);
        [self calculatepPacketDuration];
    }
    else if (propertyID == kAudioFileStreamProperty_MagicCookieData)
    {
        UInt32 cookieSize;
        Boolean writable;
        OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
        if (status != noErr)
        {
            return;
        }
        
        void *cookieData = malloc(cookieSize);
        status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
        if (status != noErr)
        {
            return;
        }
        
        NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
        free(cookieData);
        
        NSLog(@"kAudioFileStreamProperty_MagicCookieData %@", cookie);
    }
    else if (propertyID == kAudioFileStreamProperty_FormatList)
    {
        //作用和kAudioFileStreamProperty_DataFormat是一样的，区别在于用这个PropertyID获取到是一个AudioStreamBasicDescription的数组
        Boolean outWriteable;
        UInt32 formatListSize;
        OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
        if (status == noErr)
        {
            AudioFormatListItem *formatList = malloc(formatListSize);
            OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
            if (status == noErr)
            {
                UInt32 supportedFormatsSize;
                status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
                if (status != noErr)
                {
                    free(formatList);
                    return;
                }
                
                UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
                OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
                status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize, supportedFormats);
                if (status != noErr)
                {
                    free(formatList);
                    free(supportedFormats);
                    return;
                }
                
                for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem))
                {
                    AudioStreamBasicDescription format = formatList[i].mASBD;
                    for (UInt32 j = 0; j < supportedFormatCount; ++j)
                    {
                        if (format.mFormatID == supportedFormats[j])
                        {
                            _format = format;
                            [self calculatepPacketDuration];
                            break;
                        }
                    }
                }
                free(supportedFormats);
            }
            free(formatList);
        }
    }
    else if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets)
    {
        // 一旦回调中这个PropertyID出现就代表解析完成，接下来可以对音频数据进行帧分离了
        _readyToProducePackets = YES;
        _discontinuous = YES;
        
        UInt32 sizeOfUInt32 = sizeof(_maxPacketSize);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
        if (status != noErr || _maxPacketSize == 0)
        {
            status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &_maxPacketSize);
        }
        
        NSLog(@"kAudioFileStreamProperty_ReadyToProducePackets");
        
        if (_delegate && [_delegate respondsToSelector:@selector(audioFileStreamReadyToProducePackets:)])
        {
            [_delegate audioFileStreamReadyToProducePackets:self];
        }
    }
    else
    {
        NSLog(@"handleAudioFileStreamProperty propertyID %@", @(propertyID));
    }
}

- (void)handleAudioFileStreamPackets:(const void *)packets numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescriptions:(AudioStreamPacketDescription *)packetDescriptioins
{
    if (_discontinuous)
    {
        _discontinuous = NO;
    }
    
    if (numberOfBytes == 0 || numberOfPackets == 0)
    {
        return;
    }
    
    BOOL deletePackDesc = NO;
    if (packetDescriptioins == NULL)
    {
        deletePackDesc = YES;
        UInt32 packetSize = numberOfBytes / numberOfPackets;
        AudioStreamPacketDescription *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * numberOfPackets);
        
        for (int i = 0; i < numberOfPackets; i++)
        {
            UInt32 packetOffset = packetSize * i;
            descriptions[i].mStartOffset = packetOffset;
            descriptions[i].mVariableFramesInPacket = 0;
            if (i == numberOfPackets - 1)
            {
                descriptions[i].mDataByteSize = numberOfBytes - packetOffset;
            }
            else
            {
                descriptions[i].mDataByteSize = packetSize;
            }
        }
        packetDescriptioins = descriptions;
    }
    
    NSMutableArray *parsedDataArray = [[NSMutableArray alloc] init];
    for (int i = 0; i < numberOfPackets; ++i)
    {
        SInt64 packetOffset = packetDescriptioins[i].mStartOffset;
        AACParsedAudioData *parsedData = [AACParsedAudioData parsedAudioDataWithBytes:packets + packetOffset packetDescription:packetDescriptioins[i]];
        
        [parsedDataArray addObject:parsedData];
        
        if (_processedPacketsCount < BitRateEstimationMaxPackets)
        {
            _processedPacketsSizeTotal += parsedData.packetDescription.mDataByteSize;
            _processedPacketsCount += 1;
            [self calculateBitRate];
            [self calculateDuration];
        }
    }
    
    [_delegate audioFileStream:self audioDataParsed:parsedDataArray];
    
    if (deletePackDesc)
    {
        free(packetDescriptioins);
    }
}

#pragma - mark - static callbacks

void AACAudioFileStreamPropertyListener(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    AACAudioFileStream *audioFileStream = (__bridge AACAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
}

void AACAudioFileStreamPacketsCallBack(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescriptions)
{
    AACAudioFileStream *audioFileStream = (__bridge AACAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamPackets:inInputData numberOfBytes:inNumberBytes numberOfPackets:inNumberPackets packetDescriptions:inPacketDescriptions];
}

@end
