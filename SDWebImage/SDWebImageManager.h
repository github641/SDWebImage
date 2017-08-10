/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"
#import "SDWebImageOperation.h"
#import "SDWebImageDownloader.h"
#import "SDImageCache.h"
/* lzy注170720：
 http://www.jianshu.com/p/36ba5d65804f
 http://www.jianshu.com/p/dcb637dda9be
 
 e.g.系统API举例：
 typedef NS_OPTIONS(NSUInteger, UIViewAutoresizing){    二进制值    十进制
 UIViewAutoresizingNone                  = 0,       00000000    0
 UIViewAutoresizingFlexibleLeftMargin    = 1<<0,    00000001    1
 UIViewAutoresizingFlexibleWidth         = 1<<1,    00000010    2
 UIViewAutoresizingFlexibleRightMargin   = 1<<2,    00000100    4
 UIViewAutoresizingFlexibleTopMargin     = 1<<3,    00001000    8
 UIViewAutoresizingFlexibleHeight        = 1<<4,    00010000    16
 UIViewAutoresizingFlexibleBottomMargin  = 1<<5     00100000    32
 };
 
 这些枚举项，两两之间 按位与 结果肯定是0；按位或 两个肯定是1。
 于是：在调用一个方法的时候，用“按位或操作符”可组合多个选项；
 在条件判断时，使用『按位与操作符』，来判断 (传入的枚举 & 要处理的枚举)，若结果为1，说明是同一个枚举。
 
 */
