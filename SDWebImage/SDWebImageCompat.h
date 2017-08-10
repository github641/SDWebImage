/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 * (c) Jamie Pinkham
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

/* lzy注170720：
 『SDWebImageCompat』，compat是『兼容』的意思。
 这个类主要是sd运行环境的判断，包括，运行平台，开发sdk时哪个，api兼容
 */
#import <TargetConditionals.h>

/* lzy注170719：
 如果定义了『__OBJC_GC__』这个宏，直接打印错误，sd不支持OC 垃圾回收。
 */
#ifdef __OBJC_GC__
    #error SDWebImage does not support Objective-C Garbage Collection
#endif

// Apple's defines from TargetConditionals.h are a bit weird.
// Seems like TARGET_OS_MAC is always defined (on all platforms).
// To determine if we are running on OSX, we can only rely on TARGET_OS_IPHONE=0 and all the other platforms
/* lzy注170719：运行平台是否是MAC
 苹果在TargetConditionals.h的定义有点儿奇怪。
 比如宏 TARGET_OS_MAC 总是定义所有的平台。
 判断我们是不是在OSX上运行，我们可以通过 TARGET_OS_IPHONE=0等其他平台的宏来反证 是否在OSX上运行。
 */
#if !TARGET_OS_IPHONE && !TARGET_OS_IOS && !TARGET_OS_TV && !TARGET_OS_WATCH
    #define SD_MAC 1
#else
    #define SD_MAC 0
#endif

// iOS and tvOS are very similar, UIKit exists on both platforms
// Note: watchOS also has UIKit, but it's very limited
/* lzy注170719：运行平台是否拥有功能齐全的UIKIT框架。
 iOS 和 tvOS 是非常相似的。UIKit在这两个平台都存在。
 注意，watchOS也有一个功能受限的UIKit框架。
 */
#if TARGET_OS_IOS || TARGET_OS_TV
    #define SD_UIKIT 1
#else
    #define SD_UIKIT 0
#endif
/* lzy注170719：
 运行平台是否是iOS
 */
#if TARGET_OS_IOS
    #define SD_IOS 1
#else
    #define SD_IOS 0
#endif
/* lzy注170719：
 运行平台是否是tvOS
 */
#if TARGET_OS_TV
    #define SD_TV 1
#else
    #define SD_TV 0
#endif
/* lzy注170719：
 运行平台是否是watchOS
 */
#if TARGET_OS_WATCH
    #define SD_WATCH 1
#else
    #define SD_WATCH 0
#endif

/* lzy注170719：
 根据上一部分的平台、UIKIT功能是否齐全的判断，来决定头文件的引入。
 1、是OSX，则导入AppKit，
 对应
 NSImage -- UIImage
 NSImageView -- UIImageView
 NSView -- UIView
 
 2、判断sd运行环境的工程设置若是低于5.0，报错sd不支持5.0以下。
 */
#if SD_MAC
    #import <AppKit/AppKit.h>
    #ifndef UIImage
        #define UIImage NSImage
    #endif
    #ifndef UIImageView
        #define UIImageView NSImageView
    #endif
    #ifndef UIView
        #define UIView NSView
    #endif
#else
    #if __IPHONE_OS_VERSION_MIN_REQUIRED != 20000 && __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_5_0
        #error SDWebImage doesn't support Deployment Target version < 5.0
    #endif

    #if SD_UIKIT
        #import <UIKit/UIKit.h>
    #endif
    #if SD_WATCH
        #import <WatchKit/WatchKit.h>
    #endif
#endif

/* lzy注170719：
 若没有定义NS_ENUM 和 NS_OPTIONS，那么定义他们。
 这两个宏的官方定义在Foundation.framework的NSObjCRuntime.h中。
 http://blog.csdn.net/annkie/article/details/9877643
 */
#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

#ifndef NS_OPTIONS
#define NS_OPTIONS(_type, _name) enum _name : _type _name; enum _name : _type
#endif

/* lzy注170719：
 ARC开启的情况下是否需要对GCD对象dispatch_release ?http://blog.csdn.net/yohunl/article/details/17301875。
 
 OS_OBJECT_USE_OBJC这个宏是在sdk6.0之后才有的,如果是之前的,则OS_OBJECT_USE_OBJC为0
 
 对于最低sdk版本>=ios6.0来说,GCD对象已经纳入了ARC的管理范围,我们就不需要再手工调用 dispatch_release了,否则的话,在sdk<6.0的时候,即使我们开启了ARC,这个宏OS_OBJECT_USE_OBJC 也是没有的,也就是说这个时候,GCD对象还必须得自己管理
 
 
 */
#if OS_OBJECT_USE_OBJC
    #undef SDDispatchQueueRelease
    #undef SDDispatchQueueSetterSementics
    #define SDDispatchQueueRelease(q)
    #define SDDispatchQueueSetterSementics strong
#else
    #undef SDDispatchQueueRelease
    #undef SDDispatchQueueSetterSementics
    #define SDDispatchQueueRelease(q) (dispatch_release(q))
    #define SDDispatchQueueSetterSementics assign
#endif

/* lzy注170719：
 对外声明一个缩放image的函数。
 */
extern UIImage *SDScaledImageForKey(NSString *key, UIImage *image);

/* lzy注170719：
 声明一个没有参数的block
 */
typedef void(^SDWebImageNoParamsBlock)();
/* lzy注170719：
 sd的自定义错误域
 */
extern NSString *const SDWebImageErrorDomain;

/* lzy注170719：
 判断当前队列是否是主队列：当前队列标签与主队列标签进行字符串比较
 是主队列：执行block；
 不是主队列：切换到主队列执行block。
 */
#ifndef dispatch_main_async_safe
#define dispatch_main_async_safe(block)\
    if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {\
        block();\
    } else {\
        dispatch_async(dispatch_get_main_queue(), block);\
    }
#endif

/* lzy注170719：
 异步测试超时时间
 */
static int64_t kAsyncTestTimeout = 5;
