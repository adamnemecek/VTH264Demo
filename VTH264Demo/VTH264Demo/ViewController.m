//
//  ViewController.m
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import "ViewController.h"
#import "AAPLEAGLLayer.h"
#import "NaluHelper.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import "H264HwEncoder.h"
#import "H264HwDecoder.h"
#import "H264ToMp4.h"
#import "GCDWebUploader.h"
#import "AACEncoder.h"
#import "AACDecoder.h"
#import "AACHelper.h"
#import "AACPlayer.h"

#define NOW                 (CACurrentMediaTime() * 1000)

//采用audiotoolbox还是采用AVCapture来采集音频
#define USE_AUDIO_TOOLBOX   0

#define H264_FILE_NAME      @"test.h264"
#define MP4_FILE_NAME       @"test.mp4"

#define AAC_FILE_NAME       @"test.aac"
#define MP3_FILE_NAME       @"test.mp3"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AACEncoderDelegate, AACDecoderDelegate, H264HwEncoderDelegate, H264HwDecoderDelegate, GCDWebUploaderDelegate>

@property (nonatomic, assign) AudioComponentInstance componetInstance;
@property (nonatomic, assign) AudioComponent component;
@property (nonatomic, strong) dispatch_queue_t taskQueue;
@property (nonatomic, assign) NSUInteger captureAudioFrameCount;
@property (nonatomic, assign) NSUInteger encodeAudioFrameCount;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureConnection *connectionVideo;
@property (nonatomic, strong) AVCaptureConnection *connectionAudio;
@property (nonatomic, strong) AVCaptureDevice *cameraDeviceBack;
@property (nonatomic, strong) AVCaptureDevice *cameraDeviceFront;
@property (nonatomic, assign) BOOL cameraDeviceIsFront;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *recordLayer;
@property (nonatomic, strong) AVSampleBufferDisplayLayer *sampleBufferDisplayLayer;
@property (nonatomic, strong) AAPLEAGLLayer *openGLPlayLayer;
@property (nonatomic, assign) BOOL useOpenGLPlayLayer;
@property (nonatomic, strong) H264HwEncoder *h264Encoder;
@property (nonatomic, strong) H264HwDecoder *h264Decoder;
@property (nonatomic, assign) BOOL useasynDecode;
@property (nonatomic, strong) H264ToMp4 *h264MP4;
@property (nonatomic, strong) AACEncoder *aacEncoder;
@property (nonatomic, strong) AACDecoder *aacDecoder;
@property (nonatomic, strong) AVPlayerViewController *avPlayerVC;
@property (nonatomic, strong) AACPlayer *aacPlayer;
@property (nonatomic, assign) BOOL useAacPlayer;
@property (nonatomic, strong) dispatch_queue_t videoDataProcesQueue;
@property (nonatomic, strong) dispatch_queue_t audioDataProcesQueue;
@property (nonatomic, assign) NSUInteger captureVideoFrameCount;
@property (nonatomic, assign) NSUInteger encodeVideoFrameCount;
@property (nonatomic, assign) NSUInteger decodeVideoFrameCount;
@property (nonatomic, strong) NSString *h264File;
@property (nonatomic, strong) NSString *mp4File;
@property (nonatomic, assign) CGSize fileSize;
@property (nonatomic, strong) NSFileHandle *videoFileHandle;
@property (nonatomic, strong) NSString *aacFile;
@property (nonatomic, strong) NSString *mp3File;
@property (nonatomic, strong) NSFileHandle *audioFileHandle;
@property (nonatomic, strong) GCDWebUploader *webServer;
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, strong) UIButton *switchBtn;
@property (nonatomic, strong) UIButton *showFileBtn;
@property (nonatomic, strong) UIButton *displayBtn;
@property (nonatomic, strong) UIButton *fileDisplayBtn;
@property (nonatomic, strong) UIButton *toMp4Btn;
@property (nonatomic, strong) UIButton *playMp4Btn;
@property (nonatomic, strong) UIButton *playH264Btn;
@property (nonatomic, strong) UIButton *asynDecodeBtn;
@property (nonatomic, strong) UIButton *toMp3Btn;
@property (nonatomic, strong) UIButton *playMp3Btn;
@property (nonatomic, strong) UIButton *playAACBtn;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.frame = [UIScreen mainScreen].bounds;
    self.view.backgroundColor = [UIColor whiteColor];
    
    [GCDWebServer setLogLevel:4];
    
    //视频编码后数据返回的队列
    self.videoDataProcesQueue = dispatch_queue_create("com.pingan.videoProces.queue", DISPATCH_QUEUE_SERIAL);
    //音频编码后数据返回的队列
    self.audioDataProcesQueue = dispatch_queue_create("com.pingan.audioProces.queue", DISPATCH_QUEUE_SERIAL);
    
    self.fileSize = CGSizeMake(h264outputWidth, h264outputHeight);
    
    //音视频文件存储路径
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    //H264文件路径
    self.h264File = [documentsDirectory stringByAppendingPathComponent:H264_FILE_NAME];
    [fileManager removeItemAtPath:self.h264File error:nil];
    [fileManager createFileAtPath:self.h264File contents:nil attributes:nil];
    NSLog(@"h264File at %@", self.h264File);
    self.videoFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.h264File];
    
    //H264转换为mp4文件路径
    self.mp4File = [documentsDirectory stringByAppendingPathComponent:MP4_FILE_NAME];
    
    //AAC文件路径
    self.aacFile = [documentsDirectory stringByAppendingPathComponent:AAC_FILE_NAME];
    [fileManager removeItemAtPath:self.aacFile error:nil];
    [fileManager createFileAtPath:self.aacFile contents:nil attributes:nil];
    NSLog(@"aacFile at %@", self.aacFile);
    self.audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.aacFile];
    
    //AAC转换为mp3文件路径
    self.mp3File = [documentsDirectory stringByAppendingPathComponent:MP3_FILE_NAME];
    
    self.cameraDeviceIsFront = NO;
    [self initCamera:self.cameraDeviceIsFront];
    
    [self initAudio];
    
    self.h264Encoder = [H264HwEncoder alloc];
    [self.h264Encoder initEncode:h264outputWidth height:h264outputHeight];
    self.h264Encoder.delegate = self;
    self.h264Encoder.dataCallbackQueue = self.videoDataProcesQueue;
    
    self.useasynDecode = NO;
    self.h264Decoder = [[H264HwDecoder alloc] init];
    self.h264Decoder.delegate = self;
    self.h264Decoder.dataCallbackQueue = self.videoDataProcesQueue;
    self.h264Decoder.enableAsynDecompression = self.useasynDecode;
    
    self.aacEncoder = [[AACEncoder alloc] init];
    self.aacEncoder.delegate = self;
    
    self.aacDecoder = [[AACDecoder alloc] init];
    self.aacDecoder.delegate = self;
    
    CGFloat btnTop = 50;
    CGFloat btnWidth = 100;
    CGFloat btnHeight = 40;
    CGSize size = [UIScreen mainScreen].bounds.size;
    CGFloat btnX = (size.width - btnWidth * 3) / 4;
    
    UIButton *startBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop, btnWidth, btnHeight)];
    [startBtn setTitle:@"打开摄像头" forState:UIControlStateNormal];
    [startBtn setBackgroundColor:[UIColor lightGrayColor]];
    [startBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [startBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [startBtn addTarget:self action:@selector(startBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:startBtn];
    startBtn.selected = NO;
    self.startBtn = startBtn;
    
    UIButton *switchBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop, btnWidth, btnHeight)];
    [switchBtn setTitle:@"切换摄像头" forState:UIControlStateNormal];
    [switchBtn setBackgroundColor:[UIColor lightGrayColor]];
    [switchBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [switchBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [switchBtn addTarget:self action:@selector(switchBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    switchBtn.selected = NO;
    [self.view addSubview:switchBtn];
    self.switchBtn = switchBtn;
    
    UIButton *showFileBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 3 + btnWidth * 2, btnTop, btnWidth, btnHeight)];
    [showFileBtn setTitle:@"文件服务器" forState:UIControlStateNormal];
    [showFileBtn setBackgroundColor:[UIColor lightGrayColor]];
    [showFileBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [showFileBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [showFileBtn addTarget:self action:@selector(showFileBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    showFileBtn.selected = NO;
    [self.view addSubview:showFileBtn];
    self.showFileBtn = showFileBtn;
    
    UIButton *displayBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop * 2 + btnHeight, btnWidth, btnHeight)];
    [displayBtn setTitle:@"系统预览" forState:UIControlStateNormal];
    [displayBtn setBackgroundColor:[UIColor lightGrayColor]];
    [displayBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [displayBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [displayBtn addTarget:self action:@selector(displayBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    displayBtn.selected = NO;
    [self.view addSubview:displayBtn];
    self.displayBtn = displayBtn;
    
    UIButton *fileDisplayBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop * 2 + btnHeight, btnWidth, btnHeight)];
    [fileDisplayBtn setTitle:@"从文件解码" forState:UIControlStateNormal];
    [fileDisplayBtn setBackgroundColor:[UIColor lightGrayColor]];
    [fileDisplayBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [fileDisplayBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [fileDisplayBtn addTarget:self action:@selector(fileDisplayBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    fileDisplayBtn.selected = NO;
    [self.view addSubview:fileDisplayBtn];
    self.fileDisplayBtn = fileDisplayBtn;
    
    UIButton *asynDecodeBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 3 + btnWidth * 2, btnTop * 2 + btnHeight, btnWidth, btnHeight)];
    [asynDecodeBtn setTitle:@"异步解码" forState:UIControlStateNormal];
    [asynDecodeBtn setBackgroundColor:[UIColor lightGrayColor]];
    [asynDecodeBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [asynDecodeBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [asynDecodeBtn addTarget:self action:@selector(asynDecodeBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    asynDecodeBtn.selected = NO;
    [self.view addSubview:asynDecodeBtn];
    self.asynDecodeBtn = asynDecodeBtn;
    
    UIButton *toMp4Btn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop * 3 + btnHeight * 2, btnWidth, btnHeight)];
    [toMp4Btn setTitle:@"H264转MP4" forState:UIControlStateNormal];
    [toMp4Btn setBackgroundColor:[UIColor lightGrayColor]];
    [toMp4Btn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [toMp4Btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [toMp4Btn addTarget:self action:@selector(toMp4BtnClick:) forControlEvents:UIControlEventTouchUpInside];
    toMp4Btn.selected = NO;
    [self.view addSubview:toMp4Btn];
    self.toMp4Btn = toMp4Btn;
    
    UIButton *playMp4Btn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop * 3 + btnHeight * 2, btnWidth, btnHeight)];
    [playMp4Btn setTitle:@"播放MP4" forState:UIControlStateNormal];
    [playMp4Btn setBackgroundColor:[UIColor lightGrayColor]];
    [playMp4Btn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [playMp4Btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [playMp4Btn addTarget:self action:@selector(playMp4BtnClick:) forControlEvents:UIControlEventTouchUpInside];
    playMp4Btn.selected = NO;
    [self.view addSubview:playMp4Btn];
    self.playMp4Btn = playMp4Btn;
    
    UIButton *playH264Btn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 3 + btnWidth * 2, btnTop * 3 + btnHeight * 2, btnWidth, btnHeight)];
    [playH264Btn setTitle:@"播放H264" forState:UIControlStateNormal];
    [playH264Btn setBackgroundColor:[UIColor lightGrayColor]];
    [playH264Btn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [playH264Btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [playH264Btn addTarget:self action:@selector(playH264BtnClick:) forControlEvents:UIControlEventTouchUpInside];
    playH264Btn.selected = NO;
    [self.view addSubview:playH264Btn];
    self.playH264Btn = playH264Btn;
    
    UIButton *toMp3Btn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop * 4 + btnHeight * 3, btnWidth, btnHeight)];
    [toMp3Btn setTitle:@"AAC转MP3" forState:UIControlStateNormal];
    [toMp3Btn setBackgroundColor:[UIColor lightGrayColor]];
    [toMp3Btn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [toMp3Btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [toMp3Btn addTarget:self action:@selector(toMp3BtnClick:) forControlEvents:UIControlEventTouchUpInside];
    toMp3Btn.selected = NO;
    [self.view addSubview:toMp3Btn];
    self.toMp3Btn = toMp3Btn;
    
    UIButton *playMp3Btn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop * 4 + btnHeight * 3, btnWidth, btnHeight)];
    [playMp3Btn setTitle:@"播放MP3" forState:UIControlStateNormal];
    [playMp3Btn setBackgroundColor:[UIColor lightGrayColor]];
    [playMp3Btn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [playMp3Btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [playMp3Btn addTarget:self action:@selector(playMp3BtnClick:) forControlEvents:UIControlEventTouchUpInside];
    playMp3Btn.selected = NO;
    [self.view addSubview:playMp3Btn];
    self.playMp4Btn = playMp3Btn;
    
    UIButton *playAACBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX * 3 + btnWidth * 2, btnTop * 4 + btnHeight * 3, btnWidth, btnHeight)];
    [playAACBtn setTitle:@"播放AAC" forState:UIControlStateNormal];
    [playAACBtn setBackgroundColor:[UIColor lightGrayColor]];
    [playAACBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [playAACBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [playAACBtn addTarget:self action:@selector(playAACBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    playAACBtn.selected = NO;
    [self.view addSubview:playAACBtn];
    self.playAACBtn = playAACBtn;
    
    //显示拍摄原有内容
    self.recordLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    [self.recordLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    self.recordLayer.frame = CGRectMake(0, btnHeight * 4 + btnTop * 5, size.width, (size.height - (btnHeight * 4 + btnTop * 5)) / 2);
    
    self.useOpenGLPlayLayer = YES;
    
    //OpenGL代码来渲染H264解码帧
    self.openGLPlayLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, self.recordLayer.frame.origin.y + self.recordLayer.frame.size.height, self.recordLayer.frame.size.width, self.recordLayer.frame.size.height)];
    self.openGLPlayLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    //用系统自带控件渲染H264解码帧
    self.sampleBufferDisplayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.sampleBufferDisplayLayer.frame = CGRectMake(0, self.recordLayer.frame.origin.y + self.recordLayer.frame.size.height, self.recordLayer.frame.size.width, self.recordLayer.frame.size.height);
    self.sampleBufferDisplayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.sampleBufferDisplayLayer.opaque = YES;
    
    self.useAacPlayer = YES;
}

#pragma - mark - UI

- (void)startBtnClick:(UIButton *)btn
{
    btn.selected = !btn.selected;
    if (btn.selected == YES)
    {
        [self.startBtn setTitle:@"关闭摄像头" forState:UIControlStateNormal];
        
        [self.videoFileHandle closeFile];
        self.videoFileHandle = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.h264File error:nil];
        [[NSFileManager defaultManager] createFileAtPath:self.h264File contents:nil attributes:nil];
        self.videoFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.h264File];
        
        [self.audioFileHandle closeFile];
        self.audioFileHandle = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.aacFile error:nil];
        [[NSFileManager defaultManager] createFileAtPath:self.aacFile contents:nil attributes:nil];
        self.audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.aacFile];
        
        [self stopCamera];
        [self startCamera];
        [self stopAudio];
        [self startAudio];
    }
    else
    {
        [self.startBtn setTitle:@"打开摄像头" forState:UIControlStateNormal];
        [self stopCamera];
        [self stopAudio];
    }
    
    self.captureVideoFrameCount = 0;
}

- (void)switchBtnClick:(UIButton *)btn
{
    if (self.captureSession.isRunning == YES)
    {
        NSLog(@"###############摄像头切换###############");
        
        self.cameraDeviceIsFront = !self.cameraDeviceIsFront;
        [self stopCamera];
        [self initCamera:self.cameraDeviceIsFront];
        [self initAudio];
        
        CGRect frame = self.recordLayer.frame;
        self.recordLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
        [self.recordLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
        self.recordLayer.frame = frame;

        [self startCamera];
        self.captureVideoFrameCount = 0;
        [self startAudio];
    }
}

- (void)showFileBtnClick:(id)sender
{
    [_webServer stop];
    _webServer = nil;
    _webServer = [[GCDWebUploader alloc] initWithUploadDirectory:NSHomeDirectory()];
    _webServer.delegate = self;
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

- (void)displayBtnClick:(id)sender
{
    [self.openGLPlayLayer removeFromSuperlayer];
    [self.sampleBufferDisplayLayer removeFromSuperlayer];
    
    self.useOpenGLPlayLayer = !self.useOpenGLPlayLayer;
    if (self.useOpenGLPlayLayer)
    {
        [self.displayBtn setTitle:@"系统预览" forState:UIControlStateNormal];
        [self.view.layer addSublayer:self.openGLPlayLayer];
    }
    else
    {
        [self.displayBtn setTitle:@"OpenGL预览" forState:UIControlStateNormal];
        [self.view.layer addSublayer:self.sampleBufferDisplayLayer];
    }
}

- (void)fileDisplayBtnClick:(id)sender
{
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.h264File];
    NSData *allData = [fileHandle readDataToEndOfFile];
    if (allData.length == 0)
    {
        return;
    }

    [self.openGLPlayLayer removeFromSuperlayer];
    [self.sampleBufferDisplayLayer removeFromSuperlayer];
    if (self.useOpenGLPlayLayer)
    {
        [self.view.layer addSublayer:self.openGLPlayLayer];
    }
    else
    {
        [self.view.layer addSublayer:self.sampleBufferDisplayLayer];
    }
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NaluUnit naluUnit;
        NSUInteger curPos = 0;
        NSUInteger decodeFrameCount = 0;
        
        while ([NaluHelper readOneNaluFromAnnexBFormatH264:&naluUnit data:allData curPos:&curPos])
        {
            decodeFrameCount++;
            NSLog(@"naluUnit.type :%d, frameIndex:%@", naluUnit.type, @(decodeFrameCount));
            
            const char bytes[] = "\x00\x00\x00\x01";
            size_t length = (sizeof bytes) - 1;
            NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
            NSMutableData *h264Data = [[NSMutableData alloc] init];
            [h264Data appendData:ByteHeader];
            [h264Data appendData:[NSData dataWithBytes:naluUnit.data length:naluUnit.size]];

            [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
        }
    });
}

- (void)asynDecodeBtnClick:(id)sender
{
    self.useasynDecode = !self.useasynDecode;
    if (self.useasynDecode)
    {
        [self.asynDecodeBtn setTitle:@"同步解码" forState:UIControlStateNormal];
    }
    else
    {
        [self.asynDecodeBtn setTitle:@"异步解码" forState:UIControlStateNormal];
    }
    
    self.h264Decoder.enableAsynDecompression = self.useasynDecode;
    [self.h264Decoder resetH264Decoder];
}

- (void)toMp4BtnClick:(id)sender
{
    _h264MP4 = [[H264ToMp4 alloc] initWithVideoSize:self.fileSize srcFilePath:self.h264File dstFilePath:self.mp4File];
    UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    view.center = self.view.center;
    [view setHidesWhenStopped:YES];
    [self.view addSubview:view];
    
    [view startAnimating];
    [_h264MP4 startWriteWithCompletionHandler:^{
        
        [view stopAnimating];
    }];
}

- (void)playMp4BtnClick:(id)sender
{
    CGSize size = [UIScreen mainScreen].bounds.size;
    self.avPlayerVC = [[AVPlayerViewController alloc] init];
    self.avPlayerVC.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.mp4File]];
    self.avPlayerVC.view.frame = CGRectMake(0, 0, size.width, size.height);
    self.avPlayerVC.showsPlaybackControls = YES;
    
    [self presentViewController:self.avPlayerVC animated:YES completion:^{
        
        [self.avPlayerVC.player play];
    }];
}

- (void)playH264BtnClick:(id)sender
{
    //AVPlayer 无法直接播放H264文件，需要解码
    CGSize size = [UIScreen mainScreen].bounds.size;
    self.avPlayerVC = [[AVPlayerViewController alloc] init];
    self.avPlayerVC.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.h264File]];
    self.avPlayerVC.view.frame = CGRectMake(0, 0, size.width, size.height);
    self.avPlayerVC.showsPlaybackControls = YES;
    
    [self presentViewController:self.avPlayerVC animated:YES completion:^{
        
        [self.avPlayerVC.player play];
    }];
}

- (void)toMp3BtnClick:(id)sender
{

}

- (void)playMp3BtnClick:(id)sender
{

}

- (void)playAACBtnClick:(id)sender
{
    if (self.useAacPlayer)
    {
        //基于audioQueue播放
        self.aacPlayer = [[AACPlayer alloc] initWithFile:self.aacFile];
        [self.aacPlayer play];
    }
    else
    {
        //AVPlayer 可以直接播放AAC文件
        CGSize size = [UIScreen mainScreen].bounds.size;
        self.avPlayerVC = [[AVPlayerViewController alloc] init];
        self.avPlayerVC.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.aacFile]];
        self.avPlayerVC.view.frame = CGRectMake(0, 0, size.width, size.height);
        self.avPlayerVC.showsPlaybackControls = YES;
        
        [self presentViewController:self.avPlayerVC animated:YES completion:^{
            
            [self.avPlayerVC.player play];
        }];
    }
}

#pragma - mark - Audio

- (void)initAudio
{
#if USE_AUDIO_TOOLBOX
    self.taskQueue = dispatch_queue_create("com.pingan.audioCapture.Queue", NULL);
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_Output;
    //acd.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    acd.componentSubType = kAudioUnitSubType_RemoteIO;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    
    self.component = AudioComponentFindNext(NULL, &acd);
    
    OSStatus status = noErr;
    status = AudioComponentInstanceNew(self.component, &_componetInstance);
    if (noErr != status)
    {
        NSLog(@"status %@", @(status));
        return;
    }
    
    UInt32 flagOne = 1;
    
    AudioUnitSetProperty(self.componetInstance, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &flagOne, sizeof(flagOne));
    
    AudioStreamBasicDescription desc = {0};
    desc.mSampleRate = 44100;
    desc.mFormatID = kAudioFormatLinearPCM;
    desc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    desc.mChannelsPerFrame = 2;
    desc.mFramesPerPacket = 1;
    desc.mBitsPerChannel = 16;
    desc.mBytesPerFrame = desc.mBitsPerChannel / 8 * desc.mChannelsPerFrame;
    desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
    
    AURenderCallbackStruct cb;
    cb.inputProcRefCon = (__bridge void *)(self);
    cb.inputProc = handleInputBuffer;
    AudioUnitSetProperty(self.componetInstance, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &desc, sizeof(desc));
    AudioUnitSetProperty(self.componetInstance, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, sizeof(cb));
    
    status = AudioUnitInitialize(self.componetInstance);
    if (noErr != status)
    {
        NSLog(@"status %@", @(status));
        return;
    }
    
    [session setPreferredSampleRate:44100 error:nil];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers error:nil];
    [session setActive:YES withOptions:kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation error:nil];
    
    [session setActive:YES error:nil];
    return;
#else
    //用 AVCaptureDevice 无法设置音频采样率，双通道这些参数
    NSError *error;
    AVCaptureDevice *audioDev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (audioDev == nil)
    {
        NSLog(@"Couldn't create audio capture device");
        return;
    }

    NSArray *array = audioDev.formats;
    NSLog(@"audioDev formats %@", array);
    
    AVCaptureDeviceInput *audioIn = [AVCaptureDeviceInput deviceInputWithDevice:audioDev error:&error];
    if (error != nil)
    {
        NSLog(@"Couldn't create audio input");
        return;
    }

    [self.captureSession beginConfiguration];
    
    if ([self.captureSession canAddInput:audioIn] == NO)
    {
        NSLog(@"Couldn't add audio input");
        return;
    }

    [self.captureSession addInput:audioIn];
    
    // export audio data
    AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [audioOutput setSampleBufferDelegate:self queue:self.audioDataProcesQueue];
    if ([self.captureSession canAddOutput:audioOutput] == NO)
    {
        NSLog(@"Couldn't add audio output");
        return ;
    }
    
    [self.captureSession addOutput:audioOutput];
    
    [self.captureSession commitConfiguration];
    
    self.connectionAudio = [audioOutput connectionWithMediaType:AVMediaTypeAudio];

    return;
#endif
}

- (void)startAudio
{
#if USE_AUDIO_TOOLBOX
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers error:nil];
    OSStatus status = AudioOutputUnitStart(self.componetInstance);
    NSLog(@"startAudio status %@", @(status));
#endif
}

- (void)stopAudio
{
#if USE_AUDIO_TOOLBOX
    OSStatus status = AudioOutputUnitStop(self.componetInstance);
    NSLog(@"stopAudio status %@", @(status));
#endif
}

#pragma - mark - AURenderCallback

OSStatus handleInputBuffer(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
    @autoreleasepool {
        
        ViewController *ref = (__bridge ViewController *)inRefCon;
        if (!ref)
        {
            return -1;
        }
        
        ref.captureAudioFrameCount++;
        NSLog(@"handleInputBuffer captureAudioFrameCount %@, mSampleTime %@, mHostTime %@, inBusNumber %@, inNumberFrames %@", @(ref.captureAudioFrameCount), @(inTimeStamp->mSampleTime), @(inTimeStamp->mHostTime), @(inBusNumber), @(inNumberFrames));
        
        AudioStreamBasicDescription desc = {0};
        desc.mSampleRate = 48000;
        desc.mFormatID = kAudioFormatLinearPCM;
        desc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        desc.mChannelsPerFrame = 2;
        desc.mFramesPerPacket = 1;
        desc.mBitsPerChannel = 16;
        desc.mBytesPerFrame = desc.mBitsPerChannel / 8 * desc.mChannelsPerFrame;
        desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
        
        CMSampleBufferRef buff = NULL;
        CMFormatDescriptionRef format = NULL;
        
        OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &desc, 0, NULL, 0, NULL, NULL, &format);
        if (status)
        {
            NSLog(@"CMAudioFormatDescriptionCreate status %@", @(status));
            return status;
        }
        
        CMSampleTimingInfo timing = {CMTimeMake(1, 48000), kCMTimeZero, kCMTimeInvalid};
        
        status = CMSampleBufferCreate(kCFAllocatorDefault, NULL, false, NULL, NULL, format, (CMItemCount)inNumberFrames, 1, &timing, 0, NULL, &buff);
        if (status)
        {
            NSLog(@"CMSampleBufferCreate status %@", @(status));
            return status;
        }

        AudioBuffer buffer;
        buffer.mData = NULL;
        buffer.mDataByteSize = 0;
        buffer.mNumberChannels = 2;
        
        AudioBufferList buffers;
        buffers.mNumberBuffers = 1;
        buffers.mBuffers[0] = buffer;

        status = AudioUnitRender(ref.componetInstance, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &buffers);
        if (status)
        {
            NSLog(@"AudioUnitRender status %@", @(status));
            return status;
        }
        
        status = CMSampleBufferSetDataBufferFromAudioBufferList(buff, kCFAllocatorDefault, kCFAllocatorDefault, 0, &buffers);
        if (!status)
        {
            [ref.aacEncoder startEncode:buff timeStamp:0];
        }
        
        return status;
    }
}

