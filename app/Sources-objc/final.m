// پاس نهایی: صدای یک سشن، در دو تماس، تا یک متن تمیز.
//
// چرا این مسیر اصلا هست (اندازه‌گیری، نه سلیقه): متن خام همین اپ روی یک ویس ۳۶۷
// ثانیه‌ای فارسیِ واقعی فقط ۷۷٪ کلمه‌های گفته‌شده را داشت. یازده تکه‌ی محتوا در آن
// نبودند: یک جمله‌ی کامل، اسم یک شرکت، «اپ اسنپ»، «با کمک هوش مصنوعی». پاس متنی روی
// آن متن صفر از یازده را برگرداند، چون چیزی که در ورودی نیست برنمی‌گردد. مدلی که خودش
// صدا را بشنود ده تا یازده از یازده.
//
// و چرا دو تماس نه یکی: «صدا تا متن نهایی» در یک تماس با thinking_level=minimal متنِ
// درهم و دوباره‌نویسی‌شده داد (۲۰۷۲ کلمه به جای ۹۶۵). دو مرحله هم سالم‌تر بود هم
// سریع‌تر: ۲۱ ثانیه برای ۶ دقیقه صدا.
//
// قاعده‌های سختی که این فایل رعایت می‌کند:
//   · مسیر زنده هیچ‌وقت به اینجا وابسته نمی‌شود. ZPolish و بودجه‌ی ۳۰۰ میلی‌ثانیه‌اش
//     دست‌نخورده‌اند و هیچ LLM مولدی در پاس زنده نیست.
//   · هیچ چیز گم نمی‌شود: صدا، متن مو‌به‌مو و متن نهایی هر سه روی دیسک می‌مانند.
//   · دروازه‌ی کامل بودن جلوی خروجی رد شده را می‌گیرد و در تردید، خام می‌نشیند.
#import "zemzeme.h"
#import <Security/Security.h>

static NSString *const kGBase = @"https://generativelanguage.googleapis.com";
static NSString *const kKeychainService = @"zemzeme-gemini";

// مدل **پین** است، و اندازه‌گیری بیشتر از یک دلیل برایش داد. `gemini-flash-latest`
// نه‌فقط بی‌خبر جابه‌جا می‌شود، همین حالا هم `thinking_level: minimal` را رد می‌کند
// (فقط low و high). یعنی alias دنبال کردن، خروجی را نه فقط غیرقابل‌مقایسه، بلکه
// اصلا غیرقابل‌اجرا می‌کرد. `minimal` تا امروز مالِ همین یک مدل است.
//
// دو متغیر محیطی فقط برای عیب‌یابی و روزِ بدی که گوگل این مدل را بردارد. پیش‌فرض
// همان پین است و رابط هیچ راهی به این‌ها ندارد: تنظیم کاربر نیست، شیر اطمینان است.
static NSString *ZGModel(void) {
    NSString *m = NSProcessInfo.processInfo.environment[@"ZEMZEME_FINAL_MODEL"];
    return m.length ? m : @"gemini-3.6-flash";
}

// مقادیر مجاز: minimal، low، high. `none` و `off` خطای ۴۰۰ می‌دهند. minimal صفر توکن
// فکر می‌دهد و همان چیزی است که می‌خواهیم: توکن فکر مثل خروجی پول می‌گیرد و در
// اندازه‌گیری بیشترِ هزینه همان بود (۶۱۰۰ در برابر ۱۶۵۴).
static NSString *ZGThinking(void) {
    NSString *t = NSProcessInfo.processInfo.environment[@"ZEMZEME_FINAL_THINKING"];
    return t.length ? t : @"minimal";
}
// زیر این حجم، صدا درون‌خطی (base64) در همان تماس می‌رود. بالاتر، Files API.
// چرا نه همیشه Files API: روی یک فایل ۶٫۳ مگابایتی، آپلود و ACTIVE شدنش ۸۴ ثانیه
// گرفت، در حالی که همان بایت‌ها درون‌خطی ۶ ثانیه رفتند. معیار پذیرش «۱۵ ثانیه بعد از
// Esc» است، پس یادداشت‌های معمولی (تا ~۲۰ دقیقه گفتار) از راه درون‌خطی می‌روند.
#define kGInlineMaxBytes (15 * 1024 * 1024)
#define kGTimeout 300.0

// `key` در هدر نیست و نباید هم باشد (کلید از این فایل بیرون نمی‌رود)، ولی مسیر خط
// فرمان همین پایین لازمش دارد: آنجا پرسشِ بلوکه درست است.
@interface ZFinalPass (ZBlockingKey)
- (NSString *)key;
@end

@implementation ZFinalPassResult
@end

@implementation ZFinalPass {
    NSString *_key;
    BOOL _keyChecked;    // یک بار پرسیده شد؛ «نبود» هم جواب است و دوباره پرسیده نمی‌شود
    NSLock *_keyLock;    // فقط کلید. لغو و تسکِ در پرواز رفتند زیر `_pass`
    // ...و این یکی فقط دور خودِ *پرسش*. جدا از `_keyLock` و عمدا: آن قفل نباید در طول
    // یک پرسشِ چندثانیه‌ای گرفته بماند.
    NSLock *_fetchLock;
    NSLock *_logLock;
    // نوبتِ کل پاس، و مشترک با `ZEnhance`: انتقال یکی است، پس نگهبان هم باید یکی باشد.
    ZPassLock *_pass;
}

+ (instancetype)shared {
    static ZFinalPass *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [ZFinalPass new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _keyLock = [NSLock new];
        _fetchLock = [NSLock new];
        _logLock = [NSLock new];
        _pass = [ZPassLock new];
    }
    return self;
}

// ---------- کلید ----------
// سه جا، به همین ترتیب: متغیر محیطی (برای اجرای دستی و آزمایشگاه)، Keychain با
// Security framework، و در آخر خودِ ابزار `security`. سومی هست چون کلید با همان
// ابزار ساخته شده و ACL آیتم ممکن است فقط او را بشناسد؛ بی آن، فیچر روی دستگاهی که
// کلیدش را با خط فرمان گذاشته خاموش می‌ماند و کاربر نمی‌فهمد چرا.
// هیچ‌وقت لاگ نمی‌شود، در plist نمی‌رود، در ریپو نیست.

