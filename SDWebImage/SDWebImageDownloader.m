/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

@implementation SDWebImageDownloadToken
@end


@interface SDWebImageDownloader () <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
/* lzy注170725：
 下载队列，管理所有的下载操作
 */
@property (strong, nonatomic, nonnull) NSOperationQueue *downloadQueue;
@property (weak, nonatomic, nullable) NSOperation *lastAddedOperation;
@property (assign, nonatomic, nullable) Class operationClass;
/* lzy注170725：
 一个 url和NSOperation的 映射。管理图片url和请求该url的op
 */
@property (strong, nonatomic, nonnull) NSMutableDictionary<NSURL *, SDWebImageDownloaderOperation *> *URLOperations;
/* lzy注170725：
 key value都是NSString类型的字典
 */
@property (strong, nonatomic, nullable) SDHTTPHeadersMutableDictionary *HTTPHeaders;

/* lzy注170725：这个队列用于序列化『所有下载任务返回的网络数据』操作，都在这一个队列中
// This queue is used to serialize the handling of the network responses of all the download operation in a single queue
 */
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t barrierQueue;

// The session in which data tasks will run
@property (strong, nonatomic) NSURLSession *session;

@end

@implementation SDWebImageDownloader

+ (void)initialize {
    // Bind SDNetworkActivityIndicator if available (download it here: http://github.com/rs/SDNetworkActivityIndicator )
    // To use it, just add #import "SDNetworkActivityIndicator.h" in addition to the SDWebImage import
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop

        // Remove observer in case it was previously added.
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}

+ (nonnull instancetype)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (nonnull instancetype)init {
    return [self initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
}

/* lzy注170725：
 1、调用父类的初始化方法，若初始化成功，再进一步初始化本类的变量
 2、下载操作类实例
 3、是否 解码 图片，默认YES
 4、任务执行顺序
 5、下载队列实例创建及初始配置：最大并发任务数、队列名称
 6、初始化一个 url和NSOperation的 字典
 7、httpHeader字典
 8、GCD创建『所有下载任务返回的网络数据』操作队列
 
 */
- (nonnull instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)sessionConfiguration {
    if ((self = [super init])) {
        _operationClass = [SDWebImageDownloaderOperation class];
        _shouldDecompressImages = YES;
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder;
        _downloadQueue = [NSOperationQueue new];
        _downloadQueue.maxConcurrentOperationCount = 6;
        _downloadQueue.name = @"com.hackemist.SDWebImageDownloader";
        _URLOperations = [NSMutableDictionary new];
#ifdef SD_WEBP
        /* lzy注170725：
         Preprocessor Macros中定义了 SD_WEBP=1
         */
        _HTTPHeaders = [@{@"Accept": @"image/webp,image/*;q=0.8"} mutableCopy];
#else
        _HTTPHeaders = [@{@"Accept": @"image/*;q=0.8"} mutableCopy];
#endif
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        _downloadTimeout = 15.0;

        sessionConfiguration.timeoutIntervalForRequest = _downloadTimeout;

        /** 给这个下载任务创建session。将给工厂方法的delegateQueue设置为nil，这样session将创建一系列操作队列来执行所有的delegate方法调用和完成处理的调用。
         *  Create the session for this task
         *  We send nil as delegate queue so that the session creates a serial operation queue for performing all delegate
         *  method calls and completion handler calls.
         */
        self.session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                                     delegate:self
                                                delegateQueue:nil];
    }
    return self;
}

- (void)dealloc {
    [self.session invalidateAndCancel];
    self.session = nil;

    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
}
/* lzy注170725：
 给每个下载HTTPrequest请求的header添加一个键值对。可以把某个key置空来达到将该项移除的目的。
 */
- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(nullable NSString *)field {
    if (value) {
        self.HTTPHeaders[field] = value;
    }
    else {
        [self.HTTPHeaders removeObjectForKey:field];
    }
}

- (nullable NSString *)valueForHTTPHeaderField:(nullable NSString *)field {
    return self.HTTPHeaders[field];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}
/* lzy注170725：
 当前还需下载任务数
 */
- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}
/* lzy注170725：
 下载任务最大并发数
 */
- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}
/* lzy注170725：
 设定一个`SDWebImageDownloaderOperation`的子类，作为默认的`NSOperation`，用于SDWebImage对每个图片构建一个下载任务
 */
- (void)setOperationClass:(nullable Class)operationClass {
    if (operationClass && [operationClass isSubclassOfClass:[NSOperation class]] && [operationClass conformsToProtocol:@protocol(SDWebImageDownloaderOperationInterface)]) {
        _operationClass = operationClass;
    } else {
        _operationClass = [SDWebImageDownloaderOperation class];
    }
}

- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock {
    __weak SDWebImageDownloader *wself = self;
    // 『给定url对应的op』添加 进度回调、完成回调
    return [self addProgressCallback:progressBlock completedBlock:completedBlock forURL:url createCallback:^SDWebImageDownloaderOperation *{// addProgressCallback方法中取『SDWebImageDownloaderOperation *operation = self.URLOperations[url];』为空，创建op
        
        __strong __typeof (wself) sself = wself;
        NSTimeInterval timeoutInterval = sself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }

        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        /* lzy注170725：
         为了防止caching (NSURLCache + SDImageCache)api可能被废弃的问题，sd关闭了图片请求的缓存。
         1、创建req，req是否使用NSURLCache取决于SDWebImageDownloaderUseNSURLCache的值
         2、配置cookies处理
         3、HTTPShouldUsePipelining处理
         4、是否有httpHead过滤block，有调用它
         5、给req创建对应的SDWebImageDownloaderOperation以及op的配置
         6、op的shouldDecompressImages
         7、op的credential
         8、op的queuePriority
         9、op添加到下载队列中 后进先出的实现，是通过 将『上一个下载任务』依赖『当前的下载任务』，设置为依赖之后，将『当前的下载任务』设置为『上一个下载任务』
         10、return op
         */
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        
        // 主要是这些内容 e.g.@{@"Accept": @"image/webp,image/*;q=0.8"}
        if (sself.headersFilter) {
            request.allHTTPHeaderFields = sself.headersFilter(url, [sself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = sself.HTTPHeaders;
        }
        
        SDWebImageDownloaderOperation *operation = [[sself.operationClass alloc] initWithRequest:request inSession:sself.session options:options];
        operation.shouldDecompressImages = sself.shouldDecompressImages;
        
        if (sself.urlCredential) {
            operation.credential = sself.urlCredential;
        } else if (sself.username && sself.password) {
            operation.credential = [NSURLCredential credentialWithUser:sself.username password:sself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }

        [sself.downloadQueue addOperation:operation];
        if (sself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
            [sself.lastAddedOperation addDependency:operation];
            sself.lastAddedOperation = operation;
        }

        return operation;
    }];
}
/* lzy注170725：
 使用-downloadImageWithURL:options:progress:completed:方法方法的token，取消该下载任务
 */
- (void)cancel:(nullable SDWebImageDownloadToken *)token {
    dispatch_barrier_async(self.barrierQueue, ^{
        SDWebImageDownloaderOperation *operation = self.URLOperations[token.url];
        BOOL canceled = [operation cancel:token.downloadOperationCancelToken];
        if (canceled) {
            [self.URLOperations removeObjectForKey:token.url];
        }
    });
}
/* lzy注170725：
 1、验证传入参数
 2、切换到barrier给 『给定url对应的op』添加 进度回调、完成回调 并返回token
 */
- (nullable SDWebImageDownloadToken *)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock
                                           completedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock
                                                   forURL:(nullable NSURL *)url
                                           createCallback:(SDWebImageDownloaderOperation *(^)())createCallback {
    // The URL will be used as the key to the callbacks dictionary so it cannot be nil. If it is nil immediately call the completed block with no image or data.
    
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return nil;
    }

    __block SDWebImageDownloadToken *token = nil;
// 切换到并发同步的队列中
    dispatch_barrier_sync(self.barrierQueue, ^{
        // 取出url对应的op
        SDWebImageDownloaderOperation *operation = self.URLOperations[url];
        // 没有op，创建并管理op
        if (!operation) {
            // 调用 createCallback创建op
            operation = createCallback();
            // op与url对应放字典
            self.URLOperations[url] = operation;

            __weak SDWebImageDownloaderOperation *woperation = operation;
            operation.completionBlock = ^{
                
            // op 完成回调中调用的方法，主要目的是 从 字典中移除这个键值对
              SDWebImageDownloaderOperation *soperation = woperation;
              if (!soperation) return;
                
              if (self.URLOperations[url] == soperation) {
                  [self.URLOperations removeObjectForKey:url];
              };
            };
        }
        // op有了，给op添加 进度回调、完成回调。返回一个可以调用cancel方法的cancelToken
        id downloadOperationCancelToken = [operation addHandlersForProgress:progressBlock completed:completedBlock];

        // 创建token，持有url和对应的op
        token = [SDWebImageDownloadToken new];
        token.url = url;
        token.downloadOperationCancelToken = downloadOperationCancelToken;
    });

    return token;
}

/**
 *  Adds handlers for progress and completion. Returns a tokent that can be passed to -cancel: to cancel this set of
 *  callbacks.
 *
 *  @param progressBlock  the block executed when a new chunk of data arrives.
 *                        @note the progress block is executed on a background queue
 *  @param completedBlock the block executed when the download is done.
 *                        @note the completed block is executed on the main queue for success. If errors are found, there is a chance the block will be executed on a background queue
 *
 *  @return the token to use to cancel this set of handlers
 */

- (void)setSuspended:(BOOL)suspended {
    (self.downloadQueue).suspended = suspended;
}

- (void)cancelAllDownloads {
    [self.downloadQueue cancelAllOperations];
}

#pragma mark Helper methods

- (SDWebImageDownloaderOperation *)operationWithTask:(NSURLSessionTask *)task {
    SDWebImageDownloaderOperation *returnOperation = nil;
    for (SDWebImageDownloaderOperation *operation in self.downloadQueue.operations) {
        if (operation.dataTask.taskIdentifier == task.taskIdentifier) {
            returnOperation = operation;
            break;
        }
    }
    return returnOperation;
}

#pragma mark NSURLSessionDataDelegate 代理方法都被回调到 SDWebImageDownloaderOperation 实例中了

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didCompleteWithError:error];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    
    completionHandler(request);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
}

@end
