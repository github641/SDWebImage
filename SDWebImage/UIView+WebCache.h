/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

/* lzy注170720：
 引入compat类，判断是否是tvOS、OSX和iOS平台，是的话本类才有实质内容
 */
#import "SDWebImageCompat.h"

#if SD_UIKIT || SD_MAC



#import "SDWebImageManager.h"

/* lzy注170720：
 申明一个设置image的block
 */
typedef void(^SDSetImageBlock)(UIImage * _Nullable image, NSData * _Nullable imageData);

@interface UIView (WebCache)

/**获取当前图片的URL
 * Get the current image URL.
 * 注意，因为category特性的限制，当你直接使用setImage时，这个『属性』将不会同步。
 * Note that because of the limitations of categories this property can get out of sync
 * if you use setImage: directly.
 */
- (nullable NSURL *)sd_imageURL;

/**给imageView的『image』设置一个url和一个可选的占位图
 * Set the imageView `image` with an `url` and optionally a placeholder image.
 * 下载操作是异步的，且将缓存起来。
 * The download is asynchronous and cached.
 *
 * @param url            图片的url。The url for the image.
 * @param placeholder    占位图用于初始设置，直到图片请求结束。
                         The image to be set initially, until the image request finishes.
 * @param options        下载图片时的选项配置。所有可选项定义在SDWebImageOptions中。
                         The options to use when downloading the image. @see SDWebImageOptions for the possible values.
 * @param operationKey   用于标识『图片下载操作』的字符串。若传入的为nil，那么将取该类的类名。
                         A string to be used as the operation key. If nil, will use the class name
 * @param setImageBlock  用于自定义设置图片的代码的block。
                         Block used for custom set image code
 * @param progressBlock  当图片下载时不断回调的block。注意，下载进度block将在后台线程执行。
                         A block called while image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock 当图片下载操作完成时的回调。
                         这个block没有返回值，block的参数：
                         1、请求的图片、
                         2、error（当请求的图片为nil时，error将有值）
                         3、一个标识图片数据是来源于本地缓存还是网络
                         4、原始图片链接。
                         A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 */
- (void)sd_internalSetImageWithURL:(nullable NSURL *)url
                  placeholderImage:(nullable UIImage *)placeholder
                           options:(SDWebImageOptions)options
                      operationKey:(nullable NSString *)operationKey
                     setImageBlock:(nullable SDSetImageBlock)setImageBlock
                          progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                         completed:(nullable SDExternalCompletionBlock)completedBlock;

/**取消当前图片的下载
 * Cancel the current download
 */
- (void)sd_cancelCurrentImageLoad;

/* lzy注170720：
 tvOS和iOS中下面代码有效
 */
#if SD_UIKIT

#pragma mark - Activity indicator

/**展示活动指示器视图
 *  Show activity UIActivityIndicatorView
 */
- (void)sd_setShowActivityIndicatorView:(BOOL)show;

/**设置 活动指示器视图样式
 *  set desired UIActivityIndicatorViewStyle
 *
 *  @param style The style of the UIActivityIndicatorView
 */
- (void)sd_setIndicatorStyle:(UIActivityIndicatorViewStyle)style;

- (BOOL)sd_showActivityIndicatorView;
- (void)sd_addActivityIndicator;
- (void)sd_removeActivityIndicator;

#endif

@end

#endif
