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

- (void)getEncodedAudioData:(NSData *)data;

@end

@interface AACEncoder : NSObject

@property (nonatomic, weak) id<AACEncoderDelegate> delegate;

- (void)startEncode:(CMSampleBufferRef)sampleBuffer timeStamp:(uint64_t)timeStamp;
- (void)endEncode;

@end
