//
//  AACAudioFile.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACAudioFile.h"

static const UInt32 packetPerRead = 15;

@interface AACAudioFile ()

@property (nonatomic, assign) SInt64 packetOffset;
@property (nonatomic, strong) NSFileHandle *fileHandler;
@property (nonatomic, assign) SInt64 dataOffset;
@property (nonatomic, assign) NSTimeInterval packetDuration;
@property (nonatomic, assign) AudioFileID audioFileID;

@end

@implementation AACAudioFile

#pragma - mark - init & dealloc

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType
{
    self = [super init];
    if (self)
    {
        _filePath = filePath;
        _fileType = fileType;
        
        _fileHandler = [NSFileHandle fileHandleForReadingAtPath:_filePath];
        _fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
        if (_fileHandler && _fileSize > 0)
        {
            if ([self openAudioFile])
            {
                [self fetchFormatInfo];
            }
        }
        else
        {
            [_fileHandler closeFile];
        }
    }
    
    return self;
}

- (void)dealloc
{
    [_fileHandler closeFile];
    [self closeAudioFile];
}

#pragma - mark - audiofile

- (BOOL)available
{
    return _audioFileID != NULL;
}

- (BOOL)openAudioFile
{
    OSStatus status = AudioFileOpenWithCallbacks((__bridge void *)self, AACAudioFileReadCallBack, NULL, AACAudioFileGetSizeCallBack, NULL, _fileType, &_audioFileID);
    if (status != noErr)
    {
        _audioFileID = NULL;
        return NO;
    }
    
    return YES;
}

- (void)fetchFormatInfo
{
    UInt32 formatListSize;
    OSStatus status = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyFormatList, &formatListSize, NULL);
    if (status == noErr)
    {
        BOOL found = NO;
        AudioFormatListItem *formatList = malloc(formatListSize);
        OSStatus status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyFormatList, &formatListSize, formatList);
        if (status == noErr)
        {
            UInt32 supportedFormatsSize;
            status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
            if (status != noErr)
            {
                free(formatList);
                [self closeAudioFile];
                return;
            }
            
            UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
            OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
            status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize, supportedFormats);
            if (status != noErr)
            {
                free(formatList);
                free(supportedFormats);
                [self closeAudioFile];
                return;
            }
            
            for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i++)
            {
                AudioStreamBasicDescription format = formatList[i].mASBD;
                for (UInt32 j = 0; j < supportedFormatCount; ++j)
                {
                    if (format.mFormatID == supportedFormats[j])
                    {
                        _format = format;
                        found = YES;
                        break;
                    }
                }
            }
            free(supportedFormats);
        }
        free(formatList);
        
        if (!found)
        {
            [self closeAudioFile];
            return;
        }
        else
        {
            [self calculatepPacketDuration];
        }
    }
    
    UInt32 size = sizeof(_bitRate);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyBitRate, &size, &_bitRate);
    if (status != noErr)
    {
        [self closeAudioFile];
        return;
    }
    
    size = sizeof(_dataOffset);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyDataOffset, &size, &_dataOffset);
    if (status != noErr)
    {
        [self closeAudioFile];
        return;
    }
    _audioDataByteCount = _fileSize - _dataOffset;
    
    size = sizeof(_duration);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyEstimatedDuration, &size, &_duration);
    if (status != noErr)
    {
        [self calculateDuration];
    }
    
    size = sizeof(_maxPacketSize);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &_maxPacketSize);
    if (status != noErr || _maxPacketSize == 0)
    {
        status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMaximumPacketSize, &size, &_maxPacketSize);
        if (status != noErr)
        {
            [self closeAudioFile];
            return;
        }
    }
}

- (NSData *)fetchMagicCookie
{
    UInt32 cookieSize;
	OSStatus status = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyMagicCookieData, &cookieSize, NULL);
	if (status != noErr)
	{
		return nil;
	}
    
    void *cookieData = malloc(cookieSize);
	status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMagicCookieData, &cookieSize, cookieData);
	if (status != noErr)
	{
		return nil;
	}
    
    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);
    
    return cookie;
}

- (void)closeAudioFile
{
    if (self.available)
    {
        AudioFileClose(_audioFileID);
        _audioFileID = NULL;
    }
}

