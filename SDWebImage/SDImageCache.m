/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDImageCache.h"
#import "SDWebImageDecoder.h"
#import "UIImage+MultiFormat.h"
#import <CommonCrypto/CommonDigest.h>
#import "UIImage+GIF.h"
#import "NSData+ImageContentType.h"
#import "NSImage+WebCache.h"
#import "SDImageCacheConfig.h"

// See https://github.com/rs/SDWebImage/pull/1141 for discussion
/* lzy注170724：
 继承自 NSCache
 */
@interface AutoPurgeCache : NSCache
@end

@implementation AutoPurgeCache

- (nonnull instancetype)init {
    self = [super init];
    if (self) {
#if SD_UIKIT
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    }
    return self;
}

- (void)dealloc {
#if SD_UIKIT
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
}

@end

/* lzy注170724：
 函数：内存中缓存一张图片的大小的计算.
 mac中是 宽*高
 iOS、tvOS、watchOS：
 宽*scale * 高*scale
 */
FOUNDATION_STATIC_INLINE NSUInteger SDCacheCostForImage(UIImage *image) {
#if SD_MAC
    return image.size.height * image.size.width;
#elif SD_UIKIT || SD_WATCH
    return image.size.height * image.size.width * image.scale * image.scale;
#endif
}

@interface SDImageCache ()

#pragma mark - Properties

/**
 内存缓存
 */
@property (strong, nonatomic, nonnull) NSCache *memCache;

/**
 磁盘缓存
 */
@property (strong, nonatomic, nonnull) NSString *diskCachePath;

/**
 数组，管理 缓存路径
 */
@property (strong, nonatomic, nullable) NSMutableArray<NSString *> *customPaths;

/**
 GCD创建的队列变量。SDDispatchQueueSetterSementics 是对此属性关键字 兼容的修饰
 */
@property (SDDispatchQueueSetterSementics, nonatomic, nullable) dispatch_queue_t ioQueue;

@end


@implementation SDImageCache {
    NSFileManager *_fileManager;
}

#pragma mark - Singleton, init, dealloc

+ (nonnull instancetype)sharedImageCache {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (instancetype)init {
    return [self initWithNamespace:@"default"];
}

/**lzy注170724：
 使用给定的命名空间创建一个新的缓存存储
 1、使用该命名空间拼接 缓存文件夹路径
 */
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns {
    NSString *path = [self makeDiskCachePath:ns];
    return [self initWithNamespace:ns diskCacheDirectory:path];
}
/* lzy注170724：
 使用给定的命名空间、文件夹创建一个新的缓存存储
 */
- (nonnull instancetype)initWithNamespace:(nonnull NSString *)ns
                       diskCacheDirectory:(nonnull NSString *)directory {
    if ((self = [super init])) {
        NSString *fullNamespace = [@"com.hackemist.SDWebImageCache." stringByAppendingString:ns];
        
        // Create IO serial queue
        _ioQueue = dispatch_queue_create("com.hackemist.SDWebImageCache", DISPATCH_QUEUE_SERIAL);
        
        _config = [[SDImageCacheConfig alloc] init];
        
        // Init the memory cache
        _memCache = [[AutoPurgeCache alloc] init];
        _memCache.name = fullNamespace;
        
        // Init the disk cache
        if (directory != nil) {
            _diskCachePath = [directory stringByAppendingPathComponent:fullNamespace];
        } else {
            NSString *path = [self makeDiskCachePath:ns];
            _diskCachePath = path;
        }
        
        dispatch_sync(_ioQueue, ^{
            _fileManager = [NSFileManager new];
        });
        
#if SD_UIKIT
        // Subscribe to app events
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clearMemory)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deleteOldFiles)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(backgroundDeleteOldFiles)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
#endif
    }
    
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    SDDispatchQueueRelease(_ioQueue);
}

/* lzy注170724：
 再次看到 比较两个队列是否是同一个队列的方法，字符串比较他们的label
 */
- (void)checkIfQueueIsIOQueue {
    const char *currentQueueLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    const char *ioQueueLabel = dispatch_queue_get_label(self.ioQueue);
    if (strcmp(currentQueueLabel, ioQueueLabel) != 0) {
        NSLog(@"This method should be called from the ioQueue");
    }
}