// چرا کدِ خطا لاگ می‌شود: نسخه‌ی اول ساکت بود و «کلید پیدا نشد» هیچ نمی‌گفت از کجا.
// یک بار ACL آیتم عوض شد و همین سکوت، عیب‌یابی را به حدس زدن تبدیل کرد. حالا هر شکست
// کد خودش را می‌گوید: ۲۵۳۰۰ یعنی نیست، ۲۵۳۰۸ یعنی اجازه نداد، ۵۱ یعنی ACL راهت نمی‌دهد.
static NSString *ZKeyFromKeychain(void) {
    NSDictionary *q = @{(id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: kKeychainService,
                        (id)kSecReturnData: @YES,
                        (id)kSecMatchLimit: (id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if (out) CFRelease(out);
    ZLog(@"final: Keychain کلید نداد (OSStatus %d)", (int)st);
    return nil;
}

static NSString *ZKeyFromSecurityTool(void) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/security"];
    t.arguments = @[@"find-generic-password", @"-s", kKeychainService, @"-w"];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) {
        ZLog(@"final: ابزار security اجرا نشد: %@", e.localizedDescription ?: @"?");
        return nil;
    }
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (t.terminationStatus != 0 || !d.length) {
        ZLog(@"final: ابزار security کلید نداد (exit %d)", t.terminationStatus);
        return nil;
    }
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// ممکن است Keychain پنجره‌ی اجازه باز کند و بلوکه شود، پس هیچ‌وقت روی نخ اصلی نه.
//
// و **تک‌پرواز**: در هر لحظه فقط یک پرسش در جریان است. باگ واقعی و دیدنی بود، چون
// خروجی‌اش پنجره‌ی اجازه‌ی مک است نه یک خط لاگ. `_keyChecked` فقط *بعد* از تمام شدنِ
// پرسش ست می‌شود و قفل در طول خودِ پرسش باز بود، پس دو فراخوانِ نزدیک به هم هر دو
// «هنوز پرسیده نشده» می‌دیدند و هر دو می‌پرسیدند: دو دیالوگ روی هم برای یک کلید.
// و فراخوان کم نیست: `hasKey` روی نخ اصلی هر بار که جواب نداشته باشد یک `prefetchKey`
// می‌اندازد، و منو و کارت راهنما و شروع سشن و دو در تازه‌ی بهبود پرامپت همه صدایش
// می‌زنند. باز کردن منو دو بار پشت هم کافی بود.
- (NSString *)key {
    [_keyLock lock];
    NSString *k = _key;
    BOOL checked = _keyChecked;
    [_keyLock unlock];
    if (k.length || checked) return k.length ? k : nil;
    [_fetchLock lock];
    // نفر دوم پشت در ایستاده بود؛ حالا که نوبتش شده جواب از قبل آماده است
    [_keyLock lock];
    k = _key;
    checked = _keyChecked;
    [_keyLock unlock];
    if (k.length || checked) {
        [_fetchLock unlock];
        return k.length ? k : nil;
    }
    k = NSProcessInfo.processInfo.environment[@"GEMINI_API_KEY"];
    k = [k stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!k.length) k = ZKeyFromKeychain();
    if (!k.length) k = ZKeyFromSecurityTool();
    [_keyLock lock];
    _keyChecked = YES;
    if (k.length) _key = [k copy];
    [_keyLock unlock];
    [_fetchLock unlock];
    return k.length ? k : nil;
}

- (void)prefetchKey {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self key]; });
}

// جوابِ کش‌شده، و روی نخ اصلی **هیچ‌وقت** پرسشِ تازه. سه فراخوان از نخ اصلی می‌آیند
// (منو، کارت راهنما، شروع سشن) و پرسیدنِ Keychain می‌تواند پنجره‌ی اجازه باز کند و
// همان‌جا یخ بزند. اگر هنوز پرسیده نشده، پرسش را در پس‌زمینه راه می‌اندازد و جواب
// این دفعه «نه» است؛ دفعه‌ی بعد که منو باز شود درست می‌گوید.
+ (BOOL)hasKey {
    ZFinalPass *s = ZFinalPass.shared;
    if (!NSThread.isMainThread) return [s key].length > 0;
    [s->_keyLock lock];
    BOOL have = s->_key.length > 0, checked = s->_keyChecked;
    [s->_keyLock unlock];
    if (!have && !checked) [s prefetchKey];
    return have;
}

+ (BOOL)keyKnownMissing {
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    BOOL missing = s->_keyChecked && s->_key.length == 0;
    [s->_keyLock unlock];
    return missing;
}

+ (NSString *)missingKeyHint {
    // مسیر اصلی حالا داخل خود اپ است: منوی زمزمه، «کلید Gemini…» (کلیدسنج پایین همین
    // فایل). ترمینال فقط برای کسی می‌ماند که با دست می‌خواهد Keychain را دستکاری کند؛
    // `-T` آنجا هنوز لازم است چون سازنده‌ی آیتم آنجا `security` است نه خودِ اپ.
    return @"کلید جمینای پیدا نشد. از منوی زمزمه «کلید Gemini…» را بزن، یا در ترمینال: "
            "security add-generic-password -a \"$USER\" -s zemzeme-gemini "
            "-T /Applications/Zemzeme.app -T /usr/bin/security -w";
}