typedef NS_OPTIONS(NSUInteger, SDWebImageOptions) {
    /**
     * By default, when a URL fail to be downloaded, the URL is blacklisted so the library won't keep trying.
     * This flag disable this blacklisting.
     */
    /* lzy注170720：
     下载失败将重试。
     下载失败的默认处理：当一个URL下载失败，这个URL将会被加入到『黑名单』中，sd将不会再不断尝试对这个链接地址进行下载。
     这个标志位将标识这个URL不会加入『黑名单』。
     */
    SDWebImageRetryFailed = 1 << 0,

    /**
     * By default, image downloads are started during UI interactions, this flags disable this feature,
     * leading to delayed download on UIScrollView deceleration for instance.
     */
    /* lzy注170720：
     下载操作优先级降低。
     默认情况：图片的下载操作在UI交互过程中也是一直在执行的。
     这个标志位将导致下载操作的延迟。比如若UIScrollView在惯性中，那么下载操作将延迟。
     */
    SDWebImageLowPriority = 1 << 1,

    /**
     * This flag disables on-disk caching
     */
    /* lzy注170720：
     图片只在内存中缓存。
     这个标志位将使得 图片磁盘缓存 失效。
     */
    SDWebImageCacheMemoryOnly = 1 << 2,

    /**
     * This flag enables progressive download, the image is displayed progressively during download as a browser would do.
     * By default, the image is only displayed once completely downloaded.
     */
    /* lzy注170720：
     图片将边下载边渲染。
     这个标志位将开启渐进下载，图片将会在渐进下载过程中被展示，如常规浏览器做的一样。
     默认情况下，图片将只会在完全下载完毕之后才会展示。
     */
    SDWebImageProgressiveDownload = 1 << 3,

    /**
     * Even if the image is cached, respect the HTTP response cache control, and refresh the image from remote location if needed.
     * The disk caching will be handled by NSURLCache instead of SDWebImage leading to slight performance degradation.
     * This option helps deal with images changing behind the same request URL, e.g. Facebook graph api profile pics.
     * If a cached image is refreshed, the completion block is called once with the cached image and again with the final image.
     *
     * Use this flag only if you can't make your URLs static with embedded cache busting parameter.
     */
    /* lzy注170720：
     不使用SDWebImage提供的内存缓存和硬盘缓存
     采用NSURLCache提供的缓存，有效时间只有5秒
     图片不一致的问题是解决了，不过效果跟不使用缓存差别不大
     个人建议这个参数还是不要用为好，为了一个小特性，丢掉了SDWebImage最核心的特色。

     就算图片缓存过了，尊重HTTP返回数据中的缓存控制，视情况从远处服务器刷新图片。
     磁盘缓存将会用NSURLCache处理而不是SDWebImage，导致一定的性能下降。
     这个标志位，帮助解决同一个url地址背后的图片数据发生改变的情况。e.g. Facebook的用户头像api。
     如果之前被缓存过的图片被刷新，完成回调将被调用一次，回调数据有缓存的图片和最终的图片。
     仅仅在你无法给URLs嵌入缓存管理相关参数的情况下，使用这个标志位。
     比如可以建议服务端，返回的图片链接中带该图片的MD5值。
     */
    SDWebImageRefreshCached = 1 << 4,

    /**
     * In iOS 4+, continue the download of the image if the app goes to background. This is achieved by asking the system for
     * extra time in background to let the request finish. If the background task expires the operation will be cancelled.
     */
    /* lzy注170720：
     app在后台状态继续下载图片。
     在iOS4+，当app进入后台，继续图片的下载操作。实现方式是询问系统要求在后台活跃更长的时间用于把图片下载下来。如果后台任务到期了，图片下载任务也将被取消。
     */
    SDWebImageContinueInBackground = 1 << 5,

    /**
     * Handles cookies stored in NSHTTPCookieStore by setting
     * NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     */
    /* lzy注170720：
     设置NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     则sd将处理存储在NSHTTPCookieStore中的cookies
     */
    SDWebImageHandleCookies = 1 << 6,

    /**
     * Enable to allow untrusted SSL certificates.
     * Useful for testing purposes. Use with caution in production.
     */
    /* lzy注170720：
     运行不被信任的SSL证书。
     生成环境小心使用，可以用于测试目的。
     */
    SDWebImageAllowInvalidSSLCertificates = 1 << 7,

    /**
     * By default, images are loaded in the order in which they were queued. This flag moves them to
     * the front of the queue.
     */
    /* lzy注170720：
     将图片加载任务的优先级提高，使得该任务在队列前面。
     默认，图片加载任务的顺序时它们入队的顺序。
     这个标志位将把任务移到队列的前面。
     */
    SDWebImageHighPriority = 1 << 8,
    
    /**
     * By default, placeholder images are loaded while the image is loading. This flag will delay the loading
     * of the placeholder image until after the image has finished loading.
     */
    /* lzy注170720：
     在图片下载完毕后，才将占位图片赋值进行占位。
     默认情况，占位图片将在立即赋值，之后才是图片下载。
     */
    SDWebImageDelayPlaceholder = 1 << 9,

    /**
     * We usually don't call transformDownloadedImage delegate method on animated images,
     * as most transformation code would mangle it.
     * Use this flag to transform them anyway.
     */
    /* lzy注170720：
     转换动图。
     我们不常对动图调用 transformDownloadedImage delegate方法，大部分的图片转换代码都将把动图弄乱。
     */
    SDWebImageTransformAnimatedImage = 1 << 10,
    
    /**
     * By default, image is added to the imageView after download. But in some cases, we want to
     * have the hand before setting the image (apply a filter or add it with cross-fade animation for instance)
     * Use this flag if you want to manually set the image in the completion when success
     */
    /* lzy注170720：
     当图片下载完成不让sd设置图片到控件上。
     默认，图片在下载完后将添加到iamgeView上。
     但是在某些情况下，我们想在设置到imageView上之前，对图片做一些处理（比如，添加一个过滤操作或者给iv添加图片时带一个渐变效果等等）。
     使用这个标志位，如果你想在图片下载完成时，手动设置image
     */
    SDWebImageAvoidAutoSetImage = 1 << 11,
    
    /**
     * By default, images are decoded respecting their original size. On iOS, this flag will scale down the
     * images to a size compatible with the constrained memory of devices.
     * If `SDWebImageProgressiveDownload` flag is set the scale down is deactivated.
     */
    /* lzy注170720：
     缩小大图。若`SDWebImageProgressiveDownload`生效，这个标志位将不会生效。
     默认，图片是根据其原始尺寸进行解码的。
     在iOS平台上，在一些内存有限的设备中，图片将被兼容性地缩小。
     */
    SDWebImageScaleDownLargeImages = 1 << 12
};

/* lzy注170720：
 声明了一个 sd 外部使用的 完成block
 */
typedef void(^SDExternalCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL);
/* lzy注170720：
 声明了一个 sd 内部使用的 完成block
 */
typedef void(^SDInternalCompletionBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL);

/* lzy注170720：
 声明了一个 图片缓存key 过滤block
 */
typedef NSString * _Nullable (^SDWebImageCacheKeyFilterBlock)(NSURL * _Nullable url);


