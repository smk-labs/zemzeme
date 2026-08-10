// پاس نهایی: فرمت‌دهی روی متنِ رونویسی‌شده، هیچ‌وقت روی خودِ صدا.
//
// قاعده‌ی سختِ نسخه‌ی دو: صدا به مدل نمی‌رود، در هیچ حالتی، هیچ‌وقت. نسخه‌ی قبلیِ این
// فایل صدای سشن را به Files API جمینای آپلود می‌کرد، چون اندازه‌گیری‌اش روشن بود: روی
// یک ویسِ ۳۶۷ ثانیه‌ایِ فارسی که متنِ خام فقط ۷۷٪ کلمه‌ها را داشت، پاسِ متنیِ صرف صفر
// از یازده تکه‌ی گم‌شده را برگرداند و مدلی که خودش صدا را شنید ده تا یازده از یازده را.
// آن مزیت هنوز واقعی است؛ فقط دیگر مجاز نیست. این فایل حالا با همین محدودیت کار
// می‌کند، نه با نادیده گرفتنش.
//
// دو چیز جای آن مزیتِ ازدست‌رفته را پر می‌کنند. یکی: اگر پاسِ دومِ انگلیسیِ همان صدا
// هم موجود باشد، `prompts/ai-pass-two.md` اسکلتِ جمله را از متنِ فارسی می‌گیرد و
// اصطلاح‌های فنی را از متنِ انگلیسی؛ یک متن که باشد `prompts/ai-pass.md` کافی است.
// دوم: تورِ ایمنیِ شمارشِ کلمه در `runOnText:`. بازنویسیِ مولد می‌تواند بی‌سروصدا یک
// جمله را ببلعد؛ چون دیگر صدایی برای تطبیق نداریم، خروجیِ زیرِ ۷۰٪ کلمه‌های ورودی رد
// می‌شود و متنِ خامِ فراخوان به‌جایش می‌ماند.
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
#define kGTimeout 300.0
// کلیدسنج سقفِ خودش را دارد و کوتاه: پشتش یک آدم ایستاده که تازه دکمه‌ی «ذخیره» را
// زده. سه دقیقه چرخنده برای یک پینگ، یعنی کاربر فکر کند اپ گیر کرده.
#define kGProbeTimeout 20.0

// ---------- کلیدسنج: یک درخواست عمدا کوچک، پیش از ذخیره ----------
// تا امروز نبود و هزینه‌اش را کاربر داد: چیزی که کلید نبود (۵۷۶ نویسه، بی هیچ شباهتی
// به یک کلید Google) بی‌صدا ذخیره شد، منو تیک «کلید هست» زد، تاگل آبی شد، و هر سشن
// یک ۴۰۰ گرفت و متن خام تحویل داد. یعنی رابط سه جا می‌گفت «آماده‌ام» و هیچ‌کدام راست
// نبود، و تنها جایی که راستش نوشته می‌شد لاگ بود.
//
// همان اندپوینت، همان مدل، همان thinking و همان مسیر ساختِ درخواست: سنجه‌ای که راه
// دیگری برود، روزی سبز می‌دهد در حالی که پاس واقعی رد می‌شود. یک تلاش، بی retry، با
// سقف کوتاه: پشتش یک آدم ایستاده.
//
// سه جوابِ ممکن، نه دو. «نشد پرسید» با «کلید بد» یکی نیست و یکی گرفتنشان یعنی کسی
// که اینترنتش قطع است هیچ‌وقت نتواند کلید بگذارد.
typedef NS_ENUM(NSInteger, ZKeyVerdict) {
    ZKeyGood = 0,      // سرور جواب داد
    ZKeyBad,           // سرور کلید را رد کرد
    ZKeyUnknown,       // نشد پرسید: شبکه نبود، یا سرور بالا نبود
};

// درونی، و در هدر نیست و نباید باشد: کلید از این فایل بیرون نمی‌رود. مسیر خط فرمان
// (`ZCheckKeyMain`، ته همین فایل) هم از همین‌جا می‌خواندشان.
@interface ZFinalPass (Internal)
- (NSString *)keyAllowingUI:(BOOL)allowUI;
- (ZKeyVerdict)checkKey:(NSString *)key note:(NSString **)note;
@end

