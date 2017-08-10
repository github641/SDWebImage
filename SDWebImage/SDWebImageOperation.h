/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>

/* lzy注170719：
 SDWebImageOperation协议的内容，
 有一个cancel方法。
 */
@protocol SDWebImageOperation <NSObject>

- (void)cancel;

@end
