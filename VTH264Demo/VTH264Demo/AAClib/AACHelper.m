//
//  AACHelper.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/25.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "AACHelper.h"

@implementation AACHelper

+ (NSData *)adtsData:(NSInteger)channel dataLength:(NSInteger)dataLength frequencyInHz:(NSInteger)frequencyInHz
{
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LCd kMPEG4Object_AAC_LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    NSInteger freqIdx = [self sampleToRateIndex:frequencyInHz];  //44.1KHz
    int chanCfg = (int)channel;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + dataLength;
    // fill in ADTS data
    packet[0] = (char)0xFF;     // 11111111     = syncword
    packet[1] = (char)0xF9;     // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile - 1) << 6) + (freqIdx << 2) + (chanCfg >> 2));
    packet[3] = (char)(((chanCfg & 3) << 6) + (fullLength >> 11));
    packet[4] = (char)((fullLength & 0x7FF) >> 3);
    packet[5] = (char)(((fullLength & 7) << 5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    
    return data;
}

+ (BOOL)readOneAtdsFromFormatAAC:(AdtsUnit *)adts data:(NSData *)data curPos:(NSUInteger *)curPos
{
    NSUInteger i = *curPos;
    NSUInteger size = data.length;
    unsigned char *buf = (unsigned char *)[data bytes];

    while (i + 7 < size)
    {
        if (buf[i] == 0xFF && buf[i + 1] == 0xF9)
        {
            (*adts).profile = ((buf[i + 2] >> 6) & 0x03) + 1;
            (*adts).frequencyInHz = [self rateIndexToSample:((buf[i + 2] >> 2) & 0x0F)];
            (*adts).channel = (buf[i + 3] >> 6) & 0x03;
            
            i = i + 7;
            int pos = (int)i;
            while (pos + 7 < size)
            {
                if (buf[pos] == 0xFF && buf[pos + 1] == 0xF9)
                {
                    break;
                }
                
                pos++;
            }
            
            if (pos + 7 == size)
            {
                (*adts).size = (int)(pos + 7 - i);
            }
            else
            {
                (*adts).size = (int)(pos - i);
            }

            (*adts).data = buf + i;
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

+ (NSInteger)sampleToRateIndex:(NSInteger)frequencyInHz
{
    NSInteger sampleRateIndex = 0;
    switch (frequencyInHz)
    {
        case 96000:
            sampleRateIndex = 0;
            break;
        case 88200:
            sampleRateIndex = 1;
            break;
        case 64000:
            sampleRateIndex = 2;
            break;
        case 48000:
            sampleRateIndex = 3;
            break;
        case 44100:
            sampleRateIndex = 4;
            break;
        case 32000:
            sampleRateIndex = 5;
            break;
        case 24000:
            sampleRateIndex = 6;
            break;
        case 22050:
            sampleRateIndex = 7;
            break;
        case 16000:
            sampleRateIndex = 8;
            break;
        case 12000:
            sampleRateIndex = 9;
            break;
        case 11025:
            sampleRateIndex = 10;
            break;
        case 8000:
            sampleRateIndex = 11;
            break;
        case 7350:
            sampleRateIndex = 12;
            break;
        default:
            sampleRateIndex = 15;
    }
    
    return sampleRateIndex;
}

+ (int)rateIndexToSample:(int)sampleRateIndex
{
    int sample = 0;
    switch (sampleRateIndex)
    {
        case 0:
            sample = 96000;
            break;
        case 1:
            sample = 88200;
            break;
        case 2:
            sample = 64000;
            break;
        case 3:
            sample = 48000;
            break;
        case 4:
            sample = 44100;
            break;
        case 5:
            sample = 32000;
            break;
        case 6:
            sample = 24000;
            break;
        case 7:
            sample = 22050;
            break;
        case 8:
            sample = 16000;
            break;
        case 9:
            sample = 12000;
            break;
        case 10:
            sample = 11025;
            break;
        case 11:
            sample = 8000;
            break;
        case 12:
            sample = 7350;
            break;
        default:
            sample = 44100;
    }
    
    return sample;
}

@end
