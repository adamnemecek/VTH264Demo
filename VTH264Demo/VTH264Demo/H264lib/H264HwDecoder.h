//
//  H264HwDecoder.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@protocol H264HwDecoderDelegate <NSObject>

- (void)getDecodedVideoData:(CVImageBufferRef)imageBuffer timeStamp:(uint64_t)timeStamp;

@end

@interface H264HwDecoder : NSObject

@property (nonatomic, weak) id<H264HwDecoderDelegate> delegate;
@property (nonatomic, strong) dispatch_queue_t dataCallbackQueue;
@property (nonatomic, assign) BOOL enableAsynDecompression;

- (void)initEncode:(int)width height:(int)height;
- (void)startDecode:(uint8_t *)frame withSize:(uint32_t)frameSize timeStamp:(uint64_t)timeStamp;
- (void)endDecoder;
- (BOOL)resetH264Decoder;

@end
