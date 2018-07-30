//
//  AACAudioPlayer.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "AACAudioFile.h"
#import "AACAudioFileStream.h"
#import "AACAudioOutputQueue.h"
#import "AACAudioBuffer.h"
#import <pthread.h>

@interface AACAudioPlayer () <AACAudioFileStreamDelegate>

@property (nonatomic, strong) NSThread *thread;
@property (nonatomic, assign) pthread_mutex_t mutex;
@property (nonatomic, assign) pthread_cond_t cond;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) unsigned long long offset;
@property (nonatomic, strong) NSFileHandle *fileHandler;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, strong) AACAudioBuffer *buffer;
@property (nonatomic, strong) AACAudioFile *audioFile;
@property (nonatomic, strong) AACAudioFileStream *audioFileStream;
@property (nonatomic, strong) AACAudioOutputQueue *audioQueue;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL pauseRequired;
@property (nonatomic, assign) BOOL stopRequired;
@property (nonatomic, assign) BOOL pausedByInterrupt;
@property (nonatomic, assign) BOOL usingAudioFile;
@property (nonatomic, assign) BOOL seekRequired;
@property (nonatomic, assign) NSTimeInterval seekTime;
@property (nonatomic, assign) NSTimeInterval timingOffset;

@end

@implementation AACAudioPlayer

#pragma - mark - init & dealloc

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType
{
    self = [super init];
    if (self)
    {
        _status = AACAPStatusStopped;
        
        _filePath = filePath;
        _fileType = fileType;
        
        _fileHandler = [NSFileHandle fileHandleForReadingAtPath:_filePath];
        _fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
        if (_fileHandler && _fileSize > 0)
        {
            _buffer = [AACAudioBuffer buffer];
        }
        else
        {
            [_fileHandler closeFile];
            _failed = YES;
        }
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
    [_fileHandler closeFile];
}

- (void)cleanup
{
    //reset file
    _offset = 0;
    [_fileHandler seekToFileOffset:0];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    
    //clean buffer
    [_buffer clean];
    
    _usingAudioFile = NO;
    //close audioFileStream
    [_audioFileStream close];
    _audioFileStream = nil;
    
    //close audiofile
    [_audioFile close];
    _audioFile = nil;
    
    //stop audioQueue
    [_audioQueue stop:YES];
    _audioQueue = nil;
    
    //destory mutex & cond
    [self mutexDestory];
    
    _started = NO;
    _timingOffset = 0;
    _seekTime = 0;
    _seekRequired = NO;
    _pauseRequired = NO;
    _stopRequired = NO;
    
    //reset status
    [self setStatusInternal:AACAPStatusStopped];
}

#pragma mark - status
- (BOOL)isPlayingOrWaiting
{
    return self.status == AACAPStatusWaiting || self.status == AACAPStatusPlaying || self.status == AACAPStatusFlushing;
}

- (AACAPStatus)status
{
    return _status;
}

- (void)setStatusInternal:(AACAPStatus)status
{
    if (_status == status)
    {
        return;
    }
    
    [self willChangeValueForKey:@"status"];
    _status = status;
    [self didChangeValueForKey:@"status"];
}

#pragma mark - mutex
- (void)mutexInit
{
    pthread_mutex_init(&_mutex, NULL);
    pthread_cond_init(&_cond, NULL);
}

- (void)mutexDestory
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}

- (void)mutexWait
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_wait(&_cond, &_mutex);
	pthread_mutex_unlock(&_mutex);
}

- (void)mutexSignal
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}

#pragma mark - thread
- (BOOL)createAudioQueue
{
    if (_audioQueue)
    {
        return YES;
    }
    
    NSTimeInterval duration = self.duration;
    UInt64 audioDataByteCount = _usingAudioFile ? _audioFile.audioDataByteCount : _audioFileStream.audioDataByteCount;
    _bufferSize = 0;
    if (duration != 0)
    {
        _bufferSize = (0.2 / duration) * audioDataByteCount;
    }
    
    if (_bufferSize > 0)
    {
        AudioStreamBasicDescription format = _usingAudioFile ? _audioFile.format : _audioFileStream.format;
        NSData *magicCookie = _usingAudioFile ? [_audioFile fetchMagicCookie] : [_audioFileStream fetchMagicCookie];
        _audioQueue = [[AACAudioOutputQueue alloc] initWithFormat:format bufferSize:_bufferSize macgicCookie:magicCookie];
        if (!_audioQueue.available)
        {
            _audioQueue = nil;
            return NO;
        }
    }
    return YES;
}

