//
//  RtmpSocket.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "RtmpSocket.h"
#import "rtmp.h"
#import "error.h"
#import "log.h"

#define RTMP_RECEIVE_TIMEOUT    2
#define DATA_ITEMS_MAX_COUNT    100
#define RTMP_DATA_RESERVE_SIZE  400
#define RTMP_HEAD_SIZE          (sizeof(RTMPPacket) + RTMP_MAX_HEADER_SIZE)

#define SAVC(x)                 static const AVal av_ ## x = AVC(#x)

static const NSInteger RetryTimesBreaken = 5;  ///<  重连1分钟  3秒一次 一共20次
static const NSInteger RetryTimesMargin = 3;

static const AVal av_setDataFrame = AVC("@setDataFrame");
static const AVal av_SDKVersion = AVC("1.0.0");

SAVC(onMetaData);
SAVC(duration);
SAVC(width);
SAVC(height);
SAVC(videocodecid);
SAVC(videodatarate);
SAVC(framerate);
SAVC(audiocodecid);
SAVC(audiodatarate);
SAVC(audiosamplerate);
SAVC(audiosamplesize);
//SAVC(audiochannels);
SAVC(stereo);
SAVC(encoder);
//SAVC(av_stereo);
SAVC(fileSize);
SAVC(avc1);
SAVC(mp4a);

@implementation RTMPFrame

@end

@implementation RTMPAudioFrame

@end

@implementation RTMPVideoFrame

@end

@interface RTMPSocket ()

@property (nonatomic, assign) RTMP *rtmp;
@property (nonatomic, weak) id<RTMPSocketDelegate> delegate;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSMutableArray *buffer;
@property (nonatomic, strong) dispatch_queue_t rtmpSendQueue;
@property (nonatomic, assign) NSInteger retryTimes4netWorkBreaken;
@property (nonatomic, assign) NSInteger reconnectInterval;
@property (nonatomic, assign) NSInteger reconnectCount;
@property (atomic, assign) BOOL isSending;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isConnecting;
@property (nonatomic, assign) BOOL isReconnecting;
@property (nonatomic, assign) BOOL sendVideoHead;
@property (nonatomic, assign) BOOL sendAudioHead;
@property (nonatomic, assign) BOOL isPublish;

@end

@implementation RTMPSocket

#pragma - mark - RtmpSocket

- (instancetype)initWithURL:(nullable NSURL *)url isPublish:(BOOL)isPublish
{
    return [self initWithURL:url reconnectInterval:0 reconnectCount:0 isPublish:isPublish];
}

- (nullable instancetype)initWithURL:(nullable NSURL *)url reconnectInterval:(NSInteger)reconnectInterval reconnectCount:(NSInteger)reconnectCount isPublish:(BOOL)isPublish
{
    if (!url)
    {
        @throw [NSException exceptionWithName:@"LFStreamRtmpSocket init error" reason:@"stream is nil" userInfo:nil];
    }
    
    if (self = [super init])
    {
        _url = url;
        _isPublish = isPublish;
        _buffer = [NSMutableArray array];
        if (reconnectInterval > 0)
        {
            _reconnectInterval = reconnectInterval;
        }
        else
        {
            _reconnectInterval = RetryTimesMargin;
        }
        
        if (reconnectCount > 0)
        {
            _reconnectCount = reconnectCount;
        }
        else
        {
            _reconnectCount = RetryTimesBreaken;
        }
        
        //这里改成observer主要考虑一直到发送出错情况下，可以继续发送
        [self addObserver:self forKeyPath:@"isSending" options:NSKeyValueObservingOptionNew context:nil];
        
        RTMP_LogSetLevel(RTMP_LOGERROR);
    }
    
    return self;
}

- (void)setDelegate:(id<RTMPSocketDelegate>)delegate
{
    _delegate = delegate;
}

- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"isSending"];
}

- (void)start
{
    dispatch_async(self.rtmpSendQueue, ^{
        [self _start];
    });
}

