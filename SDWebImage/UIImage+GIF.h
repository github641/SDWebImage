/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Laurin Brandner
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageCompat.h"

@interface UIImage (GIF)

/** sd的4.0使用FLAnimatedImage来播放动图了，这个方法为了兼容的必要性（恐怕就是有的开发者升级了类库，但是接入方法没有跟着升级，容易报找不到方法的崩溃）。
 *  Compatibility method - creates an animated UIImage from an NSData, it will only contain the 1st frame image
 */
+ (UIImage *)sd_animatedGIFWithData:(NSData *)data;

/**
 *  Checks if an UIImage instance is a GIF. Will use the `images` array
 */
- (BOOL)isGIF;

@end