// ---------- نوشتن (از منو، «کلید Gemini…») ----------
// همان سرویس، همان کلاس، پس همان آیتمی که ZKeyFromKeychain بالا می‌خواند. تفاوتش با
// راه ترمینالی: سازنده‌ی این آیتم خودِ همین پروسه است، و مک از سازنده‌ی یک آیتم برای
// خواندنِ بعدیِ همان آیتم هیچ‌وقت اجازه نمی‌پرسد. یعنی `-T` اینجا لازم نیست؛ آن فقط
// برای وقتی بود که سازنده یک ابزار دیگر (`security`) باشد.
+ (BOOL)saveKey:(NSString *)key error:(NSError **)err {
    NSString *k = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!k.length) {
        if (err) *err = [NSError errorWithDomain:@"Zemzeme" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"کلید خالی است"}];
        return NO;
    }
    NSData *d = [k dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *q = @{(id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: kKeychainService};
    // اول به‌روزرسانی: اگر آیتمِ قدیمی (حتی ساخته‌شده با `security -T`) موجود باشد،
    // همان جایگزین می‌شود، نه یک آیتم دوم با ACL دیگر.
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)@{(id)kSecValueData: d});
    if (st == errSecItemNotFound) {
        NSMutableDictionary *add = [q mutableCopy];
        add[(id)kSecAttrAccount] = NSUserName();
        add[(id)kSecValueData] = d;
        st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (st != errSecSuccess) {
        ZLog(@"final: نوشتنِ کلید در Keychain رد شد (OSStatus %d)", (int)st);
        if (err) *err = [NSError errorWithDomain:@"Zemzeme" code:st userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Keychain کلید را نپذیرفت (کد %d)", (int)st]}];
        return NO;
    }
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    s->_key = [k copy];
    s->_keyChecked = YES;
    [s->_keyLock unlock];
    return YES;
}

+ (void)clearKey {
    NSDictionary *q = @{(id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: kKeychainService};
    SecItemDelete((__bridge CFDictionaryRef)q);
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    s->_key = nil;
    s->_keyChecked = NO;
    [s->_keyLock unlock];
}

// ---------- پرامپت‌ها ----------
// فایل‌اند نه رشته‌ی هاردکد، و کنار بسته می‌نشینند: هر دویشان روی متن واقعی تیون
// شده‌اند و باید بی‌بیلد قابل ویرایش باشند. نبودشان یعنی فیچر خاموش، نه یک پرامپت
// نصفه‌نیمه‌ی درون کد.
- (NSString *)prompt:(NSString *)name {
    NSURL *u = [[ZRes() URLByAppendingPathComponent:@"prompts"]
                URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"md"]];
    NSString *s = [NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:nil];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!s.length) ZLog(@"final: پرامپت پیدا نشد: %@", u.path);
    return s;
}

// ---------- HTTP ----------
// قطعِ وسط کار یک بار کل اجرا را کشت، پس هر تماس تلاش دوباره دارد.
//
// و ۴۲۹ داستان خودش را دارد، که با اندازه‌گیری معلوم شد: سهم مجانی این مدل **۲۰
// درخواست در روز** است، نه در دقیقه، ولی پیام خطا «۵۴ ثانیه دیگر تلاش کن» می‌گوید.
// نسخه‌ی اول دو بار همان ۵۴ ثانیه را صبر کرد و ۱۵۵ ثانیه سوخت تا باز همان ۴۲۹ بیاید.
// پس ۴۲۹ فقط **یک** تلاش دوباره دارد و آن هم با سقف ۶۰ ثانیه: اگر سقف دقیقه‌ای باشد
// همان یک صبر جوابش است، و اگر روزانه باشد کاربر بیست ثانیه بعد جوابِ روشن می‌گیرد
// نه سه دقیقه چرخنده.
// متد است نه تابع، و فقط به یک دلیل: تسکِ در پرواز باید جایی ثبت شود که `cancel`
// بتواند بکشدش. بدنه‌ی درخواست چند مگابایت صداست و کسی که «کنسل» می‌زند منتظر تمام
// شدنِ آپلود نیست.
- (NSData *)http:(NSMutableURLRequest *)req status:(NSInteger *)status headers:(NSDictionary **)headers {
    __block NSData *body = nil;
    __block NSInteger code = 0;
    __block NSDictionary *hd = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = kGTimeout;
    cfg.timeoutIntervalForResource = kGTimeout;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    NSURLSessionDataTask *task = [s dataTaskWithRequest:req
                                     completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        body = d;
        if ([r isKindOfClass:NSHTTPURLResponse.class]) {
            code = ((NSHTTPURLResponse *)r).statusCode;
            hd = ((NSHTTPURLResponse *)r).allHeaderFields;
        }
        if (e && !code) code = -1;
        dispatch_semaphore_signal(sem);
    }];
    if (![_pass armTask:task session:s]) {
        // بین شروع کار و اینجا لغو رسیده (یا نوبتی در کار نیست)؛ حتی درخواست را هم
        // نمی‌فرستیم
        if (status) *status = -2;
        return nil;
    }
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kGTimeout + 30) * NSEC_PER_SEC)));
    [_pass disarm];
    [s finishTasksAndInvalidate];
    if (status) *status = code;
    if (headers) *headers = hd;
    return body;
}

- (void)cancel { [self cancelOwner:ZPassOwnerFinal]; }

// به نامِ صاحب، نه «هرچه در پرواز است». قبلا یک بولینِ مشترک بود و همین باعث می‌شد Esc
// در سشن، کارِ پنل فایل را هم بکشد؛ و بدتر، `resetCancel` نفرِ بعدی لغوِ همین لحظه‌ی
// کاربر را پاک کند. حالا اگر کاری که در جریان است مالِ این صاحب نباشد، هیچ اتفاقی
// نمی‌افتد.
- (void)cancelOwner:(NSString *)owner {
    if ([_pass cancelOwner:owner]) ZLog(@"final: %@ لغو شد", owner);
}

// نال یعنی مشغول. `resetCancel` عمدا رفت: لغو حالا روی نسلِ همان نوبت می‌نشیند، پس
// لغوِ کهنه اصلا به کارِ بعدی نمی‌رسد و چیزی برای صفر کردن نمانده.
- (ZPassLease *)claimPass:(NSString *)owner busy:(NSString **)busy {
    return [_pass claim:owner busy:busy];
}