#pragma - mark - Camera

- (void)initCamera:(BOOL)cameraDeviceIsFront
{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == AVCaptureDevicePositionFront)
        {
            self.cameraDeviceFront = device;
            NSArray *array = device.formats;
            NSLog(@"videoDevice Front formats %@", array);
        }
        else if(device.position == AVCaptureDevicePositionBack)
        {
            self.cameraDeviceBack = device;
            NSArray *array = device.formats;
            NSLog(@"videoDevice Back formats %@", array);
        }
    }
    
    NSError *deviceError;
    AVCaptureDeviceInput *inputCameraDevice;
    if (cameraDeviceIsFront == FALSE)
    {
        inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:self.cameraDeviceBack error:&deviceError];
    }
    else
    {
        inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:self.cameraDeviceFront error:&deviceError];
    }
    
    AVCaptureVideoDataOutput *outputVideoDevice = [[AVCaptureVideoDataOutput alloc] init];
    
    //硬解必须是 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange 或者是kCVPixelFormatType_420YpCbCr8Planar
    NSString *key = (NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    outputVideoDevice.videoSettings = videoSettings;
    [outputVideoDevice setSampleBufferDelegate:self queue:self.videoDataProcesQueue];
    
    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession addInput:inputCameraDevice];
    [self.captureSession addOutput:outputVideoDevice];
    [self.captureSession beginConfiguration];
    if (cameraDeviceIsFront == YES)
    {
//        self.captureSession.sessionPreset = AVCaptureSessionPresetMedium; //480 * 360
//        self.captureSession.sessionPreset = AVCaptureSessionPresetLow; //192 * 144
//        self.captureSession.sessionPreset = AVCaptureSessionPresetHigh; //1280 * 720
        self.captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    }
    else
    {
        self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    }
    self.connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];
    [self.captureSession commitConfiguration];
}