#pragma mark - Cache paths
/* lzy注170724：
 只读缓存路径添加。
 用于SDImageCache『预存』图片的搜索；如果你想要将『预存』图片整合到一个bundle里。
 1、管理缓存路径的数组不存在，创建一个
 2、给定的路径不在 『缓存路径管理数组』中没有它，添加它
 */
- (void)addReadOnlyCachePath:(nonnull NSString *)path {
    if (!self.customPaths) {
        self.customPaths = [NSMutableArray new];
    }
    
    if (![self.customPaths containsObject:path]) {
        [self.customPaths addObject:path];
    }
}

- (nullable NSString *)cachePathForKey:(nullable NSString *)key inPath:(nonnull NSString *)path {
    // 根据key，生成一个文件名，它和文件夹拼接起来
    NSString *filename = [self cachedFileNameForKey:key];
    return [path stringByAppendingPathComponent:filename];
}

/**
 给定key（即url） 和 缓存文件夹 ==> 缓存文件的绝对路径
 */
- (nullable NSString *)defaultCachePathForKey:(nullable NSString *)key {
    return [self cachePathForKey:key inPath:self.diskCachePath];
}


/* lzy注170725：
 给定key，生成一个文件名。
 key的MD5，若key有文件扩展名，拼接在MD5结果的后面。
 */
- (nullable NSString *)cachedFileNameForKey:(nullable NSString *)key {
    const char *str = key.UTF8String;
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15], [key.pathExtension isEqualToString:@""] ? @"" : [NSString stringWithFormat:@".%@", key.pathExtension]];
    
    return filename;
}
/* lzy注170724：
 使用给定的命名空间，创建 磁盘缓存文件夹
 */
- (nullable NSString *)makeDiskCachePath:(nonnull NSString*)fullNamespace {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [paths[0] stringByAppendingPathComponent:fullNamespace];
}

#pragma mark - Store Ops
/* lzy注170724：
 使用给定key异步缓存图片到内存和磁盘中
 */
- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
        completion:(nullable SDWebImageNoParamsBlock)completionBlock {
    [self storeImage:image imageData:nil forKey:key toDisk:YES completion:completionBlock];
}

- (void)storeImage:(nullable UIImage *)image
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock {
    [self storeImage:image imageData:nil forKey:key toDisk:toDisk completion:completionBlock];
}


/**
 1、验证传入参数：没有image 或者没有key直接回调并return
 2、如果 cofig配置中的内存缓存允许，缓存image
 3、如果传入参数 存储到磁盘 的flag为真，缓存它
 */
- (void)storeImage:(nullable UIImage *)image
         imageData:(nullable NSData *)imageData
            forKey:(nullable NSString *)key
            toDisk:(BOOL)toDisk
        completion:(nullable SDWebImageNoParamsBlock)completionBlock {
    if (!image || !key) {
        if (completionBlock) {
            completionBlock();
        }
        return;
    }
    // if memory cache is enabled
    if (self.config.shouldCacheImagesInMemory) {
        // 计算内存消耗
        NSUInteger cost = SDCacheCostForImage(image);
        // 缓存到内存
        [self.memCache setObject:image forKey:key cost:cost];
    }
    
    if (toDisk) {
        
        dispatch_async(self.ioQueue, ^{// 切换到专门创建的队列中io队列
            NSData *data = imageData;
            
            if (!data && image) {// 没有data有image
                /*
                 这里有点儿奇怪，只有 ！data 为真  && image存在为真  的情况下，才会进入这个if大括号。
                 如果 data为空， ！data才会为 真。
                 data为空，调用sd_imageFormatForImageData时，方法内第一件事情就是：
                 if (!data) {
                 return SDImageFormatUndefined;
                 }
                 那么，这个大括号是用来处理这种情况：
                 若只传入了image，没有传入imageData，那么图片格式为『未定义』
                 */
                SDImageFormat imageFormatFromData = [NSData sd_imageFormatForImageData:data];
                
                // 将image转为『未定义』图片格式的data
                data = [image sd_imageDataAsFormat:imageFormatFromData];
            }
            // 存储data（可能是直接传入的，也可能是image转的）
            [self storeImageDataToDisk:data forKey:key];
            
            // 回调结束
            if (completionBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock();
                });
            }
        });
    } else {// 不存到磁盘，直接回调结束
        if (completionBlock) {
            completionBlock();
        }
    }
}
/* lzy注170725：警告，这个方法是异步的，务必在ioQueue中调用它
 使用给定的key，将给定的图片data存入磁盘
 1、验证传入参数
 2、检查当前队列是否为专门的io队列
 */
