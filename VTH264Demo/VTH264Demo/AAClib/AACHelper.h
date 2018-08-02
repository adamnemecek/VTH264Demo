//
//  AACHelper.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/25.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct _AdtsUnit
{
    int profile;
    int channel;
    int frequencyInHz;
    int size;
    unsigned char *data;
} AdtsUnit;

@interface AACHelper : NSObject

+ (NSData *)adtsData:(NSInteger)channel dataLength:(NSInteger)dataLength frequencyInHz:(NSInteger)frequencyInHz;
+ (BOOL)readOneAtdsFromFormatAAC:(AdtsUnit *)adts data:(NSData *)data curPos:(NSUInteger *)curPos;

@end
