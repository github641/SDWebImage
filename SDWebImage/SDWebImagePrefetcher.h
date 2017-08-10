/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageManager.h"

@class SDWebImagePrefetcher;
/* lzy注170726：
 图片预先获取delegate。两个可选方法
 */
@protocol SDWebImagePrefetcherDelegate <NSObject>

@optional

/**当一张图片已经预先获取时调用
 * Called when an image was prefetched.
 *
 * @param imagePrefetcher The current image prefetcher 预先获取器
 * @param imageURL        The image url that was prefetched 图片地址
 * @param finishedCount   The total number of images that were prefetched (successful or not) 已经有获取结果（成功或失败）的图片数
 * @param totalCount      The total number of images that were to be prefetched 需要预先获取的图片总数
 */
- (void)imagePrefetcher:(nonnull SDWebImagePrefetcher *)imagePrefetcher didPrefetchURL:(nullable NSURL *)imageURL finishedCount:(NSUInteger)finishedCount totalCount:(NSUInteger)totalCount;

/** 当所有图片都预先获取完毕时调用
 * Called when all images are prefetched.
 * @param imagePrefetcher The current image prefetcher 当前预先获取器
 * @param totalCount      The total number of images that were prefetched (whether successful or not) 已经有获取结果（成功或失败）的图片数
 * @param skippedCount    The total number of images that were skipped 被跳过的图片数
 */
- (void)imagePrefetcher:(nonnull SDWebImagePrefetcher *)imagePrefetcher didFinishWithTotalCount:(NSUInteger)totalCount skippedCount:(NSUInteger)skippedCount;

@end
/* lzy注170726：
 声明进度block、完成block
 */
typedef void(^SDWebImagePrefetcherProgressBlock)(NSUInteger noOfFinishedUrls, NSUInteger noOfTotalUrls);
typedef void(^SDWebImagePrefetcherCompletionBlock)(NSUInteger noOfFinishedUrls, NSUInteger noOfSkippedUrls);

/** 为方便以后使用，预先获取一些URLs图片到缓存中。图片下载是低优先级的。
 * Prefetch some URLs in the cache for future use. Images are downloaded in low priority.
 */
@interface SDWebImagePrefetcher : NSObject

/** 网络图片管理者
 *  The web image manager
 */
@property (strong, nonatomic, readonly, nonnull) SDWebImageManager *manager;

/** 最大预取URLs任务并发数，默认为3
 * Maximum number of URLs to prefetch at the same time. Defaults to 3.
 */
@property (nonatomic, assign) NSUInteger maxConcurrentDownloads;

/** 预取器的配置项，默认是低优先级。
 * SDWebImageOptions for prefetcher. Defaults to SDWebImageLowPriority.
 */
@property (nonatomic, assign) SDWebImageOptions options;

/** 预取器的队列配置项，默认是在主线程。
 * Queue options for Prefetcher. Defaults to Main Queue.
 */
@property (nonatomic, assign, nonnull) dispatch_queue_t prefetcherQueue;


@property (weak, nonatomic, nullable) id <SDWebImagePrefetcherDelegate> delegate;

/**
 * Return the global image prefetcher instance.
 */
+ (nonnull instancetype)sharedImagePrefetcher;

/**
 * Allows you to instantiate a prefetcher with any arbitrary image manager.
 */
- (nonnull instancetype)initWithImageManager:(nonnull SDWebImageManager *)manager NS_DESIGNATED_INITIALIZER;

/**
 * Assign list of URLs to let SDWebImagePrefetcher to queue the prefetching,
 * currently one image is downloaded at a time,
 * and skips images for failed downloads and proceed to the next image in the list.
 * Any previously-running prefetch operations are canceled.
 *
 * @param urls list of URLs to prefetch
 */
/* lzy注170726：
 设置一系列URLs，供预取器取用。下载失败，则next，失败的预取操作将被取消。
 */
- (void)prefetchURLs:(nullable NSArray<NSURL *> *)urls;

/** 带block的预取操作。
 * Assign list of URLs to let SDWebImagePrefetcher to queue the prefetching,
 * currently one image is downloaded at a time,
 * and skips images for failed downloads and proceed to the next image in the list.
 * Any previously-running prefetch operations are canceled.
 *
 * @param urls            list of URLs to prefetch
 * @param progressBlock   block to be called when progress updates; 
 *                        first parameter is the number of completed (successful or not) requests, 
 *                        second parameter is the total number of images originally requested to be prefetched
 * @param completionBlock block to be called when prefetching is completed
 *                        first param is the number of completed (successful or not) requests,
 *                        second parameter is the number of skipped requests
 */
- (void)prefetchURLs:(nullable NSArray<NSURL *> *)urls
            progress:(nullable SDWebImagePrefetcherProgressBlock)progressBlock
           completed:(nullable SDWebImagePrefetcherCompletionBlock)completionBlock;

/**
 * Remove and cancel queued list
 */
- (void)cancelPrefetching;


@end
