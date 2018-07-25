//
//  H264HwDecoder.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "H264HwDecoder.h"
#import "NaluHelper.h"

@interface H264HwDecoder ()
{
    VTDecompressionSessionRef deocdingSession;
    CMVideoFormatDescriptionRef decoderFormatDescription;
}

@property (nonatomic, assign) uint8_t *sps;
@property (nonatomic, assign) NSInteger spsSize;
@property (nonatomic, assign) uint8_t *pps;
@property (nonatomic, assign) NSInteger ppsSize;

@end

@implementation H264HwDecoder

- (BOOL)initH264Decoder
{
    //必须先获取到 sps 和 pps 才能创建解码器，否则无法解码后续的视频帧
    if (_spsSize == 0 || _ppsSize == 0)
    {
        return NO;
    }
    
    if (deocdingSession)
    {
        return YES;
    }
    
    const uint8_t *const parameterSetPointers[2] = {_sps, _pps};
    const size_t parameterSetSizes[2] = {_spsSize, _ppsSize};
    
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &decoderFormatDescription);
    if (status == noErr)
    {
        //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        //或者是kCVPixelFormatType_420YpCbCr8Planar
        //因为iOS是  nv12  其他是nv21
        //这里款高和编码反的
        NSDictionary *destinationPixelBufferAttributes = @{(id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange], (id)kCVPixelBufferWidthKey : [NSNumber numberWithInt:h264outputHeight * 2], (id)kCVPixelBufferHeightKey : [NSNumber numberWithInt:h264outputWidth * 2], (id)kCVPixelBufferOpenGLCompatibilityKey : [NSNumber numberWithBool:YES]};

        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompressH264;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault, decoderFormatDescription, NULL, (__bridge CFDictionaryRef)destinationPixelBufferAttributes, &callBackRecord, &deocdingSession);
        if (status != noErr)
        {
            NSLog(@"VT: reset decoder session failed status=%d", (int)status);
            return NO;
        }
        
        VTSessionSetProperty(deocdingSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(deocdingSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    }
    else
    {
        NSLog(@"VT: reset decoder session failed status=%d", (int)status);
    }
    
    return YES;
}

- (CVPixelBufferRef)decode:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(NULL, (void *)frame, frameSize, kCFAllocatorNull, NULL, 0, frameSize, FALSE, &blockBuffer);
    if (status == kCMBlockBufferNoErr)
    {
        CMSampleBufferRef sampleBuffer = NULL;
        OSStatus decodeStatus = 0;
        const size_t sampleSizeArray[] = {frameSize};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, decoderFormatDescription, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer)
        {
            VTDecodeFrameFlags flags;
            if (self.enableAsynDecompression)
            {
                flags = kVTDecodeFrame_EnableAsynchronousDecompression;
            }
            
            VTDecodeInfoFlags flagOut = 0;
            
            decodeStatus = VTDecompressionSessionDecodeFrame(deocdingSession, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
            if (decodeStatus == kVTInvalidSessionErr)
            {
                NSLog(@"VT: Invalid session, reset decoder session");
            }
            else if(decodeStatus == kVTVideoDecoderBadDataErr)
            {
                NSLog(@"VT: decode failed status=%d(Bad data)", (int)decodeStatus);
            }
            else if(decodeStatus != noErr)
            {
                NSLog(@"VT: decode failed status=%d", (int)decodeStatus);
            }
            
            if (self.enableAsynDecompression)
            {
                decodeStatus = VTDecompressionSessionWaitForAsynchronousFrames(deocdingSession);
            }
            
            CFRelease(sampleBuffer);
        }
        
        CFRelease(blockBuffer);
    }
    
    return outputPixelBuffer;
}

//此处解码的帧需要包含 00000001 start code
- (void)startDecode:(uint8_t *)frame withSize:(uint32_t)frameSize
{
    int nalu_type = (frame[4] & 0x1F);
    uint32_t nalSize = (uint32_t)(frameSize - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    frame[0] = *(pNalSize + 3);
    frame[1] = *(pNalSize + 2);
    frame[2] = *(pNalSize + 1);
    frame[3] = *(pNalSize);
    
    //传输的时候。关键帧不能丢数据 否则绿屏   B/P可以丢  这样会卡顿
    switch (nalu_type)
    {
        case NAL_SLICE_IDR:
        {
            NSLog(@"nalu_type:%d Nal type is IDR frame", nalu_type);  //关键帧
            if ([self initH264Decoder])
            {
                [self decode:frame withSize:frameSize];
            }
            break;
        }
            
        case NAL_SPS:
        {
            NSLog(@"nalu_type:%d Nal type is SPS", nalu_type);   //sps
            _spsSize = frameSize - 4;
            _sps = malloc(_spsSize);
            memcpy(_sps, &frame[4], _spsSize);
            break;
        }
            
        case NAL_PPS:
        {
            NSLog(@"nalu_type:%d Nal type is PPS", nalu_type);   //pps
            _ppsSize = frameSize - 4;
            _pps = malloc(_ppsSize);
            memcpy(_pps, &frame[4], _ppsSize);
            break;
        }
            
        default:
        {
            NSLog(@"nalu_type:%d is B/P frame", nalu_type);//其他帧
            if ([self initH264Decoder])
            {
                [self decode:frame withSize:frameSize];
            }
            break;
        }   
    }
}

- (void)endDecoder
{
    if (deocdingSession)
    {
        VTDecompressionSessionWaitForAsynchronousFrames(deocdingSession);
        VTDecompressionSessionInvalidate(deocdingSession);
        CFRelease(deocdingSession);
        deocdingSession = nil;
    }
}

- (BOOL)resetH264Decoder
{
    [self endDecoder];
    return [self initH264Decoder];
}

#pragma - mark - VTDecompressionOutputCallback

void didDecompressH264(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration)
{
    if (!pixelBuffer)
    {
        return;
    }
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    
    H264HwDecoder *decoder = (__bridge H264HwDecoder *)decompressionOutputRefCon;
    if (decoder.delegate && [decoder.delegate respondsToSelector:@selector(getDecodedData:)])
    {
        dispatch_async(decoder.dataCallbackQueue, ^{
            
            [decoder.delegate getDecodedData:pixelBuffer];
        });
    }
}

@end
