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
    }
}

#pragma - mark - open & close

- (BOOL)openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint error:(NSError *__autoreleasing *)error
{
    OSStatus status = AudioFileStreamOpen((__bridge void *)self, MCSAudioFileStreamPropertyListener, AACAudioFileStreamPacketsCallBack, fileTypeHint, &_audioFileStreamID);
    if (status != noErr)
    {
        _audioFileStreamID = NULL;
    }
    
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
    }
}

- (void)calculateDuration
{
    if (_fileSize > 0 && _bitRate > 0)
    {
        _duration = ((_fileSize - _dataOffset) * 8.0) / _bitRate;
    }
}

- (void)calculatepPacketDuration
{
    if (_format.mSampleRate > 0)
    {
        _packetDuration = _format.mFramesPerPacket / _format.mSampleRate;
    }
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets)
    {
        _readyToProducePackets = YES;
        _discontinuous = YES;
        
        UInt32 sizeOfUInt32 = sizeof(_maxPacketSize);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
        if (status != noErr || _maxPacketSize == 0)
        {
            status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &_maxPacketSize);
        }
        
        if (_delegate && [_delegate respondsToSelector:@selector(audioFileStreamReadyToProducePackets:)])
        {
            [_delegate audioFileStreamReadyToProducePackets:self];
        }
    }
    else if (propertyID == kAudioFileStreamProperty_DataOffset)
    {
        UInt32 offsetSize = sizeof(_dataOffset);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &_dataOffset);
        _audioDataByteCount = _fileSize - _dataOffset;
        [self calculateDuration];
    }
    else if (propertyID == kAudioFileStreamProperty_DataFormat)
    {
        UInt32 asbdSize = sizeof(_format);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_format);
        [self calculatepPacketDuration];
    }
    else if (propertyID == kAudioFileStreamProperty_FormatList)
    {
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

void MCSAudioFileStreamPropertyListener(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
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
