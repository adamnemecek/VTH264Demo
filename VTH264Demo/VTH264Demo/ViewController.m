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
#import "AACHelper.h"
#import "AACAudioPlayer.h"
#import "RtmpSocket.h"
#import "AACAudioOutputQueue.h"

#define h264outputWidth     800
#define h264outputHeight    600
#define H264_FPS            24

#define NOW                 (CACurrentMediaTime() * 1000)

//采用audiotoolbox还是采用AVCapture来采集音频
#define USE_AUDIO_TOOLBOX   0

#define H264_FILE_NAME      @"test.h264"
#define MP4_FILE_NAME       @"test.mp4"

#define AAC_FILE_NAME       @"test.aac"
#define MP3_FILE_NAME       @"test.mp3"

#define TEST_RTMP_URL       @"rtmp://47.52.16.147:1935/hls/stream001"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AACEncoderDelegate, H264HwEncoderDelegate, H264HwDecoderDelegate, GCDWebUploaderDelegate, RTMPSocketDelegate>

// UI
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
@property (nonatomic, strong) UIButton *pushRtmpBtn;
@property (nonatomic, strong) UIButton *pullRtmpBtn;
@property (nonatomic, strong) UITextField *pushTextField;
@property (nonatomic, strong) UITextField *pullTextField;

// 音视频设备
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

// 图像渲染
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *recordLayer;
@property (nonatomic, strong) AVSampleBufferDisplayLayer *sampleBufferDisplayLayer;
@property (nonatomic, strong) AAPLEAGLLayer *openGLPlayLayer;
@property (nonatomic, assign) BOOL useOpenGLPlayLayer;

// 视频编解码
@property (nonatomic, strong) H264HwEncoder *h264Encoder;
@property (nonatomic, strong) H264HwDecoder *h264Decoder;
@property (nonatomic, assign) BOOL useasynDecode;
@property (nonatomic, assign) BOOL timebaseSet;
@property (nonatomic, assign) CFTimeInterval frame0time;
@property (nonatomic, strong) dispatch_queue_t videoDataProcesQueue;
@property (nonatomic, assign) NSUInteger captureVideoFrameCount;
@property (nonatomic, assign) NSUInteger encodeVideoFrameCount;
@property (nonatomic, assign) NSUInteger decodeVideoFrameCount;

// 音频编解码
@property (nonatomic, strong) AACEncoder *aacEncoder;
@property (nonatomic, assign) UInt32 channelsPerFrame;
@property (nonatomic, strong) AVPlayerViewController *avPlayerVC;
@property (nonatomic, strong) AACAudioPlayer *aacPlayer;
@property (nonatomic, strong) AACAudioOutputQueue *audioQueue;
@property (nonatomic, assign) BOOL useAacPlayer;
@property (nonatomic, strong) dispatch_queue_t audioDataProcesQueue;

// 文件读写
@property (nonatomic, strong) H264ToMp4 *h264MP4;
@property (nonatomic, strong) NSString *h264File;
@property (nonatomic, strong) NSString *mp4File;
@property (nonatomic, assign) CGSize fileSize;
@property (nonatomic, strong) NSFileHandle *videoFileHandle;
@property (nonatomic, strong) NSString *aacFile;
@property (nonatomic, strong) NSString *mp3File;
@property (nonatomic, strong) NSFileHandle *audioFileHandle;

// HTTP server
@property (nonatomic, strong) GCDWebUploader *webServer;

