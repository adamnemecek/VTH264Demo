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
#import "GCDWebUploader.h"

#define H264_FILE_NAME      @"test.h264"

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
@property (nonatomic, assign) NSUInteger captureFrameCount;
@property (nonatomic, assign) NSUInteger encodeFrameCount;
@property (nonatomic, strong) NSString *h264File;
@property (nonatomic, assign) CGSize fileSize;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) GCDWebUploader *webServer;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.frame = [UIScreen mainScreen].bounds;
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.fileSize = CGSizeMake(h264outputWidth, h264outputHeight);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    self.h264File = [documentsDirectory stringByAppendingPathComponent:H264_FILE_NAME];
    [fileManager removeItemAtPath:self.h264File error:nil];
    [fileManager createFileAtPath:self.h264File contents:nil attributes:nil];
    NSLog( @"h264File at %@", self.h264File);
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.h264File];
    
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
    [self initCamera:self.cameraDeviceIsF];
    
    self.h264Encoder = [H264HwEncoder alloc];
    [self.h264Encoder initWithConfiguration];
    [self.h264Encoder initEncode:h264outputWidth height:h264outputHeight];
    self.h264Encoder.delegate = self;
    self.h264Encoder.dataCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    
    self.h264Decoder = [[H264HwDecoder alloc] init];
    self.h264Decoder.delegate = self;

    CGFloat btnTop = 50;
    CGFloat btnWidth = 100;
    CGFloat btnHeight = 40;
    CGSize size = [UIScreen mainScreen].bounds.size;
    CGFloat btnX = (size.width - btnWidth * 3) / 4;
    
    UIButton *startBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop, btnWidth, btnHeight)];
    [startBtn setTitle:@"打开" forState:UIControlStateNormal];
    [startBtn setBackgroundColor:[UIColor lightGrayColor]];
    [startBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [startBtn addTarget:self action:@selector(startBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:startBtn];
    startBtn.selected = NO;
    
    UIButton *switchBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop, btnWidth, btnHeight)];
    [switchBtn setTitle:@"切换" forState:UIControlStateNormal];
    [switchBtn setBackgroundColor:[UIColor lightGrayColor]];
    [switchBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [switchBtn addTarget:self action:@selector(switchBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    switchBtn.selected = NO;
    [self.view addSubview:switchBtn];
    
    UIButton *showFileBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 3 + btnWidth * 2, btnTop, btnWidth, btnHeight)];
    [showFileBtn setTitle:@"文件" forState:UIControlStateNormal];
    [showFileBtn setBackgroundColor:[UIColor lightGrayColor]];
    [showFileBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [showFileBtn addTarget:self action:@selector(showFileBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    showFileBtn.selected = NO;
    [self.view addSubview:showFileBtn];
    
    self.recordLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    [self.recordLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    self.recordLayer.frame = CGRectMake(0, btnTop + btnHeight + 10, size.width, (size.height - (btnTop + btnHeight + 10)) / 2);
    
    self.playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, self.recordLayer.frame.origin.y + self.recordLayer.frame.size.height, self.recordLayer.frame.size.width, self.recordLayer.frame.size.height)];
    self.playLayer.backgroundColor = [UIColor blackColor].CGColor;
}

- (void)startBtnClick:(UIButton *)btn
{
    btn.selected = !btn.selected;
    if (btn.selected == YES)
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.h264File error:nil];
        [[NSFileManager defaultManager] createFileAtPath:self.h264File contents:nil attributes:nil];
        self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.h264File];
        
        [self stopCamera];
        [self startCamera];
    }
    else
    {
        [self stopCamera];
        
        [self.fileHandle closeFile];
        self.fileHandle = nil;
    }
}

- (void)switchBtnClick:(UIButton *)btn
{
    if (self.captureSession.isRunning == YES)
    {
        self.cameraDeviceIsF = !self.cameraDeviceIsF;
        [self stopCamera];
        [self initCamera:self.cameraDeviceIsF];
        [self startCamera];
    }
}

- (void)showFileBtnClick:(id)sender
{
    [_webServer stop];
    _webServer = nil;
    _webServer = [[GCDWebUploader alloc] initWithUploadDirectory:NSHomeDirectory()];
    //    _webServer.delegate = self;
    _webServer.allowHiddenItems = YES;
    if ([_webServer startWithPort:9090 bonjourName:@"VTToolbox"])
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:[NSString stringWithFormat:@"浏览器访问:%@", _webServer.serverURL] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            
        }]];
        [self presentViewController:alert animated:YES completion:^{
            
        }];
    }
    else
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"无法启动服务" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            
        }]];
        [self presentViewController:alert animated:YES completion:^{
            
        }];
    }
}

#pragma - mark - Camera

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
    
    NSString *key = (NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    outputVideoDevice.videoSettings = videoSettings;
    
    [outputVideoDevice setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession addInput:inputCameraDevice];
    [self.captureSession addOutput:outputVideoDevice];
    [self.captureSession beginConfiguration];
    
    [self.captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset1280x720]];
    self.connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];
    
    [self.captureSession commitConfiguration];
}

- (void)startCamera
{
    [self.captureSession startRunning];
    [self.view.layer addSublayer:self.recordLayer];
    [self.view.layer addSublayer:self.playLayer];
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
    CMTime currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    self.captureFrameCount++;
    NSLog(@"captureOutput captureFrameCount %@, currentTime %@, timescale %@", @(self.captureFrameCount), @(currentTime.value), @(currentTime.timescale));
    
    if (connection == self.connectionVideo)
    {
        [self.h264Encoder startEncode:sampleBuffer];
    }
}

#pragma - mark - H264HwEncoderDelegate

- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps
{
    self.encodeFrameCount++;
    NSLog(@"getSpsPps sps length %@, frameCount %@", @(sps.length), @(self.encodeFrameCount));
    
    self.encodeFrameCount++;
    NSLog(@"getSpsPps pps length %@, frameCount %@", @(pps.length), @(self.encodeFrameCount));
    
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    //发sps
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:sps];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:sps];
    
    //发pps
    [h264Data resetBytesInRange:NSMakeRange(0, [h264Data length])];
    [h264Data setLength:0];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:pps];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:pps];
}

- (void)getEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame
{
    self.encodeFrameCount++;
    NSLog(@"getEncodedData data length %@, isKeyFrame %@, frameCount %@", @(data.length), @(isKeyFrame), @(self.encodeFrameCount));
    
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; 
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:data];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:data];
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
