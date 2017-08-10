/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"

/* lzy注170719：
 判断当前运行环境是否时ARC。不是ARC提示sd仅仅支持ARC，给给出解决方法。
 */
#if !__has_feature(objc_arc)
#error SDWebImage is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

/* lzy注170719：
 1、无image，直接return，有，next
 2、在OSX下运行，直接返回image
 3、若在iOS、tvOS、watchOS上运行，
 3.1 判断image是否是动图（image.images属性，default is nil for non-animated images），遍历其中的图片数组，递归调用本函数处理每一张图片。
 3.2 在watchOS上判断是否有screenScale方法
 3.3 在iOS或tvOS上判断是否有scale方法
 3.4 确定scale的值，根据参数处理，返回处理后的图片。
 
 */
inline UIImage *SDScaledImageForKey(NSString * _Nullable key, UIImage * _Nullable image) {
    if (!image) {
        return nil;
    }
    
#if SD_MAC
    return image;
#elif SD_UIKIT || SD_WATCH
    if ((image.images).count > 0) {
        NSMutableArray<UIImage *> *scaledImages = [NSMutableArray array];

        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:SDScaledImageForKey(key, tempImage)];
        }

        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
#if SD_WATCH
        if ([[WKInterfaceDevice currentDevice] respondsToSelector:@selector(screenScale)]) {
#elif SD_UIKIT
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
#endif
            CGFloat scale = 1;
            if (key.length >= 8) {// 一个字符length是2，4个字符是8
                NSRange range = [key rangeOfString:@"@2x."];
                if (range.location != NSNotFound) {
                    scale = 2.0;
                }
                
                range = [key rangeOfString:@"@3x."];
                if (range.location != NSNotFound) {
                    scale = 3.0;
                }
            }

            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
            image = scaledImage;
        }
        return image;
    }
#endif
}

NSString *const SDWebImageErrorDomain = @"SDWebImageErrorDomain";