// 推流
@property (nonatomic, strong) RTMPSocket *rtmpSocket;
@property (nonatomic, assign) uint64_t relativeTimestamps;  /// 上传相对时间戳
@property (nonatomic, assign) BOOL hasCaptureAudio;         /// 当前是否采集到了音频
@property (nonatomic, assign) BOOL hasKeyFrameVideo;        /// 当前是否采集到了关键帧
@property (nonatomic, assign) BOOL uploading;               /// 是否开始上传
@property (nonatomic, assign) BOOL isPublish;               /// 是推流还是拉流
@property (nonatomic, strong) dispatch_queue_t frameQueue;  /// 处理frame的队列
@property (nonatomic, assign) BOOL pulling;                 /// 开始拉流

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.frame = [UIScreen mainScreen].bounds;
    self.view.backgroundColor = [UIColor whiteColor];
    
    [GCDWebServer setLogLevel:4];
    
    //发送rtmp包队列
    self.frameQueue = dispatch_queue_create("com.pingan.sendFrame.queue", DISPATCH_QUEUE_SERIAL);
    
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
    
    self.cameraDeviceIsFront = YES;
    [self initCamera:self.cameraDeviceIsFront];
    
    [self initAudio];
    
    self.h264Encoder = [H264HwEncoder alloc];
    [self.h264Encoder initEncode:h264outputWidth height:h264outputHeight fps:H264_FPS];
    self.h264Encoder.delegate = self;
    self.h264Encoder.dataCallbackQueue = self.videoDataProcesQueue;
    
    self.useasynDecode = NO;
    self.h264Decoder = [[H264HwDecoder alloc] init];
    self.h264Decoder.delegate = self;
    self.h264Decoder.dataCallbackQueue = self.videoDataProcesQueue;
    self.h264Decoder.enableAsynDecompression = self.useasynDecode;
    [self.h264Decoder initEncode:h264outputWidth height:h264outputHeight];
    
    //按照单声道来编码，双声道在pcm和aac转换期间会失败
    self.channelsPerFrame = 1; // 1:单声道；2:双声道
    
    self.aacEncoder = [[AACEncoder alloc] init];
    self.aacEncoder.delegate = self;
    self.aacEncoder.channelsPerFrame = self.channelsPerFrame;
    self.aacEncoder.dataCallbackQueue = self.audioDataProcesQueue;
    
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
    
    UIButton *pushRtmpBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop * 5 + btnHeight * 4, btnWidth, btnHeight)];
    [pushRtmpBtn setTitle:@"RTMP推流" forState:UIControlStateNormal];
    [pushRtmpBtn setBackgroundColor:[UIColor lightGrayColor]];
    [pushRtmpBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [pushRtmpBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [pushRtmpBtn addTarget:self action:@selector(pushRtmpBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    pushRtmpBtn.selected = NO;
    [self.view addSubview:pushRtmpBtn];
    self.pushRtmpBtn = pushRtmpBtn;
    
    UITextField *pushTextField = [[UITextField alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop * 5 + btnHeight * 4, size.width - btnWidth - btnX * 3, btnHeight)];
    [pushTextField setTextAlignment:NSTextAlignmentCenter];
    [pushTextField setText:TEST_RTMP_URL];
    [pushTextField setTextColor:[UIColor blueColor]];
    [pushTextField setBackgroundColor:[UIColor lightGrayColor]];
    pushTextField.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:pushTextField];
    self.pushTextField = pushTextField;
    
    UIButton *pullRtmpBtn = [[UIButton alloc] initWithFrame:CGRectMake(btnX, btnTop * 6 + btnHeight * 5, btnWidth, btnHeight)];
    [pullRtmpBtn setTitle:@"RTMP拉流" forState:UIControlStateNormal];
    [pullRtmpBtn setBackgroundColor:[UIColor lightGrayColor]];
    [pullRtmpBtn.titleLabel setAdjustsFontSizeToFitWidth:YES];
    [pullRtmpBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [pullRtmpBtn addTarget:self action:@selector(pullRtmpBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    pullRtmpBtn.selected = NO;
    [self.view addSubview:pullRtmpBtn];
    self.pullRtmpBtn = pullRtmpBtn;
    
    UITextField *pullTextField = [[UITextField alloc] initWithFrame:CGRectMake(btnX * 2 + btnWidth, btnTop * 6 + btnHeight * 5, size.width - btnWidth - btnX * 3, btnHeight)];
    [pullTextField setTextAlignment:NSTextAlignmentCenter];
    [pullTextField setText:TEST_RTMP_URL];
    [pullTextField setTextColor:[UIColor blueColor]];
    [pullTextField setBackgroundColor:[UIColor lightGrayColor]];
    pullTextField.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:pullTextField];
    self.pullTextField = pullTextField;
    
    //显示拍摄原有内容
    self.recordLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    [self.recordLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    self.recordLayer.frame = CGRectMake(0, btnHeight * 6 + btnTop * 7, size.width, (size.height - (btnHeight * 6 + btnTop * 7)) / 2);
    
    self.useOpenGLPlayLayer = YES;
    
    //OpenGL代码来渲染H264解码帧
    self.openGLPlayLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, self.recordLayer.frame.origin.y + self.recordLayer.frame.size.height, self.recordLayer.frame.size.width, self.recordLayer.frame.size.height)];
    self.openGLPlayLayer.backgroundColor = [UIColor blackColor].CGColor;
    
    //用系统自带控件渲染H264解码帧
    self.sampleBufferDisplayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.sampleBufferDisplayLayer.frame = CGRectMake(0, self.recordLayer.frame.origin.y + self.recordLayer.frame.size.height, self.recordLayer.frame.size.width, self.recordLayer.frame.size.height);
    self.sampleBufferDisplayLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.sampleBufferDisplayLayer.opaque = YES;
    
    self.useAacPlayer = NO;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
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
    self.timebaseSet = 0;
}

- (void)switchBtnClick:(UIButton *)btn
{
    self.timebaseSet = 0;
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
    
    self.decodeVideoFrameCount = 0;
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
    
    self.timebaseSet = 0;
    self.frame0time = 0;
    self.decodeVideoFrameCount = 0;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NaluUnit naluUnit;
        NSUInteger curPos = 0;
        NSUInteger decodeFrameCount = 0;
        
        while ([NaluHelper readOneNaluFromAnnexBFormatH264:&naluUnit data:allData curPos:&curPos])
        {
            decodeFrameCount++;
            NSLog(@"naluUnit.type :%d, frameIndex:%@", naluUnit.type, @(decodeFrameCount));
            
            NSData *ByteHeader = [NaluHelper getH264Header];
            NSMutableData *h264Data = [[NSMutableData alloc] init];
            [h264Data appendData:ByteHeader];
            [h264Data appendData:[NSData dataWithBytes:naluUnit.data length:naluUnit.size]];

            [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:0];
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
    // H264 -> MP4
//    _h264MP4 = [[H264ToMp4 alloc] initWithVideoSize:self.fileSize videoFilePath:self.h264File dstFilePath:self.mp4File fps:H264_FPS];
    
    // H264 + AAC -> MP4
    NSString *pathAAC = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"aac"];
    NSString *pathH264 = nil;//[[NSBundle mainBundle] pathForResource:@"test" ofType:@"h264"];

    _h264MP4 = [[H264ToMp4 alloc] initWithVideoSize:self.fileSize videoFilePath:pathH264 audioFilePath:pathAAC dstFilePath:self.mp4File];
    
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
    //AVPlayer 无法直接播放H264文件，需要转MP4
    NSString *path = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"h264"];
    _h264MP4 = [[H264ToMp4 alloc] initWithVideoSize:self.fileSize videoFilePath:path dstFilePath:self.mp4File fps:H264_FPS];
    UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    view.center = self.view.center;
    [view setHidesWhenStopped:YES];
    [self.view addSubview:view];
    
    [view startAnimating];
    [_h264MP4 startWriteWithCompletionHandler:^{
        
        [view stopAnimating];
    }];
}

- (void)toMp3BtnClick:(id)sender
{

}

- (void)playMp3BtnClick:(id)sender
{
    UIButton *button = (UIButton *)sender;
    if (button.selected == NO)
    {
        //基于audioQueue播放
        NSString *path = [[NSBundle mainBundle] pathForResource:@"MP3Sample" ofType:@"mp3"];
        self.aacPlayer = [[AACAudioPlayer alloc] initWithFilePath:path fileType:kAudioFileMP3Type];
        [self.aacPlayer play];
    }
    else
    {
        [self.aacPlayer stop];
    }
    
    button.selected = !button.selected;
}

- (void)playAACBtnClick:(id)sender
{
    if (self.useAacPlayer)
    {
        //基于audioQueue播放
        self.aacPlayer = [[AACAudioPlayer alloc] initWithFilePath:self.aacFile fileType:kAudioFileAAC_ADTSType];
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

- (void)pushRtmpBtnClick:(UIButton *)sender
{
    sender.selected = !sender.selected;
    if (sender.selected == YES)
    {
        [self.pushRtmpBtn setTitle:@"停止推流" forState:UIControlStateNormal];
        self.isPublish = YES;
        NSURL *url = [NSURL URLWithString:self.pullTextField.text];
        _rtmpSocket = [[RTMPSocket alloc] initWithURL:url isPublish:self.isPublish];
        [_rtmpSocket setDelegate:self];
        [_rtmpSocket start];
    }
    else
    {
        [self.pushRtmpBtn setTitle:@"RTMP推流" forState:UIControlStateNormal];
        [self startBtnClick:self.startBtn];
        self.isPublish = NO;
        self.uploading = NO;
        [_rtmpSocket stop];        
    }
}

- (void)pullRtmpBtnClick:(UIButton *)sender
{
    sender.selected = !sender.selected;
    if (sender.selected == YES)
    {
        [self.pullRtmpBtn setTitle:@"停止拉流" forState:UIControlStateNormal];
        self.pulling = YES;
        self.isPublish = NO;
        NSURL *url = [NSURL URLWithString:self.pullTextField.text];
        _rtmpSocket = [[RTMPSocket alloc] initWithURL:url isPublish:self.isPublish];
        [_rtmpSocket setDelegate:self];
        [_rtmpSocket start];
        
        if (self.useOpenGLPlayLayer)
        {
            [self.view.layer addSublayer:self.openGLPlayLayer];
        }
        else
        {
            [self.view.layer addSublayer:self.sampleBufferDisplayLayer];
        }
    }
    else
    {
        [self.pullRtmpBtn setTitle:@"RTMP拉流" forState:UIControlStateNormal];
        self.pulling = NO;
        self.isPublish = NO;
        
        if (self.useOpenGLPlayLayer)
        {
            [self.openGLPlayLayer removeFromSuperlayer];
        }
        else
        {
            [self.sampleBufferDisplayLayer removeFromSuperlayer];
        }
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
    desc.mChannelsPerFrame = self.channelsPerFrame;
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
    if ([self.captureSession canAddInput:inputCameraDevice] == NO)
    {
        NSLog(@"Couldn't add video input");
        return;
    }
    [self.captureSession addInput:inputCameraDevice];
    
    if ([self.captureSession canAddOutput:outputVideoDevice] == NO)
    {
        NSLog(@"Couldn't add video output");
        return;
    }
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

- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset
{
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
    CMSampleTimingInfo *pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++)
    {
        pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    
    CMSampleBufferRef sout;
    CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
    free(pInfo);
    
    return sout;
}

#pragma - mark - Use AVSampleBufferDisplayLayer
//把pixelBuffer包装成samplebuffer送给displayLayer
- (void)dispatchPixelBuffer:(CVPixelBufferRef)pixelBuffer timeStamp:(uint64_t)timeStamp
{
    if (!pixelBuffer)
    {
        return;
    }

    //设置每帧数据的显示时间pts, 不设置的话，每帧数据会以60fps的速度播放
    if (self.frame0time == 0)
    {
        //记录第一帧的时间戳，再根据fps调整后续每一帧的时间戳
        self.frame0time = CACurrentMediaTime();
        NSLog(@"frame0time = %@", @(self.frame0time));
    }

    CMTime pts;
    if (timeStamp > 0)
    {
        pts = CMTimeMake(timeStamp, 1000);
    }
    else
    {
        pts = CMTimeMakeWithSeconds(self.frame0time + (1.0 / H264_FPS) * self.decodeVideoFrameCount, 1000);
    }
    
    CMSampleTimingInfo timing = {
        .presentationTimeStamp = pts,
        .duration = CMTimeMakeWithSeconds(1.0 / H264_FPS, 1000),
        .decodeTimeStamp = kCMTimeInvalid
    };

    NSLog(@"frame %@ timing pts value %@ pts timescale %@, duration value %@ duration timescale %@", @(self.decodeVideoFrameCount), @(timing.presentationTimeStamp.value), @(timing.presentationTimeStamp.timescale), @(timing.duration.value), @(timing.duration.timescale));
    
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
    
    //kCMSampleAttachmentKey_DisplayImmediately 为 ture 就不考虑时间戳渲染, 这里每帧都设置了时间戳，所以要关掉
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanFalse);

    //设置每帧数据的显示时间pts, 不设置的话，每帧数据会以60fps的速度播放, controlTimebase只能设置一次
    CMTime ptsInitial = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    double seconds = CMTimeGetSeconds(ptsInitial);
    if (!self.timebaseSet && seconds != 0)
    {
        NSLog(@"timebaseSet ptsInitial value %@ v timescale %@", @(ptsInitial.value), @(ptsInitial.timescale));
        
        self.timebaseSet = YES;
        CMTimebaseRef controlTimebase;
        CMTimebaseCreateWithMasterClock(CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase);
        CMTimebaseSetTime(controlTimebase, CMTimeMake(seconds, 1));
        CMTimebaseSetRate(controlTimebase, 1.0);
        self.sampleBufferDisplayLayer.controlTimebase = controlTimebase;
    }

    [self enqueueSampleBuffer:sampleBuffer toLayer:self.sampleBufferDisplayLayer];
    CFRelease(sampleBuffer);
}

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer toLayer:(AVSampleBufferDisplayLayer *)layer
{
    if (sampleBuffer)
    {
        CFRetain(sampleBuffer);
//        if ([layer isReadyForMoreMediaData])
        {
            [layer enqueueSampleBuffer:sampleBuffer];
        }
//        else
//        {
//            NSLog(@"Not Ready...");
//        }
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

#pragma - mark - Push Stream

- (BOOL)alignment
{
    if (self.hasCaptureAudio && self.hasKeyFrameVideo)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

- (uint64_t)uploadTimestamp:(uint64_t)captureTimestamp
{
    uint64_t currentts = 0;
    currentts = captureTimestamp - self.relativeTimestamps;
    
    return currentts;
}

- (void)pushSendBuffer:(RTMPFrame *)frame
{
    dispatch_async(self.frameQueue, ^{
        
        if (self.relativeTimestamps == 0)
        {
            //记录音视频对齐之后的第一个发出去的帧时间戳，后续帧时间戳只记录差值，记录相对时间
            self.relativeTimestamps = frame.timestamp;
        }
        
        frame.timestamp = [self uploadTimestamp:frame.timestamp];
        [self.rtmpSocket sendFrame:frame];
        
        NSLog(@"pushSendBuffer frame length = %@", @(frame.data.length));
    });
}

#pragma - mark - Pull Stream

- (void)pullReceiveBuffer
{
    dispatch_async(self.frameQueue, ^{
        
        RTMPFrame *frame;
        while (self.pulling)
        {
            @autoreleasepool {
                
                frame = [_rtmpSocket receiveFrame];
                if (frame)
                {
                    if ([frame isKindOfClass:[RTMPVideoFrame class]])
                    {
                        [self processVideoFrame:(RTMPVideoFrame *)frame];
                    }
                    else if ([frame isKindOfClass:[RTMPAudioFrame class]])
                    {
                        [self processAudioFrame:(RTMPAudioFrame *)frame];
                    }
                }
            }
            
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01f]];
        }
        
        if (self.pulling == NO)
        {
            [_rtmpSocket stop];
        }
    });
}

- (void)processVideoFrame:(RTMPVideoFrame *)videoFrame
{
    dispatch_async(self.videoDataProcesQueue, ^{
        
        NSData *ByteHeader = [NaluHelper getH264Header];
        if (videoFrame.sps.length > 0)
        {
            NSMutableData *h264Data = [[NSMutableData alloc] init];
            [h264Data appendData:ByteHeader];
            [h264Data appendData:[NSData dataWithBytes:[videoFrame.sps bytes] length:videoFrame.sps.length]];
            [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:0];
        }
        
        if (videoFrame.pps.length > 0)
        {
            NSMutableData *h264Data = [[NSMutableData alloc] init];
            [h264Data appendData:ByteHeader];
            [h264Data appendData:[NSData dataWithBytes:[videoFrame.pps bytes] length:videoFrame.pps.length]];
            [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:0];
        }
        
        if (videoFrame.data.length > 0)
        {
            NSMutableData *h264Data = [[NSMutableData alloc] init];
            [h264Data appendData:ByteHeader];
            [h264Data appendData:[NSData dataWithBytes:[videoFrame.data bytes] length:videoFrame.data.length]];
            [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:videoFrame.timestamp];
        }
    });
}

- (void)processAudioFrame:(RTMPAudioFrame *)audioFrame
{
    static int numberOfChannels = 0;
    static int sampleRate = 0;

    if (audioFrame.numberOfChannels > 0)
    {
        numberOfChannels = audioFrame.numberOfChannels;
        sampleRate = audioFrame.sampleRate;
        
        dispatch_async(self.audioDataProcesQueue, ^{
            
            if (!self.audioQueue)
            {
                AudioStreamBasicDescription format;
                memset(&format, 0, sizeof(format));
                format.mSampleRate = [AACHelper rateIndexToSample:sampleRate];
                format.mFormatID = kAudioFormatMPEG4AAC;
                format.mFormatFlags = kMPEG4Object_AAC_LC;
                format.mChannelsPerFrame = numberOfChannels;
                format.mFramesPerPacket = 1024;
                
                self.audioQueue = [[AACAudioOutputQueue alloc] initWithFormat:format bufferSize:2000 macgicCookie:nil];
            }
        });
    }
    
    if (audioFrame.data.length > 0)
    {
        audioFrame.numberOfChannels = numberOfChannels;
        audioFrame.sampleRate = sampleRate;
        
        dispatch_async(self.audioDataProcesQueue, ^{
            
            if (self.audioQueue)
            {
                AudioStreamPacketDescription description;
                memset(&description, 0, sizeof(AudioStreamPacketDescription));
                description.mDataByteSize = (UInt32)(audioFrame.data.length);
                description.mStartOffset = 0;
                description.mVariableFramesInPacket = 0;
                
                [self.audioQueue playData:audioFrame.data packetCount:1 packetDescriptions:&description isEof:NO];
            }
        });
    }
}

#pragma - mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (connection == self.connectionVideo)
    {
        CMFormatDescriptionRef des = CMSampleBufferGetFormatDescription(sampleBuffer);
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer);
        int bufferWidth = (int)CVPixelBufferGetWidth(cameraFrame);
        int bufferHeight = (int)CVPixelBufferGetHeight(cameraFrame);

        self.captureVideoFrameCount++;
        NSLog(@"captureOutput captureVideoFrameCount %@, pts value %@, pts timescale %@, dts value %@, dts timescale %@, duration value %@, duration timescale %@, bufferWidth %@, bufferHeight %@, des %@", @(self.captureVideoFrameCount), @(pts.value), @(pts.timescale), @(dts.value), @(dts.timescale), @(duration.value), @(duration.timescale), @(bufferWidth), @(bufferHeight), des);
    
        //系统采样返回的时间戳 对于 AVAssetWriter 本地写文件有用，网络传输没什么用，这里重新获取时间戳
        [self.h264Encoder startEncode:sampleBuffer timeStamp:NOW];
    }
    else if (connection == self.connectionAudio)
    {
        CMFormatDescriptionRef des = CMSampleBufferGetFormatDescription(sampleBuffer);
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);

        self.captureAudioFrameCount++;
        NSLog(@"captureOutput captureAudioFrameCount %@, pts value %@, pts timescale %@, dts value %@, dts timescale %@, duration value %@, duration timescale %@des %@", @(self.captureAudioFrameCount), @(pts.value), @(pts.timescale), @(dts.value), @(dts.timescale), @(duration.value), @(duration.timescale), des);
        
        //系统采样返回的时间戳 对于 AVAssetWriter 本地写文件有用，网络传输没什么用，这里重新获取时间戳
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
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:0];
    
    //发pps
    [h264Data resetBytesInRange:NSMakeRange(0, [h264Data length])];
    [h264Data setLength:0];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:pps];
    [self.videoFileHandle writeData:h264Data];
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:0];
}

- (void)getEncodedVideoData:(NSData *)data sps:(NSData *)sps pps:(NSData *)pps isKeyFrame:(BOOL)isKeyFrame timeStamp:(uint64_t)timeStamp
{
    self.encodeVideoFrameCount++;
    NSLog(@"getEncodedVideoData data length %@, isKeyFrame %@, frameCount %@, timeStamp %@", @(data.length), @(isKeyFrame), @(self.encodeVideoFrameCount), @(timeStamp));

    NSData *ByteHeader = [NaluHelper getH264Header];
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:ByteHeader];
    [h264Data appendData:data];
    [self.videoFileHandle writeData:h264Data];
    
    // 上传, 时间戳对齐
    if (self.uploading)
    {
        RTMPVideoFrame *videoFrame = [RTMPVideoFrame new];
        videoFrame.timestamp = timeStamp;
        videoFrame.data = data;
        videoFrame.isKeyFrame = isKeyFrame;
        videoFrame.sps = sps;
        videoFrame.pps = pps;
        
        //做音视频同步，此处要判断是否采集到音频，否则收到关键帧也丢弃
        if (videoFrame.isKeyFrame)
        {
            if (self.hasCaptureAudio)
            {
                self.hasKeyFrameVideo = YES;
            }
        }
        
        if ([self alignment])
        {
            [self pushSendBuffer:videoFrame];
        }
    }
    
    [self.h264Decoder startDecode:(uint8_t *)[h264Data bytes] withSize:(uint32_t)h264Data.length timeStamp:0];
}
    