- (void)_start
{
    if (!_url) return;
    if (_isConnecting) return;
    if (_rtmp != NULL) return;
    if (_isConnecting) return;
    
    _isConnecting = YES;
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)])
    {
        [self.delegate socketStatus:self status:RTMPSocketPending];
    }
    
    if (_rtmp != NULL)
    {
        RTMP_Close(_rtmp);
        RTMP_Free(_rtmp);
    }
    
    [self RTMP264_Connect:(char *)[_url.absoluteString cStringUsingEncoding:NSASCIIStringEncoding]];
}

- (void)stop
{
    dispatch_async(self.rtmpSendQueue, ^{
        [self _stop];
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    });
}

- (void)_stop
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)])
    {
        [self.delegate socketStatus:self status:RTMPSocketStop];
    }
    if (_rtmp != NULL)
    {
        RTMP_Close(_rtmp);
        RTMP_Free(_rtmp);
        _rtmp = NULL;
    }
    [self clean];
}

- (void)clean
{
    _isConnecting = NO;
    _isReconnecting = NO;
    _isSending = NO;
    _isConnected = NO;
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    [self.buffer removeAllObjects];
    self.retryTimes4netWorkBreaken = 0;
}

- (void)sendFrame:(RTMPFrame *)frame
{
    if (!frame)
    {
        return;
    }
    
    [self.buffer addObject:frame];
    
    if (!self.isSending)
    {
        [self sendFrame];
    }
}

- (RTMPFrame *)receiveFrame
{
    RTMPFrame *frame;
    unsigned char buf[RTMP_BUFFER_CACHE_SIZE] = {0};
    uint8_t m_packetType = 0;
    int i = 0;
    int len = 0;
    
    // buf 足够大，一次读可以读一个完整的帧
    len = RTMP_Read(_rtmp, (char *)buf, RTMP_BUFFER_CACHE_SIZE);
    if (len > 0)
    {
        // 读取到的第一帧是FLV头，基本不用解析，需要跳过这部分
        if ((buf[0] == 'F') && (buf[1] == 'L') && (buf[2] == 'V'))
        {
            i = i + 13;
        }
        
        m_packetType = buf[i];
        if (m_packetType == RTMP_PACKET_TYPE_AUDIO)
        {
            RTMPAudioFrame *audioFrame;
            if ((buf[i + 11] == 0xAF) && (buf[i + 12] == 0x00))
            {
                audioFrame = [self receiveAudioHeader:buf + i + 13 len:len - i - 13 timeStamp:_rtmp->m_mediaStamp];
                frame = audioFrame;
            }
            else if ((buf[i + 11] == 0xAF) && (buf[i + 12] == 0x01))
            {
                audioFrame = [self receiveAudio:buf + i + 13 len:len - i - 13 timeStamp:_rtmp->m_mediaStamp];
                frame = audioFrame;
            }
        }
        else if (m_packetType == RTMP_PACKET_TYPE_VIDEO)
        {
            RTMPVideoFrame *videoFrame;
            if ((buf[i + 11] == 0x17) && (buf[i + 12] == 0x00))
            {
                videoFrame = [self receiveVideoHeader:buf + i + 13 len:len - i - 13 timeStamp:_rtmp->m_mediaStamp];
                frame = videoFrame;
            }
            else if ((buf[i + 11] == 0x17) && (buf[i + 12] == 0x01))
            {
                videoFrame = [self receiveVideo:buf + i + 12 len:len - i - 12 isKeyFrame:YES timeStamp:_rtmp->m_mediaStamp];
                frame = videoFrame;
            }
            else if ((buf[i + 11] == 0x27) && (buf[i + 12] == 0x01))
            {
                videoFrame = [self receiveVideo:buf + i + 12 len:len - i - 12 isKeyFrame:NO timeStamp:_rtmp->m_mediaStamp];
                frame = videoFrame;
            }
        }
        else if (m_packetType == RTMP_PACKET_TYPE_INFO)
        {
            // 有可能第一帧 info 后面还会携带一帧 audio header 带过来
            int infoLen = (buf[i + 1] << 16) + (buf[i + 2] << 8) + (buf[i + 3]);
            i = i + infoLen + 10;
            int j = i;
            while (j < len)
            {
                if ((buf[j] == 0xAF) && (buf[i + 1] == 0x00))
                {
                    RTMPAudioFrame *audioFrame = [self receiveAudioHeader:buf + j + 2 len:2 timeStamp:_rtmp->m_mediaStamp];
                    frame = audioFrame;
                    break;
                }
                j++;
            }
        }
        else
        {
            NSData *data = [NSData dataWithBytes:buf length:len];
            NSLog(@"receive unknow frame %@, len = %@", data, @(data.length));
        }
    }
    
    return frame;
}

