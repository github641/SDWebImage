/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageManager.h"
#import <objc/message.h>
#import "NSImage+WebCache.h"

/* lzy注170720：
 图片整合操作类，这个类遵守SDWebImageOperation协议，有cancel方法
 */
@interface SDWebImageCombinedOperation : NSObject <SDWebImageOperation>
/* lzy注170720：
 是否被取消
 */
@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
/* lzy注170720：
 没有参数的取消操作block
 */
@property (copy, nonatomic, nullable) SDWebImageNoParamsBlock cancelBlock;
/* lzy注170720：
 缓存操作
 */
@property (strong, nonatomic, nullable) NSOperation *cacheOperation;

@end

@interface SDWebImageManager ()

/**
 网络图片缓存器
 */
@property (strong, nonatomic, readwrite, nonnull) SDImageCache *imageCache;

/**
 网络图片下载器
 */
@property (strong, nonatomic, readwrite, nonnull) SDWebImageDownloader *imageDownloader;
/**
 请求失败的URLs集合，如果下载失败，那么一直传这个地址，也不会去重试下载
 */
@property (strong, nonatomic, nonnull) NSMutableSet<NSURL *> *failedURLs;
/**
 管理正在进行的『图片整合操作』的数组
 */
@property (strong, nonatomic, nonnull) NSMutableArray<SDWebImageCombinedOperation *> *runningOperations;

@end

@implementation SDWebImageManager

// 单例
+ (nonnull instancetype)sharedManager {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

/* lzy注170720：
 SDWebImageManager初始化。
 1、初始化图片缓存器。
 2、初始化图片下载器。
 3、利用以上两个实例作为变量，初始化图片管理者实例
 */
- (nonnull instancetype)init {
    SDImageCache *cache = [SDImageCache sharedImageCache];
    SDWebImageDownloader *downloader = [SDWebImageDownloader sharedDownloader];
    return [self initWithCache:cache downloader:downloader];
}
/* lzy注170720：
 使用指定的缓存器实例、下载器实例初始化一个图片管理者实例。
 1、父类初始化方法
 2、持有缓存器
 3、持有下载器
 4、初始化一个数组管理『请求图片失败的url』
 5、初始化一个数组管理『正在执行的下载请求』
 */
- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader {
    if ((self = [super init])) {
        _imageCache = cache;
        _imageDownloader = downloader;
        _failedURLs = [NSMutableSet new];
        _runningOperations = [NSMutableArray new];
    }
    return self;
}
/* lzy注170720：
 给定一个URL，返回对应的缓存key
 1、url不存在，返回空字符串
 2、若有缓存key过滤器，调用过滤器方法返回
 3、没有过滤器，直接调用url.absoluteString返回缓存key
 */
- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url {
    if (!url) {
        return @"";
    }

    if (self.cacheKeyFilter) {
        return self.cacheKeyFilter(url);
    } else {
        return url.absoluteString;
    }
}
/* lzy注170720：
 异步查看，给定url的图片是否已经被缓存了。
 完成block将在检查结束后回调。
 注意，完成block只会在主线程回调。
 
 1、通过url，取出缓存key
 2、是否在内存中缓存的BOOL，在则回到主线程回调完成结果，否，next
 3、是否在磁盘中缓存的BOOL
 */
- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    // 缓存中取到了image，说明在缓存中
    BOOL isInMemoryCache = ([self.imageCache imageFromMemoryCacheForKey:key] != nil);
    
    if (isInMemoryCache) {
        // making sure we call the completion block on the main queue
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(YES);
            }
        });
        return;
    }
    // 异步查看图片是否已经存储在磁盘中了,并在主线程回调
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];

}
/* lzy注170720：
 异步查看给定url的图片是否仅仅被缓存在磁盘上。
 完成block将在检查结束后回调。
 注意，完成block只会在主线程回调。
 1、通过url，取出缓存key
 2、缓存key，是否在磁盘中缓存的BOOL
 */
