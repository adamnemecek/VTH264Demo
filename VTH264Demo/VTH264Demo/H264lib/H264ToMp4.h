//
//  H264ToMp4.h
//  VTToolbox
//
//  Created by MOON on 2018/7/17.
//  Copyright © 2018年 Ganvir, Manish. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface H264ToMp4 : NSObject

- (instancetype)initWithVideoSize:(CGSize)videoSize srcFilePath:(NSString *)srcFilePath dstFilePath:(NSString *)dstFilePath;
- (void)startWriteWithCompletionHandler:(void (^)(void))handler;
- (void)endWritingCompletionHandler:(void (^)(void))handler;

@end