- (void)storeImageDataToDisk:(nullable NSData *)imageData forKey:(nullable NSString *)key {
    
    if (!imageData || !key) {
        return;
    }
    // 如果不是io队列，仅仅时打印一个警告log
    [self checkIfQueueIsIOQueue];
    // 当前实例的磁盘缓存路径不存在，创建一个路径
    if (![_fileManager fileExistsAtPath:_diskCachePath]) {
        [_fileManager createDirectoryAtPath:_diskCachePath withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    
    // get cache Path for image key，这个图片的缓存路径 = 磁盘缓存文件夹 + 『处理后的文件名』
    NSString *cachePathForKey = [self defaultCachePathForKey:key];
    // transform to NSUrl
    NSURL *fileURL = [NSURL fileURLWithPath:cachePathForKey];
    
    // 文件管理器写入文件
    [_fileManager createFileAtPath:cachePathForKey contents:imageData attributes:nil];
    
    // disable iCloud backup 给文件路径添加不在iCloud备份属性
    if (self.config.shouldDisableiCloud) {
        [fileURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
}

#pragma mark - Query and Retrieve Ops
/* lzy注170725：
 异步查看图片是否已经存储在磁盘中了
 */
- (void)diskImageExistsWithKey:(nullable NSString *)key completion:(nullable SDWebImageCheckCacheCompletionBlock)completionBlock {
    dispatch_async(_ioQueue, ^{
        BOOL exists = [_fileManager fileExistsAtPath:[self defaultCachePathForKey:key]];
        
        // fallback because of https://github.com/rs/SDWebImage/pull/976 that added the extension to the disk file name
        // checking the key with and without the extension
        if (!exists) {
            exists = [_fileManager fileExistsAtPath:[self defaultCachePathForKey:key].stringByDeletingPathExtension];
        }
        
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(exists);
            });
        }
    });
}
/* lzy注170725：
 从内存中取出给定key的UIImage并返回
 */
- (nullable UIImage *)imageFromMemoryCacheForKey:(nullable NSString *)key {
    return [self.memCache objectForKey:key];
}
/* lzy注170725：
 从磁盘中取出给定key的UIImage并返回并返回。
 若cofig实例中允许存储在内存中，再缓存到内存中
 */
- (nullable UIImage *)imageFromDiskCacheForKey:(nullable NSString *)key {
    UIImage *diskImage = [self diskImageForKey:key];
    if (diskImage && self.config.shouldCacheImagesInMemory) {
        NSUInteger cost = SDCacheCostForImage(diskImage);
        [self.memCache setObject:diskImage forKey:key cost:cost];
    }
    
    return diskImage;
}
/* lzy注170725：
 从内存中取出给定key的UIImage并返回；
 不存在；
 从磁盘中取出给定key的UIImage并返回。
 */
- (nullable UIImage *)imageFromCacheForKey:(nullable NSString *)key {
    // First check the in-memory cache...
    UIImage *image = [self imageFromMemoryCacheForKey:key];
    if (image) {
        return image;
    }
    
    // Second check the disk cache...
    image = [self imageFromDiskCacheForKey:key];
    return image;
}
/* lzy注170725：
 从磁盘中取出给定key的data
 1、key > path
 2、path > data
 3、data有值，直接return
 4、没取成功，移除path中的扩展名，再取。取成功直接return，失败next
 5、遍历 『自定义缓存路径管理数组』，重复1~4步
 */
- (nullable NSData *)diskImageDataBySearchingAllPathsForKey:(nullable NSString *)key {
    NSString *defaultPath = [self defaultCachePathForKey:key];
    NSData *data = [NSData dataWithContentsOfFile:defaultPath];
    if (data) {
        return data;
    }
    
    // fallback because of https://github.com/rs/SDWebImage/pull/976 that added the extension to the disk file name
    // checking the key with and without the extension
    data = [NSData dataWithContentsOfFile:defaultPath.stringByDeletingPathExtension];
    if (data) {
        return data;
    }
    
    NSArray<NSString *> *customPaths = [self.customPaths copy];
    for (NSString *path in customPaths) {
        NSString *filePath = [self cachePathForKey:key inPath:path];
        NSData *imageData = [NSData dataWithContentsOfFile:filePath];
        if (imageData) {
            return imageData;
        }
        
        // fallback because of https://github.com/rs/SDWebImage/pull/976 that added the extension to the disk file name
        // checking the key with and without the extension
        imageData = [NSData dataWithContentsOfFile:filePath.stringByDeletingPathExtension];
        if (imageData) {
            return imageData;
        }
    }
    
    return nil;
}
/* lzy注170725：
 从磁盘中取出给定key的UIImage并返回。
 1、从磁盘中取出给定key的data
 2、根据data创建image：得到图片格式；若是gif和webp需要单独处理，其他格式直接data转image；图片方向处理
 3、根据scale，处理图片
 4、根据cofig配置实例中是否 『解码图片』设置，处理图片解码
 */
- (nullable UIImage *)diskImageForKey:(nullable NSString *)key {
    NSData *data = [self diskImageDataBySearchingAllPathsForKey:key];
    if (data) {
        UIImage *image = [UIImage sd_imageWithData:data];
        image = [self scaledImageForKey:key image:image];
        if (self.config.shouldDecompressImages) {
            image = [UIImage decodedImageWithImage:image];
        }
        return image;
    }
    else {
        return nil;
    }
}

- (nullable UIImage *)scaledImageForKey:(nullable NSString *)key image:(nullable UIImage *)image {
    return SDScaledImageForKey(key, image);
}

/* lzy注170725：
 返回一个 异步查询缓存的『operation』，并在查询结束回调。
 如果operation被取消了，那么block不会被调用
 1、检查传入参数是否为空
 2、查询内存缓存
 3、查询磁盘缓存
 */
- (nullable NSOperation *)queryCacheOperationForKey:(nullable NSString *)key done:(nullable SDCacheQueryCompletedBlock)doneBlock {
    if (!key) {
        if (doneBlock) {
            doneBlock(nil, nil, SDImageCacheTypeNone);
        }
        return nil;
    }
    
    // First check the in-memory cache...
    UIImage *image = [self imageFromMemoryCacheForKey:key];
    if (image) {
        NSData *diskData = nil;
        if ([image isGIF]) {
            diskData = [self diskImageDataBySearchingAllPathsForKey:key];
        }
        if (doneBlock) {
            doneBlock(image, diskData, SDImageCacheTypeMemory);
        }
        return nil;
    }
    
    NSOperation *operation = [NSOperation new];
    dispatch_async(self.ioQueue, ^{
        if (operation.isCancelled) {
            // do not call the completion if cancelled
            return;
        }
        
        @autoreleasepool {
            NSData *diskData = [self diskImageDataBySearchingAllPathsForKey:key];
            UIImage *diskImage = [self diskImageForKey:key];
            if (diskImage && self.config.shouldCacheImagesInMemory) {
                NSUInteger cost = SDCacheCostForImage(diskImage);
                [self.memCache setObject:diskImage forKey:key cost:cost];
            }
            
            if (doneBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    doneBlock(diskImage, diskData, SDImageCacheTypeDisk);
                });
            }
        }
    });
    
    return operation;
}

