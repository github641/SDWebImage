/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) james <https://github.com/mystcolor>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

@interface UIImage (ForceDecode)

/**
 画bitmap
 */
+ (nullable UIImage *)decodedImageWithImage:(nullable UIImage *)image;

/**
如果配置了SDWebImageScaleDownLargeImages，对老设备，降低图片质量
 iPad1、iPad2 、iPhone 3GS、 iPhone 4、iPod 2 and earlier devices: 10.
 */
+ (nullable UIImage *)decodedAndScaledDownImageWithImage:(nullable UIImage *)image;

@end
