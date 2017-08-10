/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCache.h"

/* lzy注170720：
 引入compat类，判断是否是tvOS、OSX和iOS平台，是的话本类才有实质内容
 */
#if SD_UIKIT || SD_MAC

#import "objc/runtime.h"
#import "UIView+WebCacheOperation.h"

/* lzy注170720：
 申明几个char型静态变量,作为 associated的key：
 1、做图片url的键
 2、活动指示器tag
 3、活动指示器的style的tag
 4、活动指示器是否展示
 */
static char imageURLKey;

#if SD_UIKIT
static char TAG_ACTIVITY_INDICATOR;
static char TAG_ACTIVITY_STYLE;
#endif
static char TAG_ACTIVITY_SHOW;

@implementation UIView (WebCache)

/* lzy注170720：
 这是本类对外开放的一个 getter，内部是getAssociated，取到的是『char型静态变量』
 */
- (nullable NSURL *)sd_imageURL {
    return objc_getAssociatedObject(self, &imageURLKey);
}
/**给imageView的『image』设置一个url和一个可选的占位图
 * 下载操作是异步的，且将缓存起来。
 * @param url            图片的url。
 * @param placeholder    占位图用于初始设置，直到图片请求结束。
 * @param options        下载图片时的选项配置。所有可选项定义在SDWebImageOptions中。
 * @param operationKey   用于标识『图片下载操作』的字符串。若传入的为nil，那么将取该类的类名。
 * @param setImageBlock  用于自定义设置图片的代码的block。
 * @param progressBlock  当图片下载时不断回调的block。注意，下载进度block将在后台线程执行。
 * @param completedBlock 当图片下载操作完成时的回调。
 这个block没有返回值，block的参数：
 1、请求的图片、
 2、error（当请求的图片为nil时，error将有值）
 3、一个标识图片数据是来源于本地缓存还是网络
 4、原始图片链接。
 
 #调用流程#
 1、获取有效的下载操作标志符，若传入了有效的则使用，传入的无效则获取调用本方法的实例所属的类的类名。
 2、使用第一步的操作标志符，先cancel下正在执行该『操作标志符』的下载操作。
 3、给调用本方法的对象使用setAssociated关联该『操作标志符』
 4、给iv赋值占位图片。关于枚举位运算的注释在SDWebImageOptions定义处。
 传入的图片枚举选项是SDWebImageDelayPlaceholder（占位图片不会在图片下载过程中赋值给iv）吗？
 是，不进入if语句
 不是，到主线程给iv设置占位图。
 5、无url，到主线程移除活动指示器，调用completeBlock
 有url：
     1）、若『显示活动指示器』，则『添加活动显示器』
     2）、SDWebImageManager单例 load该url，请求url图片
     3）、把该图片下载操作加入『图片下载操作管理字典』中
     4）、图片加载操作的回调结果的处理（见代码处）
 
 */
- (void)sd_internalSetImageWithURL:(nullable NSURL *)url
                  placeholderImage:(nullable UIImage *)placeholder
                           options:(SDWebImageOptions)options
                      operationKey:(nullable NSString *)operationKey
                     setImageBlock:(nullable SDSetImageBlock)setImageBlock
                          progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                         completed:(nullable SDExternalCompletionBlock)completedBlock {
    NSString *validOperationKey = operationKey ?: NSStringFromClass([self class]);
    [self sd_cancelImageLoadOperationWithKey:validOperationKey];
    objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    if (!(options & SDWebImageDelayPlaceholder)) {
        dispatch_main_async_safe(^{
            [self sd_setImage:placeholder imageData:nil basedOnClassOrViaCustomSetImageBlock:setImageBlock];
        });
    }
    
    if (url) {
        // check if activityView is enabled or not
        if ([self sd_showActivityIndicatorView]) {
            [self sd_addActivityIndicator];
        }
        
        __weak __typeof(self)wself = self;
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager loadImageWithURL:url options:options progress:progressBlock completed:^(UIImage *image, NSData *data, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
            __strong __typeof (wself) sself = wself;
            [sself sd_removeActivityIndicator];
            // 若调用者已经不在了，直接return
            if (!sself) {
                return;
            }
            // 到主线程
            dispatch_main_async_safe(^{
                // 若调用者已经不在了，直接return
                if (!sself) {
                    return;
                }
                // 图片数据存在 且 下载完图片不马上赋值选项 且 完成block存在
                if (image && (options & SDWebImageAvoidAutoSetImage) && completedBlock) {
                    completedBlock(image, error, cacheType, url);
                    return;
                } else if (image) {// 图片数据存在
                    // 传到block中去赋值
                    [sself sd_setImage:image imageData:data basedOnClassOrViaCustomSetImageBlock:setImageBlock];
                    // sd为了兼容做的统一刷新界面做法
                    [sself sd_setNeedsLayout];
                } else {// 没有图片数据
                    if ((options & SDWebImageDelayPlaceholder)) {// 若是『占位图片不会在图片下载过程中赋值给iv』选项，那么此时，把占位图片赋值给iv
                        [sself sd_setImage:placeholder imageData:nil basedOnClassOrViaCustomSetImageBlock:setImageBlock];
                        // 调用兼容刷新界面方法
                        [sself sd_setNeedsLayout];
                    }
                }
                // 以上种种判断与处理完毕，若结束 且 有completedBlock，调用这个block
                if (completedBlock && finished) {
                    completedBlock(image, error, cacheType, url);
                }
            });
        }];
        
        [self sd_setImageLoadOperation:operation forKey:validOperationKey];
    } else {
        dispatch_main_async_safe(^{
            [self sd_removeActivityIndicator];
            if (completedBlock) {
                NSError *error = [NSError errorWithDomain:SDWebImageErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
                completedBlock(nil, error, SDImageCacheTypeNone, url);
            }
        });
    }
}