- (void)startCamera
{
    [self.captureSession startRunning];
    [self.view.layer addSublayer:self.recordLayer];
    if (self.useOpenGLPlayLayer)
    {
        [self.view.layer addSublayer:self.openGLPlayLayer];
    }
    else
    {
        [self.view.layer addSublayer:self.sampleBufferDisplayLayer];
    }
}

- (void)stopCamera
{
    [self.captureSession stopRunning];
    [self.recordLayer removeFromSuperlayer];
    [self.openGLPlayLayer removeFromSuperlayer];
    [self.sampleBufferDisplayLayer removeFromSuperlayer];
}

#pragma - mark - Use AVSampleBufferDisplayLayer
//把pixelBuffer包装成samplebuffer送给displayLayer
- (void)dispatchPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if (!pixelBuffer)
    {
        return;
    }
    
    CMTime frameTime = CMTimeMake(1, 24);
    CMSampleTimingInfo timing = {frameTime, frameTime, kCMTimeInvalid};
    
    //获取视频信息
    CMVideoFormatDescriptionRef videoInfo = NULL;
    OSStatus result = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
    if (result != 0 || videoInfo == nil)
    {
        return;
    }
    
    CMSampleBufferRef sampleBuffer = NULL;
    result = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, videoInfo, &timing, &sampleBuffer);
    if (result != 0 || sampleBuffer == nil)
    {
        return;
    }

    CFRelease(pixelBuffer);
    CFRelease(videoInfo);
    
    //同步显示
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    
    //kCMSampleAttachmentKey_DisplayImmediately 为 ture 就不考虑时间戳渲染
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanFalse);
    
    //设置每帧数据的时间戳
    CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, CMTimeMake(self.decodeVideoFrameCount, 24));

    [self enqueueSampleBuffer:sampleBuffer toLayer:self.sampleBufferDisplayLayer];
    CFRelease(sampleBuffer);
}

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer toLayer:(AVSampleBufferDisplayLayer *)layer
{
    if (sampleBuffer)
    {
        CFRetain(sampleBuffer);
        [layer enqueueSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
        if (layer.status == AVQueuedSampleBufferRenderingStatusFailed)
        {
            NSLog(@"ERROR: %@", layer.error);
            [layer flush];
        }
        else
        {
            NSLog(@"STATUS: %i", (int)layer.status);
        }
    }
    else
    {
        NSLog(@"ignore null samplebuffer");
    }
}

#pragma - mark - Use OpenGLPlayLayer

- (void)dispatchImageBuffer:(CVImageBufferRef)imageBuffer
{
    if (!imageBuffer)
    {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.openGLPlayLayer.pixelBuffer = imageBuffer;
        CVPixelBufferRelease(imageBuffer);
    });
}