// ---------- انتقالِ قرضی ----------
// یک تماسِ فقط‌متنی روی همین انتقال. مصرف‌کننده‌اش `ZEnhance` است و صدا لازم ندارد،
// پس عمدا هیچ چیزِ صوتی در امضا نیست. کلید هم از همین‌جا خوانده می‌شود: بیرون رفتنِ
// کلید از این فایل، همان قاعده‌ای است که نمی‌شکند.
- (NSString *)askText:(NSString *)system parts:(NSArray<NSString *> *)texts
                label:(NSString *)label thinking:(NSString *)thinking
                usage:(NSMutableDictionary *)usage error:(NSString **)err {
    NSString *key = [self key];
    if (!key) {
        if (err) *err = ZFinalPass.missingKeyHint;
        return nil;
    }
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSString *t in texts) [parts addObject:@{@"type": @"text", @"text": t}];
    return [self ask:system parts:parts label:label key:key thinking:thinking
               usage:usage error:err];
}

- (NSString *)promptNamed:(NSString *)name { return [self prompt:name]; }

// «Please retry in 57.4s» را خود سرور در پیام ۴۲۹ می‌گوید. حدس زدن به‌جایش یعنی یا
// بی‌دلیل معطل شدن، یا دوباره خوردن به همان سقف.
static NSTimeInterval ZRetryAfter(NSData *body, NSTimeInterval fallback) {
    NSString *s = [[NSString alloc] initWithData:body ?: [NSData data] encoding:NSUTF8StringEncoding];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"retry in ([0-9.]+)s|\"retryDelay\"\\s*:\\s*\"([0-9.]+)s\"" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s ?: @"" options:0 range:NSMakeRange(0, s.length)];
    for (NSUInteger g = 1; m && g <= 2; g++) {
        NSRange r = [m rangeAtIndex:g];
        if (r.location != NSNotFound) return MIN(90.0, [[s substringWithRange:r] doubleValue] + 1.0);
    }
    return fallback;
}

- (NSData *)send:(NSMutableURLRequest *)req label:(NSString *)label
          status:(NSInteger *)outStatus headers:(NSDictionary **)outHeaders {
    NSData *body = nil;
    NSInteger st = 0;
    int rateTries = 0;
    for (int try = 0; try < 3; try++) {
        body = [self http:req status:&st headers:outHeaders];
        if (st == 200) break;
        if (try == 2) break;
        NSTimeInterval wait = 2.0 * (try + 1);
        if (st == 429 || st == 503) {
            if (++rateTries > 1) break;    // سقفِ روزانه با صبر کردن باز نمی‌شود
            // سقف ۲۰ ثانیه، و نه عددی که سرور می‌گوید (معمولا ~۵۸): پشتِ این مسیر
            // فال‌بکِ تشخیص گفتار نشسته، و بیست ثانیه چرخنده بعد رفتن به فال‌بک،
            // بهتر از یک دقیقه چرخنده است. اندازه‌گیری: تلاش دوم هم ۴۲۹ بود.
            wait = MIN(20.0, ZRetryAfter(body, wait));
            ZLog(@"final: %@ جواب %ld داد، %.0f ثانیه صبر و یک تلاش دوباره", label, (long)st, wait);
        } else if (st < 0) {
            ZLog(@"final: %@ شبکه قطع شد، تلاش %d از ۳", label, try + 2);
        } else {
            break;    // ۴۰۰ و ۴۰۳ با تلاش دوباره درست نمی‌شوند
        }
        [NSThread sleepForTimeInterval:wait];
    }
    if (outStatus) *outStatus = st;
    return body;
}

