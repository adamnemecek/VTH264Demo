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

@protocol AACDecoderDelegate <NSObject>

- (void)getDecodedAudioData:(NSData *)data;

@end

@interface AACDecoder : NSObject

@property (nonatomic, weak) id<AACDecoderDelegate> delegate;

- (void)startDecode:(uint8_t *)frame withSize:(uint32_t)frameSize;
- (void)endDecoder;

@end