@implementation ZFinalPass {
    NSString *_key;
    BOOL _keyChecked;    // یک بار پرسیده شد؛ «نبود» هم جواب است و دوباره پرسیده نمی‌شود
    BOOL _keyBlocked;    // پرسشِ بی‌پنجره خورد به ACL: کلید شاید هست، ولی اجازه‌اش نه
    NSLock *_keyLock;    // فقط کلید
    // ...و این یکی فقط دور خودِ *پرسش*. جدا از `_keyLock` و عمدا: آن قفل نباید در طول
    // یک پرسشِ چندثانیه‌ای گرفته بماند.
    NSLock *_fetchLock;
    NSLock *_logLock;
    BOOL _keyRejected;   // سرور همین کلید را رد کرد؛ «هست» گفتنش دیگر دروغ است
    // نوبتِ کل پاس. دیگر قفلِ مشترکی با ZEnhance نیست: آپلودِ چندمگابایتیِ صدا که لغو
    // بخواهد از میان رفت، یک تماسِ متنیِ کوتاه ماند، پس یک بولینِ ساده کافی است.
    BOOL _busy;
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
// `allowUI` جدی است و باگِ واقعی از همین‌جا آمد: آیتمِ کلید را یک بار `security` در
// ترمینال ساخته بود، پس ACL آن اپ را نمی‌شناسد و مک برای هر خواندن پنجره‌ی «رمز
// کی‌چین را بده» باز می‌کند. آن پنجره وسط دیکته می‌پرید بالا، فوکوس را می‌برد و کاربر
// فقط می‌دید زمزمه ریست شد. بدتر: هیچ‌کس کلید را نخواسته بود، فقط منو باز شده بود و
// منو می‌خواست بداند تیک «کلید تنظیم شده» را بزند یا نه.
//
// پس دو جور پرسش داریم. پرسشِ رابط (منو، کارت راهنما) بی‌پنجره است: اگر ACL راه
// ندهد، جوابش «نمی‌دانم» است و همان‌جا تمام. پنجره فقط وقتی حق دارد باز شود که کاربر
// واقعا کاری خواسته که کلید لازم دارد (پاس هوش مصنوعی). آن‌وقت پنجره
// معنا دارد، چون کاربر تازه دکمه‌اش را زده و «همیشه اجازه بده» یعنی دیگر پرسیده نشود.
static NSString *ZKeyFromKeychain(BOOL allowUI, BOOL *blocked) {
    if (blocked) *blocked = NO;
    NSDictionary *q = @{(id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: kKeychainService,
                        (id)kSecReturnData: @YES,
                        (id)kSecMatchLimit: (id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // پرچمِ پروسه است نه نخ، ولی خواندنِ کلید تک‌پرواز است (`_fetchLock`) و جای دیگری
    // در اپ کی‌چین را نمی‌خواند، پس در عمل همان یک پرسش را می‌پوشاند.
    if (!allowUI) SecKeychainSetUserInteractionAllowed(FALSE);
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (!allowUI) SecKeychainSetUserInteractionAllowed(TRUE);
#pragma clang diagnostic pop
    if (st == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if (out) CFRelease(out);
    // ۲۵۳۰۸ یعنی «کلید هست ولی بی‌پنجره نمی‌دهم». این «نبود» نیست و نباید مثل نبود
    // بایگانی شود، وگرنه تا ری‌استارت بعدی اپ فکر می‌کند کلیدی در کار نیست.
    if (st == errSecInteractionNotAllowed && blocked) *blocked = YES;
    ZLog(@"final: Keychain کلید نداد (OSStatus %d%@)", (int)st, allowUI ? @"" : @"، بی‌پنجره");
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
// می‌اندازد، و منو و کارت راهنما و شروع سشن همه صدایش
// می‌زنند. باز کردن منو دو بار پشت هم کافی بود.
- (NSString *)key { return [self keyAllowingUI:YES]; }

- (NSString *)keyAllowingUI:(BOOL)allowUI {
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
    BOOL blocked = NO;
    if (!k.length) k = ZKeyFromKeychain(allowUI, &blocked);
    // ابزار `security` هم می‌تواند پنجره باز کند، پس در پرسشِ رابط اصلا صدا نمی‌شود
    if (!k.length && allowUI) k = ZKeyFromSecurityTool();
    [_keyLock lock];
    // «پرسیدم و نبود» را فقط وقتی می‌نویسیم که واقعا پرسیده باشیم. پرسشِ بی‌پنجره‌ای
    // که ACL جلویش را گرفت هیچ نمی‌داند، و اگر «نبود» بایگانی شود پاس نهایی تا
    // ری‌استارت بعدی خاموش می‌ماند با اینکه کلید سر جایش است.
    _keyChecked = k.length || !blocked;
    _keyBlocked = blocked;
    if (k.length) _key = [k copy];
    [_keyLock unlock];
    [_fetchLock unlock];
    return k.length ? k : nil;
}

// پرسشِ رابط: بی‌پنجره، همیشه. تنها فراخوانش از `hasKey` است و `hasKey` فقط برای
// کشیدنِ منو و کارت راهنماست؛ هیچ‌کدام آنقدر مهم نیستند که کاربر را وسط کار
// بایستانند پای رمز کی‌چین.
- (void)prefetchKey {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self keyAllowingUI:NO]; });
}

// جوابِ کش‌شده، و روی نخ اصلی **هیچ‌وقت** پرسشِ تازه. سه فراخوان از نخ اصلی می‌آیند
// (منو، کارت راهنما، شروع سشن) و همان‌جا یخ زدن یعنی اپ ایستاده. اگر هنوز پرسیده
// نشده، پرسش را در پس‌زمینه راه می‌اندازد و جواب این دفعه «نه» است؛ دفعه‌ی بعد که منو
// باز شود درست می‌گوید. پرسشِ پس‌زمینه هم بی‌پنجره است: این تابع رابط را می‌کشد، و
// رابط حق ندارد پنجره‌ی رمزِ کی‌چین را بالا بیاورد.
+ (BOOL)hasKey {
    ZFinalPass *s = ZFinalPass.shared;
    if (!NSThread.isMainThread) return [s keyAllowingUI:NO].length > 0;
    [s->_keyLock lock];
    BOOL have = s->_key.length > 0, checked = s->_keyChecked;
    [s->_keyLock unlock];
    if (!have && !checked) [s prefetchKey];
    return have;
}

// «کلیدی هست ولی کی‌چین بی‌اجازه نمی‌دهدش». منو با این حالت سوم درست حرف می‌زند،
// وگرنه «کلید تنظیم نشده» می‌گفت و کاربر می‌رفت کلید تازه بسازد بی‌آنکه لازم باشد.
+ (BOOL)keyNeedsPermission {
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    BOOL blocked = s->_keyBlocked && s->_key.length == 0;
    [s->_keyLock unlock];
    return blocked;
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
    //
    // و «نیست» با «پذیرفته نشد» یکی نیست: اولی یعنی برو کلید بگیر، دومی یعنی کلیدی
    // که داری کار نمی‌کند. یک جمله برای هر دو، کاربر را دنبال کارِ اشتباه می‌فرستد.
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    BOOL rejected = s->_keyRejected;
    [s->_keyLock unlock];
    if (rejected) return @"کلید Gemini پذیرفته نشد. از منوی زمزمه «کلید Gemini…» را بزن و کلید تازه بگذار.";
    return @"کلید Gemini نیست. از منوی زمزمه «کلید Gemini…» را بزن.";
}

// سرور کلید را رد کرد. از این لحظه اپ نباید بگوید کلید دارد: تاگل آبی و تیکِ «کلید
// هست» روی کلیدی که سرور نمی‌شناسد، همان حالت بینابینی است که این اپ جای دیگری
// اجازه‌اش را نمی‌دهد (روشن، و بی‌کار). فقط کشِ حافظه پاک می‌شود، نه خودِ آیتم
// Keychain: آن مالِ کاربر است و پاک کردنش کارِ دکمه‌ی «پاک کردن کلید» است.
- (void)noteKeyRejected {
    [_keyLock lock];
    BOOL first = !_keyRejected;
    _key = nil;
    _keyChecked = YES;
    _keyRejected = YES;
    [_keyLock unlock];
    if (first) ZLog(@"final: سرور کلید را رد کرد؛ از حالا «کلید نیست» حساب می‌شود");
}

// ---------- کلیدسنج ----------
- (ZKeyVerdict)checkKey:(NSString *)key note:(NSString **)note {
    NSMutableURLRequest *req = [self requestFor:@"Reply with exactly: ok"
                                          parts:@[@{@"type": @"text", @"text": @"ping"}]
                                            key:key thinking:ZGThinking()];
    if (!req) {
        if (note) *note = @"درخواست تست ساخته نشد";
        return ZKeyUnknown;
    }
    NSInteger st = 0;
    NSDate *t0 = NSDate.date;
    NSData *raw = [self http:req timeout:kGProbeTimeout status:&st headers:nil];
    NSString *body = [[NSString alloc] initWithData:raw ?: [NSData data]
                                          encoding:NSUTF8StringEncoding] ?: @"";
    NSTimeInterval dt = [NSDate.date timeIntervalSinceDate:t0];
    ZLog(@"final: کلیدسنج HTTP %ld در %.1f ثانیه", (long)st, dt);
    if (st == 200) {
        if (note) *note = @"تست شد و کار کرد.";
        return ZKeyGood;
    }
    if (ZKeyRejected(st, body)) {
        ZLog(@"final: کلیدسنج کلید را رد کرد: %@",
             [body substringToIndex:MIN((NSUInteger)300, body.length)]);
        if (note) *note = @"گوگل این کلید را نشناخت. مطمئن شو کلِ کلید را از AI Studio "
                           "کپی کرده‌ای (یک رشته‌ی کوتاه که با AIza شروع می‌شود) و چیز دیگری "
                           "به‌جایش نچسبیده.";
        return ZKeyBad;
    }
    // ۴۲۹ یعنی کلید **شناخته شد** و سهمش تمام شده: سهم مالِ یک کلید واقعی است. پس
    // این «کلید بد» نیست و رد کردنش یعنی کسی که امروز بیست درخواستش را خرج کرده
    // نتواند کلید درستش را ذخیره کند.
    if (st == 429) {
        if (note) *note = ZHumanError(@"کلیدسنج", st, raw);
        return ZKeyGood;
    }
    if (note) *note = [NSString stringWithFormat:@"نشد تستش کنیم (%@)", ZHumanError(@"کلیدسنج", st, raw)];
    return ZKeyUnknown;
}

// ---------- نوشتن (از منو، «کلید Gemini…») ----------
// همان سرویس، همان کلاس، پس همان آیتمی که ZKeyFromKeychain بالا می‌خواند. تفاوتش با
// راه ترمینالی: سازنده‌ی این آیتم خودِ همین پروسه است، و مک از سازنده‌ی یک آیتم برای
// خواندنِ بعدیِ همان آیتم هیچ‌وقت اجازه نمی‌پرسد. یعنی `-T` اینجا لازم نیست؛ آن فقط
// برای وقتی بود که سازنده یک ابزار دیگر (`security`) باشد.
+ (ZKeySave)saveKey:(NSString *)key message:(NSString **)msg {
    NSString *k = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!k.length) {
        if (msg) *msg = @"کلید خالی است";
        return ZKeySaveBadInput;
    }
    // ورودیِ به‌وضوح غلط را بی رفت‌وبرگشت شبکه بگیر: کلید Google یک رشته‌ی کوتاه و
    // بی‌فاصله است. چیزی که فاصله دارد یا صدها نویسه است، یک چیز دیگر است که اشتباهی
    // چسبانده شده (توکن، JSON، یا کلِ یک فایل). عمدا سقفِ گشاد و بی شرطِ «با AIza
    // شروع شود»: قالبِ کلید مالِ گوگل است و روزی عوض می‌شود، ولی «فاصله ندارد و
    // دویست نویسه نیست» تا آن روز هم درست می‌ماند.
    if ([k rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound
        || k.length > 200) {
        ZLog(@"final: ورودی شبیه کلید نبود (%lu نویسه)", (unsigned long)k.length);
        if (msg) *msg = @"این شبیه کلید Gemini نیست: کلید یک رشته‌ی کوتاه و بی‌فاصله است "
                         "(معمولا با AIza شروع می‌شود). از AI Studio دوباره کپی کن.";
        return ZKeySaveBadInput;
    }
    // تست، بعد نوشتن. برعکسش یعنی همان حالتی که این تابع دارد از بین می‌بردش: کلیدِ
    // غلطِ ذخیره‌شده و رابطی که می‌گوید همه‌چیز آماده است.
    NSString *note = nil;
    ZKeyVerdict v = [ZFinalPass.shared checkKey:k note:&note];
    if (v == ZKeyBad) {
        if (msg) *msg = note;
        return ZKeySaveRejected;
    }
    NSData *d = [k dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *q = @{(id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: kKeychainService};
    // **یک آیتم، نه یک آیتمِ بیشتر.** روی همین دستگاه دو آیتم با همین سرویس پیدا شد
    // (یکی از `security` و یکی از خودِ اپ) و نتیجه‌اش بدترین حالت ممکن بود: خواندن با
    // kSecMatchLimitOne هر بار می‌توانست آن یکی را بدهد، پس «کلید تازه را گذاشتم» و
    // «اپ کلید قبلی را می‌خواند» هم‌زمان راست بودند. SecItemUpdate این تضمین را
    // نمی‌داد (روی آیتمِ دوم دست نمی‌زد)، پس اول همه پاک، بعد یکی نوشته می‌شود.
    SecItemDelete((__bridge CFDictionaryRef)q);
    NSMutableDictionary *add = [q mutableCopy];
    add[(id)kSecAttrAccount] = NSUserName();
    add[(id)kSecValueData] = d;
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (st != errSecSuccess) {
        ZLog(@"final: نوشتنِ کلید در Keychain رد شد (OSStatus %d)", (int)st);
        if (msg) *msg = [NSString stringWithFormat:@"Keychain کلید را نپذیرفت (کد %d)", (int)st];
        return ZKeySaveKeychainNo;
    }
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    s->_key = [k copy];
    s->_keyChecked = YES;
    s->_keyBlocked = NO;
    s->_keyRejected = NO;    // کلیدِ تازه، پرونده‌ی تازه
    [s->_keyLock unlock];
    if (msg) *msg = note;
    return v == ZKeyGood ? ZKeySaveOK : ZKeySaveUntested;
}

+ (void)clearKey {
    NSDictionary *q = @{(id)kSecClass: (id)kSecClassGenericPassword,
                        (id)kSecAttrService: kKeychainService};
    SecItemDelete((__bridge CFDictionaryRef)q);
    ZFinalPass *s = ZFinalPass.shared;
    [s->_keyLock lock];
    s->_key = nil;
    s->_keyChecked = NO;
    s->_keyRejected = NO;
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
- (NSData *)http:(NSMutableURLRequest *)req timeout:(NSTimeInterval)timeout
          status:(NSInteger *)status headers:(NSDictionary **)headers {
    __block NSData *body = nil;
    __block NSInteger code = 0;
    __block NSDictionary *hd = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = timeout;
    cfg.timeoutIntervalForResource = timeout;
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
    // arm/disarm (قفلِ ZPassLock) با حذفِ صدا از این پاس رفتند: آن‌ها برای لغوِ آپلودِ
    // چندمگابایتیِ وسطِ کار بودند؛ حالا بدنه‌ی هر تماس یک متنِ کوتاه است و لغو معنا ندارد.
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 30) * NSEC_PER_SEC)));
    [s finishTasksAndInvalidate];
    if (status) *status = code;
    if (headers) *headers = hd;
    return body;
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
        body = [self http:req timeout:kGTimeout status:&st headers:outHeaders];
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

// کلیدِ غلط **۴۰۰** می‌گیرد، نه ۴۰۱ و نه ۴۰۳. این یک خط، یک شب کامل عیب‌یابی را
// خورد: کلیدی که کلید نبود ذخیره شده بود و اپ هر بار «سرور این درخواست را نپذیرفت
// (۴۰۰)» می‌گفت، یعنی دقیقا آن جمله‌ای که کاربر را دنبال هیچ می‌فرستد. جواب واقعیِ
// گوگل در بدنه است: `API_KEY_INVALID`.
static BOOL ZKeyRejected(NSInteger st, NSString *body) {
    if (st == 401 || st == 403) return YES;
    if (st != 400) return NO;
    return [body rangeOfString:@"API_KEY_INVALID"].location != NSNotFound
        || [body rangeOfString:@"API key not valid" options:NSCaseInsensitiveSearch].location != NSNotFound
        || [body rangeOfString:@"API_KEY_SERVICE_BLOCKED"].location != NSNotFound;
}

// پیام برای خودِ کاربر، نه کد HTTP. «HTTP 429» به کسی نمی‌گوید چه کند؛ «سهم مجانی
// کلید تمام شد» می‌گوید.
static NSString *ZHumanError(NSString *label, NSInteger st, NSData *raw) {
    NSString *body = [[NSString alloc] initWithData:raw ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
    if (st == 429) {
        return [body rangeOfString:@"free_tier"].location != NSNotFound
            ? @"سهم رایگان کلید Gemini برای امروز تمام شد (۲۰ درخواست در روز). "
               "فردا دوباره امتحان کن."
            : @"سرور Gemini فعلا جواب نمی‌دهد. چند دقیقه بعد دوباره بزن.";
    }
    if (ZKeyRejected(st, body)) return @"کلید Gemini پذیرفته نشد؛ از منوی زمزمه یک کلید تازه بگذار.";
    if (st == 400) return @"سرور Gemini این درخواست را نپذیرفت (۴۰۰)";
    if (st < 0) return @"اینترنت نیست؛ متن تمیز نشد";
    return [NSString stringWithFormat:@"تمیز کردن متن نشد (HTTP %ld)", (long)st];
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
// یک درخواست، یک جا. کلیدسنج و خودِ پاس باید **عین هم** ساخته شوند، وگرنه روزی
// کلیدسنج سبز می‌دهد و پاس ۴۰۰ می‌گیرد؛ آن‌وقت سنجه‌ای داریم که فقط خودش را می‌سنجد.
- (NSMutableURLRequest *)requestFor:(NSString *)system parts:(NSArray *)parts
                                key:(NSString *)key thinking:(NSString *)thinking {
    NSDictionary *body = @{@"model": ZGModel(),
                           @"system_instruction": system,
                           @"input": parts,
                           @"generation_config": @{@"thinking_level": thinking}};
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!json) return nil;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[kGBase stringByAppendingString:@"/v1beta/interactions"]]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = json;
    [req setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    return req;
}

- (NSString *)ask:(NSString *)system parts:(NSArray *)parts label:(NSString *)label
              key:(NSString *)key thinking:(NSString *)thinking
            usage:(NSMutableDictionary *)usage error:(NSString **)err {
    NSMutableURLRequest *req = [self requestFor:system parts:parts key:key thinking:thinking];
    if (!req) {
        if (err) *err = @"درخواست ساخته نشد";
        return nil;
    }
    NSDate *t0 = NSDate.date;
    NSInteger st = 0;
    NSData *raw = [self send:req label:label status:&st headers:nil];
    NSTimeInterval dt = [NSDate.date timeIntervalSinceDate:t0];
    if (st != 200) {
        NSString *msg = [[NSString alloc] initWithData:
            [raw subdataWithRange:NSMakeRange(0, MIN((NSUInteger)600, raw.length))]
                                             encoding:NSUTF8StringEncoding];
        if (err) *err = ZHumanError(label, st, raw);
        ZLog(@"final: %@ HTTP %ld در %.1f ثانیه: %@", label, (long)st, dt, msg ?: @"?");
        // کلیدی که سرور ردش کرد، دفعه‌ی بعد هم رد می‌شود. پس همین‌جا علامت می‌خورد،
        // وگرنه رابط تا ری‌استارت بعدی «آماده‌ام» می‌گفت و هر سشن یک رفت‌وبرگشت
        // بی‌فایده خرج می‌کرد تا آخرش همان متن خام تحویل بدهد.
        NSString *full = [[NSString alloc] initWithData:raw ?: [NSData data]
                                              encoding:NSUTF8StringEncoding] ?: @"";
        if (ZKeyRejected(st, full)) [self noteKeyRejected];
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
        if (err) *err = @"جوابی برنگشت";
        return nil;
    }
    return ZDropPreamble(text);
}

// ---------- پاس روی متن ----------
// شمارشِ کلمه‌های جداشده با فاصله/خط‌جدید؛ چند فاصله‌ی پشت‌سرهم یک کلمه‌ی خالی
// نمی‌سازد.
static NSUInteger ZWordCount(NSString *s) {
    NSUInteger n = 0;
    for (NSString *w in [s componentsSeparatedByCharactersInSet:
                          NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (w.length) n++;
    }
    return n;
}

// پاس روی **متن**، هیچ‌وقت روی صدا. کار روی نخ پس‌زمینه، `done` روی نخ اصلی.
// `second` متنِ پاس دوم انگلیسی است و می‌تواند نال باشد.
// out نال یا خالی یعنی هیچ اتفاقی نیفتاد و فراخوان باید متن خام خودش را نگه دارد.
// ادامه‌ی یک متنِ در حال ساخت: متنِ تمیزِ قبلی به‌اضافه‌ی تکه‌ی خامِ تازه، و خروجی
// کلِ متنِ از نو نوشته‌شده.
//
// چرا نه فقط «تکه‌ی تازه را تمیز کن و بچسبان»: تکه‌ای که جدا تمیز شود کانتکست ندارد،
// پس نه ضمیرش به جمله‌ی قبلی وصل می‌شود نه نقطه‌گذاری‌اش با بقیه یک‌دست درمی‌آید، و
// درزش پیداست. مدل باید کل متن را ببیند تا جوش بخورد.
//
// و چرا دو ورودیِ جدا و نه یک متنِ سرهم: مدل باید بداند کدام قسمت را خودش نوشته
// (پس دست‌نخورده بماند) و کدام قسمت خامِ تشخیص گفتار است (پس تمیزکاری لازم دارد).
// یک متنِ سرهم این تفاوت را پاک می‌کند و مدل کل متن را دوباره‌نویسی می‌کند.
- (void)runOnText:(NSString *)raw appendingTo:(NSString *)previous lang:(NSString *)lang
             done:(void (^)(NSString *out, NSString *err))done {
    if (!previous.length) {
        [self runOnText:raw second:nil lang:lang done:done];
        return;
    }
    [self work:@"ai-pass-append" parts:@[previous, raw]
      guardOn:[NSString stringWithFormat:@"%@ %@", previous, raw] done:done];
}

- (void)runOnText:(NSString *)text second:(NSString *)second lang:(NSString *)lang
             done:(void (^)(NSString *out, NSString *err))done {
    if (!text.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"متنی برای تمیز کردن نیست"); });
        return;
    }
    BOOL twoPass = second.length > 0;
    [self work:twoPass ? @"ai-pass-two" : @"ai-pass"
         parts:twoPass ? @[text, second] : @[text]
       guardOn:text done:done];
}

// تنها پیاده‌سازی. سه ورودی دارد (تک‌متنی، دو‌زبانه، ادامه) و هر سه از همین‌جا
// می‌روند، وگرنه نگهبانِ «یک کار در هر لحظه» و تورِ ایمنیِ کوتاه‌شدن سه بار نوشته
// می‌شد و سه رفتار واگرا می‌داد.
//
// `guardOn` متنی است که خروجی با آن سنجیده می‌شود. در حالت ادامه، ورودیِ واقعی
// مجموعِ متنِ قبلی و تکه‌ی تازه است، نه فقط تکه‌ی تازه.
- (void)work:(NSString *)promptName parts:(NSArray<NSString *> *)parts
     guardOn:(NSString *)guardText done:(void (^)(NSString *out, NSString *err))done {
    @synchronized (self) {
        if (_busy) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"یک کار دیگر در جریان است"); });
            return;
        }
        _busy = YES;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = nil, *err = nil;
        @autoreleasepool {
            NSDate *t0 = NSDate.date;
            NSString *key = [self key];
            NSString *sys = key ? [self prompt:promptName] : nil;
            if (!key) {
                err = ZFinalPass.missingKeyHint;
            } else if (!sys.length) {
                // پرامپت در بسته نبود. تا امروز همین نیل تا داخل بدنه‌ی درخواست
                // می‌رفت و اپ با NSInvalidArgumentException می‌مرد، یعنی یک فایلِ
                // جامانده در بسته کل اپ را می‌کشت.
                err = @"یک فایل داخلی زمزمه گم شده؛ نسخه‌ی تازه را نصب کن";
            } else {
                NSMutableDictionary *usage = [NSMutableDictionary dictionary];
                NSString *aerr = nil;
                NSString *result = [self askText:sys parts:parts label:promptName
                                        thinking:@"minimal" usage:usage error:&aerr];
                NSUInteger inWords = ZWordCount(guardText);
                NSUInteger outWords = ZWordCount(result);
                if (!result.length) {
                    err = aerr ?: @"جوابی نیامد";
                } else if (inWords > 0 && (double)outWords < (double)inWords * 0.7) {
                    // تنها تورِ ایمنی: بازنویسیِ مولد می‌تواند بی‌سروصدا یک جمله را
                    // ببلعد. متنِ خامِ فراخوان همیشه فال‌بکِ امن است، پس خروجیِ
                    // به‌وضوح کوتاه‌تر رد می‌شود.
                    ZLog(@"final: %@ متن را کوتاه کرد (ورودی %lu کلمه، خروجی %lu کلمه)",
                         promptName, (unsigned long)inWords, (unsigned long)outWords);
                    err = @"جواب ناقص بود، پس رد شد";
                } else {
                    out = result;
                    ZLog(@"final: %@ در %.1f ثانیه، %ld+%ld توکن", promptName,
                         [NSDate.date timeIntervalSinceDate:t0],
                         (long)[usage[@"in"] integerValue], (long)[usage[@"out"] integerValue]);
                }
            }
        }
        @synchronized (self) { _busy = NO; }
        dispatch_async(dispatch_get_main_queue(), ^{ done(out, err); });
    });
}

