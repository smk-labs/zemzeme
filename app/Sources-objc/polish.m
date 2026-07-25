// پاس ویرایش: پل به دیمن پایتون polish.py روی 127.0.0.1:17636.
// همان الگوی ZChromeRelayEngine: پینگ /alive، نشد spawn، بعد گرم کردن.
// سقف سخت هر تکه ۳۰۰ms + بیمه ۴۰۰ms؛ جفت قبل/بعد هر تکه در polish.log می‌نشیند.
#import "zemzeme.h"

static NSString *const kPolishBase = @"http://127.0.0.1:17636";
static const NSTimeInterval kPolishTimeout = 0.30;
static const NSTimeInterval kPolishFailsafe = 0.40;

@implementation ZPolish {
    NSURLSession *_http;    // تایم‌اوت کوتاه، مخصوص /polish روی مسیر داغ
    NSLock *_logLock;
}

+ (instancetype)shared {
    static ZPolish *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZPolish new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        cfg.timeoutIntervalForRequest = kPolishTimeout;
        cfg.timeoutIntervalForResource = kPolishTimeout;
        _http = [NSURLSession sessionWithConfiguration:cfg];
        _logLock = [NSLock new];
    }
    return self;
}

+ (BOOL)hasPersian:(NSString *)s {
    static NSCharacterSet *fa;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *m = [NSMutableCharacterSet new];
        [m addCharactersInRange:NSMakeRange(0x0600, 0x0100)];
        [m addCharactersInRange:NSMakeRange(0x0750, 0x0030)];
        [m addCharactersInRange:NSMakeRange(0xFB50, 0x02B0)];
        [m addCharactersInRange:NSMakeRange(0xFE70, 0x0090)];
        fa = m;
    });
    return [s rangeOfCharacterFromSet:fa].location != NSNotFound;
}

+ (BOOL)ping {
    __block BOOL ok = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 1;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    [[s dataTaskWithURL:[NSURL URLWithString:[kPolishBase stringByAppendingString:@"/alive"]]
      completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        ok = [resp isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)resp).statusCode == 200;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)));
    [s invalidateAndCancel];
    return ok;
}

- (void)spawnDaemon {
    // اسکریپت همراه اپ می‌آید، ولی venv و مدل‌ها (~۵۰۰ مگ) بیرون بسته می‌مانند
    NSString *py = [ZSupport() URLByAppendingPathComponent:@"py/.venv/bin/python3"].path;
    NSString *script = [ZRes() URLByAppendingPathComponent:@"polish.py"].path;
    if (![NSFileManager.defaultManager isExecutableFileAtPath:py]) {
        ZLog(@"polish: venv نیست (%@)؛ یک بار bash app/py/setup.sh را اجرا کن", py);
        return;
    }
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"ZEMZEME_MODELS"] = [ZSupport() URLByAppendingPathComponent:@"py/models"].path;
    NSTask *p = [NSTask new];
    p.executableURL = [NSURL fileURLWithPath:py];
    p.arguments = @[script];
    p.environment = env;
    p.currentDirectoryURL = ZSupport();
    p.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    p.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *e = nil;
    if ([p launchAndReturnError:&e]) {
        ZLog(@"polish: spawned polish.py pid=%d", p.processIdentifier);
    } else {
        ZLog(@"polish: spawn failed: %@", e.localizedDescription);
    }
}

// دوباره صدا زدنش بی‌ضرر است: نمونه دوم دیمن سر پورت اشغال، خودش خارج می‌شود
- (void)prepare {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (![ZPolish ping]) [self spawnDaemon];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:[kPolishBase stringByAppendingString:@"/polish"]]];
        req.HTTPMethod = @"POST";
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"text": @"گرم شو", @"lang": @"fa-IR"}
                                                       options:0 error:nil];
        req.timeoutInterval = 8;
        [[NSURLSession.sharedSession dataTaskWithRequest:req] resume];
    });
}

- (void)polish:(NSString *)raw completion:(void (^)(NSString *text))done {
    if (!ZSettings.shared.polishEnabled
        || [ZSettings.shared.lang hasPrefix:@"en"]
        || ![ZPolish hasPersian:raw]) {
        done(raw);
        return;
    }
    NSDate *t0 = NSDate.date;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[kPolishBase stringByAppendingString:@"/polish"]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"text": raw, @"lang": ZSettings.shared.lang}
                                                   options:0 error:nil];
    __block BOOL called = NO;    // هر دو مسیر روی نخ اصلی؛ قفل لازم نیست
    __weak typeof(self) ws = self;
    void (^finish)(NSString *, NSString *) = ^(NSString *text, NSString *outcome) {
        if (called) return;
        called = YES;
        [ws log:outcome ms:(int)([NSDate.date timeIntervalSinceDate:t0] * 1000) raw:raw out:text];
        done(text);
    };
    [[_http dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        NSString *out = nil;
        NSString *outcome = @"empty";
        if (!e && d.length) {
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if ([obj isKindOfClass:NSDictionary.class]) {
                NSString *t = [obj[@"text"] isKindOfClass:NSString.class] ? obj[@"text"] : nil;
                NSNumber *ready = [obj[@"ready"] isKindOfClass:NSNumber.class] ? obj[@"ready"] : @NO;
                if (t.length) {
                    out = t;
                    outcome = ready.boolValue ? @"ok" : @"warming";
                }
            }
        } else if (e) {
            outcome = e.code == NSURLErrorTimedOut ? @"timeout" : @"down";
        }
        dispatch_async(dispatch_get_main_queue(), ^{ finish(out ?: raw, outcome); });
    }] resume];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPolishFailsafe * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ finish(raw, @"failsafe"); });
}

// جفت قبل/بعد هر تکه، کنار app.log؛ فایل در .gitignore است
- (void)log:(NSString *)outcome ms:(int)ms raw:(NSString *)raw out:(NSString *)out {
    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss";
    });
    NSString *entry = [NSString stringWithFormat:@"%@ %@ %dms\n< %@\n> %@\n",
                       [df stringFromDate:NSDate.date], outcome, ms, raw, out];
    NSData *d = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [ZSupport() URLByAppendingPathComponent:@"polish.log"].path;
    [_logLock lock];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) {
        [NSFileManager.defaultManager createFileAtPath:path contents:d attributes:nil];
    } else {
        @try {
            [h seekToEndOfFile];
            [h writeData:d];
        } @catch (NSException *e) {}
        [h closeFile];
    }
    [_logLock unlock];
}

@end