#pragma - mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (connection == self.connectionVideo)
    {
        CMFormatDescriptionRef des = CMSampleBufferGetFormatDescription(sampleBuffer);
        CMTime currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
        int bufferWidth = (int)CVPixelBufferGetWidth(cameraFrame);
        int bufferHeight = (int)CVPixelBufferGetHeight(cameraFrame);

        self.captureVideoFrameCount++;
        NSLog(@"captureOutput captureVideoFrameCount %@, currentTime %@, timescale %@, duration %@, durationScale %@, bufferWidth %@, bufferHeight %@, des %@", @(self.captureVideoFrameCount), @(currentTime.value), @(currentTime.timescale), @(duration.value), @(duration.timescale), @(bufferWidth), @(bufferHeight), des);
    
        //系统采样返回的时间戳没什么用，这里重新获取时间戳
        [self.h264Encoder startEncode:sampleBuffer timeStamp:NOW];
    }
    else if (connection == self.connectionAudio)
    {
        CMFormatDescriptionRef des = CMSampleBufferGetFormatDescription(sampleBuffer);
        CMTime currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        
        self.captureAudioFrameCount++;
        NSLog(@"captureOutput captureAudioFrameCount %@, currentTime %@, timescale %@, duration %@, durationScale %@, des %@", @(self.captureAudioFrameCount), @(currentTime.value), @(currentTime.timescale), @(duration.value), @(duration.timescale), des);
        
        //系统采样返回的时间戳没什么用，这里重新获取时间戳
        [self.aacEncoder startEncode:sampleBuffer timeStamp:NOW];
    }
}