@end

// ---------- zemzeme --checkkey ----------
// همان کلیدسنجی که منو می‌زند، روی کلیدِ ذخیره‌شده، بی‌پنجره و بی‌آدم. دلیل وجودش همان
// شرط سختِ بقیه‌ی اپ است: ادعای «کلید کار می‌کند» باید بی‌آدم تکرارپذیر باشد. چاپ هم
// همین‌جا انجام می‌شود و **خود کلید هیچ‌وقت چاپ نمی‌شود**، فقط طولش: کلید از این فایل
// بیرون نمی‌رود، از خروجی ترمینال هم نه.
int ZCheckKeyMain(void) {
    NSString *k = [ZFinalPass.shared keyAllowingUI:YES];
    if (!k.length) {
        fprintf(stderr, "%s\n", ZFinalPass.missingKeyHint.UTF8String);
        return 2;
    }
    NSString *note = nil;
    ZKeyVerdict v = [ZFinalPass.shared checkKey:k note:&note];
    const char *verdict = v == ZKeyGood ? "کلید کار می‌کند"
                        : v == ZKeyBad ? "کلید پذیرفته نشد" : "نشد تستش کرد";
    fprintf(v == ZKeyGood ? stdout : stderr, "%s (کلیدِ %lu نویسه‌ای): %s\n",
            verdict, (unsigned long)k.length, note.UTF8String ?: "?");
    return v == ZKeyGood ? 0 : 1;
}
