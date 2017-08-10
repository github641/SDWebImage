/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageDownloader.h"
#import "SDWebImageOperation.h"

/* lzy注170726：
 SDWebImageDownloader监听了这两个 通知
 */
extern NSString * _Nonnull const SDWebImageDownloadStartNotification;
extern NSString * _Nonnull const SDWebImageDownloadStopNotification;

/* lzy注170726：
 这两个通知sd对外开放，但是sd本身并未使用
 */
extern NSString * _Nonnull const SDWebImageDownloadReceiveResponseNotification;
extern NSString * _Nonnull const SDWebImageDownloadFinishNotification;



/**协议，一系列的下载操作描述。如果开发者想使用一个自定义的下载op，这个自定义的op需要是『NSOperation』的子类，并且需要遵守这个协议
 Describes a downloader operation. If one wants to use a custom downloader op, it needs to inherit from `NSOperation` and conform to this protocol
 */
@protocol SDWebImageDownloaderOperationInterface<NSObject>

- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options;

- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

- (BOOL)shouldDecompressImages;
- (void)setShouldDecompressImages:(BOOL)value;

- (nullable NSURLCredential *)credential;
- (void)setCredential:(nullable NSURLCredential *)value;

@end

/* lzy注170726：
 sd网络图片下载器操作类
 */
@interface SDWebImageDownloaderOperation : NSOperation <SDWebImageDownloaderOperationInterface, SDWebImageOperation, NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

/**
 * The request used by the operation's task.
 */
@property (strong, nonatomic, readonly, nullable) NSURLRequest *request;

/**
 * The operation's task
 */
@property (strong, nonatomic, readonly, nullable) NSURLSessionTask *dataTask;

/* lzy注170726：
 SDWebImageDownloaderOperationInterface协议方法的setter和getter
 */
@property (assign, nonatomic) BOOL shouldDecompressImages;

/**现在这个类没有用了。之前用于决定URL 链接是否应该先看看 『credential storage』是否授权链接。好几个版本之前就没有用了。
 *  Was used to determine whether the URL connection should consult the credential storage for authenticating the connection.
 *  @deprecated Not used for a couple of versions
 */
@property (nonatomic, assign) BOOL shouldUseCredentialStorage __deprecated_msg("Property deprecated. Does nothing. Kept only for backwards compatibility");

/**
 SDWebImageDownloaderOperationInterface协议方法的setter和getter
 一个请求的『认证挑战』方法`-connection:didReceiveAuthenticationChallenge:`中，用于应对的『证书』
 * The credential used for authentication challenges in `-connection:didReceiveAuthenticationChallenge:`.
 *
 * This will be overridden by any shared credentials that exist for the username or password of the request URL, if present.
 */
@property (nonatomic, strong, nullable) NSURLCredential *credential;

/**
 * The SDWebImageDownloaderOptions for the receiver.
 */
@property (assign, nonatomic, readonly) SDWebImageDownloaderOptions options;

/**预期的二进制数据的大小
 * The expected size of data.
 */
@property (assign, nonatomic) NSInteger expectedSize;

/**
 * The response returned by the operation's connection.
 */
@property (strong, nonatomic, nullable) NSURLResponse *response;

/** SDWebImageDownloaderOperationInterface协议方法：初始化一个op实例
 *  Initializes a `SDWebImageDownloaderOperation` object
 *
 *  @see SDWebImageDownloaderOperation
 *
 *  @param request        the URL request
 *  @param session        the URL session in which this operation will run
 *  @param options        downloader options
 *
 *  @return the initialized instance
 */
- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options NS_DESIGNATED_INITIALIZER;

/** SDWebImageDownloaderOperationInterface协议方法。
 添加进度和完成处理block。返回一个可以给他发送-cancel：方法的token。
 *  Adds handlers for progress and completion. Returns a token that can be passed to -cancel: to cancel this set of
 *  callbacks.
 *
 *  @param progressBlock  the block executed when a new chunk of data arrives.
 *                        @note the progress block is executed on a background queue
 *  @param completedBlock the block executed when the download is done.
 *                        @note the completed block is executed on the main queue for success. If errors are found, there is a chance the block will be executed on a background queue
 *
 *  @return the token to use to cancel this set of handlers
 */
- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

/** 取消一系列的 回调block。一旦所有的 回调block都被取消了。相应的op也将被取消。
 *  Cancels a set of callbacks. Once all callbacks are canceled, the operation is cancelled.
 *
 *  @param token the token representing a set of callbacks to cancel
 *
 *  @return YES if the operation was stopped because this was the last token to be canceled. NO otherwise.
 */
- (BOOL)cancel:(nullable id)token;

@end