#pragma - mark - H264HwEncoderDelegate

- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps
{
    self.encodeVideoFrameCount++;
    NSLog(@"getSpsPps sps length %@, frameCount %@", @(sps.length), @(self.encodeVideoFrameCount));
    
    self.encodeVideoFrameCount++;
    NSLog(@"getSpsPps pps length %@, frameCount %@", @(pps.length), @(self.encodeVideoFrameCount));
    
    NSData *ByteHeader = [NaluHelper getH264Header];
    
    //发sps
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:sps];
    [self.videoFileHandle writeData:h264Data];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
    
    //发pps
    [h264Data resetBytesInRange:NSMakeRange(0, [h264Data length])];
    [h264Data setLength:0];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:pps];
    [self.videoFileHandle writeData:h264Data];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
}

- (void)getEncodedVideoData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame timeStamp:(uint64_t)timeStamp
{
    self.encodeVideoFrameCount++;
    NSLog(@"getEncodedVideoData data length %@, isKeyFrame %@, frameCount %@, timeStamp %@", @(data.length), @(isKeyFrame), @(self.encodeVideoFrameCount), @(timeStamp));

    NSData *ByteHeader = [NaluHelper getH264Header];
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:data];
    [self.videoFileHandle writeData:h264Data];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length];
}
    