// پیام برای خودِ کاربر، نه کد HTTP. «HTTP 429» به کسی نمی‌گوید چه کند؛ «سهم مجانی
// کلید تمام شد» می‌گوید.
static NSString *ZHumanError(NSString *label, NSInteger st, NSData *raw) {
    NSString *body = [[NSString alloc] initWithData:raw ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
    if (st == 429) {
        return [body rangeOfString:@"free_tier"].location != NSNotFound
            ? @"سهم مجانی کلید جمینای تمام شد (۲۰ درخواست در روز، هر پاس ۲ تا). "
               "فردا، یا کلید با بیلینگ."
            : @"سرور جمینای فعلا جواب نمی‌دهد (سقف درخواست). چند دقیقه بعد دوباره بزن.";
    }
    if (st == 403 || st == 401) return @"کلید جمینای پذیرفته نشد؛ یک کلید تازه در Keychain بگذار.";
    if (st == 400) return [NSString stringWithFormat:@"درخواست %@ را سرور نپسندید (۴۰۰)؛ "
                           @"پاسخ خام در پوشه‌ی final ذخیره شد", label];
    if (st < 0) return @"شبکه در دسترس نیست؛ پاس نهایی اجرا نشد";
    return [NSString stringWithFormat:@"%@ شکست خورد (HTTP %ld)", label, (long)st];
}

// ---------- بیرون کشیدن متن از پاسخ ----------
// شکل دقیق پاسخ مستند نیست (کلیدهای سطح بالا: id, status, usage, steps, model…) و متن
// جایی داخل `steps` است. پس مثل آزمایشگاه می‌گردیم: هر کلید `text` را جمع کن و هر
// تکه‌ی فکر را رد کن. دو نشانه‌ی فکر دیده شده و هر دو چک می‌شوند: `thought: true` و
// `type: "thought"`.
static void ZWalkText(id node, NSMutableArray<NSString *> *acc) {
    if ([node isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = node;
        if ([d[@"thought"] respondsToSelector:@selector(boolValue)] && [d[@"thought"] boolValue]) return;
        if ([d[@"type"] isEqual:@"thought"]) return;
        for (NSString *k in d) {
            id v = d[k];
            if (([k isEqualToString:@"text"] || [k isEqualToString:@"output_text"])
                && [v isKindOfClass:NSString.class]) {
                [acc addObject:v];
            } else {
                ZWalkText(v, acc);
            }
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id v in node) ZWalkText(v, acc);
    }
}

// مقدمه‌ی خودساخته: با minimal، مرحله‌ی رونویسی یک بار از خودش جمله اضافه کرد («متن
// پیاده‌شده به شرح زیر است»). پرامپت سخت‌تر شد، ولی یک لایه‌ی ارزان هم اینجا هست.
//
// عمدا **تنگ** است، و نسخه‌ی اولش نبود: فهرست قبلی «در ادامه» و «متن زیر» را هم داشت،
// و یادداشتی که واقعا با «در ادامه‌ی جلسه‌ی دیروز…» شروع می‌شد سطر اولش را از دست
// می‌داد. یک لایه‌ی احتیاطی که خودش محتوا بخورد بدتر از نبودنش است. پس شرط‌ها جمع
// می‌شوند: خط اول کوتاه باشد، پشتش خط خالی بیاید (یعنی برچسب است نه جمله‌ی متن)، و
// یا به دونقطه تمام شود یا یکی از همان چند جمله‌ی خودمعرفِ شناخته‌شده باشد.
static NSString *ZDropPreamble(NSString *t) {
    NSRange nl = [t rangeOfString:@"\n"];
    if (nl.location == NSNotFound || nl.location > 70) return t;
    NSString *first = [[t substringToIndex:nl.location]
                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *rest = [[t substringFromIndex:nl.location]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!rest.length) return t;    // همه‌ی متن همان یک خط است؛ انداختنش یعنی خالی شدن
    static NSArray *tells;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tells = @[@"به شرح زیر", @"به این شرح", @"متن پیاده‌شده", @"متن پیاده شده",
                  @"رونویسی مو‌به‌مو", @"here is the transcript", @"transcript:"];
    });
    BOOL label = [first hasSuffix:@":"] && first.length <= 40;
    for (NSString *tell in tells) {
        if ([first rangeOfString:tell options:NSCaseInsensitiveSearch].location != NSNotFound) {
            label = YES;
            break;
        }
    }
    if (!label) return t;
    ZLog(@"final: مقدمه‌ی خودساخته انداخته شد: %@", first);
    return rest;
}

// ---------- یک تماس ----------
// `thinking` پارامتر است نه پیش‌فرض، چون دو مصرف‌کننده دو جواب می‌خواهند: پاس نهایی
// `minimal` (توکن فکر مثل خروجی پول می‌گیرد و کاربر منتظر متنِ خودش است) و پاس بهبود
// پرامپت `low` (کاربر خودش دکمه را زده و منتظر یک کارِ فکری است).
- (NSString *)ask:(NSString *)system parts:(NSArray *)parts label:(NSString *)label
              key:(NSString *)key thinking:(NSString *)thinking
            usage:(NSMutableDictionary *)usage error:(NSString **)err {
    NSMutableDictionary *body = [@{@"model": ZGModel(),
                                   @"system_instruction": system,
                                   @"input": parts,
                                   @"generation_config": @{@"thinking_level": thinking}} mutableCopy];
    NSError *jerr = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jerr];
    if (!json) {
        if (err) *err = @"درخواست ساخته نشد";
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[kGBase stringByAppendingString:@"/v1beta/interactions"]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = json;
    [req setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDate *t0 = NSDate.date;
    NSInteger st = 0;
    NSData *raw = [self send:req label:label status:&st headers:nil];
    NSTimeInterval dt = [NSDate.date timeIntervalSinceDate:t0];
    if (st != 200) {
        // پاسخ خام هر تماس ناموفق روی دیسک: تنها راه فهمیدن اینکه اندپوینتِ مستندنشده
        // چه چیزی را نپسندید. کلید در بدنه نیست، پس نوشتنش بی‌خطر است.
        [self writeRaw:raw name:[NSString stringWithFormat:@"%@-http%ld", label, (long)st]];
        NSString *msg = [[NSString alloc] initWithData:
            [raw subdataWithRange:NSMakeRange(0, MIN((NSUInteger)600, raw.length))]
                                             encoding:NSUTF8StringEncoding];
        if (err) *err = ZHumanError(label, st, raw);
        ZLog(@"final: %@ HTTP %ld در %.1f ثانیه — %@", label, (long)st, dt, msg ?: @"?");
        return nil;
    }
    id doc = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
    NSMutableArray *acc = [NSMutableArray array];
    ZWalkText(doc, acc);
    NSString *text = [[acc componentsJoinedByString:@""]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDictionary *u = [doc isKindOfClass:NSDictionary.class] ? ((NSDictionary *)doc)[@"usage"] : nil;
    if ([u isKindOfClass:NSDictionary.class]) {
        NSInteger in = [u[@"total_input_tokens"] integerValue];
        NSInteger out = [u[@"total_output_tokens"] integerValue] + [u[@"total_thought_tokens"] integerValue];
        usage[@"in"] = @([usage[@"in"] integerValue] + in);
        usage[@"out"] = @([usage[@"out"] integerValue] + out);
    }
    ZLog(@"final: %@ در %.1f ثانیه، %lu نویسه", label, dt, (unsigned long)text.length);
    if (!text.length) {
        [self writeRaw:raw name:[NSString stringWithFormat:@"%@-empty", label]];
        if (err) *err = [label stringByAppendingString:@" متنی برنگرداند"];
        return nil;
    }
    return ZDropPreamble(text);
}

// ---------- صدا ----------
// تکه‌ی صدا برای تماس: درون‌خطی، وگرنه از Files API.
- (NSDictionary *)audioPart:(NSURL *)audio key:(NSString *)key
                   progress:(void (^)(NSString *))progress error:(NSString **)err {
    NSData *data = [NSData dataWithContentsOfURL:audio options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length) {
        if (err) *err = @"فایل صدا خوانده نشد";
        return nil;
    }
    NSString *mime = [audio.pathExtension.lowercaseString isEqualToString:@"wav"]
        ? @"audio/wav" : @"audio/flac";
    if (data.length <= kGInlineMaxBytes) {
        progress([NSString stringWithFormat:@"فرستادن صدا (%@ مگابایت)…",
                  ZFaDigits([NSString stringWithFormat:@"%.1f", data.length / 1048576.0])]);
        return @{@"type": @"audio", @"mime_type": mime,
                 @"data": [data base64EncodedStringWithOptions:0]};
    }
    progress(@"آپلود صدای بلند…");
    NSString *uri = [self upload:data name:audio.lastPathComponent mime:mime key:key error:err];
    if (!uri) return nil;
    return @{@"type": @"audio", @"mime_type": mime, @"uri": uri};
}

// Files API، سه مرحله‌ی resumable. فایل تا ۴۸ ساعت زنده می‌ماند و سقف صدا ۹٫۵ ساعت
// است، پس در این مسیر هیچ چرخش و جوش درزی لازم نیست: یک فایل، یک تماس.
- (NSString *)upload:(NSData *)data name:(NSString *)name mime:(NSString *)mime
                 key:(NSString *)key error:(NSString **)err {
    NSMutableURLRequest *start = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[kGBase stringByAppendingString:@"/upload/v1beta/files"]]];
    start.HTTPMethod = @"POST";
    start.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"file": @{@"display_name": name}}
                                                    options:0 error:nil];
    [start setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    [start setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [start setValue:@"resumable" forHTTPHeaderField:@"X-Goog-Upload-Protocol"];
    [start setValue:@"start" forHTTPHeaderField:@"X-Goog-Upload-Command"];
    [start setValue:@(data.length).stringValue forHTTPHeaderField:@"X-Goog-Upload-Header-Content-Length"];
    [start setValue:mime forHTTPHeaderField:@"X-Goog-Upload-Header-Content-Type"];
    NSInteger st = 0;
    NSDictionary *hd = nil;
    [self send:start label:@"upload-start" status:&st headers:&hd];
    NSString *url = nil;
    for (NSString *k in hd) {
        if ([k caseInsensitiveCompare:@"x-goog-upload-url"] == NSOrderedSame) url = hd[k];
    }
    if (st != 200 || !url.length) {
        if (err) *err = @"شروع آپلود صدا نشد";
        return nil;
    }
    NSMutableURLRequest *put = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    put.HTTPMethod = @"POST";
    put.HTTPBody = data;
    [put setValue:@"0" forHTTPHeaderField:@"X-Goog-Upload-Offset"];
    [put setValue:@"upload, finalize" forHTTPHeaderField:@"X-Goog-Upload-Command"];
    NSData *body = [self send:put label:@"upload" status:&st headers:nil];
    if (st != 200) {
        if (err) *err = @"آپلود صدا نشد";
        return nil;
    }
    NSDictionary *doc = [NSJSONSerialization JSONObjectWithData:body ?: [NSData data] options:0 error:nil];
    NSDictionary *file = [doc isKindOfClass:NSDictionary.class] ? doc[@"file"] : nil;
    NSString *uri = [file[@"uri"] isKindOfClass:NSString.class] ? file[@"uri"] : nil;
    NSString *fname = [file[@"name"] isKindOfClass:NSString.class] ? file[@"name"] : nil;
    if (!uri.length) {
        if (err) *err = @"آدرس فایل صدا برنگشت";
        return nil;
    }
    // صدا لحظه‌ای در حال پردازش می‌ماند و تماس روی فایلِ غیرِ ACTIVE خطا می‌دهد.
    // روی فایل ۶ مگابایتی همین انتظار بیشترِ آن ۸۴ ثانیه بود، و دقیقا دلیلی است که
    // مسیر درون‌خطی پیش‌فرض است.
    for (int i = 0; i < 90 && fname.length; i++) {
        NSString *state = [file[@"state"] isKindOfClass:NSString.class] ? file[@"state"] : nil;
        if (!state || [state isEqualToString:@"ACTIVE"]) break;
        if ([state isEqualToString:@"FAILED"]) {
            if (err) *err = @"سرور صدا را نپذیرفت";
            return nil;
        }
        [NSThread sleepForTimeInterval:2];
        NSMutableURLRequest *q = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:[NSString stringWithFormat:@"%@/v1beta/%@", kGBase, fname]]];
        [q setValue:key forHTTPHeaderField:@"x-goog-api-key"];
        NSData *qb = [self http:q status:&st headers:nil];
        file = st == 200 ? [NSJSONSerialization JSONObjectWithData:qb options:0 error:nil] : nil;
        if (!file) break;
    }
    return uri;
}