/* lzy注170720：
 上一个方法中调用的- (void)sd_setImageLoadOperation:forKey:方法和下面的方法都在UIView+WebCacheOperation中。
 */
/**取消当前图片的下载。
 调用的是类UIView+WebCacheOperation中的方法。
 */
- (void)sd_cancelCurrentImageLoad {
    [self sd_cancelImageLoadOperationWithKey:NSStringFromClass([self class])];
}

/* lzy注170720：
 把图片对象，图片二进制数据，『设置图片的block』作为参数传入，内部调用『设置图片的block』
 若block存在，调用该block，给图片赋值。
 */
- (void)sd_setImage:(UIImage *)image imageData:(NSData *)imageData basedOnClassOrViaCustomSetImageBlock:(SDSetImageBlock)setImageBlock {
    // 若开发者实现了block，那么直接调用
    if (setImageBlock) {
        setImageBlock(image, imageData);
        return;
    }
    // 兼容处理：iOS、tvOS、OSX
#if SD_UIKIT || SD_MAC
    // 调用者是UIImageView对象，给iv.image赋值
    if ([self isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)self;
        imageView.image = image;
    }
#endif
    // 兼容处理：iOS、tvOS
#if SD_UIKIT
    // 若调用者是btn，给btn的图片赋值
    if ([self isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)self;
        [button setImage:image forState:UIControlStateNormal];
    }
#endif
}

/* lzy注170720：
 sd为平台兼容：界面是否需要刷新，刷新方法调用的统一处理。
 */
- (void)sd_setNeedsLayout {
    // tvOS、iOS
#if SD_UIKIT
    [self setNeedsLayout];
    // OSX
#elif SD_MAC
    [self setNeedsLayout:YES];
#endif
}

#pragma mark - Activity indicator

/* lzy注170720：
 一下是活动指示器相关的方法
 */
#pragma mark -
// tvOS、iOS开始
#if SD_UIKIT
/* lzy注170720：
 activityIndicator的『getter』
 */
- (UIActivityIndicatorView *)activityIndicator {
    return (UIActivityIndicatorView *)objc_getAssociatedObject(self, &TAG_ACTIVITY_INDICATOR);
}
/* lzy注170720：
 activityIndicator的『setter』
 */
- (void)setActivityIndicator:(UIActivityIndicatorView *)activityIndicator {
    objc_setAssociatedObject(self, &TAG_ACTIVITY_INDICATOR, activityIndicator, OBJC_ASSOCIATION_RETAIN);
}
#endif
// tvOS、iOS结束


/* lzy注170720：
 是否展示activityIndicator的『setter』
 */
- (void)sd_setShowActivityIndicatorView:(BOOL)show {
    objc_setAssociatedObject(self, &TAG_ACTIVITY_SHOW, @(show), OBJC_ASSOCIATION_RETAIN);
}
/* lzy注170720：
 是否展示activityIndicator的『getter』
 */
- (BOOL)sd_showActivityIndicatorView {
    return [objc_getAssociatedObject(self, &TAG_ACTIVITY_SHOW) boolValue];
}

#if SD_UIKIT // tvOS、iOS
/* lzy注170720：
 UIActivityIndicatorViewStyle的『setter』
 */
- (void)sd_setIndicatorStyle:(UIActivityIndicatorViewStyle)style{
    objc_setAssociatedObject(self, &TAG_ACTIVITY_STYLE, [NSNumber numberWithInt:style], OBJC_ASSOCIATION_RETAIN);
}
/* lzy注170720：
 UIActivityIndicatorViewStyle的『getter』
 */
- (int)sd_getIndicatorStyle{
    return [objc_getAssociatedObject(self, &TAG_ACTIVITY_STYLE) intValue];
}
#endif// tvOS、iOS结束

/* lzy注170720：
 添加活动指示器
 */
- (void)sd_addActivityIndicator {
#if SD_UIKIT
    if (!self.activityIndicator) {//不存在，则创建
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[self sd_getIndicatorStyle]];
        // 手动写autoLayout的约束，把这个属性置为NO。
        self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        
        dispatch_main_async_safe(^{
            // 回到主线程
            // 添加视图
            [self addSubview:self.activityIndicator];
            // 约束指示器的中心在调用者的中心
            [self addConstraint:[NSLayoutConstraint constraintWithItem:self.activityIndicator
                                                             attribute:NSLayoutAttributeCenterX
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:self
                                                             attribute:NSLayoutAttributeCenterX
                                                            multiplier:1.0
                                                              constant:0.0]];
            [self addConstraint:[NSLayoutConstraint constraintWithItem:self.activityIndicator
                                                             attribute:NSLayoutAttributeCenterY
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:self
                                                             attribute:NSLayoutAttributeCenterY
                                                            multiplier:1.0
                                                              constant:0.0]];
        });
    }
    
    dispatch_main_async_safe(^{// 在主线程开启指示器的动画
        [self.activityIndicator startAnimating];
    });
#endif
}

- (void)sd_removeActivityIndicator {
#if SD_UIKIT
    if (self.activityIndicator) {
        [self.activityIndicator removeFromSuperview];
        self.activityIndicator = nil;
    }
#endif
}

@end

#endif