#pragma mark - Remove Ops

- (void)removeImageForKey:(nullable NSString *)key withCompletion:(nullable SDWebImageNoParamsBlock)completion {
    [self removeImageForKey:key fromDisk:YES withCompletion:completion];
}
/* lzy注170725：
 根据fromDisk的值，决定是否从磁盘移除缓存
 根据是否在内存中缓存：self.config.shouldCacheImagesInMemory，决定是否做移除内存缓存的图片的操作
 */
- (void)removeImageForKey:(nullable NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(nullable SDWebImageNoParamsBlock)completion {
    if (key == nil) {
        return;
    }
    
    if (self.config.shouldCacheImagesInMemory) {
        [self.memCache removeObjectForKey:key];
    }
    
    if (fromDisk) {
        dispatch_async(self.ioQueue, ^{
            [_fileManager removeItemAtPath:[self defaultCachePathForKey:key] error:nil];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion();
                });
            }
        });
    } else if (completion){
        completion();
    }
    
}

# pragma mark - Mem Cache settings
/* lzy注170725：
 最大的内存缓存。内存开销是计算sd创建的图片的像素点数。
 p.s. NSCache的limit是不精确的：limits are imprecise/not strict
 */
- (void)setMaxMemoryCost:(NSUInteger)maxMemoryCost {
    self.memCache.totalCostLimit = maxMemoryCost;
}

