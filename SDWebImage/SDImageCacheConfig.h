//
//  SDImageCacheConfig.h
//  SDWebImage
//
//  Created by Bogdan on 09/09/16.
//  Copyright © 2016 Dailymotion. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

/* lzy注170724：
 这个类时sd的缓存（内存、磁盘）策略配置类，
 */

@interface SDImageCacheConfig : NSObject

/** 解压图片（下载完、缓存的）可以提升性能，但是将消耗大量的内存。默认时YES，如果你总是因为过多的内存使用而造成崩溃，将它设置为NO。
 * Decompressing images that are downloaded and cached can improve performance but can consume lot of memory.
 * Defaults to YES. Set this to NO if you are experiencing a crash due to excessive memory consumption.
 */
@property (assign, nonatomic) BOOL shouldDecompressImages;

/** 缓存不在iCloud备份。默认为YES。
 *  disable iCloud backup [defaults to YES]
 */
@property (assign, nonatomic) BOOL shouldDisableiCloud;

/**使用内存缓存。默认为Yes
 * use memory cache [defaults to YES]
 */
@property (assign, nonatomic) BOOL shouldCacheImagesInMemory;

/**最大缓存秒数。默认一周。
 * The maximum length of time to keep an image in the cache, in seconds
 */
@property (assign, nonatomic) NSInteger maxCacheAge;

/**最大缓存字节。默认为0。
 * The maximum size of the cache, in bytes.
 */
@property (assign, nonatomic) NSUInteger maxCacheSize;

@end
