//
//  AACEncoder.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@protocol AACEncoderDelegate <NSObject>

- (void)getEncodedAudioData:(NSData *)data timeStamp:(uint64_t)timeStamp;

@end

@interface AACEncoder : NSObject

@property (nonatomic, weak) id<AACEncoderDelegate> delegate;
@property (nonatomic, assign) UInt32 channelsPerFrame; // 1:单声道；2:双声道
@property (nonatomic, strong) dispatch_queue_t dataCallbackQueue;

- (void)startEncode:(CMSampleBufferRef)sampleBuffer timeStamp:(uint64_t)timeStamp;
- (void)endEncode;

@end