- (void)close
{
    [self closeAudioFile];
}

- (void)calculatepPacketDuration
{
    if (_format.mSampleRate > 0)
    {
        _packetDuration = _format.mFramesPerPacket / _format.mSampleRate;
    }
}

- (void)calculateDuration
{
    if (_fileSize > 0 && _bitRate > 0)
    {
        _duration = ((_fileSize - _dataOffset) * 8) / _bitRate;
    }
}

- (NSArray *)parseData:(BOOL *)isEof
{
    UInt32 ioNumPackets = packetPerRead;
    UInt32 ioNumBytes = ioNumPackets * _maxPacketSize;
    void * outBuffer = (void *)malloc(ioNumBytes);
    
    AudioStreamPacketDescription * outPacketDescriptions = NULL;
    OSStatus status = noErr;
    if (_format.mFormatID != kAudioFormatLinearPCM)
    {
        UInt32 descSize = sizeof(AudioStreamPacketDescription) * ioNumPackets;
        outPacketDescriptions = (AudioStreamPacketDescription *)malloc(descSize);
        status = AudioFileReadPacketData(_audioFileID, false, &ioNumBytes, outPacketDescriptions, _packetOffset, &ioNumPackets, outBuffer);
    }
    else
    {
        status = AudioFileReadPacketData(_audioFileID, false, &ioNumBytes, outPacketDescriptions, _packetOffset, &ioNumPackets, outBuffer);
    }
    
    if (status != noErr)
    {
        *isEof = status == kAudioFileEndOfFileError;
        free(outBuffer);
        return nil;
    }
    
    if (ioNumBytes == 0)
    {
        *isEof = YES;
    }
    
    _packetOffset += ioNumPackets;
    
    if (ioNumPackets > 0)
    {
        NSMutableArray *parsedDataArray = [[NSMutableArray alloc] init];
        for (int i = 0; i < ioNumPackets; ++i)
        {
            AudioStreamPacketDescription packetDescription;
            if (outPacketDescriptions)
            {
                packetDescription = outPacketDescriptions[i];
            }
            else
            {
                packetDescription.mStartOffset = i * _format.mBytesPerPacket;
                packetDescription.mDataByteSize = _format.mBytesPerPacket;
                packetDescription.mVariableFramesInPacket = _format.mFramesPerPacket;
            }
            
            AACParsedAudioData *parsedData = [AACParsedAudioData parsedAudioDataWithBytes:outBuffer + packetDescription.mStartOffset packetDescription:packetDescription];
            if (parsedData)
            {
                [parsedDataArray addObject:parsedData];
            }
        }
        
        return parsedDataArray;
    }
    
    return nil;
}

- (void)seekToTime:(NSTimeInterval)time
{
    _packetOffset = floor(time / _packetDuration);
}

- (UInt32)availableDataLengthAtOffset:(SInt64)inPosition maxLength:(UInt32)requestCount
{
    if ((inPosition + requestCount) > _fileSize)
    {
        if (inPosition > _fileSize)
        {
            return 0;
        }
        else
        {
            return (UInt32)(_fileSize - inPosition);
        }
    }
    else
    {
        return requestCount;
    }
}

- (NSData *)dataAtOffset:(SInt64)inPosition length:(UInt32)length
{
    [_fileHandler seekToFileOffset:inPosition];
    return [_fileHandler readDataOfLength:length];
}

#pragma - mark - callback

OSStatus AACAudioFileReadCallBack(void *inClientData, SInt64 inPosition, UInt32 requestCount, void *buffer, UInt32 *actualCount)
{
    AACAudioFile *audioFile = (__bridge AACAudioFile *)inClientData;
    
    *actualCount = [audioFile availableDataLengthAtOffset:inPosition maxLength:requestCount];
    if (*actualCount > 0)
    {
        NSData *data = [audioFile dataAtOffset:inPosition length:*actualCount];
        memcpy(buffer, [data bytes], [data length]);
    }

    return noErr;
}

SInt64 AACAudioFileGetSizeCallBack(void *inClientData)
{
    AACAudioFile *audioFile = (__bridge AACAudioFile *)inClientData;
    return audioFile.fileSize;
}

@end
