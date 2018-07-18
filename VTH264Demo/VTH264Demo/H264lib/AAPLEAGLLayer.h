//
//  AAPLEAGLLayer.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#include <QuartzCore/QuartzCore.h>
#include <CoreVideo/CoreVideo.h>

@interface AAPLEAGLLayer : CAEAGLLayer

@property CVPixelBufferRef pixelBuffer;

- (id)initWithFrame:(CGRect)frame;
- (void)resetRenderBuffer;

@end