- (NSInteger)RTMP264_Connect:(char *)push_url
{
    //由于摄像头的timestamp是一直在累加，需要每次得到相对时间戳
    //分配与初始化
    _rtmp = RTMP_Alloc();
    RTMP_Init(_rtmp);

    //设置URL
    if (RTMP_SetupURL(_rtmp, push_url) == FALSE)
    {
        //log(LOG_ERR, "RTMP_SetupURL() failed!");
        goto Failed;
    }

    _rtmp->m_msgCounter = 1;
    _rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    //设置可写，即发布流，这个函数必须在连接前使用，否则无效
    if (_isPublish)
    {
        RTMP_EnableWrite(_rtmp);
    }

    //连接服务器
    if (RTMP_Connect(_rtmp, NULL) == FALSE)
    {
        goto Failed;
    }

    //连接流
    if (RTMP_ConnectStream(_rtmp, 0) == FALSE)
    {
        goto Failed;
    }

    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)])
    {
        [self.delegate socketStatus:self status:RTMPSocketStart];
    }

    if (_isPublish)
    {
        [self sendMetaData];
    }

    _isConnected = YES;
    _isConnecting = NO;
    _isReconnecting = NO;
    _isSending = NO;
    return 0;

Failed:
    RTMP_Close(_rtmp);
    RTMP_Free(_rtmp);
    _rtmp = NULL;
    [self reconnect];
    return -1;
}

// 断线重连
- (void)reconnect
{
    dispatch_async(self.rtmpSendQueue, ^{
        
        if (self.retryTimes4netWorkBreaken++ < self.reconnectCount && !self.isReconnecting)
        {
            self.isConnected = NO;
            self.isConnecting = NO;
            self.isReconnecting = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self performSelector:@selector(_reconnect) withObject:nil afterDelay:self.reconnectInterval];
            });
        }
        else if (self.retryTimes4netWorkBreaken >= self.reconnectCount)
        {
            if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)])
            {
                [self.delegate socketStatus:self status:RTMPSocketError];
            }
            if (self.delegate && [self.delegate respondsToSelector:@selector(socketDidError:errorCode:)])
            {
                [self.delegate socketDidError:self errorCode:RTMPError_ReConnectTimeOut];
            }
        }
    });
}

- (void)_reconnect
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    _isReconnecting = NO;
    if (_isConnected)
    {
        return;
    }
    
    _isReconnecting = NO;
    if (_isConnected)
    {
        return;
    }
    if (_rtmp != NULL)
    {
        RTMP_Close(_rtmp);
        RTMP_Free(_rtmp);
        _rtmp = NULL;
    }
    _sendAudioHead = NO;
    _sendVideoHead = NO;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketStatus:status:)])
    {
        [self.delegate socketStatus:self status:RTMPSocketRefresh];
    }
    
    if (_rtmp != NULL)
    {
        RTMP_Close(_rtmp);
        RTMP_Free(_rtmp);
    }
    
    [self RTMP264_Connect:(char *)[_url.absoluteString cStringUsingEncoding:NSASCIIStringEncoding]];
}

#pragma - mark - Rtmp Receive

- (RTMPAudioFrame *)receiveAudioHeader:(unsigned char *)buf len:(int)len timeStamp:(uint32_t)timeStamp
{
    RTMPAudioFrame *audioFrame = [[RTMPAudioFrame alloc] init];
    audioFrame.sampleRate = ((buf[0] & 0x0F) << 1) + ((buf[1] & 0x80) >> 7);
    audioFrame.numberOfChannels = buf[1] >> 3;
    audioFrame.timestamp = timeStamp;

    return audioFrame;
}

