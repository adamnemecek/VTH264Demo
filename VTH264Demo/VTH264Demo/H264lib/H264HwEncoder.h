//
//  H264HwEncoder.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@protocol H264HwEncoderDelegate <NSObject>

- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps;
- (void)getEncodedVideoData:(NSData *)data sps:(NSData *)sps pps:(NSData *)pps isKeyFrame:(BOOL)isKeyFrame timeStamp:(uint64_t)timeStamp;

@end

@interface H264HwEncoder : NSObject

- (void)initEncode:(int)width height:(int)height fps:(int)fps;
- (void)startEncode:(CMSampleBufferRef)sampleBuffer timeStamp:(uint64_t)timeStamp;
- (void)endEncode;

@property (nonatomic, weak) id<H264HwEncoderDelegate> delegate;
@property (nonatomic, strong) dispatch_queue_t dataCallbackQueue;

@end
