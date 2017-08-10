/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"
#import "SDWebImageOperation.h"

/* lzy注170725：
 图片下载选项 枚举
 */
typedef NS_OPTIONS(NSUInteger, SDWebImageDownloaderOptions) {
    SDWebImageDownloaderLowPriority = 1 << 0,
    SDWebImageDownloaderProgressiveDownload = 1 << 1,

    /**NSURLCache做缓存策略。
     默认是不是用NSURLCache做缓存的。
     * By default, request prevent the use of NSURLCache. With this flag, NSURLCache
     * is used with default policies.
     */
    SDWebImageDownloaderUseNSURLCache = 1 << 2,

    /**忽略缓存返回的数据。使用这个flag：如果图片数据是从NSURLCache中读取的，在完成回调调用时，将回调空的image和imageData
     * Call completion block with nil image/imageData if the image was read from NSURLCache
     * (to be combined with `SDWebImageDownloaderUseNSURLCache`).
     */
    SDWebImageDownloaderIgnoreCachedResponse = 1 << 3,
    
    /**
     * In iOS 4+, continue the download of the image if the app goes to background. This is achieved by asking the system for
     * extra time in background to let the request finish. If the background task expires the operation will be cancelled.
     */
    /* lzy注170725：
     app在后台状态继续下载图片。
     在iOS4+，当app进入后台，继续图片的下载操作。实现方式是询问系统要求在后台活跃更长的时间用于把图片下载下来。如果后台任务到期了，图片下载任务也将被取消。
     */
    SDWebImageDownloaderContinueInBackground = 1 << 4,

    /**
     * Handles cookies stored in NSHTTPCookieStore by setting 
     * NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     */
    /* lzy注170725：
     设置NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     则sd将处理存储在NSHTTPCookieStore中的cookies
     */
    SDWebImageDownloaderHandleCookies = 1 << 5,

    /**
     * Enable to allow untrusted SSL certificates.
     * Useful for testing purposes. Use with caution in production.
     */
    /* lzy注170720：
     运行不被信任的SSL证书。
     生成环境小心使用，可以用于测试目的。
     */
    SDWebImageDownloaderAllowInvalidSSLCertificates = 1 << 6,

    /**
     * Put the image in the high priority queue.
     */
    SDWebImageDownloaderHighPriority = 1 << 7,
    
    /**
     * Scale down the image
     */
    /* lzy注170725：
     缩小大图。若`SDWebImageProgressiveDownload`生效，这个标志位将不会生效。
     默认，图片是根据其原始尺寸进行解码的。
     在iOS平台上，在一些内存有限的设备中，图片将被兼容性地缩小。
     */
    SDWebImageDownloaderScaleDownLargeImages = 1 << 8,
};

/* lzy注170725：
下载任务执行顺序
 */
typedef NS_ENUM(NSInteger, SDWebImageDownloaderExecutionOrder) {
    /**先进先出。默认。
     * Default value. All download operations will execute in queue style (first-in-first-out).
     */
    SDWebImageDownloaderFIFOExecutionOrder,

    /**后进先出。
     * All download operations will execute in stack style (last-in-first-out).
     */
    SDWebImageDownloaderLIFOExecutionOrder
};

/* lzy注170725：
 两个对外开放的 通知，下载开始、下载结束。
 */
extern NSString * _Nonnull const SDWebImageDownloadStartNotification;
extern NSString * _Nonnull const SDWebImageDownloadStopNotification;

typedef void(^SDWebImageDownloaderProgressBlock)(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL);

typedef void(^SDWebImageDownloaderCompletedBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, BOOL finished);

typedef NSDictionary<NSString *, NSString *> SDHTTPHeadersDictionary;
typedef NSMutableDictionary<NSString *, NSString *> SDHTTPHeadersMutableDictionary;

/* lzy注170725：
 下载请求的http头部的处理block的声明
 */
typedef SDHTTPHeadersDictionary * _Nullable (^SDWebImageDownloaderHeadersFilterBlock)(NSURL * _Nullable url, SDHTTPHeadersDictionary * _Nullable headers);

/**一个下载任务对应一个token对象。用于管理下载任务。
 *  A token associated with each download. Can be used to cancel a download
 */
@interface SDWebImageDownloadToken : NSObject

@property (nonatomic, strong, nullable) NSURL *url;
@property (nonatomic, strong, nullable) id downloadOperationCancelToken;

@end


/**网络图片异步下载器，专注于图片加载并做了最佳优化
 * Asynchronous downloader dedicated and optimized for image loading.
 */
@interface SDWebImageDownloader : NSObject

/**解压图片（下载完、缓存的）可以提升性能，但是将消耗大量的内存。默认是YES，如果你总是因为过多的内存使用而造成崩溃，将它设置为NO。
 * Decompressing images that are downloaded and cached can improve performance but can consume lot of memory.
 * Defaults to YES. Set this to NO if you are experiencing a crash due to excessive memory consumption.
 */
@property (assign, nonatomic) BOOL shouldDecompressImages;

/**下载任务最大并发数。
 *  The maximum number of concurrent downloads
 */