- (RTMPAudioFrame *)receiveAudio:(unsigned char *)buf len:(int)len timeStamp:(uint32_t)timeStamp
{
    RTMPAudioFrame *audioFrame = [[RTMPAudioFrame alloc] init];
    audioFrame.data = [NSData dataWithBytes:buf length:len];
    audioFrame.timestamp = timeStamp;
    audioFrame.sampleRate = 0;
    audioFrame.numberOfChannels = 0;
    
    return audioFrame;
}

- (RTMPVideoFrame *)receiveVideoHeader:(unsigned char *)buf len:(int)len timeStamp:(uint32_t)timeStamp
{
    RTMPVideoFrame *videoFrame = [[RTMPVideoFrame alloc] init];
    videoFrame.timestamp = timeStamp;
    
    int spslen = (buf[9] << 8) + buf[10];
    videoFrame.sps = [NSData dataWithBytes:buf + 9 + 2 length:spslen];
    
    int ppslen = (buf[9 + 2 + spslen + 1] << 8) + buf[9 + 2 + spslen + 2];
    videoFrame.pps = [NSData dataWithBytes:buf + 9 + 2 + spslen + 1 + 2 length:ppslen];
    
    return videoFrame;
}

- (RTMPVideoFrame *)receiveVideo:(unsigned char *)buf len:(int)len isKeyFrame:(BOOL)isKeyFrame timeStamp:(uint32_t)timeStamp
{
    RTMPVideoFrame *videoFrame = [[RTMPVideoFrame alloc] init];
    videoFrame.timestamp = timeStamp;
    videoFrame.isKeyFrame = isKeyFrame;
    
    int datalen = (buf[4] << 24) + (buf[5] << 16) + (buf[6] << 8) + buf[7];
    videoFrame.data = [NSData dataWithBytes:buf + 4 + 4 length:datalen];
    
    return videoFrame;
}

#pragma - mark - Rtmp Send

- (void)sendFrame
{
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(self.rtmpSendQueue, ^{
        
        if (!weakSelf.isSending && weakSelf.buffer.count > 0)
        {
            weakSelf.isSending = YES;
            
            if (!weakSelf.isConnected || weakSelf.isReconnecting || weakSelf.isConnecting || !_rtmp)
            {
                weakSelf.isSending = NO;
                return;
            }
            
            // 调用发送接口
            RTMPFrame *frame = [weakSelf.buffer firstObject];
            [weakSelf.buffer removeObjectAtIndex:0];
            
            if ([frame isKindOfClass:[RTMPVideoFrame class]])
            {
                if (!weakSelf.sendVideoHead)
                {
                    weakSelf.sendVideoHead = YES;
                    if (!((RTMPVideoFrame *)frame).sps || !((RTMPVideoFrame *)frame).pps)
                    {
                        weakSelf.isSending = NO;
                        return;
                    }
                    [weakSelf sendVideoHeader:(RTMPVideoFrame *)frame];
                }
                else
                {
                    [weakSelf sendVideo:(RTMPVideoFrame *)frame];
                }
            }
            else
            {
                if (!weakSelf.sendAudioHead)
                {
                    weakSelf.sendAudioHead = YES;
                    if (!(((RTMPAudioFrame *)frame).numberOfChannels))
                    {
                        weakSelf.isSending = NO;
                        return;
                    }
                    [weakSelf sendAudioHeader:(RTMPAudioFrame *)frame];
                }
                else
                {
                    [weakSelf sendAudio:frame];
                }
            }
            
            //修改发送状态
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //这里只为了不循环调用sendFrame方法 调用栈是保证先出栈再进栈
                weakSelf.isSending = NO;
            });
        }
    });
}

