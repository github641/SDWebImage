/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"

#if SD_UIKIT || SD_MAC

#import "SDWebImageManager.h"

/**
 * Integrates SDWebImage async downloading and caching of remote images with UIImageView.
 *
 * Usage with a UITableViewCell sub-class:
 *
 * @code
 
#import <SDWebImage/UIImageView+WebCache.h>

...

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *MyIdentifier = @"MyIdentifier";
 
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
 
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MyIdentifier]
                 autorelease];
    }
 
    // Here we use the provided sd_setImageWithURL: method to load the web image
    // Ensure you use a placeholder image otherwise cells will be initialized with no image
    [cell.imageView sd_setImageWithURL:[NSURL URLWithString:@"http://example.com/image.jpg"]
                      placeholderImage:[UIImage imageNamed:@"placeholder"]];
 
    cell.textLabel.text = @"My Text";
    return cell;
}

 * @endcode
 */

/* lzy注170719：
 扩展UIImageView组件，集成sd，异步下载，缓存远程图片
 */
@interface UIImageView (WebCache)

/**
 * Set the imageView `image` with an `url`.
 * 给imageView的『image』属性设置一个『url』
 * The download is asynchronous and cached.
 * 下载动作时异步且缓存的
 * @param url The url for the image.
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url;

/**
 * Set the imageView `image` with an `url` and a placeholder.
 * 给imageView的『image』设置一个『url』和一个占位图片
 * The download is asynchronous and cached.
 * 根据url下载图片的操作时异步且进行缓存的。
 * @param url         The url for the image.
 * @param placeholder The image to be set initially, until the image request finishes.占位图片用初始设置，打给你图片请求完成后替换。
 * @see sd_setImageWithURL:placeholderImage:options:
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder;

/**
 * Set the imageView `image` with an `url`, placeholder and custom options.
 * 给imageView的『image』设置一个url、占位图片以及自定义选项
 * The download is asynchronous and cached.
 * 下载操作时异步的且将进行缓存。
 * @param url         The url for the image.
 * @param placeholder The image to be set initially, until the image request finishes.
 * @param options     The options to use when downloading the image. @see SDWebImageOptions for the possible values.这个自定义选项用于下载图片时。参看SDWebImageOptions中定义的可选值。
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options;

/**
 * Set the imageView `image` with an `url`.
 *
 * The download is asynchronous and cached.
 *
 * @param url            The url for the image.
 * @param completedBlock A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 
 typedef void(^SDExternalCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL);
 当下载操作完成后，这个完成block将会被调用。
 这个block没有返回值，将请求过的UIImage对象当做第一参数。
 请求图片可能出错，将放在参数error中。
 SDImageCacheType指明了图片数据时来源于网络还是缓存。
 原始图片url也是参数之一。
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * Set the imageView `image` with an `url`, placeholder.
 *
 * The download is asynchronous and cached.
 *
 * @param url            The url for the image.
 * @param placeholder    The image to be set initially, until the image request finishes.
 * @param completedBlock A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * Set the imageView `image` with an `url`, placeholder and custom options.
 *
 * The download is asynchronous and cached.
 *
 * @param url            The url for the image.
 * @param placeholder    The image to be set initially, until the image request finishes.
 * @param options        The options to use when downloading the image. @see SDWebImageOptions for the possible values.
 * @param completedBlock A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**
 * Set the imageView `image` with an `url`, placeholder and custom options.
 *
 * The download is asynchronous and cached.
 *
 * @param url            The url for the image.
 * @param placeholder    The image to be set initially, until the image request finishes.
 * @param options        The options to use when downloading the image. @see SDWebImageOptions for the possible values.
 * @param progressBlock  A block called while image is downloading
 *                       @note the progress block is executed on a background queue
 * 一个在下载图片过程中进行回调的block，注意，这个进度block是在后台线程执行的。
 * @param completedBlock A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 */
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                   options:(SDWebImageOptions)options
                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                 completed:(nullable SDExternalCompletionBlock)completedBlock;

/**这个方法会先根据url去缓存中取一下是否『之前缓存过』，缓存过，拿来当『占位图』，再请求；没有缓存过，用开发者自己传入的占位图，再请求
 * Set the imageView `image` with an `url` and optionally a placeholder image.
 *
 * The download is asynchronous and cached.
 *
 * @param url            The url for the image.
 * @param placeholder    The image to be set initially, until the image request finishes.
 * @param options        The options to use when downloading the image. @see SDWebImageOptions for the possible values.
 * @param progressBlock  A block called while image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 */
- (void)sd_setImageWithPreviousCachedImageWithURL:(nullable NSURL *)url
                                 placeholderImage:(nullable UIImage *)placeholder
                                          options:(SDWebImageOptions)options
                                         progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                        completed:(nullable SDExternalCompletionBlock)completedBlock;

#if SD_UIKIT

#pragma mark - Animation of multiple images

/**根据一组图片URLs下载一组图片，并在『动画循环』中开启播放
 * Download an array of images and starts them in an animation loop
 *
 * @param arrayOfURLs An array of NSURL
 */
- (void)sd_setAnimationImagesWithURLs:(nonnull NSArray<NSURL *> *)arrayOfURLs;

/* lzy注170719：
 取消当前 动图 的加载
 */
- (void)sd_cancelCurrentAnimationImagesLoad;

#endif

@end

#endif
