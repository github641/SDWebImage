/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCacheOperation.h"

#if SD_UIKIT || SD_MAC

#import "objc/runtime.h"

static char loadOperationKey;

typedef NSMutableDictionary<NSString *, id> SDOperationsDictionary;

@implementation UIView (WebCacheOperation)

/* lzy注170720：
 UIView扩展出来的operationDictionary『属性』的『getter』
 */
- (SDOperationsDictionary *)operationDictionary {
    SDOperationsDictionary *operations = objc_getAssociatedObject(self, &loadOperationKey);
    if (operations) {
        return operations;
    }
    operations = [NSMutableDictionary dictionary];
    objc_setAssociatedObject(self, &loadOperationKey, operations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return operations;
}
/* lzy注170720：
 设置图片加载操作（使用字典管理，字典是对UIView的associated）
 */
- (void)sd_setImageLoadOperation:(nullable id)operation forKey:(nullable NSString *)key {
    if (key) {
        // 有key
        // 给字典设置键值之前，先调用cacel方法，cancel一下目标key所关联的下载操作
        [self sd_cancelImageLoadOperationWithKey:key];
        
        if (operation) {
            // 有key有operation，设置
            SDOperationsDictionary *operationDictionary = [self operationDictionary];
            operationDictionary[key] = operation;
        }
    }
}
/* lzy注170720：
 为当前UIView取消key对应的下载操作。
 从队列中取消正在下载的操作
 */
- (void)sd_cancelImageLoadOperationWithKey:(nullable NSString *)key {
    // Cancel in progress downloader from queue
    
    SDOperationsDictionary *operationDictionary = [self operationDictionary];
    id operations = operationDictionary[key];
    // 用给定的key从associated字典中取到了相关任务，取消它
    if (operations) {
        if ([operations isKindOfClass:[NSArray class]]) {// 是数组
            for (id <SDWebImageOperation> operation in operations) {// 数组对象都时遵守SDWebImageOperation协议的对象
                if (operation) {
                    [operation cancel];
                }
            }
        } else if ([operations conformsToProtocol:@protocol(SDWebImageOperation)]){// 操作对象遵守SDWebImageOperation方法
            [(id<SDWebImageOperation>) operations cancel];
        }
        // 从字典移除
        [operationDictionary removeObjectForKey:key];
    }
}
/* lzy注170720：
 从当前UIView的dict中，移除与key相关的图片下载操作，但不取消该操作
 */
- (void)sd_removeImageLoadOperationWithKey:(nullable NSString *)key {
    if (key) {
        SDOperationsDictionary *operationDictionary = [self operationDictionary];
        [operationDictionary removeObjectForKey:key];
    }
}

@end

#endif
