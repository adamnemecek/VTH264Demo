//
//  AACDecoder.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "AACHelper.h"

@protocol AACDecoderDelegate <NSObject>

- (void)getDecodedAudioData:(CMSampleBufferRef)sampleBuffer;

@end

@interface AACDecoder : NSObject

@property (nonatomic, weak) id<AACDecoderDelegate> delegate;
@property (nonatomic, strong) dispatch_queue_t dataCallbackQueue;

- (CMSampleBufferRef)startDecode:(AdtsUnit)adtsUnit;
- (void)endDecode;

@end