@property (assign, nonatomic) NSInteger maxConcurrentDownloads;

/**当前还需下载任务数
 * Shows the current amount of downloads that still need to be downloaded
 */
@property (readonly, nonatomic) NSUInteger currentDownloadCount;


/**请求响应超时，默认15s
 *  The timeout value (in seconds) for the download operation. Default: 15.0.
 */
@property (assign, nonatomic) NSTimeInterval downloadTimeout;


/**下载任务执行顺序
 * Changes download operations execution order. Default value is `SDWebImageDownloaderFIFOExecutionOrder`.
 */
@property (assign, nonatomic) SDWebImageDownloaderExecutionOrder executionOrder;

/**
 *  Singleton method, returns the shared instance
 *
 *  @return global shared instance of downloader class
 */
+ (nonnull instancetype)sharedDownloader;

/**下载操作默认的URL证书
 *  Set the default URL credential to be set for request operations.
 */
@property (strong, nonatomic, nullable) NSURLCredential *urlCredential;

/**
 * Set username
 */
@property (strong, nonatomic, nullable) NSString *username;

/**
 * Set password
 */
@property (strong, nonatomic, nullable) NSString *password;

/**设置这个过滤器，用于下载图片的HTTP请求时，对headers做一些处理
 * Set filter to pick headers for downloading image HTTP request.
 * 每个请求的都会调用这个blcok，返回将会在HTTP 请求中使用的headers
 * This block will be invoked for each downloading image request, returned
 * NSDictionary will be used as headers in corresponding HTTP request.
 */
@property (nonatomic, copy, nullable) SDWebImageDownloaderHeadersFilterBlock headersFilter;

/**使用给定的session configuration创建一个下载器实例。默认初始化方法。
 cofig的`timeoutIntervalForRequest`会被改写为默认的15s
 * Creates an instance of a downloader with specified session configuration.
 * *Note*: `timeoutIntervalForRequest` is going to be overwritten.
 * @return new instance of downloader class
 */
- (nonnull instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)sessionConfiguration NS_DESIGNATED_INITIALIZER;

/**给每个下载HTTPrequest请求的header添加一个键值对。可以把某个key置空来达到将该项移除的目的。
 * Set a value for a HTTP header to be appended to each download HTTP request.
 *
 * @param value The value for the header field. Use `nil` value to remove the header.
 * @param field The name of the header field to set.
 */
- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(nullable NSString *)field;

/**
 * Returns the value of the specified HTTP header field.
 *
 * @return The value associated with the header field field, or `nil` if there is no corresponding header field.
 */
- (nullable NSString *)valueForHTTPHeaderField:(nullable NSString *)field;

/**设定一个`SDWebImageDownloaderOperation`的子类，作为默认的`NSOperation`，用于SDWebImage对每个图片构建一个下载任务。
 * Sets a subclass of `SDWebImageDownloaderOperation` as the default
 * `NSOperation` to be used each time SDWebImage constructs a request
 * operation to download an image.
 *
 * @param operationClass The subclass of `SDWebImageDownloaderOperation` to set 
 *        as default. Passing `nil` will revert to `SDWebImageDownloaderOperation`.
 */
- (void)setOperationClass:(nullable Class)operationClass;

/**使用给定的url，创建一个 网络图片异步下载器 实例
 * Creates a SDWebImageDownloader async downloader instance with a given URL
 *delegate将在唉图片被下载完毕、出现错误的时候调用
 * The delegate will be informed when the image is finish downloaded or an error has happen.
 *
 * @see SDWebImageDownloaderDelegate
 *
 * @param url            The URL to the image to download
 * @param options        The options to be used for this download
 * @param progressBlock   图片下载过程中不断通知（后台队列）A block called repeatedly while the image is downloading
 *                       @note the progress block is executed on a background queue
 
 (NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL)
 
 * @param completedBlock A block called once the download is completed.
 *                       If the download succeeded, the image parameter is set, in case of error,
 *                       error parameter is set with the error. The last parameter is always YES
 *                       if SDWebImageDownloaderProgressiveDownload isn't use. With the
 *                       SDWebImageDownloaderProgressiveDownload option, this block is called
 *                       repeatedly with the partial image object and the finished argument set to NO
 *                       before to be called a last time with the full image and finished argument
 *                       set to YES. In case of error, the finished argument is always YES.
 
 (UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, BOOL finished);
 如果SDWebImageDownloaderProgressiveDownload 下载选项没有指定，那么finished会一直是 YES
 *
 * @return A token (SDWebImageDownloadToken) that can be passed to -cancel: to cancel this operation
 */
- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

/**使用-downloadImageWithURL:options:progress:completed:方法方法的token，取消该下载任务
 * Cancels a download that was previously queued using -downloadImageWithURL:options:progress:completed:
 *
 * @param token The token received from -downloadImageWithURL:options:progress:completed: that should be canceled.
 */
- (void)cancel:(nullable SDWebImageDownloadToken *)token;

/**
 * Sets the download queue suspension state
 */
- (void)setSuspended:(BOOL)suspended;

/**
 * Cancels all download operations in the queue
 */
- (void)cancelAllDownloads;

@end
