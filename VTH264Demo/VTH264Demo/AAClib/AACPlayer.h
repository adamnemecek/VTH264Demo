//
//  AACPlayer.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/23.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AACPlayer : NSObject

- (instancetype)initWithFile:(NSString *)filePath;
- (void)play;
- (void)stop;
- (Float64)getCurrentTime;

@end