- (void)diskImageExistsForURL:(nullable NSURL *)url
                   completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    NSString *key = [self cacheKeyForURL:url];
    
    [self.imageCache diskImageExistsWithKey:key completion:^(BOOL isInDiskCache) {
        // the completion block of checkDiskCacheForImageWithKey:completion: is always called on the main queue, no need to further dispatch
        if (completionBlock) {
            completionBlock(isInDiskCache);
        }
    }];
}
/* lzy注170720：
 给定URL，
 图片在缓存，返回缓存中的图片，
 下载不在缓存中的图片并回调。
 这个方法返回一个SDWebImageDownloaderOperation对象，该对象遵守SDWebImageOperation协议。
 */
- (id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                     options:(SDWebImageOptions)options
                                    progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                   completed:(nullable SDInternalCompletionBlock)completedBlock {
    
    // Invoking this method without a completedBlock is pointless
    /* lzy注170720：
     断言，判断completedBlock是否存在。不存在完成回调，打印『如果你想预缓存图片，使用[SDWebImagePrefetcher prefetchURLs]』
     */
    NSAssert(completedBlock != nil, @"If you mean to prefetch the image, use -[SDWebImagePrefetcher prefetchURLs] instead");

    // Very common mistake is to send the URL using NSString object instead of NSURL. For some strange reason, Xcode won't
    // throw any warning for this type mismatch. Here we failsafe this error by allowing URLs to be passed as NSString.
    /* lzy注170720：
     常见错误之一是，把NSString类型的实参传递给NSURL形参。
     这里做一个防御编程，若传入时string，做处理。
     */
    
    /* lzy注170720：
     传入的url类型的参数，如果是字符串，用它生成URL对象。
     */
    if ([url isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)url];
    }

    // Prevents app crashing on argument type error like sending NSNull instead of NSURL
    /* lzy注170720：
     防止app因为参数类型不匹配而崩溃。
     */
    if (![url isKindOfClass:NSURL.class]) {
        url = nil;
    }

    /* lzy注170720：
     准备，可以在block中修改的图片整合操作队列实例，和weak的图片整合操作实例
     */
    __block SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
    __weak SDWebImageCombinedOperation *weakOperation = operation;
    
    
    BOOL isFailedUrl = NO;
    // url不为nil，看是否在黑名单中
    if (url) {
        @synchronized (self.failedURLs) {
            isFailedUrl = [self.failedURLs containsObject:url];
        }
    }
    
    /* lzy注170724：
     1、url中的网址str的长度是否为0：
         是，调用完成回调，生成错误 ❤
         否，next
     2、下载操作选项是否为『失败重试』
         是，不进if语句大括号，直接下一个方法（url有效，失败重试，）❤
         否，next
     3、是否在『失败名单』中
         是，调用完成回调，生成错误❤
         否，不进if语句大括号，直接下一个方法（url有效 且 不是失败重试 且 不在失败名单中）❤
     */
    if (url.absoluteString.length == 0 || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
        [self callCompletionBlockForOperation:operation completion:completedBlock error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil] url:url];
        return operation;
    }
    
