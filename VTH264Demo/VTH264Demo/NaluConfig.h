//
//  config.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#ifndef __VTH264examples__config__
#define __VTH264examples__config__

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

#define h264outputWidth         800
#define h264outputHeight        600

#include <stdio.h>

#endif /* defined(__VTH264examples__config__) */