@class SDWebImageManager;


/* lzy注170720：
 图片管理者类的两个可选协议方法
 */
@protocol SDWebImageManagerDelegate <NSObject>

@optional


/**
 * Controls which image should be downloaded when the image is not found in the cache.
 *
 * @param imageManager The current `SDWebImageManager`
 * @param imageURL     The url of the image to be downloaded
 *
 * @return Return NO to prevent the downloading of the image on cache misses. If not implemented, YES is implied.
 */
/* lzy注170720：
 当图片没有在缓存中找到，这个图片是否应该被下载。
 默认是YES。
 返回一个NO，防止当缓存中没有图时，去下载该图。
 */
- (BOOL)imageManager:(nonnull SDWebImageManager *)imageManager shouldDownloadImageForURL:(nullable NSURL *)imageURL;

/**
 * Allows to transform the image immediately after it has been downloaded and just before to cache it on disk and memory.
 * NOTE: This method is called from a global queue in order to not to block the main thread.
 *
 * @param imageManager The current `SDWebImageManager`
 * @param image        The image to transform
 * @param imageURL     The url of the image to transform
 *
 * @return The transformed image object.
 */
/* lzy注170720：
 当图片被下载下来之后，立即对其进行 图形变换，这个时间点在它被缓存到内存和磁盘之前。
 注意：为了不阻塞主线程，这个方法将在全局队列中被调用。
 */
- (nullable UIImage *)imageManager:(nonnull SDWebImageManager *)imageManager transformDownloadedImage:(nullable UIImage *)image withURL:(nullable NSURL *)imageURL;

@end

/**
 * The SDWebImageManager is the class behind the UIImageView+WebCache category and likes.
 * It ties the asynchronous downloader (SDWebImageDownloader) with the image cache store (SDImageCache).
 * You can use this class directly to benefit from web image downloading with caching in another context than
 * a UIView.
 *
 * Here is a simple example of how to use SDWebImageManager:
 *
 * @code

SDWebImageManager *manager = [SDWebImageManager sharedManager];
[manager loadImageWithURL:imageURL
                  options:0
                 progress:nil
                completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
                    if (image) {
                        // do something with image
                    }
                }];

 * @endcode
 */

/* lzy注170720：
 SDWebImageManager类，是UIImageView+WebCache等UI组件扩展的基本类。
 这个类，组织管理了异步下载器(SDWebImageDownloader)和缓存器(SDImageCache)。
 使用这个类可以获得网络图片下载与缓存的能力，你也可以在除了UIView之外的其他上下文环境中使用这个类。
 */
@interface SDWebImageManager : NSObject

/* lzy注170720：
 本类代理
 */
@property (weak, nonatomic, nullable) id <SDWebImageManagerDelegate> delegate;
/* lzy注170720：
 图片缓存器
 */
@property (strong, nonatomic, readonly, nullable) SDImageCache *imageCache;
/* lzy注170720：
 图片下载器
 */
@property (strong, nonatomic, readonly, nullable) SDWebImageDownloader *imageDownloader;

/**
 * The cache filter is a block used each time SDWebImageManager need to convert an URL into a cache key. This can
 * be used to remove dynamic part of an image URL.
 *
 * The following example sets a filter in the application delegate that will remove any query-string from the
 * URL before to use it as a cache key:
 *这个例子将演示，设定一个过滤处理，从url中移除所有的query字符串，之后再将处理后的字符串作为缓存key。
 * @code

[[SDWebImageManager sharedManager] setCacheKeyFilter:^(NSURL *url) {
    url = [[NSURL alloc] initWithScheme:url.scheme host:url.host path:url.path];
    return [url absoluteString];
}];

 * @endcode
 */
/* lzy注170720：
 sd图片缓存key过滤器。
 这个是一个block，用于当SDWebImageManager需要将一个URL转换为一个缓存key时使用。
 这个block可以用于移除一个图片URL的动态部分（不确定部分、随机部分、每次都变化的部分）。
 */
@property (nonatomic, copy, nullable) SDWebImageCacheKeyFilterBlock cacheKeyFilter;

/**
 * Returns global SDWebImageManager instance.
 *
 * @return SDWebImageManager shared instance
 */
+ (nonnull instancetype)sharedManager;

/**
 * Allows to specify instance of cache and image downloader used with image manager.
 * @return new instance of `SDWebImageManager` with specified cache and downloader.
 */