// 添加到『图片整合操作』数组中
    @synchronized (self.runningOperations) {
        [self.runningOperations addObject:operation];
    }
    // 生成缓存key
    NSString *key = [self cacheKeyForURL:url];
    
    
    /* lzy注170725：
     返回一个 异步查询缓存的『operation』，并在查询结束回调。
     如果operation被取消了，那么block不会被调用
     内部做了：
     1、检查传入参数是否为空
     2、查询内存缓存
     3、查询磁盘缓存
     */
    operation.cacheOperation = [self.imageCache queryCacheOperationForKey:key done:^(UIImage *cachedImage, NSData *cachedData, SDImageCacheType cacheType) {
        // 缓存队列状态是『已取消』，则安全移除『图片整合操作』队列实例
        if (operation.isCancelled) {
            [self safelyRemoveOperationFromRunning:operation];
            return;
        }
        /* lzy注170724：
         1 && 2
         
             1、
                 1.1 缓存图片是否存在
                     是，去1.2
                     否，整个 1 都是真，去 2 判断
         
                 1.2 下载网络图片操作选项是否有 『刷新缓存』一项
                     是，整个 1 都是真，去 2 判断
                     否，整个 1 都是假，整个if判断结果为假，不进此分支大括号 💔(有缓存图片 且 不刷新缓存)
         
             2、开发者没有实现『无缓存图，是否下载』代理方法，默认是进行图片下载的
                 2.1 是否实现了『无缓存图，是否下载』代理方法
                     是，去2.2
                     否，整个 2 结果为真，判断走到这儿，整个if判断结果为真，执行分支大括号 ❤（①有缓存图片、刷新缓存、无代理方法；②无缓存、无代理）
         
                 2.2 代理方法执行结果，无缓存图，是否下载
                     是，整个 2 结果为真，判断走到这儿，整个if判断结果为真，执行分支大括号 ❤（③有缓存图片、刷新缓存、实现了代理方法、代理结果为真；④无缓存、实现了代理方法、代理结果为真）
                     否，整个 2 结果为假，整个if判断结果为假，不进此分支大括号 💔（有缓存图片、刷新缓存、实现了代理方法，代理结果为假；无缓存、实现了代理方法、代理结果为假）
         (
         !cachedImage 
         || 
         options & SDWebImageRefreshCached
         )
         
         2、
         (
         ![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)]
         ||
         [self.delegate imageManager:self shouldDownloadImageForURL:url]
         )
         */
        if ((!cachedImage || options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url])) {
            
            // ①有缓存图片、刷新缓存，直接回调该图片数据（注意，后续还会去该url重新下载图片，如果下载成功，还会再次回调）
            if (cachedImage && options & SDWebImageRefreshCached) {
                // If image was found in the cache but SDWebImageRefreshCached is provided, notify about the cached image
                // AND try to re-download it in order to let a chance to NSURLCache to refresh it from server.
                /* lzy注170724：
                 如果图片在缓存中找到了，但是SDWebImageRefreshCached，先回调找到的缓存图片；
                 然后尝试重新下载这个图片，让NSURLCache有机会去后台刷新图片数据
                 */
                [self callCompletionBlockForOperation:weakOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            }

            // download if no image or requested to refresh anyway, and download allowed by delegate
    
            // 确定下载选项
            SDWebImageDownloaderOptions downloaderOptions = 0;
            if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
            if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
            if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
            if (options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
            if (options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
            if (options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
            if (options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
            if (options & SDWebImageScaleDownLargeImages) downloaderOptions |= SDWebImageDownloaderScaleDownLargeImages;
            
            /* lzy注170724：继续处理下载选项。
             ~按位取反。
             有缓存 而且 刷新缓存的话
             1、强制关闭『下载进度』opt
             2、忽略 NSURLCache 中读取的图片
             */
            if (cachedImage && options & SDWebImageRefreshCached) {
                // force progressive off if image already cached but forced refreshing
                downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
                // ignore image read from NSURLCache if image if cached but force refreshing
                downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
            }
            
                /* TODO: #待完成# */
            // 使用网络图片下载器 下载图片
            SDWebImageDownloadToken *subOperationToken = [self.imageDownloader downloadImageWithURL:url options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *downloadedData, NSError *error, BOOL finished) {
                __strong __typeof(weakOperation) strongOperation = weakOperation;
                if (!strongOperation || strongOperation.isCancelled) {
                    // Do nothing if the operation was cancelled
                    // See #699 for more details
                    // if we would call the completedBlock, there could be a race condition between this block and another completedBlock for the same object, so if this one is called second, we will overwrite the new data
                    /* lzy注170724：若operation不存在或者被取消了。
                     如果operation被取消了，什么也不做。
                     */
                } else if (error) {// 下载出错。
                    [self callCompletionBlockForOperation:strongOperation completion:completedBlock error:error url:url];

                    if (   error.code != NSURLErrorNotConnectedToInternet
                        && error.code != NSURLErrorCancelled
                        && error.code != NSURLErrorTimedOut
                        && error.code != NSURLErrorInternationalRoamingOff
                        && error.code != NSURLErrorDataNotAllowed
                        && error.code != NSURLErrorCannotFindHost
                        && error.code != NSURLErrorCannotConnectToHost) {
                        @synchronized (self.failedURLs) {
                            // 下载出错的errorCode如果不是以上所有的话，那么加入『失败黑名单』，以后没有特殊配置不再重复尝试请求该url
                            [self.failedURLs addObject:url];
                        }
                    }
                }
                else {
                    if ((options & SDWebImageRetryFailed)) {// 有重试配置，从『失败黑名单』移除
                        @synchronized (self.failedURLs) {
                            [self.failedURLs removeObject:url];
                        }
                    }
                    
                    // 获取是否缓存到磁盘的配置
                    BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);

                    if (options & SDWebImageRefreshCached && cachedImage && !downloadedImage) {
                        // 刷新缓存，有缓存图片，没有下载图片
                        // Image refresh hit the NSURLCache cache, do not call the completion block
                    } else if (downloadedImage && (!downloadedImage.images || (options & SDWebImageTransformAnimatedImage)) && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                        /* lzy注170724：
                         1 2 3 都是YES才进入此大括号：
                         
                         1、downloadedImage 图片数据下载成功
                         
                         && 
                         
                         2、(!downloadedImage.images || (options & SDWebImageTransformAnimatedImage))
                         『不是动图』 『转换动图』 二必有一个是YES
                         && 
                         
                         3、[self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]
                         实现了『转换下载图片』的delegate方法
                         */
                        
                        
                        
                        
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                            // 全局队列中调用以下方法
                            
                            // 调用实现的代理方法
                            UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];

                            // 外部传入了图片
                            if (transformedImage && finished) {
                                // 图片是否进行了转换的flag
                                BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                                // pass nil if the image was transformed, so we can recalculate the data from the image
                                // 图片如果被『转换』了，传nil，这样可以重新计算图片数据。调用图片缓存方法。
                                /* lzy注170725：
                                 1、验证传入参数：没有image 或者没有key直接回调并return
                                 2、如果 cofig配置中的内存缓存允许，缓存image
                                 3、如果传入参数 存储到磁盘 的flag为真，缓存它
                                 */
                                [self.imageCache storeImage:transformedImage imageData:(imageWasTransformed ? nil : downloadedData) forKey:key toDisk:cacheOnDisk completion:nil];
                            }
                            
                            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:transformedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                        });
                    } else {// 常规配置，下载完图片，缓存并回调
                        if (downloadedImage && finished) {
                            [self.imageCache storeImage:downloadedImage imageData:downloadedData forKey:key toDisk:cacheOnDisk completion:nil];
                        }
                        [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:downloadedImage data:downloadedData error:nil cacheType:SDImageCacheTypeNone finished:finished url:url];
                    }
                }

                // 操作结束，移除操作operation
                if (finished) {
                    [self safelyRemoveOperationFromRunning:strongOperation];
                }
            }];// 下载方法结束
            
            // 给operation的cancelBlock赋值
            operation.cancelBlock = ^{
                    /* TODO: #待完成# */
                [self.imageDownloader cancel:subOperationToken];
                __strong __typeof(weakOperation) strongOperation = weakOperation;
                [self safelyRemoveOperationFromRunning:strongOperation];
            };
        } else if (cachedImage) {// 缓存图片数据存在
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:cachedImage data:cachedData error:nil cacheType:cacheType finished:YES url:url];
            [self safelyRemoveOperationFromRunning:operation];
        } else {// 图片不在缓存中 并且 开发者通过本类代理不允许通过url下载该图片
            // Image not in cache and download disallowed by delegate
            __strong __typeof(weakOperation) strongOperation = weakOperation;
            [self callCompletionBlockForOperation:strongOperation completion:completedBlock image:nil data:nil error:nil cacheType:SDImageCacheTypeNone finished:YES url:url];
            [self safelyRemoveOperationFromRunning:operation];
        }
    }];

    return operation;
}
/* lzy注170724：
 将图片保存到缓存中。
 图片和url都存在。生成一个key，调用下载器方法缓存该图。
 */
- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url {
    if (image && url) {
        NSString *key = [self cacheKeyForURL:url];
        /* lzy注170725：
         1、验证传入参数：没有image 或者没有key直接回调并return
         2、如果 cofig配置中的内存缓存允许，缓存image
         3、如果传入参数 存储到磁盘 的flag为真，缓存它
         */
        [self.imageCache storeImage:image forKey:key toDisk:YES completion:nil];
    }
}
/* lzy注170724：
 取消所有的下载整合操作实例。
 调用了SDWebImageCombinedOperation的cancel方法（这个方法没有在interface中声明）
 */
- (void)cancelAll {
    @synchronized (self.runningOperations) {
        NSArray<SDWebImageCombinedOperation *> *copiedOperations = [self.runningOperations copy];
        [copiedOperations makeObjectsPerformSelector:@selector(cancel)];
        [self.runningOperations removeObjectsInArray:copiedOperations];
    }
}
/* lzy注170724：
 只要有下载操作，就是running状态
 */
- (BOOL)isRunning {
    BOOL isRunning = NO;
    @synchronized (self.runningOperations) {
        isRunning = (self.runningOperations.count > 0);
    }
    return isRunning;
}

/* lzy注170724：
 从『图片整合操作』线程安全得移除某个操作
 */
- (void)safelyRemoveOperationFromRunning:(nullable SDWebImageCombinedOperation*)operation {
    @synchronized (self.runningOperations) {
        if (operation) {
            [self.runningOperations removeObject:operation];
        }
    }
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  error:(nullable NSError *)error
                                    url:(nullable NSURL *)url {
    [self callCompletionBlockForOperation:operation completion:completionBlock image:nil data:nil error:error cacheType:SDImageCacheTypeNone finished:YES url:url];
}

- (void)callCompletionBlockForOperation:(nullable SDWebImageCombinedOperation*)operation
                             completion:(nullable SDInternalCompletionBlock)completionBlock
                                  image:(nullable UIImage *)image
                                   data:(nullable NSData *)data
                                  error:(nullable NSError *)error
                              cacheType:(SDImageCacheType)cacheType
                               finished:(BOOL)finished
                                    url:(nullable NSURL *)url {
    // 到主线程中，下载操作存在，没有被需求，完成回调外面传入了，则调用这个回调。
    dispatch_main_async_safe(^{
        if (operation && !operation.isCancelled && completionBlock) {
            completionBlock(image, data, error, cacheType, finished, url);
        }
    });
}

@end


@implementation SDWebImageCombinedOperation

/* lzy注170724：
 图片整合操作类
 cancel的block的setter
 */
- (void)setCancelBlock:(nullable SDWebImageNoParamsBlock)cancelBlock {
    // check if the operation is already cancelled, then we just call the cancelBlock
    if (self.isCancelled) {// 是否时取消状态，是调用取消block，然后把block置空
        if (cancelBlock) {
            cancelBlock();
        }
        _cancelBlock = nil; // don't forget to nil the cancelBlock, otherwise we will get crashes
    } else {// 不是取消状态，直接copy
        _cancelBlock = [cancelBlock copy];
    }
}

- (void)cancel {
    self.cancelled = YES;
    if (self.cacheOperation) {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    if (self.cancelBlock) {
        self.cancelBlock();
        
        // TODO: this is a temporary fix to #809.
        // Until we can figure the exact cause of the crash, going with the ivar instead of the setter
//        self.cancelBlock = nil;
        _cancelBlock = nil;
    }
}

@end