- (NSUInteger)maxMemoryCost {
    return self.memCache.totalCostLimit;
}

/* lzy注170725：
 最大持有对象数。
 */
- (NSUInteger)maxMemoryCountLimit {
    return self.memCache.countLimit;
}

- (void)setMaxMemoryCountLimit:(NSUInteger)maxCountLimit {
    self.memCache.countLimit = maxCountLimit;
}

#pragma mark - Cache clean Ops

- (void)clearMemory {
    [self.memCache removeAllObjects];
}
/* lzy注170725：
 异步清理所有的磁盘缓存，在清理完毕之后，若有block，调用block。
 1、到特定的io队列
 2、移除指定路径的文件或者文件夹
 3、在原路径创建一个空文件夹
 */
- (void)clearDiskOnCompletion:(nullable SDWebImageNoParamsBlock)completion {
    dispatch_async(self.ioQueue, ^{
        [_fileManager removeItemAtPath:self.diskCachePath error:nil];
        [_fileManager createDirectoryAtPath:self.diskCachePath
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:NULL];
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

- (void)deleteOldFiles {
    [self deleteOldFilesWithCompletionBlock:nil];
}
/* lzy注170725：
 异步删除磁盘上所有过期的缓存图片。
 */
- (void)deleteOldFilesWithCompletionBlock:(nullable SDWebImageNoParamsBlock)completionBlock {
    dispatch_async(self.ioQueue, ^{
        
        
        /* lzy注170725：https://www.objccn.io/issue-9-2/
         简单来说就是我们不应该使用 NSString 来描述文件路径。对于 OS X 10.7 和 iOS 5，NSURL 更便于使用，而且更有效率，它还能缓存文件系统的属性。
         
         再者，NSURL 有八个方法来访问被称为 resource values 的东西。这些方法提供了一个稳定的接口，使我们可以用来获取和设置文件与目录的各种属性，例如本地化文件名（NSURLLocalizedNameKey）、文件大小（NSURLFileSizeKey），以及创建日期（NSURLCreationDateKey），等等。
         
         尤其是在遍历目录内容时，使用 -[NSFileManager enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:]，并传入一个关键词（keys）列表，然后用 -getResourceValue:forKey:error: 检索它们，能带来显著的性能提升。
         
         */
        // str转url
        NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
        // 准备文件属性键，用来预获取文件对应的这些key的值
        NSArray<NSString *> *resourceKeys = @[NSURLIsDirectoryKey, NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];
        
        // This enumerator prefetches useful properties for our cache files.预先获取缓存URL下所有缓存文件的 文件属性信息
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:resourceKeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];
        // 准备过期时间，用于比较文件修改时间，判断是否过期
        /* lzy注170725：
         假定100s
         expirationDate是，距离现在-100s的日期
         
         文件最后修改时间与 expirationDate 时间比较，如果expirationDate更晚，说明文件过了时间了，已经失效了
         |------------|
         eTime           现在
         文件修改日期必须时落在 区间里的，即要比 expirationDate晚。
         如果文件修改时间在expirationDate左侧，即比它早，那么它距离现在的总时间就会大于100s，超过了缓存时间
         */
        NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:-self.config.maxCacheAge];
        // 准备缓存文件属性管理字典，用来后面筛选文件进行删除
        NSMutableDictionary<NSURL *, NSDictionary<NSString *, id> *> *cacheFiles = [NSMutableDictionary dictionary];
        NSUInteger currentCacheSize = 0;
        
        // Enumerate all of the files in the cache directory.  This loop has two purposes:
        //
        //  1. Removing files that are older than the expiration date.
        //  2. Storing file attributes for the size-based cleanup pass.
        // 装『将要删除文件的URL』的空数组
        NSMutableArray<NSURL *> *urlsToDelete = [[NSMutableArray alloc] init];
        // 遍历
        for (NSURL *fileURL in fileEnumerator) {
            NSError *error;
            // 获取某个URL对应的文件的文件属性
            NSDictionary<NSString *, id> *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:&error];
            
            // Skip directories and errors.如果是文件夹或者 获取文件属性出错，直接跳过该文件
            if (error || !resourceValues || [resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }
            
            // Remove files that are older than the expiration date;文件最后修改的时间
            NSDate *modificationDate = resourceValues[NSURLContentModificationDateKey];
            
            // 过期文件URL保存起来
            if ([[modificationDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
                [urlsToDelete addObject:fileURL];
                continue;
            }
            
            // Store a reference to this file and account for its total size.
            // 计算缓存总大小
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += totalAllocatedSize.unsignedIntegerValue;
            // 存一份文件属性，用来后面筛选文件进行删除
            cacheFiles[fileURL] = resourceValues;
        }
        // 删除过期文件
        for (NSURL *fileURL in urlsToDelete) {
            [_fileManager removeItemAtURL:fileURL error:nil];
        }
        
        // If our remaining disk cache exceeds a configured maximum size, perform a second
        // size-based cleanup pass.  We delete the oldest files first.
        /* lzy注170725：
         删除掉过期文件之后，如果当前缓存总大小 还是大于 cofig中的最大缓存字节。
         */
        if (self.config.maxCacheSize > 0 && currentCacheSize > self.config.maxCacheSize) {
            // Target half of our maximum cache size for this cleanup pass.删到config设定的『最大缓存字节』的一半为止
            const NSUInteger desiredCacheSize = self.config.maxCacheSize / 2;
            
            // Sort the remaining cache files by their last modification time (oldest first).
            // 按最后修改时间排序，老文件排在前面
            NSArray<NSURL *> *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                                     usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                         return [obj1[NSURLContentModificationDateKey] compare:obj2[NSURLContentModificationDateKey]];
                                                                     }];
            
            // Delete files until we fall below our desired cache size.
            for (NSURL *fileURL in sortedFiles) {
                if ([_fileManager removeItemAtURL:fileURL error:nil]) {
                    // 遍历已排序数组，删一个，根据该文件属性减小缓存。直到见到需要的大小，跳出
                    NSDictionary<NSString *, id> *resourceValues = cacheFiles[fileURL];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= totalAllocatedSize.unsignedIntegerValue;
                    
                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock();
            });
        }
    });
}

#if SD_UIKIT
/* lzy注170725：
 接到通知会调用的方法
 */
- (void)backgroundDeleteOldFiles {
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    UIApplication *application = [UIApplication performSelector:@selector(sharedApplication)];
    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        // Clean up any unfinished task business by marking where you
        // stopped or ending the task outright.
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    
    // Start the long-running task and return immediately.
    [self deleteOldFilesWithCompletionBlock:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
}
#endif

#pragma mark - Cache Info

- (NSUInteger)getSize {
    __block NSUInteger size = 0;
    dispatch_sync(self.ioQueue, ^{
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtPath:self.diskCachePath];
        for (NSString *fileName in fileEnumerator) {
            NSString *filePath = [self.diskCachePath stringByAppendingPathComponent:fileName];
            NSDictionary<NSString *, id> *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
            size += [attrs fileSize];
        }
    });
    return size;
}

- (NSUInteger)getDiskCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.ioQueue, ^{
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtPath:self.diskCachePath];
        count = fileEnumerator.allObjects.count;
    });
    return count;
}

- (void)calculateSizeWithCompletionBlock:(nullable SDWebImageCalculateSizeBlock)completionBlock {
    NSURL *diskCacheURL = [NSURL fileURLWithPath:self.diskCachePath isDirectory:YES];
    
    dispatch_async(self.ioQueue, ^{
        NSUInteger fileCount = 0;
        NSUInteger totalSize = 0;
        
        NSDirectoryEnumerator *fileEnumerator = [_fileManager enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:@[NSFileSize]
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];
        
        for (NSURL *fileURL in fileEnumerator) {
            NSNumber *fileSize;
            [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:NULL];
            totalSize += fileSize.unsignedIntegerValue;
            fileCount += 1;
        }
        
        if (completionBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(fileCount, totalSize);
            });
        }
    });
}

@end