- (void)threadMain
{
    _failed = YES;
    NSError *error = nil;
    //set audiosession category
    if ([[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error])
    {
        //active audiosession
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruptHandler:) name:AVAudioSessionInterruptionNotification object:nil];
        if ([[AVAudioSession sharedInstance] setActive:YES error:NULL])
        {
            //create audioFileStream
            _audioFileStream = [[AACAudioFileStream alloc] initWithFileType:_fileType fileSize:_fileSize error:&error];
            if (!error)
            {
                _failed = NO;
                _audioFileStream.delegate = self;
            }
        }
    }
    
    if (_failed)
    {
        [self cleanup];
        return;
    }
    
    [self setStatusInternal:AACAPStatusWaiting];
    BOOL isEof = NO;
    while (self.status != AACAPStatusStopped && !_failed && _started)
    {
        @autoreleasepool
        {
            //read file & parse
            if (_usingAudioFile)
            {
                if (!_audioFile)
                {
                    _audioFile = [[AACAudioFile alloc] initWithFilePath:_filePath fileType:_fileType];
                }
                
                [_audioFile seekToTime:_seekTime];
                
                if ([_buffer bufferedSize] < _bufferSize || !_audioQueue)
                {
                    NSArray *parsedData = [_audioFile parseData:&isEof];
                    if (parsedData)
                    {
                        [_buffer enqueueFromDataArray:parsedData];
                    }
                    else
                    {
                        _failed = YES;
                        break;
                    }
                }
            }
            else
            {
                if (_offset < _fileSize && (!_audioFileStream.readyToProducePackets || [_buffer bufferedSize] < _bufferSize || !_audioQueue))
                {
                    //每次读3000个字节进行分析
                    NSData *data = [_fileHandler readDataOfLength:3000];
                    
                    _offset += [data length];
                    if (_offset >= _fileSize)
                    {
                        isEof = YES;
                    }
                    
                    [_audioFileStream parseData:data error:&error];
                    
                    if (error)
                    {
                        _usingAudioFile = YES;
                        continue;
                    }
                }
            }

            if (_audioFileStream.readyToProducePackets || _usingAudioFile)
            {
                if (![self createAudioQueue])
                {
                    _failed = YES;
                    break;
                }
                
                if (!_audioQueue)
                {
                    continue;
                }
                
                if (self.status == AACAPStatusFlushing && !_audioQueue.isRunning)
                {
                    break;
                }
                
                //stop
                if (_stopRequired)
                {
                    _stopRequired = NO;
                    _started = NO;
                    [_audioQueue stop:YES];
                    break;
                }
                
                //pause
                if (_pauseRequired)
                {
                    [self setStatusInternal:AACAPStatusPaused];
                    [_audioQueue pause];
                    [self mutexWait];
                    _pauseRequired = NO;
                }
                
                //play
                if ([_buffer bufferedSize] >= _bufferSize || isEof)
                {
                    UInt32 packetCount;
                    AudioStreamPacketDescription *desces = NULL;
                    NSData *data = [_buffer dequeueDataWithSize:_bufferSize packetCount:&packetCount descriptions:&desces];
                    if (packetCount != 0)
                    {
                        [self setStatusInternal:AACAPStatusPlaying];
                        _failed = ![_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:isEof];
                        free(desces);
                        if (_failed)
                        {
                            break;
                        }
                        
                        if (![_buffer hasData] && isEof && _audioQueue.isRunning)
                        {
                            [_audioQueue stop:NO];
                            [self setStatusInternal:AACAPStatusFlushing];
                        }
                    }
                    else if (isEof)
                    {
                        //wait for end
                        if (![_buffer hasData] && _audioQueue.isRunning)
                        {
                            [_audioQueue stop:NO];
                            [self setStatusInternal:AACAPStatusFlushing];
                        }
                    }
                    else
                    {
                        _failed = YES;
                        break;
                    }
                }
                
                //seek
                if (_seekRequired && self.duration != 0)
                {
                    [self setStatusInternal:AACAPStatusWaiting];
                    
                    _timingOffset = _seekTime - _audioQueue.playedTime;
                    [_buffer clean];
                    
                    if (_usingAudioFile)
                    {
                        [_audioFile seekToTime:_seekTime];
                    }
                    else
                    {
                        _offset = [_audioFileStream seekToTime:&_seekTime];
                        [_fileHandler seekToFileOffset:_offset];
                    }
                    
                    _seekRequired = NO;
                    [_audioQueue reset];
                }
            }
        }
    }
    
    //clean
    [self cleanup];
}

#pragma - mark - interrupt

- (void)interruptHandler:(NSNotification *)notification
{
    UInt32 interruptionState = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntValue];
    
    if (interruptionState == AVAudioSessionInterruptionTypeBegan)
    {
        _pausedByInterrupt = YES;
        [_audioQueue pause];
        [self setStatusInternal:AACAPStatusPaused];
        
    }
    else if (interruptionState == AVAudioSessionInterruptionTypeEnded)
    {
        AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntValue];
        if (interruptionType == AVAudioSessionInterruptionOptionShouldResume)
        {
            if (self.status == AACAPStatusPaused && _pausedByInterrupt)
            {
                if ([[AVAudioSession sharedInstance] setActive:YES error:NULL])
                {
                    [self play];
                }
            }
        }
    }
}

#pragma - mark - parser

- (void)audioFileStream:(AACAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData
{
    [_buffer enqueueFromDataArray:audioData];
}

#pragma - mark - progress

- (NSTimeInterval)progress
{
    if (_seekRequired)
    {
        return _seekTime;
    }
    return _timingOffset + _audioQueue.playedTime;
}

- (void)setProgress:(NSTimeInterval)progress
{
    _seekRequired = YES;
    _seekTime = progress;
}

- (NSTimeInterval)duration
{
    return _usingAudioFile ? _audioFile.duration : _audioFileStream.duration;
}

#pragma - mark - method

- (void)play
{
    if (!_started)
    {
        _started = YES;
        [self mutexInit];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
        [_thread start];
    }
    else
    {
        if (_status == AACAPStatusPaused || _pauseRequired)
        {
            _pausedByInterrupt = NO;
            _pauseRequired = NO;
            if ([[AVAudioSession sharedInstance] setActive:YES error:NULL])
            {
                [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
                [self resume];
            }
        }
    }
}

- (void)resume
{
    [_audioQueue resume];
    [self mutexSignal];
}

- (void)pause
{
    if (self.isPlayingOrWaiting && self.status != AACAPStatusFlushing)
    {
        _pauseRequired = YES;
    }
}

- (void)stop
{
    _stopRequired = YES;
    [self mutexSignal];
}

@end