#pragma - mark - H264HwDecoderDelegate

- (void)getDecodedVideoData:(CVImageBufferRef)imageBuffer timeStamp:(uint64_t)timeStamp
{
    CGSize bufferSize = CVImageBufferGetDisplaySize(imageBuffer);
    
    self.decodeVideoFrameCount++;
    NSLog(@"getDecodedData decodeVideoFrameCount %@, bufferWidth %@, bufferHeight %@, timeStamp %@", @(self.decodeVideoFrameCount), @(bufferSize.width), @(bufferSize.height), @(timeStamp));
    
    if (imageBuffer)
    {
        if (self.useOpenGLPlayLayer)
        {
            [self dispatchImageBuffer:imageBuffer];
        }
        else
        {
            [self dispatchPixelBuffer:imageBuffer timeStamp:timeStamp];
        }
    }
}

#pragma - mark - AACEncoderDelegate

- (void)getEncodedAudioData:(NSData *)data timeStamp:(uint64_t)timeStamp
{
    self.encodeAudioFrameCount++;
    NSLog(@"getEncodedAudioData data length %@, frameCount %@", @(data.length), @(self.encodeAudioFrameCount));

    NSData *dataAdts = [AACHelper adtsData:self.channelsPerFrame dataLength:data.length frequencyInHz:44100];
    NSMutableData *aacData = [[NSMutableData alloc] init];
    [aacData appendData:dataAdts];
    [aacData appendData:data];
    
    [self.audioFileHandle writeData:aacData];
    
    // 上传, 时间戳对齐
    if (self.uploading)
    {
        self.hasCaptureAudio = YES;
        if ([self alignment])
        {
            RTMPAudioFrame *audioFrame = [RTMPAudioFrame new];
            audioFrame.timestamp = timeStamp;
            audioFrame.data = data;
            audioFrame.sampleRate = 4; // 对应44100
            audioFrame.numberOfChannels = self.channelsPerFrame;
            
            [self pushSendBuffer:audioFrame];
        }
    }
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

#pragma - mark - RTMPSocketDelegate

- (void)socketBufferStatus:(RTMPSocket *)socket status:(RTMPBuffferState)status
{
    NSLog(@"socketBufferStatus status %@", @(status));
}

- (void)socketStatus:(RTMPSocket *)socket status:(RTMPSocketState)status
{
    NSLog(@"socketStatus status %@", @(status));
    if (status == RTMPSocketStart)
    {
        if (self.isPublish)
        {
            self.uploading = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startBtnClick:self.startBtn];
            });
        }
        else
        {
            [self pullReceiveBuffer];
        }
    }
}

- (void)socketDidError:(RTMPSocket *)socket errorCode:(RTMPErrorCode)errorCode
{
    NSLog(@"socketDidError errorCode %@", @(errorCode));
}

@end