// ---------- کل پاس ----------

- (void)runOnAudio:(NSURL *)audio lang:(NSString *)lang
          progress:(void (^)(NSString *msg))progress
              done:(void (^)(ZFinalPassResult *r))done {
    void (^say)(NSString *) = ^(NSString *m) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (progress) progress(m); });
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // استخر عمدی است: نوبت با `dealloc` آزاد می‌شود و باید **قبل از** `done` رفته
        // باشد. وگرنه کاربری که همان لحظه دکمه‌ی بعدی را می‌زند می‌توانست به نوبتی
        // بخورد که هنوز در استخرِ نخِ پس‌زمینه منتظرِ تخلیه است.
        ZFinalPassResult *r;
        @autoreleasepool { r = [self work:audio lang:lang say:say]; }
        dispatch_async(dispatch_get_main_queue(), ^{ done(r); });
    });
}

- (ZFinalPassResult *)work:(NSURL *)audio lang:(NSString *)lang say:(void (^)(NSString *))say {
    ZFinalPassResult *r = [ZFinalPassResult new];
    NSDate *t0 = NSDate.date;
    // نوبت، **اولین** کار و روی کل پاس. اول به دو دلیل: پاس نهایی دو تا سه تماس دارد و
    // نوبتِ تماس‌به‌تماس بین «مو‌به‌مو» و «تمیزکاری» به کارِ دیگری راه می‌داد؛ و از این
    // خط به بعد هر `return` خودش نوبت را پس می‌دهد، چون آزادسازی کارِ `dealloc` است نه
    // کارِ ما. نُه نقطه‌ی بازگشتِ این متد هیچ‌کدام چیزی برای یادش ماندن ندارند.
    NSString *busy = nil;
    ZPassLease *lease = [self claimPass:ZPassOwnerFinal busy:&busy];
    if (!lease) {
        ZLog(@"final: نوبت آزاد نبود: %@", busy);
        r.error = busy;
        return r;
    }
    // لغو بین هر دو مرحله چک می‌شود، نه فقط اولش: تماس اول ده ثانیه طول می‌کشد و
    // کاربری که در آن فاصله کنسل زده نباید تماس دوم را هم بپردازد.
    #define ZBailIfCancelled() do { \
        if (lease.cancelled) { r.cancelled = YES; return r; } \
    } while (0)
    NSString *key = [self key];
    if (!key) {
        r.error = ZFinalPass.missingKeyHint;
        return r;
    }
    NSString *pVerbatim = [self prompt:@"verbatim"];
    NSString *pPolish = [self prompt:@"polish"];
    if (!pVerbatim.length || !pPolish.length) {
        r.error = @"پرامپت‌های پاس نهایی در بسته‌ی اپ نیستند";
        return r;
    }
    NSMutableDictionary *usage = [NSMutableDictionary dictionary];
    NSString *err = nil;
    ZBailIfCancelled();

    // ---------- تماس ۱: صدا ← رونویسی مو‌به‌مو ----------
    NSDictionary *part = [self audioPart:audio key:key progress:say error:&err];
    if (!part) {
        r.error = err ?: @"صدا فرستاده نشد";
        return r;
    }
    say(@"رونویسی مو‌به‌مو…");
    ZBailIfCancelled();
    NSString *verbatim = [self ask:pVerbatim
                             parts:@[@{@"type": @"text", @"text": @"فقط صدا."}, part]
                             label:@"verbatim" key:key thinking:ZGThinking()
                             usage:usage error:&err];
    if (!verbatim.length) {
        r.error = err ?: @"رونویسی نشد";
        return r;
    }
    r.verbatim = verbatim;
    r.text = verbatim;    // از این لحظه، بدترین حالت هم متن دارد

    // ---------- تماس ۲: متن مو‌به‌مو ← متن نهایی ----------
    say(@"تمیزکاری متن…");
    ZBailIfCancelled();
    NSString *shape = ZSettings.shared.plainNotes
        ? @"\n\nساختار: پاراگراف. هیچ بولت و فهرستی نزن، حتی اگر گفتار شمرده بود."
        : @"";
    NSArray *parts2 = @[@{@"type": @"text",
                          @"text": [@"فقط متن رونویسی مو‌به‌موی همین صدا را داری. "
                                     "این متن کامل است ولی خام و پر از فیلر؛ صدا را نداری."
                                    stringByAppendingString:shape]},
                        @{@"type": @"text", @"text": [@"متن رونویسی مو‌به‌مو:\n\n"
                                                      stringByAppendingString:verbatim]}];
    NSString *polished = [self ask:pPolish parts:parts2 label:@"polish" key:key
                          thinking:ZGThinking() usage:usage error:&err];

    // ---------- دروازه‌ی کامل بودن ----------
    if (polished.length) {
        ZCoverage *c = [ZCoverage ofDraft:verbatim output:polished];
        r.coverage = c;
        if (!c.passed) {
            ZLog(@"final: دروازه بست — %@", c.summary);
            say(@"بررسی کامل بودن: یک بار دیگر…");
            // تلاش دوم با پرامپت سخت‌گیرتر، و صریحا با فهرست همان چیزی که افتاد.
            // یک پرامپتِ کلیِ «سخت‌گیرتر» را اندازه گرفتیم و کم اثر بود؛ نام بردنِ خودِ
            // واژه‌ها کارِ مدل را از «حدس بزن چه می‌خواهی» به «این‌ها را برگردان» می‌برد.
            NSString *strict = [self strictAddendum:c];
            NSArray *parts3 = [parts2 arrayByAddingObject:@{@"type": @"text", @"text": strict}];
            NSString *again = [self ask:pPolish parts:parts3 label:@"polish-strict" key:key
                               thinking:ZGThinking() usage:usage error:&err];
            ZCoverage *c2 = again.length ? [ZCoverage ofDraft:verbatim output:again] : nil;
            if (c2 && c2.passed) {
                polished = again;
                r.coverage = c2;
            } else {
                // در تردید، خام. قاعده‌ی خود ریپو، و اینجا «خام» یعنی متن مو‌به‌مو که
                // خودش از متن خام گوگل کامل‌تر است.
                ZLog(@"final: تلاش دوم هم رد شد (%@)؛ متن مو‌به‌مو می‌نشیند",
                     c2 ? c2.summary : @"متنی نیامد");
                if (c2) r.coverage = c2;
                r.gated = YES;
                polished = nil;
            }
        }
    }

    NSString *out = polished.length ? polished : verbatim;

    // ---------- پاس مکانیکی ----------
    // بعد از مدل و نه قبلش: LLM ها با نیم‌فاصله بی‌دقت‌اند و همین یک تکه‌ی قاعده‌ای
    // ارزشش را دارد. املا و نقطه‌گذاریِ مدلِ کوچک عمدا اجرا نمی‌شوند؛ آن دو کورند و
    // اینجا مدل بزرگ هر دو را بهتر انجام داده. روی سشن انگلیسی هم کلا رد می‌شود.
    if (![lang hasPrefix:@"en"]) {
        say(@"نیم‌فاصله و ارقام…");
        NSString *mech = [ZPolish.shared mechanicalSync:out lang:lang];
        // دروازه یک بار دیگر، این بار روی خودِ پاس مکانیکی: قاعده‌ای است و نباید چیزی
        // بخورد، ولی «نباید» دلیل نیست که نسنجیم.
        if (mech.length) {
            ZCoverage *cm = [ZCoverage ofDraft:out output:mech];
            if (cm.lostNumbers.count || cm.lostLatin.count) {
                ZLog(@"final: پاس مکانیکی چیزی انداخت (%@)؛ نادیده گرفته شد", cm.summary);
            } else {
                out = mech;
            }
        }
    }

    r.text = out;
    r.inTokens = [usage[@"in"] integerValue];
    r.outTokens = [usage[@"out"] integerValue];
    r.seconds = [NSDate.date timeIntervalSinceDate:t0];
    ZBailIfCancelled();
    r.dir = [self archive:audio result:r];
    ZLog(@"final: تمام در %.0f ثانیه، %ld+%ld توکن، %@%@", r.seconds,
         (long)r.inTokens, (long)r.outTokens,
         r.coverage ? r.coverage.summary : @"بی‌سنجش", r.gated ? @" (دروازه بست)" : @"");
    return r;
    #undef ZBailIfCancelled
}