- (void)sendMetaData
{
    RTMPPacket packet;

    char pbuf[2048], *pend = pbuf + sizeof(pbuf);

    packet.m_nChannel = 0x03;                   // control channel (invoke)
    packet.m_headerType = RTMP_PACKET_SIZE_LARGE;
    packet.m_packetType = RTMP_PACKET_TYPE_INFO;
    packet.m_nTimeStamp = 0;
    packet.m_nInfoField2 = _rtmp->m_stream_id;
    packet.m_hasAbsTimestamp = TRUE;
    packet.m_body = pbuf + RTMP_MAX_HEADER_SIZE;

    char *enc = packet.m_body;
    enc = AMF_EncodeString(enc, pend, &av_setDataFrame);
    enc = AMF_EncodeString(enc, pend, &av_onMetaData);

    *enc++ = AMF_OBJECT;

    enc = AMF_EncodeNamedNumber(enc, pend, &av_duration, 0.0);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_fileSize, 0.0);

    // videosize
    enc = AMF_EncodeNamedNumber(enc, pend, &av_width, 640);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_height, 360);

    // video
    enc = AMF_EncodeNamedString(enc, pend, &av_videocodecid, &av_avc1);

    enc = AMF_EncodeNamedNumber(enc, pend, &av_videodatarate, 800 * 1024 / 1000.f);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_framerate, 24);

    // audio
    enc = AMF_EncodeNamedString(enc, pend, &av_audiocodecid, &av_mp4a);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_audiodatarate, 96000);

    enc = AMF_EncodeNamedNumber(enc, pend, &av_audiosamplerate, 44100);
    enc = AMF_EncodeNamedNumber(enc, pend, &av_audiosamplesize, 16.0);
    enc = AMF_EncodeNamedBoolean(enc, pend, &av_stereo, 1);

    // sdk version
    enc = AMF_EncodeNamedString(enc, pend, &av_encoder, &av_SDKVersion);

    *enc++ = 0;
    *enc++ = 0;
    *enc++ = AMF_OBJECT_END;

    packet.m_nBodySize = (uint32_t)(enc - packet.m_body);
    if (!RTMP_SendPacket(_rtmp, &packet, FALSE))
    {
        return;
    }
}

- (void)sendAudioHeader:(RTMPAudioFrame *)audioFrame
{
    NSInteger rtmpLength = 2 + 2;     /*spec data长度,一般是2*/
    unsigned char *body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);
    
    /*AF 00 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x00;
    
    /*spec_buf是AAC sequence header数据*/
    body[2] = 0x10 | ((audioFrame.sampleRate >> 1) & 0x7);
    body[3] = ((audioFrame.sampleRate & 0x1) << 7) | ((audioFrame.numberOfChannels & 0xF) << 3);

    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:0];
    free(body);
}

- (void)sendAudio:(RTMPFrame *)frame
{
    NSInteger rtmpLength = frame.data.length + 2;    /*spec data长度,一般是2*/
    unsigned char *body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);
    
    /*AF 01 + AAC RAW data*/
    body[0] = 0xAF;
    body[1] = 0x01;
    memcpy(&body[2], frame.data.bytes, frame.data.length);
    [self sendPacket:RTMP_PACKET_TYPE_AUDIO data:body size:rtmpLength nTimestamp:frame.timestamp];
    free(body);
}

- (void)sendVideoHeader:(RTMPVideoFrame *)videoFrame
{
    unsigned char *body = NULL;
    NSInteger iIndex = 0;
    NSInteger rtmpLength = 1024;
    const char *sps = videoFrame.sps.bytes;
    const char *pps = videoFrame.pps.bytes;
    NSInteger sps_len = videoFrame.sps.length;
    NSInteger pps_len = videoFrame.pps.length;

    body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);

    body[iIndex++] = 0x17;
    body[iIndex++] = 0x00;

    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;
    body[iIndex++] = 0x00;

    body[iIndex++] = 0x01;
    body[iIndex++] = sps[1];
    body[iIndex++] = sps[2];
    body[iIndex++] = sps[3];
    body[iIndex++] = 0xff;

    /*sps*/
    body[iIndex++] = 0xe1;
    body[iIndex++] = (sps_len >> 8) & 0xff;
    body[iIndex++] = sps_len & 0xff;
    memcpy(&body[iIndex], sps, sps_len);
    iIndex += sps_len;

    /*pps*/
    body[iIndex++] = 0x01;
    body[iIndex++] = (pps_len >> 8) & 0xff;
    body[iIndex++] = (pps_len) & 0xff;
    memcpy(&body[iIndex], pps, pps_len);
    iIndex += pps_len;

    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:iIndex nTimestamp:0];
    free(body);
}

