//
//  ViewController.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "ViewController.h"
#import "AAPLEAGLLayer.h"
#import "NaluConfig.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "H264HwEncoder.h"
#import "H264HwDecoder.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, H264HwEncoderDelegate, H264HwDecoderDelegate>

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureConnection *connectionVideo;
@property (nonatomic, strong) AVCaptureDevice *cameraDeviceB;
@property (nonatomic, strong) AVCaptureDevice *cameraDeviceF;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *recordLayer;
@property (nonatomic, assign) BOOL cameraDeviceIsF;
@property (nonatomic, strong) H264HwEncoder *h264Encoder;
@property (nonatomic, strong) H264HwDecoder *h264Decoder;
@property (nonatomic, strong) AAPLEAGLLayer *playLayer;

@end

@implementation ViewController

- (instancetype)initWithFrame
{
    if (self= [super init])
    {
        
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.frame = [UIScreen mainScreen].bounds;
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.cameraDeviceIsF = YES;
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == AVCaptureDevicePositionFront)
        {
            self.cameraDeviceF = device;
        }
        else if(device.position == AVCaptureDevicePositionBack)
        {
            self.cameraDeviceB = device;
        }
    }
    
    self.h264Encoder = [H264HwEncoder alloc];
    [self.h264Encoder initWithConfiguration];
    [self.h264Encoder initEncode:h264outputWidth height:h264outputHeight];
    self.h264Encoder.delegate = self;
    
    self.h264Decoder = [[H264HwDecoder alloc] init];
    self.h264Decoder.delegate = self;

    UIButton *kaiguanBtn = [[UIButton alloc] initWithFrame:CGRectMake(50, 30, 100, 40)];
    [kaiguanBtn setTitle:@"开摄像头" forState:UIControlStateNormal];
    [kaiguanBtn setBackgroundColor:[UIColor redColor]];
    [kaiguanBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [kaiguanBtn addTarget:self action:@selector(kaiguanBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:kaiguanBtn];
    kaiguanBtn.selected = NO;
    
    UIButton *qianhouBtn = [[UIButton alloc] initWithFrame:CGRectMake(240, 30, 100, 40)];
    [qianhouBtn setTitle:@"前后摄像头" forState:UIControlStateNormal];
    [qianhouBtn setBackgroundColor:[UIColor redColor]];
    [qianhouBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [qianhouBtn addTarget:self action:@selector(qianhouBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    qianhouBtn.selected = NO;
    [self.view addSubview:qianhouBtn];
    
    CGSize size = [UIScreen mainScreen].bounds.size;
    self.playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, size.height / 2, size.width, size.height / 2)];
    self.playLayer.backgroundColor = [UIColor blackColor].CGColor;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)kaiguanBtnClick:(UIButton *)btn
{
    btn.selected = !btn.selected;
    if (btn.selected==YES)
    {
        [self stopCamera];
        [self initCamera:self.cameraDeviceIsF];
        [self startCamera];
    }
    else
    {
        [self stopCamera];
    }
}

- (void)qianhouBtnClick:(UIButton *)btn
{
    if (self.captureSession.isRunning == YES)
    {
        self.cameraDeviceIsF = !self.cameraDeviceIsF;
        NSLog(@"变位置");
        [self stopCamera];
        [self initCamera:self.cameraDeviceIsF];
        [self startCamera];
    }
}

- (void)initCamera:(BOOL)type
{
    NSError *deviceError;
    AVCaptureDeviceInput *inputCameraDevice;
    if (type == FALSE)
    {
        inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:self.cameraDeviceB error:&deviceError];
    }
    else
    {
        inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:self.cameraDeviceF error:&deviceError];
    }
    
    AVCaptureVideoDataOutput *outputVideoDevice = [[AVCaptureVideoDataOutput alloc] init];
    
    NSString *key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    outputVideoDevice.videoSettings = videoSettings;
    [outputVideoDevice setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession addInput:inputCameraDevice];
    [self.captureSession addOutput:outputVideoDevice];
    [self.captureSession beginConfiguration];
    
    [self.captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset1280x720]];
    self.connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];

    [self.captureSession commitConfiguration];
    self.recordLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    [self.recordLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
}

- (void)startCamera
{
    self.recordLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    [self.recordLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    CGSize size = [UIScreen mainScreen].bounds.size;
    self.recordLayer.frame = CGRectMake(0, 100, size.width, size.height / 2);
    [self.view.layer addSublayer:self.recordLayer];
    [self.captureSession startRunning];
    [self.view.layer addSublayer:self.recordLayer];
}

- (void)stopCamera
{
    [self.captureSession stopRunning];
    [self.recordLayer removeFromSuperlayer];
    [self.playLayer removeFromSuperlayer];
}

#pragma - mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (connection == self.connectionVideo)
    {
        [self.h264Encoder startEncode:sampleBuffer];
    }
}

#pragma - mark - H264HwEncoderDelegate

- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps
{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    //发sps
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:sps];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
    
    //发pps
    [h264Data resetBytesInRange:NSMakeRange(0, [h264Data length])];
    [h264Data setLength:0];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:pps];
    
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
}

- (void)getEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame
{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; 
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:data];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
}
    
#pragma - mark - H264HwDecoderDelegate

- (void)getDecodedData:(CVImageBufferRef)imageBuffer
{
    if (imageBuffer)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            self.playLayer.pixelBuffer = imageBuffer;
            CVPixelBufferRelease(imageBuffer);
        });
    }
}

@end
