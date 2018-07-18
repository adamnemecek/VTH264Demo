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
- (void)getEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;

@end

@interface H264HwEncoder : NSObject

- (void)initWithConfiguration;
- (void)initEncode:(int)width height:(int)height;
- (void)startEncode:(CMSampleBufferRef)sampleBuffer;
- (void)endEncode;

@property (nonatomic, weak) id<H264HwEncoderDelegate> delegate;

@end