/* lzy注170720：
 使用指定的缓存器实例、下载器实例初始化一个图片管理者实例。
 */
- (nonnull instancetype)initWithCache:(nonnull SDImageCache *)cache downloader:(nonnull SDWebImageDownloader *)downloader NS_DESIGNATED_INITIALIZER;

/**
 * Downloads the image at the given URL if not present in cache or return the cached version otherwise.
 *
 * @param url            The URL to the image
 * @param options        请求图片时的特定选项。A mask to specify options to use for this request
 * @param progressBlock  图片下载过程中不断通知（后台队列）。A block called while image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock A block called when operation has been completed.
 *   
 下载操作完成回调。
 这个回调是必须传入的。
 这个block没有返回值，有参数：
 1、请求的image、
 2、image对应的二进制数据
 3、error（当请求的图片为nil时，error将有值）
 4、一个标识图片数据是来源于本地缓存还是网络，SDImageCacheType类型
 5、下载进度block。
 当使用下载选项SDWebImageProgressiveDownload，而图片正在下载中，block将被定期调用，finish的布尔值一直为NO，不断有image的片段数据被回调。当图片被全部下载下来之后，这个block将最后一次被回调，携带的是整个图片数据和最后的finish布尔值为YES。
 6、原始图片链接。
 
 *   This parameter is required.
 *
 *   This block has no return value and takes the requested UIImage as first parameter and the NSData representation as second parameter.
 *   In case of error the image parameter is nil and the third parameter may contain an NSError.
 *
 *   The forth parameter is an `SDImageCacheType` enum indicating if the image was retrieved from the local cache
 *   or from the memory cache or from the network.
 *
 *   The fith parameter is set to NO when the SDWebImageProgressiveDownload option is used and the image is
 *   downloading. This block is thus called repeatedly with a partial image. When image is fully downloaded, the
 *   block is called a last time with the full image and the last parameter set to YES.
 *
 *   The last parameter is the original image URL
 *
 * @return Returns an NSObject conforming to SDWebImageOperation. Should be an instance of SDWebImageDownloaderOperation
 */
/* lzy注170720：
 给定URL，
 图片在缓存，返回缓存中的图片，
 下载不在缓存中的图片并回调。
 这个方法返回一个SDWebImageDownloaderOperation对象，该对象遵守SDWebImageOperation协议。
 */
- (nullable id <SDWebImageOperation>)loadImageWithURL:(nullable NSURL *)url
                                              options:(SDWebImageOptions)options
                                             progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                            completed:(nullable SDInternalCompletionBlock)completedBlock;

/**
 * Saves image to cache for given URL
 *
 * @param image The image to cache
 * @param url   The URL to the image
 *
 */
/* lzy注170720：
 使用给定的URL缓存image数据
 */
- (void)saveImageToCache:(nullable UIImage *)image forURL:(nullable NSURL *)url;

/**
 * Cancel all current operations
 */
/* lzy注170720：
 取消所有的下载操作。
 */
- (void)cancelAll;

/**
 * Check one or more operations running
 */
/* lzy注170720：
 查看是否有下载任务在执行。
 */
- (BOOL)isRunning;

/**
 *  Async check if image has already been cached
 *
 *  @param url              image url
 *  @param completionBlock  the block to be executed when the check is finished
 *  
 *  @note the completion block is always executed on the main queue
 */
/* lzy注170720：
 异步查看，给定url的图片是否已经被缓存了。
 完成block将在检查结束后回调。
 注意，完成block只会在主线程回调。
 */
- (void)cachedImageExistsForURL:(nullable NSURL *)url
                     completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;

/**
 *  Async check if image has already been cached on disk only
 *
 *  @param url              image url
 *  @param completionBlock  the block to be executed when the check is finished
 *
 *  @note the completion block is always executed on the main queue
 */
/* lzy注170720：
 异步查看给定url的图片是否仅仅被缓存在磁盘上。
 完成block将在检查结束后回调。
 注意，完成block只会在主线程回调。
 */
- (void)diskImageExistsForURL:(nullable NSURL *)url
                   completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock;


/**
 *Return the cache key for a given URL
 */
/* lzy注170720：
 给定一个URL，返回对应的缓存key
 */
- (nullable NSString *)cacheKeyForURL:(nullable NSURL *)url;

@end