- (void)sendVideo:(RTMPVideoFrame *)frame
{
    NSInteger i = 0;
    NSInteger rtmpLength = frame.data.length + 9;
    unsigned char *body = (unsigned char *)malloc(rtmpLength);
    memset(body, 0, rtmpLength);

    if (frame.isKeyFrame)
    {
        body[i++] = 0x17;        // 1:Iframe  7:AVC
    }
    else
    {
        body[i++] = 0x27;        // 2:Pframe  7:AVC
    }
    body[i++] = 0x01;    // AVC NALU
    body[i++] = 0x00;
    body[i++] = 0x00;
    body[i++] = 0x00;
    body[i++] = (frame.data.length >> 24) & 0xff;
    body[i++] = (frame.data.length >> 16) & 0xff;
    body[i++] = (frame.data.length >>  8) & 0xff;
    body[i++] = (frame.data.length) & 0xff;
    memcpy(&body[i], frame.data.bytes, frame.data.length);

    [self sendPacket:RTMP_PACKET_TYPE_VIDEO data:body size:(rtmpLength) nTimestamp:frame.timestamp];
    free(body);
}

- (NSInteger)sendPacket:(unsigned int)nPacketType data:(unsigned char *)data size:(NSInteger)size nTimestamp:(uint64_t)nTimestamp
{
    NSInteger rtmpLength = size;
    RTMPPacket rtmp_pack;
    RTMPPacket_Reset(&rtmp_pack);
    RTMPPacket_Alloc(&rtmp_pack, (uint32_t)rtmpLength);

    rtmp_pack.m_nBodySize = (uint32_t)size;
    memcpy(rtmp_pack.m_body, data, size);
    rtmp_pack.m_hasAbsTimestamp = 0;
    rtmp_pack.m_packetType = nPacketType;
    if (_rtmp) rtmp_pack.m_nInfoField2 = _rtmp->m_stream_id;
    rtmp_pack.m_nChannel = 0x04;
    rtmp_pack.m_headerType = RTMP_PACKET_SIZE_LARGE;
    if (RTMP_PACKET_TYPE_AUDIO == nPacketType && size != 4)
    {
        rtmp_pack.m_headerType = RTMP_PACKET_SIZE_MEDIUM;
    }
    rtmp_pack.m_nTimeStamp = (uint32_t)nTimestamp;

    NSInteger nRet = [self RtmpPacketSend:&rtmp_pack];

    RTMPPacket_Free(&rtmp_pack);
    return nRet;
}

- (NSInteger)RtmpPacketSend:(RTMPPacket *)packet
{
    if (_rtmp && RTMP_IsConnected(_rtmp))
    {
        int success = RTMP_SendPacket(_rtmp, packet, 0);
        return success;
    }
    return -1;
}

#pragma - mark - LFStreamingBufferDelegate

- (void)streamingBuffer:(nullable RTMPSocket *)buffer bufferState:(RTMPBuffferState)state
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(socketBufferStatus:status:)])
    {
        [self.delegate socketBufferStatus:self status:state];
    }
}

#pragma - mark - Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"isSending"])
    {
        if (!self.isSending)
        {
            [self sendFrame];
        }
    }
}

#pragma - mark - Getter Setter

- (dispatch_queue_t)rtmpSendQueue
{
    if (!_rtmpSendQueue)
    {
        _rtmpSendQueue = dispatch_queue_create("com.pingan.RtmpSendQueue", NULL);
    }
    
    return _rtmpSendQueue;
}

@end
