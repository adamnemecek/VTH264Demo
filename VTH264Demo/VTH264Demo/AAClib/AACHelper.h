//
//  AACHelper.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/25.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AACHelper : NSObject

+ (NSData *)adtsData:(NSInteger)channel dataLength:(NSInteger)dataLength;

@end
