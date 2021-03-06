//
//  RtmpSocket.h
//  VTH264Demo
//
//  Created by MOON on 2018/7/18.
//  Copyright © 2018年 MOON. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM (NSUInteger, RTMPBuffferState) {
    RTMPBuffferUnknown = 0,     // 未知
    RTMPBuffferIncrease = 1,    // 缓冲区状态差应该降低码率
    RTMPBuffferDecline = 2      // 缓冲区状态好应该提升码率
};

/// 流状态
typedef NS_ENUM (NSUInteger, RTMPSocketState) {
    RTMPSocketReady = 0,        /// 准备
    RTMPSocketPending = 1,      /// 连接中
    RTMPSocketStart = 2,        /// 已连接
    RTMPSocketStop = 3,         /// 已断开
    RTMPSocketError = 4,        /// 连接出错
    RTMPSocketRefresh = 5       ///  正在刷新
};

typedef NS_ENUM (NSUInteger, RTMPErrorCode) {
    RTMPError_PreView = 201,              ///< 预览失败
    RTMPError_GetStreamInfo = 202,        ///< 获取流媒体信息失败
    RTMPError_ConnectSocket = 203,        ///< 连接socket失败
    RTMPError_Verification = 204,         ///< 验证服务器失败
    RTMPError_ReConnectTimeOut = 205      ///< 重新连接服务器超时
};

@interface RTMPFrame : NSObject

@property (nonatomic, assign) uint64_t timestamp;
@property (nonatomic, strong) NSData *data;

@end

@interface RTMPAudioFrame : RTMPFrame

@property (nonatomic, assign) int numberOfChannels;
@property (nonatomic, assign) int sampleRate;

@end

@interface RTMPVideoFrame : RTMPFrame

@property (nonatomic, assign) BOOL isKeyFrame;
@property (nonatomic, strong) NSData *sps;
@property (nonatomic, strong) NSData *pps;

@end

@class RTMPSocket;
@protocol RTMPSocketDelegate <NSObject>
@optional
// 回调当前缓冲区情况，可实现相关切换帧率 码率等策略
- (void)socketBufferStatus:(RTMPSocket *)socket status:(RTMPBuffferState)status;
// 回调当前网络情况
- (void)socketStatus:(RTMPSocket *)socket status:(RTMPSocketState)status;
- (void)socketDidError:(RTMPSocket *)socket errorCode:(RTMPErrorCode)errorCode;

@end

@interface RTMPSocket : NSObject

- (instancetype)initWithURL:(nullable NSURL *)url isPublish:(BOOL)isPublish;
- (void)start;
- (void)stop;
- (void)sendFrame:(nullable RTMPFrame *)frame;
- (RTMPFrame *)receiveFrame;
- (void)setDelegate:(nullable id <RTMPSocketDelegate>)delegate;

@end