// فهرست همان چیزی که افتاد، به زبان خودِ پرامپت. متنِ کمکی عمدا «مرجع» صدا زده
// نمی‌شود: در آزمایش، جمله‌ی «متن خام مرجع کامل بودن است» باعث شد مدل فقط ۳ از ۱۱
// تکه‌ی گم‌شده را برگرداند، یعنی بدتر از حالتی که هیچ متنی نداشت. متنِ ناقصی که مرجع
// معرفی شود سقف می‌شود نه لنگر.
- (NSString *)strictAddendum:(ZCoverage *)c {
    NSMutableString *s = [NSMutableString stringWithString:
        @"تلاش قبلی‌ات محتوا انداخت. این بار هیچ چیزی حذف نمی‌شود جز فیلر و تکرار و "
         "جمله‌ی نیمه‌ی رهاشده. هر جمله‌ی متن بالا باید در خروجی معادلی داشته باشد."];
    NSArray *hard = [c.lostNumbers arrayByAddingObjectsFromArray:c.lostLatin];
    if (hard.count) {
        [s appendFormat:@"\n\nاین‌ها در خروجی‌ات نبودند و باید باشند: %@",
         [hard componentsJoinedByString:@"، "]];
    }
    if (c.missing.count) {
        NSArray *head = [c.missing subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)40, c.missing.count))];
        [s appendFormat:@"\n\nاین واژه‌ها هم افتاده بودند: %@", [head componentsJoinedByString:@"، "]];
    }
    return s;
}

