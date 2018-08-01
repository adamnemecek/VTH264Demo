//
//  NaluHeader.h
//  VTToolbox
//
//  Created by MOON on 2018/7/17.
//  Copyright © 2018年 Ganvir, Manish. All rights reserved.
//

#import <Foundation/Foundation.h>

//nal类型
typedef enum nal_unit_type_e
{
    NAL_UNKNOWN     = 0,
    NAL_SLICE       = 1,
    NAL_SLICE_DPA   = 2,
    NAL_SLICE_DPB   = 3,
    NAL_SLICE_DPC   = 4,
    NAL_SLICE_IDR   = 5,    /* ref_idc != 0 */
    NAL_SEI         = 6,    /* ref_idc == 0 */
    NAL_SPS         = 7,
    NAL_PPS         = 8
    /* ref_idc == 0 for 6,9,10,11,12 */
} NaluUnitType;

typedef struct _NaluUnit
{
    int type;               //IDR or INTER：note：SequenceHeader is IDR too
    int size;               //note: don't contain startCode
    unsigned char *data;    //note: don't contain startCode
} NaluUnit;

@interface NaluHelper : NSObject

+ (NSData *)getH264Header;
+ (BOOL)readOneNaluFromAnnexBFormatH264:(NaluUnit *)nalu data:(NSData *)data curPos:(NSUInteger *)curPos;

@end



