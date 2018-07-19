//
//  NaluHeader.h
//  VTToolbox
//
//  Created by MOON on 2018/7/17.
//  Copyright © 2018年 Ganvir, Manish. All rights reserved.
//

#import "NaluHelper.h"

@implementation NaluHelper

+ (BOOL)readOneNaluFromAnnexBFormatH264:(NaluUnit *)nalu data:(NSData *)data curPos:(NSUInteger *)curPos
{
    NSUInteger i = *curPos;
    NSUInteger size = data.length;
    unsigned char *buf = (unsigned char *)[data bytes];
    
    while (i + 2 < size)
    {
        if (buf[i] == 0x00 && buf[i + 1] == 0x00 && buf[i + 2] == 0x01)
        {
            i = i + 3;
            int pos = i;
            while (pos + 2 < size)
            {
                if (buf[pos] == 0x00 && buf[pos + 1] == 0x00 && buf[pos + 2] == 0x01)
                {
                    break;
                }
                
                pos++;
            }
            
            if (pos + 2 == size)
            {
                (*nalu).size = pos + 2 - i;
            }
            else
            {
                while (buf[pos - 1] == 0x00)
                {
                    pos--;
                }
                
                (*nalu).size = pos - i;
            }
            
            (*nalu).type = buf[i] & 0x1f;
            (*nalu).data = buf + i;
            *curPos = pos;
            
            return TRUE;
        }
        else
        {
            i++;
        }
    }
    
    return FALSE;
}

@end