// ---------- روی دیسک ----------
// صدا، متن مو‌به‌مو و متن نهایی، در یک پوشه با نام همان سشن. سه فایل، پس مقایسه‌ی
// دستی هم ممکن است، نه فقط چرخش در پنل.
- (NSURL *)archive:(NSURL *)audio result:(ZFinalPassResult *)r {
    NSString *stem = audio.lastPathComponent.stringByDeletingPathExtension;
    NSURL *dir = [[ZSupport() URLByAppendingPathComponent:@"final"] URLByAppendingPathComponent:stem];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES
                                           attributes:nil error:nil];
    [r.verbatim writeToURL:[dir URLByAppendingPathComponent:@"verbatim.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [r.text writeToURL:[dir URLByAppendingPathComponent:@"final.txt"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *meta = [NSString stringWithFormat:
        @"model=%@ thinking=%@\naudio=%@\nseconds=%.0f tokens=%ld+%ld gated=%d\n%@\n",
        ZGModel(), ZGThinking(), audio.path, r.seconds, (long)r.inTokens, (long)r.outTokens,
        r.gated, r.coverage ? r.coverage.summary : @"بی‌سنجش"];
    [meta writeToURL:[dir URLByAppendingPathComponent:@"meta.txt"]
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return dir;
}

- (void)writeRaw:(NSData *)raw name:(NSString *)name {
    if (!raw.length) return;
    NSURL *dir = [ZSupport() URLByAppendingPathComponent:@"final"];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES
                                           attributes:nil error:nil];
    [raw writeToURL:[dir URLByAppendingPathComponent:
        [NSString stringWithFormat:@"raw-%@-%@.json", ZTimestampId(), name]] atomically:YES];
}

@end

// zemzeme --finalpass <audio> [--lang fa-IR]
// همان مسیری که پنل استفاده می‌کند، بی‌میکروفن و بی‌رابط. دلیل بودنش تست است: بی این،
// تنها راهِ سنجیدن این خط لوله «سه دقیقه حرف زدن و امیدوار بودن» بود. مسیر خروجی و
// عددهای مصرف روی stdout می‌روند، پس با ست طلایی آزمایشگاه قابل مقایسه است.
int ZFinalPassMain(NSArray<NSString *> *args) {
    NSUInteger i = [args indexOfObject:@"--finalpass"];
    if (i == NSNotFound || i + 1 >= args.count) {
        printf("usage: zemzeme --finalpass <audio> [--lang fa-IR]\n");
        return 2;
    }
    NSString *path = args[i + 1].stringByExpandingTildeInPath;
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        printf("finalpass: فایل نیست: %s\n", path.UTF8String);
        return 2;
    }
    NSUInteger li = [args indexOfObject:@"--lang"];
    NSString *lang = (li != NSNotFound && li + 1 < args.count) ? args[li + 1] : @"fa-IR";
    // پرسشِ بلوکه، عمدا، و نه `hasKey`: آن یکی برای رابط است و روی نخ اصلی هیچ‌وقت
    // Keychain را نمی‌پرسد (پنجره‌ی اجازه می‌تواند یخ بزند)، پس اینجا همیشه «نه»
    // می‌گفت و خط فرمان بی‌دلیل تسلیم می‌شد. در یک ابزار خط فرمان، صبر کردن درست است.
    if (![ZFinalPass.shared key]) {
        printf("finalpass: %s\n", ZFinalPass.missingKeyHint.UTF8String);
        return 1;
    }
    __block ZFinalPassResult *res = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [ZFinalPass.shared runOnAudio:[NSURL fileURLWithPath:path] lang:lang
                         progress:^(NSString *msg) { fprintf(stderr, "  %s\n", msg.UTF8String); }
                             done:^(ZFinalPassResult *r) {
        res = r;
        dispatch_semaphore_signal(sem);
    }];
    // کال‌بک روی نخ اصلی می‌آید و اینجا ران‌لوپی نمی‌چرخد، پس خودمان می‌چرخانیمش
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW)) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (res.error.length) {
        printf("finalpass: %s\n", res.error.UTF8String);
        return 1;
    }
    fprintf(stderr, "  %.0f ثانیه، %ld+%ld توکن، %s%s\n", res.seconds,
            (long)res.inTokens, (long)res.outTokens,
            res.coverage ? res.coverage.summary.UTF8String : "بی‌سنجش",
            res.gated ? " (دروازه بست)" : "");
    printf("%s\n", res.dir.path.UTF8String);
    return 0;
}