#pragma - mark - H264HwDecoderDelegate

- (void)getDecodedVideoData:(CVImageBufferRef)imageBuffer
{
    CGSize bufferSize = CVImageBufferGetDisplaySize(imageBuffer);
    
    self.decodeVideoFrameCount++;
    NSLog(@"getDecodedData decodeVideoFrameCount %@, bufferWidth %@, bufferHeight %@", @(self.decodeVideoFrameCount), @(bufferSize.width), @(bufferSize.height));
    
    if (imageBuffer)
    {
        if (self.useOpenGLPlayLayer)
        {
            [self dispatchImageBuffer:imageBuffer];
        }
        else
        {
            [self dispatchPixelBuffer:imageBuffer];
        }
    }
}

#pragma - mark - AACEncoderDelegate

- (void)getEncodedAudioData:(NSData *)data timeStamp:(uint64_t)timeStamp
{
    self.encodeAudioFrameCount++;
    NSLog(@"getEncodedAudioData data length %@, frameCount %@", @(data.length), @(self.encodeAudioFrameCount));

    NSData *dataAdts = [AACHelper adtsData:2 dataLength:data.length];
    NSMutableData *aacData = [[NSMutableData alloc] init];
    [aacData appendData:dataAdts];
    [aacData appendData:data];
    
    [self.audioFileHandle writeData:aacData];
}

#pragma - mark - GCDWebUploaderDelegate

- (void)webUploader:(GCDWebUploader *)uploader didDownloadFileAtPath:(NSString *)path
{
    NSLog(@"webUploader didDownloadFileAtPath:%@", path);
}

- (void)webUploader:(GCDWebUploader *)uploader didUploadFileAtPath:(NSString *)path
{
    NSLog(@"webUploader didUploadFileAtPath:%@", path);
}

- (void)webUploader:(GCDWebUploader *)uploader didDeleteItemAtPath:(NSString *)path
{
    NSLog(@"webUploader didDeleteItemAtPath:%@", path);
}

@end
