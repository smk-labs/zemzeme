// زمزمه: دیکته فارسی شناور روی مک.
// چرا ObjC؟ سوئیفت روی این دستگاه فعلا بیلد نمی‌شود: CLT نصب‌شده (swiftlang-6.2.0.19.9)
// با ماژول‌های همه SDK های موجود (6.2.0.17.14 و قدیمی‌تر) ناسازگار است و بازسازی
// interface ها هم به برخورد modulemap مربوط به SwiftBridging می‌خورد. clang سالم است.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------- مسیرها، لاگ، اعداد فارسی ----------
NSURL *ZRes(void);           // خواندنی‌های همراه اپ: پرامپت‌های پاس هوش مصنوعی
NSURL *ZSupport(void);       // ~/Library/Application Support/Zemzeme: داده، لاگ، venv
NSURL *ZSessionsDir(void);
void ZLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
// خطوط لاگ فقط ساعت دارند، پس به‌تنهایی نمی‌شود گفت کدامشان مالِ کدام روزند. ZLog
// سرِ هر روزِ تازه (و سرِ هر اجرا) یک خطِ نشانه با همین سرآیند می‌گذارد، و جاروی
// روزانه از روی همان می‌برد. بی این نشانه، لاگ برای همیشه بزرگ می‌شد.
extern NSString *const ZLogDayPrefix;                 // "--- " و بعدش yyyy-MM-dd
// خطوطِ قدیمی‌تر از روزِ مرز را ببر. زیر همان قفلی که ZLog می‌نویسد، وگرنه یک خطِ
// هم‌زمان روی فایلِ رهاشده می‌نشیند و گم می‌شود. برمی‌گرداند چند خط رفت.
NSUInteger ZLogTrimBefore(NSDate *cutoff);

// ---------- صدای کارها ----------
// هر کار صدای خودش را دارد، پس بی‌نگاه کردن به پنل می‌فهمی چه شد. صداهای سیستمی
// مک‌اند (بی‌فایل همراه)، آرام، و با تاگل «صدا» در منو خاموش می‌شوند.
typedef NS_ENUM(NSInteger, ZSound) {
    ZSoundStart,      // شروع سشن
    ZSoundPause,      // مکث
    ZSoundResume,     // ادامه
    ZSoundFinish,     // Esc: پایان و درج
    ZSoundInsert,     // درج، ولی سشن باز می‌ماند
    ZSoundTrash,      // دور ریختن
    ZSoundCopy,       // کپی
    ZSoundMode,       // عوض کردن حالت
    ZSoundLang,       // عوض کردن زبان
    ZSoundPolish,     // پاس هوش مصنوعی نشست
    ZSoundHole,       // یک تکه بی‌متن برگشت؛ عمدا همان صدای ناخوشایندِ دور ریختن
};
void ZPlay(ZSound s);
NSString *ZFaDigits(NSString *s);
NSString *ZTimestampId(void);

// ---------- تنظیمات ----------
#define kZRDPBundleId @"com.microsoft.rdc.macos"    // Windows App، تنها اپی که همیشه پیست می‌گیرد

// در منو: «درج مستقیم» و «ذخیره در کلیپ‌بورد». اسم‌ها از روی کاری است که با متن
// می‌شود، نه از روی مکانیزم، چون تفاوتی که به کاربر می‌رسد همین است: اولی کلیپ‌بورد را
// دست‌نخورده می‌گذارد، دومی محتوای قبلی‌اش را با متن دیکته عوض می‌کند.
typedef NS_ENUM(NSInteger, ZInsertMode) {
    ZInsertType = 0,     // درج مستقیم، حرف‌به‌حرف با رویداد یونیکد
    ZInsertPaste = 1,    // کلیپ‌بورد و بعد Command+V (برای ریموت دسکتاپ تنها راه)
};

// دو حالت، یک تنظیم. Command راست + E بینشان می‌چرخد.
//
// «درج زنده» و «یادداشت» هر دو رفتند و هر دو به یک دلیل: نسخه دو در حین حرف زدن
// هیچ متنی نشان نمی‌دهد. زنده کلا یعنی متنِ لحظه‌ای، پس موضوعیتش رفت؛ و یادداشت
// یعنی «صدا را بده به مدل»، که حالا ممنوع است. آنچه مانده دو مقصدِ واقعی است:
// متن در پنل بنشیند، یا سر کرسر برود.
//
// عددها عمدا دست‌نخورده‌اند: تنظیم روی دیسک همان کلید قدیمی «collect» است، پس
// انتخاب کاربر قدیمی بی‌هیچ کد مهاجرتی سر جایش می‌ماند. عددِ بیرون از این دو
// (کسی که در نسخه یک روی زنده یا یادداشت بوده) به «جمع» برمی‌گردد.
typedef NS_ENUM(NSInteger, ZMode) {
    ZModeCollect = 1,    // جمع در ادیتور خود پنل، درج یا کپی در پایان
    ZModeCursor = 2,     // بی‌پنل، فقط یک نقطه کنار کرسر. متن سر پایان یک بار درج می‌شود
};

// نام حالت، یک بار. سشن آن را روی خط وضعیت فلش می‌کند و منو با همان دو ردیفِ
// انتخابش را می‌سازد؛ دو رشته‌ی جدا یعنی روزی منو یک اسم بگوید و پنل اسمی دیگر.
NSString *ZModeLabel(ZMode m);

@interface ZSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *lang;         // fa-IR | en-US
@property (nonatomic) ZInsertMode insertMode;       // روش درج (تایپ/پیست)
@property (nonatomic) ZMode mode;                   // حالتی که سشن بعدی با آن شروع می‌شود
@property (nonatomic) BOOL internalHotkey;
@property (nonatomic) BOOL highSensitivity;   // بهره‌ی بیشتر برای پچ‌پچ و میکروفن کم‌جان
@property (nonatomic) BOOL soundsEnabled;           // صدای کارها؛ پیش‌فرض روشن
@property (nonatomic) BOOL upstreamFLAC;            // فشرده‌سازی FLAC آپلود؛ پیش‌فرض روشن
@property (nonatomic, copy) NSString *batchLang;    // زبان پیش‌فرض رونویسی فایل؛ جدا از lang زنده
// پاس هوش مصنوعی روی **متن**. پیش‌فرض خاموش و عمدا: تا کلید ست نشده باشد روشن
// بودنش فقط یک پیام کوتاه در پایان هر سشن است.
@property (nonatomic) BOOL finalPassEnabled;
// **ماندنِ** صدای سشن روی دیسک بعد از پایان. ضبط خودش همیشه انجام می‌شود (فایل
// مرجع همه‌چیز است و اگر شبکه بمیرد حرفِ گفته‌شده نباید گم شود)، ولی خاموش که باشد
// همان لحظه‌ی آماده شدن متن پاک می‌شود. روشن یعنی هفت روز می‌ماند و بعد جارو.
// پیش‌فرض خاموش: ضبطِ بی‌خواسته بدترین پیش‌فرض ممکن است.
@property (nonatomic) BOOL recordSessions;
// پاس دوم انگلیسی روی همان صدا. رایگان و موازی، و پیش‌فرض خاموش: روی متنِ پر از
// اصطلاح فنی عالی است (ضبط ۰۲) و روی گفتار روزمره تقریبا هیچ (ضبط ۰۷). بیمه است،
// نه ستون، پس روشن کردنش باید انتخاب صریح باشد.
@property (nonatomic) BOOL secondPass;
// پیش‌نمایش: تکه‌های رونویسی‌شده همان‌طور که می‌رسند، خاکستری، در ادیتور پنل. هیچ
// چیزی در مسیر تشخیص عوض نمی‌شود: این همان متنی است که خط لوله سر پایان تحویل
// می‌دهد، فقط زودتر دیده می‌شود. پیش‌فرض خاموش، چون خواندنِ حرفِ خود آدم در حالی که
// دارد همان را می‌گوید، رشته‌ی کلام را پاره می‌کند.
@property (nonatomic) BOOL previewStream;
// تاریخچه و لاگ چند روز بمانند. پیش‌فرض شصت: بلند است که «آن متنِ هفته‌ی پیش» هنوز
// پیدا شود، و کوتاه است که حرف‌های آدم تا ابد روی دیسک نمانند. صفر یعنی هرگز جارو
// نکن، و آن هم انتخابِ صریحِ کاربر است نه پیش‌فرض.
@property (nonatomic) NSInteger historyKeepDays;
// روش درج برای یک اپ مشخص. Windows App همیشه پیست، بی‌تنظیم و بی‌استثنا؛ دلیلش در core.m
- (ZInsertMode)insertModeForBundleId:(NSString *)bundleId;
- (useconds_t)typeDelayMicros;
- (useconds_t)pasteDelayMicros;
@end

// ---------- رویداد گفتار (پارس‌شده از protobuf گوگل) ----------
@interface ZSpeechEvent : NSObject
@property (nonatomic) NSInteger status;        // -1 یعنی نیامده
@property (nonatomic) NSInteger endpoint;      // -1 یعنی نیامده
@property (nonatomic) BOOL hasResults;         // فریم بدون result (endpointer/status) نباید interim را پاک کند
@property (nonatomic, strong) NSMutableArray<NSString *> *finals;
@property (nonatomic, copy) NSString *interim;
@end

ZSpeechEvent *ZProtoDecodeEvent(NSData *body);

// ---------- برش‌زن ----------
// پی‌سی‌ام خام همه‌جا یک شکل است: s16le مونو ۱۶ کیلوهرتز، یعنی ۳۲۰۰۰ بایت بر ثانیه.
#define kZPcmBytesPerSec 32000.0

// هدف ~۷ ثانیه، پنجره‌ی گشتن ۴ تا ۱۲. عددها اندازه‌گیری‌اند نه سلیقه: منحنیِ طولِ
// تکه روی دو ضبط واقعی قله دارد و قله‌اش هفت ثانیه است (شرحش سر seg.m). سقف ۱۲ هم
// خیلی زیر سقفِ ~۳۰ ثانیه‌ای خودِ اندپوینت است، پس چرخشِ پیش‌دستانه‌ی نسخه یک اصلا
// موضوعیت ندارد: هیچ سشنی به آن سقف نزدیک نمی‌شود.
#define kZSegTargetSec 7.0
#define kZSegMinSec 4.0
#define kZSegMaxSec 12.0

// مکث واجد شرایط: دست‌کم این‌قدر میلی‌ثانیه زیر آستانه. آستانه دست‌ودل‌بازتر از حد
// شنوایی است که نویز زمینه‌ی ضبط واقعی هم «سکوت» به حساب بیاید.
#define kZSegQuietMs 200
#define kZSegRMS 0.02f

// و این یکی جداست، با اینکه هر دو «بلندی» را می‌سنجند: آستانه‌ی بالا جواب «اینجا
// مکث است؟» را می‌دهد و این یکی جواب «این تکه اصلا صدایی دارد؟». یک عدد برای هر دو
// سوال غلط بود و روی ضبط ۰۴ (پچ‌پچ) گران تمام شد: از ۱۴۳۴ قاب فقط ۱۰ تا از ۰٫۰۲ رد
// می‌شدند، پس کلِ ضبط «سکوت» اعلام و دور ریخته شد و تطبیق از ۷۹٪ به ۱۴٪ افتاد.
// نامتقارن هم هست: فرستادنِ یک تکه‌ی ساکت فقط یک رفت‌وبرگشتِ هدررفته است، ولی
// انداختنِ یک تکه‌ی پچ‌پچ یعنی حرفِ کاربر ناپدید شود. پس در تردید، بفرست.
#define kZVoiceRMS 0.005f

typedef struct {
    NSUInteger cut;      // بایت، زوج. صفر یعنی هنوز تصمیم نگیر: بافر به سقف نرسیده
    double score;        // امتیاز مکثِ برنده؛ صفر یعنی مکثی نبود
    double quietSec;     // طول مکثِ برنده
    float rms;           // بلندیِ ناحیه‌ای که بریدیم
    BOOL degraded;       // مکثی در پنجره نبود و برش تحمیل شد
    BOOL tail;           // آخرین تکه: صدا تمام شد، هرچه مانده همین است
} ZSegCut;

// بهترین جای برش در [۴s, ۱۲s]. `eof` یعنی صدا تمام شده و ته‌مانده هرچقدر هم کوتاه
// باشد باید برود. تابع خالص است و هیچ حالتی نگه نمی‌دارد.
ZSegCut ZSegFind(const void *pcm, NSUInteger len, BOOL eof);

// ---------- خط لوله ----------
// بعد از پایان آپلود، این‌قدر ثانیه هیچ فریمی نیاید یعنی سرور کارش تمام است. و این
// سقف سخت که یک سشنِ نامتعارف کل صف را گرو نگیرد.
#define kZSegQuietWaitSec 3.0
#define kZSegHardWaitSec 15.0

BOOL ZSegHasVoice(NSData *pcm);
// یک تکه، یک سشن، یک متن. بلوکه است: فقط از نخ پس‌زمینه.
NSString *ZTranscribeSegment(NSData *pcm, NSString *lang, BOOL rawUpload,
                             unsigned long long *bytesUp);

// ---------- جای خالی ----------
// تکه‌ای که حرف داشت و بی‌متن برگشت.
//
// یک قاعده همه‌ی این بخش را ساده می‌کند و باید صریح نوشته شود: `ZSegHasVoice` پیش از
// هر تماس شبکه‌ای تکه‌های ساکت را رد می‌کند، پس **هر تکه‌ای که به شبکه می‌رسد حرف
// دارد**. یعنی متنِ خالی همیشه شکست است، نه جوابِ درست. با این قاعده نه سنجشِ
// اینترنت لازم است، نه heuristic، نه backoff: خالی یعنی خراب، و بس.
//
// تا امروز همین‌جا حرف گم می‌شد: تکه‌ی بی‌متن از `_parts` می‌افتاد و بقیه به هم
// می‌چسبیدند، پس یک جمله‌ی گم‌شده هیچ ردی نمی‌گذاشت. هفته‌ی گذشته ۱۲ دقیقه از ۲۲۴
// دقیقه دیکته (۱۳۹ تکه) همین‌طور پاک شد و ۳۴ سشن با سوراخِ دوخته‌شده درج شدند.
extern NSString *const ZHoleMark;    // نشانه‌ای که جای متنِ نرسیده می‌نشیند

// صدای یک تکه‌ی جامانده، تا بشود دوباره فرستادش. لایه‌ی ذخیره‌ی تازه‌ای در کار نیست:
// audio.flac کلِ سشن را از قبل روی دیسک دارد و این فقط تا پایانِ همین سشن در حافظه
// می‌ماند.
@interface ZHole : NSObject
- (instancetype)initWithPCM:(NSData *)pcm lang:(NSString *)lang;
@property (nonatomic, readonly) NSData *pcm;
@property (nonatomic, readonly) NSString *lang;
@end

// جاهای خالی را دوباره بفرست. بلوکه است: فقط از نخ پس‌زمینه.
//
// هر کدام که رسید از آرایه برداشته می‌شود و متنش سر جای نشانه‌ی **خودش** می‌نشیند
// (nامین نشانه برای nامین جای خالیِ باقی‌مانده)، نه سر جای اولین نشانه: اگر اولی
// دوباره نرسد و دومی برسد، متنِ دومی حق ندارد جای اولی بنشیند. برمی‌گرداند چند تا
// هنوز مانده‌اند.
//
// `texts` همه‌ی متن‌هایی است که همان نشانه‌ها را با همان ترتیب دارند (متنِ تحویل و
// رونوشتِ خام)، چون یک پر شدن باید در هر دوشان بنشیند.
NSInteger ZRetryHoles(NSMutableArray<ZHole *> *holes, NSArray<NSMutableString *> *texts);

// صدا بده، متن بگیر. منبع صدا (میکروفن یا فایل) بیرون از این می‌ماند، پس مسیر
// زنده و رونویسی فایل واقعا یک پیاده‌سازی دارند نه دو تا.
@interface ZPipe : NSObject
- (instancetype)initWithLang:(NSString *)lang;
@property (nonatomic, readonly) NSString *text;          // تکه‌ها با یک فاصله، و نشانه‌ی جای خالی
@property (nonatomic, readonly) NSInteger degradedCuts;  // چند بار مکثی پیدا نشد
@property (nonatomic, readonly) unsigned long long bytesUp;
@property (nonatomic, copy) void (^onPart)(NSString *text);   // روی صف خط لوله
// تکه‌هایی که حرف داشتند و بی‌متن برگشتند. جایشان در `text` با ZHoleMark علامت خورده.
@property (nonatomic, readonly) NSInteger holes;
// یک تکه بی‌متن برگشت و علامت خورد؛ صدایش همراه است تا بشود دوباره فرستادش.
@property (nonatomic, copy) void (^onHole)(ZHole *hole);      // روی صف خط لوله
// دو تکه‌ی پشت سر هم بی‌متن برگشتند، یعنی اینترنت رفته نه اینکه تکه بد بوده. سرِ
// هر شکستِ بعدی هم می‌آید تا وقتی یکی برسد؛ «یک بار بس است» کارِ مصرف‌کننده است، چون
// فقط او می‌داند به کاربر گفته یا نه.
@property (nonatomic, copy) void (^onLost)(void);             // روی صف خط لوله
- (void)feed:(NSData *)pcm;   // s16le مونو ۱۶ کیلوهرتز
- (void)finish;               // ته‌مانده را ببر و تا خالی شدن صف بمان. بلوکه
- (void)cancel;
// سطل آشغال: متنِ جمع‌شده، صدای نبریده، و **تکه‌های در راه**، هر سه. خط لوله زنده
// می‌ماند و از صفر ادامه می‌دهد. تکه‌ای که همین حالا روی شبکه است متنش دور ریخته
// می‌شود، وگرنه چند ثانیه بعد بی‌صدا برمی‌گشت.
- (void)discard;
@end

// ---------- بافر بک‌لاگ صدا ----------
// سقف _pending استریم (stream.m): چقدر صدای خام می‌تواند روی شبکه ضعیف معطل بماند
// قبل از این‌که قدیمی‌ترینش دور ریخته شود.
#define kZBacklogSec 60
#define kZBacklogCapBytes ((NSUInteger)(32000 * kZBacklogSec))

// ---------- موتور ----------
typedef NS_ENUM(NSInteger, ZEngineState) {
    ZEngineIdle,
    ZEngineConnecting,
    ZEngineListening,
    ZEngineGaveUp,
    ZEnginePaused,
};

// موتور در حین حرف زدن **هیچ متنی نمی‌دهد**، و همین کوتاه‌ترین توضیح تفاوت نسخه دو
// است. قرارداد قبلی یک رونوشتِ زنده بود (`committed` + `pending`) و تمام پیچیدگیِ
// نسخه یک از همان‌جا می‌آمد: متنی که هنوز قطعی نیست روی صفحه می‌نشست، پس باید
// می‌شد پسش گرفت، پس دفتر متن و پاک‌کن و راچت و جوش لازم می‌شد.
//
// حالا دو کانال بیشتر نیست: بلندی صدا (برای نشان)، و یک متن سر پایان.
@protocol ZEngineDelegate <NSObject>
- (void)engineState:(ZEngineState)state message:(NSString *)msg; // پیام فقط برای GaveUp
- (void)engineLevel:(float)rms;                                  // ۰ تا ۱ برای ضربان
// دقیقا یک بار، روی نخ اصلی. `second` متنِ پاس دوم انگلیسی است و معمولا نال.
// `took` ثانیه‌ی «از پایان صدا تا آماده شدن متن» است: بودجه‌ی این عدد ۵ ثانیه است و
// چون در هدر است، اندازه‌گیری‌اش کار حدس نیست.
- (void)engineDidFinish:(NSString *)text second:(NSString *)second took:(NSTimeInterval)took;
@optional
// متنِ **خامِ** پیش‌نمایش، هم‌گام با حرف زدن، روی نخ اصلی. هر بار کلِ متن از نو، نه
// تکه‌ی تازه: مصرف‌کننده فقط جایگزین می‌کند و هیچ حسابی نگه نمی‌دارد.
//
// این از مسیر تشخیص نمی‌آید و هیچ ربطی به متنِ نهایی ندارد (ZPreviewStream پایین‌تر).
// نمایشی است و دور ریختنی، پس هیچ تصمیمی نباید از آن بگذرد.
//
// اختیاری، و عمدا: تنها مصرف‌کننده‌اش رابط کاربری است. مسیر اندازه‌گیری و مسیر دسته‌ای
// نه لازمش دارند نه باید با آمدنش رفتارشان عوض شود.
- (void)enginePreview:(NSString *)text;
// یک تکه بی‌متن برگشت و جایش در متن علامت خورد. روی نخ اصلی و **همان لحظه**، نه سر
// پایان: کاربر هنوز دارد حرف می‌زند و باید همان‌جا بداند یک جمله جا مانده.
//
// صدای تکه همراهش می‌آید و نگه داشتنش کارِ مصرف‌کننده است، چون تنها اوست که می‌داند
// متن کجا رفته و سر Esc باید کجا وصله شود.
- (void)engineHole:(ZHole *)hole;
@end

@class ZRecorder;

// سقف سشن. این ابزار دیکته است نه ضبط جلسه، و صدای بلندتر جای خودش را دارد
// (پنل رونویسی فایل، Command راست + F). سقف یعنی «تمامش کن»، نه «دورش بریز».
#define kZMaxSessionSec 300.0
// صدای سشن برای عیب‌یابی می‌ماند، ولی نه برای همیشه.
#define kZSessionKeepDays 7

// یک موتور، یک کلاس. پروتکل برداشته شد چون فقط یک پیاده‌سازی دارد و پروتکلِ
// تک‌پیاده‌سازی فقط تشریفات است.
@interface ZEngine : NSObject
- (instancetype)initWithLang:(NSString *)lang;
@property (nonatomic, weak) id<ZEngineDelegate> delegate;
// ضبطِ سشن. موتور هر تکه‌ی صدا را همان‌جا به این هم می‌دهد، و بس: «کجا نوشته شود»
// تصمیم خودِ ضبط‌کننده است.
@property (nonatomic, strong) ZRecorder *recorder;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) BOOL cappedOut;      // سقف پنج دقیقه خودش تمامش کرد
@property (nonatomic, readonly) NSTimeInterval seconds;
@property (nonatomic, readonly) NSInteger degradedCuts;
// مسیر فایل پیش‌نمایش ندارد (آدمی پشتش نیست و ابزار اندازه‌گیری نباید تماس شبکه‌ی
// اضافه در حسابش بیاورد). این تنها راهِ روشن کردنش آنجاست، و فقط یک مصرف‌کننده دارد:
// `--livewav --preview`، که ادعای «پیش‌نمایش کار می‌کند» را بی‌میکروفن قابل تکرار کند.
@property (nonatomic) BOOL previewInFileMode;
- (BOOL)startWithError:(NSError **)err;
// همان موتور، ولی صدا از یک بافر می‌آید نه از میکروفن. هیچ میان‌بری نمی‌زند: همان
// تکه‌های ۱۰۰ میلی‌ثانیه‌ای و همان خط لوله. speed=۱ یعنی زمان واقعی، ۰ یعنی تندترین.
// شرط سخت این بازنویسی است: هر ادعای سرتاسری باید بی‌میکروفن و بی‌آدم تکرار شود.
- (BOOL)startFromPCM:(NSData *)pcm speed:(double)speed error:(NSError **)err;
- (void)pause;     // شنیدن می‌ایستد؛ میکروفن گرم می‌ماند که ادامه آنی باشد
- (void)resume;
// زبان را وسط همین سشن عوض کن، هر چند بار که لازم شد. صدای گفته‌شده تا این لحظه با
// زبان قبلی رونویسی می‌شود و صدای بعدی با زبان تازه؛ متن هر دو سر پایان به ترتیب
// به هم می‌چسبد. بلوکه نیست: نخ اصلی وسط دیکته نمی‌ایستد.
- (void)switchLang:(NSString *)lang;
- (void)stop;      // آسنکرون: صف خالی می‌شود و بعد engineDidFinish: می‌آید
- (void)cancel;    // دور ریختن: نه متنی، نه صدایی
- (void)resetClock;   // سطل آشغال: شمارنده هم از صفر
- (void)resetPreview; // و دُم خاکستری هم از صفر، وگرنه حرفِ دورریخته برمی‌گردد
// و متن، که جای دیگری زندگی می‌کند: داخل خط لوله‌ها، از جمله بازنشسته‌ها. بی این،
// «دور ریختن» فقط متنِ سشن را پاک می‌کرد و همان حرف‌ها سر پایان از خط لوله برمی‌گشتند
- (void)discardText;
@end

// جاروی سشن‌های قدیمی‌تر از kZSessionKeepDays. سر لانچ و بی‌صدا.
void ZSweepOldSessions(void);

// ---------- تاریخچه‌ی متن‌های تحویل‌شده ----------
// خانه‌ی خودِ اپ برای هر متنی که واقعا به دست کاربر رسیده. کلیپ‌بورد و درج هر دو
// بیرون از دست ما هستند، و `sessions/<تاریخ>/text.txt` هفت‌روزه جارو می‌شود؛ این
// یکی همان لحظه‌ی تحویل نوشته می‌شود و شصت روز می‌ماند. شکل و دلیلِ فرمت: history.m
#define kZHistoryKeepDays 60
#define kZHistoryPanelRows 20    // چند ردیف در پنل دیده می‌شود؛ بقیه در خودِ فایل

extern NSString *const ZHistoryViaAuto;     // پایان یا مکثِ سشن
extern NSString *const ZHistoryViaCopy;     // دکمه‌ی کپی
extern NSString *const ZHistoryViaInsert;   // دکمه‌ی درج

@interface ZHistoryEntry : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *sid;    // نام پوشه‌ی سشن؛ پلِ برگشت به صدا و متنِ خام
@property (nonatomic, copy) NSString *via;
@property (nonatomic, copy) NSString *app;    // اپی که متن قرار بود در آن بنشیند
@property (nonatomic, strong) NSDate *at;
@end

NSURL *ZHistoryFile(void);    // ~/Library/Application Support/Zemzeme/history.jsonl
// یک رکورد به ته فایل. هر تحویل یک عکسِ کامل از متنِ سشن است؛ خواننده با sid
// جمعشان می‌کند و تازه‌ترین را نگه می‌دارد، پس فایل افزودنیِ خالص می‌ماند.
void ZHistoryAppend(NSString *text, NSString *sid, NSString *via, NSString *app);
// تازه‌ترین‌ها، نو به کهنه، یکی به ازای هر سشن.
NSArray<ZHistoryEntry *> *ZHistoryRecent(NSUInteger max);
// روزی یک بار، بی‌صدا: رکوردها و خطوط لاگِ قدیمی‌تر از historyKeepDays می‌روند.
void ZHistorySweepIfDue(void);

// همان سه تا، ولی روی یک فایلِ دلخواه. تنها مصرف‌کننده‌شان تست طلایی است
// (tools/history_test.sh)، که باید روی فایل خودش کار کند نه روی تاریخچه‌ی کاربر.
void ZHistoryAppendTo(NSURL *file, NSString *text, NSString *sid, NSString *via, NSString *app);
NSArray<ZHistoryEntry *> *ZHistoryRecentIn(NSURL *file, NSUInteger max);
NSUInteger ZHistorySweepFile(NSURL *file, NSDate *cutoff);

// رکوردِ تازه نشست. پنجره‌ی بازِ تاریخچه با همین خودش را تازه می‌کند، وگرنه یک عکسِ
// کهنه می‌ماند و کاربر فکر می‌کند دیکته‌اش ثبت نشده.
extern NSString *const ZHistoryDidChangeNotification;

// پنجره‌ی مرور: بیست متن آخر، هر ردیف با یک دکمه‌ی درج و یک دکمه‌ی کپی. عمدا
// nonactivating است تا کرسرِ کاربر از جایش کنده نشود؛ دلیل کامل در historyui.m.
@interface ZHistoryPanel : NSObject
+ (instancetype)shared;
- (void)toggle;
- (void)show;
- (void)hide;
- (BOOL)visible;
- (void)makeShots:(NSString *)dir then:(void (^)(void))done;   // history.png برای بازبینی طراحی
// zemzeme --historycheck: دکمه‌های واقعیِ ردیف اول را می‌زند و می‌سنجد چه روی
// کلیپ‌بورد نشست. از بیرون نمی‌شود زد (اجازه‌ی دسترسی کمکی مالِ خودِ اپ است).
- (void)runCheck:(void (^)(int fails))done;
@end

// zemzeme --livewav <file.wav> [--lang] [--speed] [--ref] | --livewav --table
int ZLiveWavMain(NSArray<NSString *> *args);
// zemzeme --aipass <متن.txt|-> [--second متن-en.txt]. تنها مسیری که چیزی از دستگاه
// بیرون می‌فرستد، پس باید بشود بی‌سشن و بی‌آدم دقیقا دید چه رفت و چه برگشت.
int ZAIPassMain(NSArray<NSString *> *args);
// zemzeme --checkkey: همان کلیدسنجی که منو می‌زند، روی کلیدِ ذخیره‌شده، بی‌پنجره.
// کلید از این فایل بیرون نمی‌رود، پس خودِ خروجی هم اینجا چاپ می‌شود نه در فراخوان.
int ZCheckKeyMain(void);

// ---------- فشرده‌ساز FLAC برای آپلود ----------
// پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز را با AudioConverter سیستم (AudioToolbox) به
// فریم‌های FLAC می‌فشرد. اگر ساخت کانورتر شکست بخورد، init نال برمی‌گرداند و فراخوان
// (ZGoogleStream) باید بی‌سروصدا به آپلود خام l16 برگردد.
@interface ZFlacEncoder : NSObject
@property (nonatomic, readonly) NSData *streamHeader;   // "fLaC" + بلاک STREAMINFO؛ فقط یک‌بار، اول بدنه
@property (nonatomic, readonly) UInt32 blockFrames;     // نمونه در هر بلاک؛ ته‌مانده با سکوت تا همین پر می‌شود
- (NSData *)encode:(NSData *)pcm;   // ممکن است خالی برگردد (هنوز یک فریم کامل جمع نشده)
@end

// ---------- ضبط صدای سشن روی دیسک ----------
// یک فایل FLAC کنار متن هر سشن، با همان انکودری که مسیر آپلود زنده استفاده می‌کند
// (روی گفتار ~۵۴٪ حجم خام). چرا FLAC و نه WAV: نصف حجم، و خودِ جمینای مستقیم
// می‌خوانَدش، پس هیچ تبدیلی در مسیر پاس نهایی لازم نیست.
//
// فایل تنبل ساخته می‌شود، سرِ اولین بایت: موتوری که میکروفن ندارد یا سشنی که یک
// ثانیه هم صدا نگرفت، فایل خالی روی دیسک جا نمی‌گذارد و `url` نال می‌ماند.
// feed: از نخ صداست و بقیه از نخ اصلی، پس همه‌چیز پشت یک قفل است.
@interface ZRecorder : NSObject
- (instancetype)initWithURL:(NSURL *)url;
@property (nonatomic, readonly) NSURL *url;              // نال تا اولین بایت صدا
@property (nonatomic, readonly) NSTimeInterval seconds;  // از بایت‌های خام، نه ساعت دیوار
@property (nonatomic, readonly) unsigned long long fileBytes;
- (void)feed:(NSData *)pcm;   // s16le مونو ۱۶ کیلوهرتز، از نخ صدا
// ته‌مانده‌ی کمتر از یک بلاک با سکوت پر و فریم می‌شود، وگرنه تا ~۲۹۰ میلی‌ثانیه‌ی آخر
// (یعنی ممکن است آخرین کلمه) هیچ‌وقت وارد فایل نمی‌شد. بعد از این، feed بی‌اثر است.
- (void)finish;
// سطل آشغال: هرچه تا اینجا ضبط شده از روی دیسک هم برود، و ضبط از همین لحظه از صفر
// ادامه پیدا کند. تنها جایی که صدا حق دارد پاک شود، و عمدا صریح است: «دور بریز» اگر
// صدا را نگه دارد، پاس نهایی همان حرف‌های دورریخته را برمی‌گرداند.
- (void)discard;
@end

// ---------- استریم full-duplex گوگل ----------
@interface ZGoogleStream : NSObject
@property (nonatomic, readonly) NSString *pair;
@property (nonatomic, readonly) NSString *codecName;            // "flac" یا "l16"؛ بعد از connect معتبر است
@property (atomic, readonly) unsigned long long bytesFed;        // بایت واقعی نوشته‌شده روی سیم (برای لاگ نرخ)
@property (nonatomic, copy) void (^onEvent)(ZSpeechEvent *ev);   // روی صف دلیگیت URLSession
@property (nonatomic, copy) void (^onClose)(NSString *reason);   // دقیقا یک بار
// سقفِ صدای معطل روی شبکه‌ی کند، پیش‌فرض kZBacklogCapBytes. استریم نمایشی عمدا خیلی
// کوچک‌ترش می‌کند تا **اول خودش** عقب بکشد و سر پهنای باند با مسیر کیفیت دعوا نکند.
@property (nonatomic) NSUInteger backlogCap;
// آپلود خام l16 حتی اگر تنظیم FLAC روشن باشد؛ قبل از connect ست می‌شود. مسیر دسته‌ای
// این را می‌خواهد: انکودر FLAC سر finishUpload تا ~۲۵۰ms ته‌مانده را فریم نمی‌کند و
// در فایل ۹۰ دقیقه‌ای این یعنی صدها بار «آخر پاره» غیرقطعی. خام، قطعی است.
@property (nonatomic) BOOL rawUpload;
- (instancetype)initWithLang:(NSString *)lang;
- (void)connect;
- (void)feed:(NSData *)pcm;      // s16le مونو ۱۶ کیلوهرتز
- (void)finishUpload;            // پایان نرم: نتیجه‌های آخر می‌آیند
- (void)cancel;
@end

// ---------- استریم نمایشی (پیش‌نمایش) ----------
// متن هم‌گام با حرف زدن، سریع و خام، و **کاملا جدا از مسیر کیفیت**. یک سشن پیوسته که
// هر ~۸ ثانیه می‌چرخد (بی چرخش، اندپوینت سر ~۳۰ ثانیه از تشخیص می‌افتد و پیش‌نمایش
// یخ می‌زند). خروجی‌اش فقط به دُم خاکستری پنل می‌رود: نه به متن سشن، نه به درج، نه به
// کپی، نه به دیسک. یک‌طرفه، و همین یک قاعده تضمین می‌کند که نتواند کیفیت را خراب کند.
//
// چرا سشن جدا و نه خودِ خط لوله: برش‌زن تا بافر به دوازده ثانیه نرسد تصمیم نمی‌گیرد
// (seg.m:93) و مرزی که انتخاب می‌کند ~۵ ثانیه عقب‌تر از «الان» است. سشنی که زنده
// تغذیه شود تا وقتی مرز معلوم شود صدای تکه‌ی بعدی را هم بلعیده: هم‌پوشانی، یعنی همان
// درزِ نسخه یک. آن دوازده ثانیه اندازه‌گیری‌شده است و برای متنِ سریع دست نمی‌خورد.
@interface ZPreviewStream : NSObject
- (instancetype)initWithLang:(NSString *)lang;
@property (nonatomic, copy) void (^onText)(NSString *text);   // کلِ متن، هر بار از نو، روی نخ اصلی
- (void)start;
- (void)feed:(NSData *)pcm;   // s16le مونو ۱۶ کیلوهرتز، از نخ صدا
// از صفر: هرچه تا حالا جمع شده دور، و سشن تازه. مالِ سطل آشغال است، وگرنه حرفِ
// دورریخته چند ثانیه بعد دوباره خاکستری برمی‌گشت.
- (void)reset;
- (void)stop;                 // برگشت ندارد: سشن که تمام شد، این هم تمام است
@end

// ---------- میکروفن ----------
@interface ZMic : NSObject
@property (nonatomic, copy) void (^onChunk)(NSData *pcm);        // نخ صدا
@property (nonatomic, copy) void (^onLevel)(float rms);          // نخ صدا
// میکروفن باز شد ولی هیچ صدایی نمی‌آید، و ساختنِ دوباره‌ی موتور هم درستش نکرد. نخ
// اصلی. سکوتِ بی‌خبر بدترین حالت است: کاربر تا آخر حرف می‌زند و متنی نمی‌آید.
@property (nonatomic, copy) void (^onDeaf)(void);                // نخ اصلی
- (BOOL)startWithError:(NSError **)err;
- (void)stop;
@end

// ---------- پاس هوش مصنوعی: فقط روی متن ----------
// **صدا هیچ‌وقت به مدل نمی‌رود، در هیچ حالتی.** نسخه یک کل فایل صدا را آپلود می‌کرد
// و روی کیفیت هم حق داشت (مدل چیزی را می‌شنید که تشخیص گفتار انداخته بود)، ولی آن
// معامله دیگر روی میز نیست: صدای آدم از این دستگاه بیرون نمی‌رود مگر همان جایی که
// برای تشخیص گفتار لازم است.
//
// پس این پاس چه کار می‌کند: فرمتینگ، و اصلاح واژه‌ای که صد در صد غلط است. و اگر پاس
// دوم انگلیسی هم روشن باشد، آشتی دادن دو رونویسیِ همان صدا. اندازه‌گیری روی ضبط ۰۲:
// «او آف» شد OAuth، «ان پلاسمان» شد N+1، «ایگر لودینگ» شد Eager Loading، با ۲۹۷
// توکن ورودی و ۱۴۲ توکن خروجی برای یک دقیقه حرف.
//
// آنچه برنمی‌گرداند: چیزی که هیچ‌کدام از دو موتور نشنیده‌اند. مدل صدا را نشنیده، پس
// این آخرین لایه است نه اولی. پیش‌فرض خاموش، و بی‌کلید هم فقط یک پیام کوتاه.
@interface ZFinalPass : NSObject
+ (instancetype)shared;
// کلید در Keychain (سرویس zemzeme-gemini) یا متغیر محیطی GEMINI_API_KEY. نه در plist،
// نه در ریپو. نبودنش خطا نیست، فقط یعنی فیچر خاموش است و پیامش همین را می‌گوید.
+ (BOOL)hasKey;
// «پرسیدیم و نبود»، در برابر «هنوز نپرسیده‌ایم». hasKey روی نخ اصلی محافظه‌کار است و
// تا جواب نرسیده «نه» می‌گوید، پس برای *هشدار دادن* به کاربر کافی نیست: سشنی که
// همان لحظه‌ی لانچ شروع شود، هشدارِ غلطِ «کلید نیست» می‌گرفت و بعد خودِ پاس درست
// اجرا می‌شد. هشدار فقط با این تابع.
+ (BOOL)keyKnownMissing;
// حالت سوم: کلید شاید هست، ولی ACL آیتمِ کی‌چین این اپ را نمی‌شناسد. رابط هیچ‌وقت
// پنجره‌ی رمز را بالا نمی‌آورد، پس این را می‌گوید تا کاربر بداند چرا خاموش است.
+ (BOOL)keyNeedsPermission;
+ (NSString *)missingKeyHint;
// نوشتن از خودِ اپ (منو، «کلید Gemini…»): چون سازنده‌ی آیتم همین پروسه است، خواندنِ
// بعدی هم از همین پروسه هیچ پنجره‌ی اجازه‌ای باز نمی‌کند؛ دیگر نیازی به ترمینال نیست.
//
// و **پیش از نوشتن، تست می‌شود**: یک درخواست عمدا کوچک به همان اندپوینت و همان مدلی
// که پاس واقعی استفاده می‌کند. دلیلش یک شب واقعی است: چیزی که کلید نبود بی‌صدا ذخیره
// شد، منو تیک «هست» زد، تاگل آبی شد، و هر سشن ۴۰۰ گرفت و متن خام تحویل داد. هزینه‌ی
// تست چند توکن است و جای «روشن است و کار نمی‌کند» را می‌گیرد.
typedef NS_ENUM(NSInteger, ZKeySave) {
    ZKeySaveOK = 0,        // تست شد، کار کرد، نوشته شد
    ZKeySaveUntested,      // نوشته شد، ولی نشد تستش کرد (اینترنت نبود یا سرور بالا نبود)
    ZKeySaveRejected,      // سرور کلید را رد کرد؛ **چیزی نوشته نشد** و کلید قبلی سر جایش است
    ZKeySaveBadInput,      // ورودی شبیه کلید نبود؛ بی رفت‌وبرگشت شبکه رد شد
    ZKeySaveKeychainNo,    // کلید درست بود ولی Keychain نپذیرفتش
    // هیچ جوابی نیامد و سقفِ نگهبان خورد. این حالت را خودِ saveKey برنمی‌گرداند؛ مالِ
    // فراخوان است، و وجودش صریح است چون قاعده صریح است: **هر انتظاری سقف دارد**، و
    // رسیدن به سقف باید یک پیام باشد نه یک چرخنده‌ی ابدی.
    ZKeySaveStuck,
};
// شبکه لازم دارد و بلوکه است، پس **هیچ‌وقت روی نخ اصلی**: تپ کیبورد روی همان نخ
// نشسته و یخ زدنش یعنی Esc و Command راست از کار بیفتند. `msg` همیشه پر می‌شود و
// همان چیزی است که به کاربر نشان داده می‌شود.
+ (ZKeySave)saveKey:(NSString *)key message:(NSString **)msg;
// پاک کردن، با **تایید**: جوابِ Keychain چک می‌شود، فال‌بکِ ابزار `security` هست، و
// آخرش دوباره خوانده می‌شود. NO یعنی کلید هنوز آنجاست، و رابط باید همین را بگوید نه
// «پاک شد». بلوکه است (ابزار بیرونی، و شاید پنجره‌ی کی‌چین): از نخ اصلی صدا نزن.
+ (BOOL)clearKeyWithMessage:(NSString **)msg;
- (void)prefetchKey;    // یک بار، آسنکرون: پرسش Keychain نباید سر پایان معطلی بسازد
// همان، ولی با اجازه‌ی پنجره و در یک لحظه‌ی آرام (سرِ روشن کردنِ تاگل). حداکثر یک
// پنجره در هر اجرای اپ، و هیچ‌وقت وسط دیکته.
- (void)warmKeyAllowingUI;
// پاس روی متن. کار روی نخ پس‌زمینه، `done` روی نخ اصلی. `second` متنِ پاس دوم
// انگلیسی است و می‌تواند نال باشد. `out` خالی یعنی هیچ اتفاقی نیفتاد و فراخوان باید
// متن خام خودش را نگه دارد: این پاس هیچ‌وقت حق ندارد نتیجه را گرو بگیرد.
- (void)runOnText:(NSString *)text second:(NSString *)second lang:(NSString *)lang
             done:(void (^)(NSString *out, NSString *err))done;
// ادامه‌ی یک متنِ در حال ساخت: متنِ تمیزِ قبلی به‌اضافه‌ی تکه‌ی خامِ تازه، و خروجی کلِ
// متن از نو. دو ورودیِ جدا و نه یک متنِ سرهم، چون مدل باید بداند کدام قسمت را خودش
// نوشته (دست‌نخورده بماند) و کدام خامِ تشخیص گفتار است (تمیزکاری لازم دارد).
- (void)runOnText:(NSString *)raw appendingTo:(NSString *)previous lang:(NSString *)lang
             done:(void (^)(NSString *out, NSString *err))done;

// ---------- انتقالِ قرضی ----------
// کلید، تلاش دوباره، رفتار ۴۲۹، و پارس پاسخِ اندپوینتِ مستندنشده فقط در همین یک فایل
// نشسته‌اند. پنل رونویسی فایل هم همین را قرض می‌گیرد، پس لایه‌ی دومی ساخته نمی‌شود.
//
// `thinking` صریح است نه پیش‌فرض: این پاس `minimal` می‌خواهد، چون کارش فرمتینگ است و
// توکنِ فکر مثل خروجی پول می‌گیرد.
- (NSString *)askText:(NSString *)system parts:(NSArray<NSString *> *)texts
                label:(NSString *)label thinking:(NSString *)thinking
                usage:(NSMutableDictionary *)usage error:(NSString **)err;
- (NSString *)promptNamed:(NSString *)name;   // نال یعنی فایل در بسته نیست
@end

// ---------- درج ----------
// چطور ثابت شد که پاک کردن امن است. شمارنده‌ها همین را می‌شمارند و معیار پذیرش از
// همین‌جا ثابت می‌شود: تعداد جایگزینی‌ها باید دقیقا برابر مجموع دو مدرک باشد.
typedef NS_ENUM(NSInteger, ZWriteProof) {
    ZProofNone = 0,     // ثابت نشد. هیچ‌چیز پاک نشد
    ZProofRead,         // متن واقعی خوانده و با انتظار تطبیق داده شد
    ZProofUntouched,    // اپ خواندن نمی‌دهد، ولی از آخرین نوشتنِ ما کسی دست نزده
};

// ---------- فلیکِ پنجره‌ی کلید ----------
// یک پنجره‌ی ۱×۱ نامرئی کلید را می‌گیرد و همان‌جا پس می‌دهد، بی این‌که اپِ جلو عوض شود.
// تنها مشتری‌اش پیستِ ریموت است: کلاینت ریموت دسکتاپ کلیپ‌بوردِ مک را فقط سرِ عوض شدنِ
// پنجره‌ی کلید به سرور می‌فرستد (شرحِ اندازه‌گیری‌اش در inject.m). بلوکه است، پس نباید
// روی نخ اصلی صدا زده شود.
@interface ZKeyFlick : NSObject
+ (void)flick;
@end

// یک رویدادِ کیبورد این‌قدر واحد UTF-16 می‌برد. مرزِ «می‌تواند نصفه بیفتد» همین است.
#define kZEventUnits 18

// انتخابِ مسیرِ نوشتن، به‌صورت یک تابعِ **خالص** و در هدر، تا هم کنارِ قراردادش بنشیند و
// هم بی هیچ لینکی آزمودنی باشد (tools/insert_test.m). دلیلِ جدا بودنش تشریفات نیست:
// همین تصمیم یک بار بی‌صدا از کد افتاد و سه خط توضیحِ بالای سرش وعده‌ی چیزی را می‌داد
// که کد اجرا نمی‌کرد. یک تابعِ نام‌دار با یک جدولِ تست، دیگر نمی‌گذارد این تکرار شود.
typedef NS_ENUM(NSInteger, ZWritePath) {
    ZWriteAX = 0,     // نوشتنِ اتمیکِ اکسسبیلیتی
    ZWritePaste,      // کلیپ‌بورد و Command+V
    ZWriteType,       // رگبار رویدادِ یونیکد
};

static inline ZWritePath ZChooseWritePath(BOOL alwaysPaste, BOOL axAvailable, NSUInteger units) {
    if (alwaysPaste) return ZWritePaste;            // ریموت دسکتاپ، بی‌قید و شرط
    if (units < kZEventUnits) {
        // یک رویداد کافی است: نصفه شدن ممکن نیست، پس تایپ امن است و کلیپ‌بورد سالم
        // می‌ماند. AX هم اینجا لازم نیست و هزینه‌اش را نمی‌دهیم.
        return ZWriteType;
    }
    if (axAvailable) return ZWriteAX;
    // بلند است و AX رد شد. تایپ یعنی رگبار، و رگبار یعنی احتمالِ افتادنِ یک رویدادِ
    // کامل (۱۸ واحد) از وسط متن. پیست تنها مسیرِ اتمیکِ باقی‌مانده است.
    return ZWritePaste;
}

@interface ZInjector : NSObject
+ (BOOL)accessibilityOK;
+ (void)promptAccessibility;
+ (BOOL)secureInputActive;
+ (void)copyFinal:(NSString *)text;                     // کپی ماندگار پایانی
- (void)type:(NSString *)text delayMicros:(useconds_t)d;
- (void)paste:(NSString *)text delayMicros:(useconds_t)d;
- (void)copyFinalAfterPending:(NSString *)text;         // پشت صف درج، که مسابقه با پیست نگیرد
// همان type: ولی با خبرِ «نشست»، چون دفتر تا نشستنِ یک عملیات، عملیات بعدی را نمی‌فرستد
- (void)type:(NSString *)text delayMicros:(useconds_t)d done:(void (^)(void))done;
// درجِ اتمیک. متنِ بلندتر از یک رویداد (۱۸ واحد UTF-16) با یک نوشتنِ اکسسبیلیتی
// می‌رود، نه با رگبار رویدادِ ساختگی. دلیلش اندازه‌گیری است نه سلیقه: یک رویدادِ کامل
// را اپ مقصد می‌تواند بیندازد و آن‌وقت دقیقا ۱۸ واحد از وسط متن گم می‌شود. یک نوشتنِ
// AX یا کامل می‌نشیند یا خطا می‌دهد؛ نصفه نمی‌شود. اپی که نپذیرد یک بار امتحان می‌شود
// و دیگر نه.
//
// **متنِ بلندی که نوشتنِ اتمیک را رد کرد، همیشه از پیست می‌رود.** شرط ندارد و
// تنظیم هم ندارد: اپی که نوشتنِ AX را نپذیرفت همان اپی است که رگبارِ رویداد را هم
// کامل نمی‌گیرد، و آنجا انتخاب بین «پیست» و «تایپ» نیست، بین «متن» و «متنِ قیچی‌شده»
// است. اندازه‌گیری‌اش: یک بولتِ کامل از وسط یک فهرست غیب شد، دقیقا ۱۸ واحد UTF-16،
// یعنی یک رویدادِ کامل. کلیپ‌بورد هم چیزی نمی‌بازد، چون هر مسیرِ تحویل پیش از درج
// `copyFinal:` را صدا زده و همین متن از قبل رویش هست.
//
// متنِ کوتاه‌تر از یک رویداد (۱۸ واحد) تایپ می‌شود: نصفه شدنش ممکن نیست و کلیپ‌بورد
// دست‌نخورده می‌ماند.
//
// `pasteIfRefused` حالا فقط یک معنی دارد: «این اپ **همیشه** پیست می‌خواهد، حتی برای
// متنِ کوتاه». تنها مشتری‌اش ریموت دسکتاپ است.
- (void)insert:(NSString *)text pid:(pid_t)pid delayMicros:(useconds_t)d
 pasteIfRefused:(BOOL)pasteIfRefused done:(void (^)(BOOL viaAX))done;

// جایگزینیِ تاییدشده. `expected` باید همین حالا واقعا دمِ متن باشد؛ اگر نبود هیچ‌چیز
// پاک نمی‌شود و ZProofNone برمی‌گردد. مسیر ترجیحی یک عملِ اکسسبیلیتی است (رنجِ انتخاب
// را می‌گذارد و متن را می‌نویسد): بی Backspace، بی رویداد مصنوعی، بی خطر مودیفایر.
// اپی که نوشتنِ AX را نپذیرد به همان مسیر کلیدی می‌افتد، ولی فقط روی ناحیه‌ی تاییدشده.
@end

// ---------- تپ کیبورد سراسری: Esc و همه‌ی کارهای Command راست ----------
// یک CGEventTap واحد برای کل اپ؛ از لانچ تا کوییت زنده می‌ماند (نه هر سشن یک تپ نو).
// دابل‌تپ Command راست (شروع/پایان سشن) در هر حالتی کار می‌کند؛ بقیه (Esc، تک‌تپ،
// Command راست+C) فقط وقتی sessionActive=YES باشد.
@interface ZHotkeyTap : NSObject
// همه‌ی میان‌برها روی Command راست سوار شده‌اند و جای دیگری ندارند: تک‌تپ مکث/ادامه،
// دابل‌تپ شروع/پایان، و Command راست + یک حرف برای هر دکمه. مسیر دوم ⌥ برداشته شد،
// چون یک تپ سراسری هر ترکیبی را که بگیرد از اپ‌های دیگر می‌دزدد و ⌥ جای شلوغی بود.
@property (nonatomic, copy) void (^onToggle)(void);        // دابل‌تپ Command راست
// Esc، با اولویت: کارت راهنما باز است ببندش، وگرنه سشن را تمام کن. جواب YES یعنی
// رویداد مصرف شد و به اپ زیرین نمی‌رسد؛ NO یعنی Esc مال ما نبود، دست‌نخورده رد شود
// (بیرون از سشن و بی‌کارتِ باز، Esc نباید از vim و بقیه دزدیده شود). هم‌زمان (نه
// dispatch) صدا زده می‌شود، چون تصمیم «بلعیدن یا نه» تاخیر نمی‌پذیرد؛ تپ خودش روی
// نخ اصلی نشسته، پس امن است.
@property (nonatomic, copy) BOOL (^onEscape)(void);
@property (nonatomic, copy) void (^onHelp)(void);           // H: کارت راهنما، در سشن و بیرونش
@property (nonatomic, copy) void (^onAIPass)(void);         // A: روشن/خاموش کردن پاس هوش مصنوعی
// تک‌تپ Command راست. در نسخه یک یعنی مکث بود؛ حالا یعنی **پایان**. دلیلش سر
// session.m نوشته شده: کاربر باید راهی ساده برای گفتن «حرفم تمام شد» داشته باشد و
// آن راه باید همان کلیدی باشد که دستش رویش است.
@property (nonatomic, copy) void (^onPauseToggle)(void);
@property (nonatomic, copy) void (^onPause)(void);          // Space: مکث و ادامه
@property (nonatomic, copy) void (^onCopyNow)(void);        // C
@property (nonatomic, copy) void (^onInsertHere)(void);     // I (نه V: V مال تاریخچه‌ی کلیپ‌بورد است)
@property (nonatomic, copy) void (^onTrash)(void);          // D
@property (nonatomic, copy) void (^onLangSwitch)(void);     // L
@property (nonatomic, copy) void (^onModeToggle)(void);     // E
// F: پنل رونویسی فایل. تنها میان‌بری که بی‌سشن هم کار می‌کند، چون به سشن ربطی ندارد
@property (nonatomic, copy) void (^onFilePanel)(void);      // F
// T: پنجره‌ی تاریخچه. مثل F و H بی‌سشن هم کار می‌کند، و بیشترِ وقت‌ها دقیقا همان‌جا
// لازم می‌شود: کسی که دنبال متنِ گم‌شده می‌گردد، سشنی ندارد که از داخلش بازش کند.
@property (nonatomic, copy) void (^onHistory)(void);        // T
@property (nonatomic, copy) void (^onSensToggle)(void);     // S
// B: همین صدا را انگلیسی هم بشنو. مثل A بی‌سشن هم کار می‌کند، چون تنظیم است نه کارِ
// سشن. «نگه داشتن صدا» عمدا میان‌بر ندارد: یک ترجیحِ یک‌باره است و جایش «پیشرفته».
@property (nonatomic, copy) void (^onSecondPass)(void);     // B
@property (nonatomic, copy) void (^onPreview)(void);        // P: مثل A و B یک تنظیم است، پس بی‌سشن هم کار می‌کند
@property (nonatomic) BOOL sessionActive;
@property (nonatomic, readonly) BOOL enabled;   // تپ واقعا بالا است، نه فقط enable صدا خورده
- (void)enable;
- (void)disable;
@end

// ---------- پس‌زمینه‌ی شیشه‌ای قابل‌کشیدن ----------
// NSVisualEffectView به‌خودی‌خود opaque حساب می‌شود و mouseDownCanMoveWindow پیش‌فرض
// NO می‌دهد، پس movableByWindowBackground روی هیچ پیکسلی اثر ندارد. این زیرکلاس صریحا
// اجازه‌ی کشیدن می‌دهد. هم نوار شناور از آن است هم کارت میان‌برها.
@interface ZDragEffectView : NSVisualEffectView
@end

// ---------- کارت میان‌برها ----------
// یک پنجره‌ی کوچک مرجع (چیت‌شیت): هر کار با آیکون خودش، کلیدها به شکل کی‌کپ، چیدمان
// راست‌به‌چپ. جای فهرستِ داخل منو را گرفت: آن فهرست مجبور بود غیرفعال باشد، پس مک
// خاکستری‌اش می‌کشید، و فارسی و لاتینِ یک‌خطی هم جابه‌جا خوانده می‌شد.
@interface ZCheatSheet : NSObject
+ (void)toggle;                  // باز اگر بسته است، بسته اگر باز است
+ (BOOL)visible;
+ (void)close;
+ (void)shot:(NSString *)dir;    // cheatsheet.png برای بازبینی طراحی (--uishot)
@end

// ---------- پنل ----------
@interface ZPanelModel : NSObject
@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL listening;
@property (nonatomic) BOOL paused;
@property (nonatomic) BOOL error;       // gaveUp: دکمه مکث می‌شود «تلاش دوباره»
@property (nonatomic, copy) NSString *lang;
@property (nonatomic) ZMode mode;
// در نسخه دو هیچ متنی در حین حرف زدن نمی‌آید، پس بی این دو پنل مرده به نظر می‌رسد
// و آدم نمی‌فهمد اصلا شنیده می‌شود یا نه. بدترین حالتِ این طراحی همان است.
@property (nonatomic) NSTimeInterval elapsed;       // دورِ فعلی، زنده؛ صفر یعنی نشان نده
@property (nonatomic) NSTimeInterval elapsedTotal;  // روی هم، همه‌ی دورهای این سشن
@property (nonatomic) NSInteger rounds;             // چند دور شنیدن؛ صفر یعنی هنوز دورِ اول
// دو انتظار داریم و کاربر باید بی‌خواندن بفهمد کدام است، چون طولشان و دلیلشان فرق
// دارد: یکی چند ثانیه است و مالِ خودِ دیکته، آن یکی تا ~۲۰ ثانیه و مالِ یک تنظیمِ
// اختیاری. یک چرخنده‌ی خاکستری برای هر دو، فقط می‌گفت «یک چیزی دارد کار می‌کند» و
// همین کافی نبود. پس هر کدام شکلِ کارِ خودش را دارد: میله‌های صدا، و جرقه.
typedef NS_ENUM(NSInteger, ZBusy) {
    ZBusyNone = 0,
    ZBusySpeech,     // صدا دارد متن می‌شود (خط لوله در حال خالی شدن)
    ZBusyPolish,     // پاس هوش مصنوعی روی متن
};

@property (nonatomic) ZBusy busy;                // کاری در جریان است، و کدام کار
@property (nonatomic, copy) NSString *workingMsg;
// سشن تمام شده ولی پنل با متن نهایی باز مانده تا خوانده و ویرایش شود. دکمه‌های
// شنیدن می‌روند، دکمه‌های متن می‌مانند.
@property (nonatomic) BOOL review;
@end

// رنگ وضعیت، یک منبع حقیقت: نشان روی پنل، نشانگر کنار کرسر و آیتم منوبار هر سه
// از همین می‌خوانند، پس معنی سبز/قرمز/نارنجی/خاکستری جایی واگرا نمی‌شود.
NSColor *ZStatusColor(ZPanelModel *m);

// ---------- نشان زمزمه (mark.m) ----------
// حباب گفتار با سه میله‌ی صدای خالی‌شده از دلش: «حرف می‌زنی، پیام می‌شود». یک
// تعریف برداری برای همه جا؛ پهن‌تر از بلندی‌اش است (نسبت ZMarkAspect)، پس هر
// جایی که وسط‌چین می‌کند باید عرض را جدا حساب کند نه با یک ثابت مربع.
extern const CGFloat ZMarkAspect;
void ZMarkDraw(NSRect box, NSColor *color);     // وسط box، با حفظ نسبت
NSImage *ZMarkImage(CGFloat height, NSColor *tint);  // نال یعنی template برای منوبار بی‌کار
int ZMarkIconMain(NSString *dir);               // iconset آیکون بسته، برای build.sh
void ZMarkShot(NSString *dir);                  // mark.png برای --uishot

// ویوی نشان: جای NSView رنگی قبلی. رنگ که عوض شود خودش دوباره می‌کشد؛ ضربان و
// مقیاس بلندی صدا مثل قبل روی layer همین ویو سوارند.
@interface ZMarkView : NSView
@property (nonatomic, strong) NSColor *color;
@end

// ---------- نشانگر کنار کرسر (حالت کرسر) ----------
// پنجره‌ی ۲۲ نقطه‌ای بدون قاب که فقط نشانِ وضعیت در خود دارد و زیر کرسرِ اپِ فوکس‌دار
// می‌نشیند. نه فوکس می‌گیرد نه کلیک (`ignoresMouseEvents`)، پس کلیک روی همان نقطه به
// اپ زیرین می‌رسد. جای کرسر با اکسسبیلیتی و روی نخ پس‌زمینه پرسیده می‌شود (۶ هرتز)،
// چون هر فراخوان AX می‌تواند کند باشد یا اصلا جواب ندهد؛ نردبانی از تِکست مارکر تا
// قابِ پنجره دارد و هیچ‌وقت ناپدید نمی‌شود: تا سشن زنده است باید پیدا باشد. کرسر
// پیدا نشود، نشان مثل بَجِ Grammarly گوشه‌ی باکس تایپ می‌ایستد، نه وسطش.
@interface ZCaretDot : NSObject
- (void)show;                     // پنجره را بالا می‌آورد و دنبال کردن کرسر را شروع می‌کند
- (void)hide;                     // تایمر همان لحظه می‌ایستد
- (void)render:(ZPanelModel *)m;  // فقط رنگ و ضربان وضعیت
- (void)pulseLevel:(float)level;
@end

// عنصر فوکس‌دارِ اپِ جلویی، کش‌شده و با تعویض اپ باطل. دو مصرف دارد و عمدا یک
// پیاده‌سازی: نشانگر کنار کرسر، و تاییدِ درج پیش از هر پاک کردن. فراخوان CFRelease
// می‌کند. نال یعنی اپ چیزی نداد و تاییدِ خواندنی ممکن نیست.
AXUIElementRef ZCopyFocusedElement(pid_t frontPid) CF_RETURNS_RETAINED;
void ZInvalidateFocusCache(void);

// ورودیِ غیرِ خودمان (کلید کاربر، کلیک). تنها راهِ ثابت کردنِ «کسی دست نزده» در اپی
// که خواندنِ AX ندارد، مثل ریموت دسکتاپ. رویدادهای خودمان با kCGEventSourceUserData
// علامت می‌خورند و اینجا حساب نمی‌شوند، وگرنه هر تایپِ خودمان مدرک را باطل می‌کرد.
void ZNoteForeignInput(void);
CFAbsoluteTime ZLastForeignInputAt(void);

// ابزار اندازه‌گیری همان نردبان، بی هیچ سشن دیکته‌ای: نردبان یک بار روی اپِ فوکس‌دار
// اجرا می‌شود و چاپ می‌کند چه صفت‌هایی موجود بود، هر پله چه قابی داد و کدام زد.
// zemzeme --caretprobe [ثانیه‌ی صبر] [--watch]
int ZCaretProbeMain(NSArray<NSString *> *args);

// نوار پنل همه‌ی یازده دکمه را دارد و همان‌جا می‌ماند: دستِ کاربر روی پنل است، پس
// هر کاری که وسط دیکته به ذهنش می‌رسد باید همان‌جا یک کلیک باشد. مرتب کردن، کارِ
// منوی منوبار است نه کم کردن این‌ها.
// پنجره‌ی پنل. فقط برای اینکه `canBecomeKeyWindow` را YES کند: پنجره‌ی borderless
// پیش‌فرض NO می‌دهد و همان یک پیش‌فرض بود که ادیتورِ پنل را غیرقابل‌ویرایش کرده بود.
@interface ZPanelWindow : NSPanel
@end

@interface ZPanel : NSObject
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onPauseToggle)(void);   // دکمه‌ی مکث؛ تک‌تپ کلید یعنی پایان، نه مکث
@property (nonatomic, copy) void (^onCopyNow)(void);
@property (nonatomic, copy) void (^onTrash)(void);      // دور ریختن
@property (nonatomic, copy) void (^onInsertAll)(void);  // درج متنِ پنل سر کرسر
@property (nonatomic, copy) void (^onLangSwitch)(void); // چرخش زبان
@property (nonatomic, copy) void (^onModeToggle)(void); // چرخش حالت: جمع ← کرسر
@property (nonatomic, copy) void (^onFilePanel)(void);  // باز کردن پنل رونویسی فایل
@property (nonatomic, copy) void (^onHistory)(void);    // باز کردن پنجره‌ی تاریخچه
@property (nonatomic, copy) void (^onSensToggle)(void); // حساسیت بالای میکروفن
// راهنما از خود نوار. در نسخه یک اختیاری بود چون کاربر لازم نبود چیزی بداند؛ حالا
// باید بداند تک‌تپ یعنی پایان، پس کارت باید از خودِ پنل هم پیدا شود.
@property (nonatomic, copy) void (^onHelp)(void);
@property (nonatomic, copy) void (^onAIToggle)(void);   // A: روشن/خاموش کردن پاس هوش مصنوعی
@property (nonatomic, copy) void (^onSecondPass)(void); // B: شنیدنِ دوزبانه، سومین تاگلِ نوار
@property (nonatomic, copy) void (^onPreview)(void);    // P: پیش‌نمایش تکه‌ها حین حرف زدن
- (void)show;
- (void)hide;
- (void)render:(ZPanelModel *)m;
- (void)pulseLevel:(float)level;
// **پیش از هر درجی صدا زده می‌شود، و بندِ حیاتیِ فوکوس‌دار شدنِ پنل است.** رویدادِ
// پیست با `CGEventPost(kCGSessionEventTap, …)` می‌رود، یعنی به هر که فوکوس دارد، نه
// به یک pid. پس اگر ادیتورِ خودمان پنجره‌ی کلید باشد، `Cmd+V` متن را در همین پنل
// می‌ریزد نه در اپ مقصد. اینجا کلید پس داده می‌شود تا مقصد دوباره فوکوس بگیرد.
- (void)yieldKey;
// ادیتور حالت جمع: متن سر پایان یک بار اینجا می‌نشیند، و با یک کلیک روی متن قابل
// ویرایش است.
- (NSString *)editorText;
// کاربر خودش تایپ کرده؟ مسیر تحویل باید **پیش از** نوشتنِ متن تازه بپرسدش، وگرنه
// نوشتن، تایپِ کاربر را پاک می‌کند و پس‌خواندنِ بعدش همان خام را برمی‌گرداند.
- (BOOL)editorTouched;
- (void)setEditorText:(NSString *)text;   // متنِ **تمام‌شده**: سفید، و دُم پیش‌نمایش را می‌بلعد
- (void)clearEditor;
// دُمِ خاکستری ته ادیتور: تکه‌هایی که رسیده‌اند ولی سشن هنوز تمام نشده. نال یا خالی
// یعنی پاکش کن. رنگ تنها معنی‌اش همین است: خاکستری یعنی هنوز تمام نشده، سفید یعنی
// تمام شد. پس اگر پاس هوش مصنوعی روشن باشد، خاکستری تا نشستنِ آن پاس می‌ماند.
//
// هرگز روی متنِ کاربر نمی‌نویسد: هرچه نوشته را عینا به یاد دارد و اگر دُم دیگر همان
// نبود (یعنی کاربر خودش تایپ کرده)، رهایش می‌کند و تا نوشتنِ کاملِ بعدی ساکت می‌ماند.
- (void)setPreviewText:(NSString *)text;
- (void)flash:(NSString *)msg;    // فیدبک کوتاه کار روی خط وضعیت
- (void)makeShots:(NSString *)dir;
@end

// ---------- سشن ----------
// از دابل‌تپ تا متن. در حین حرف زدن هیچ متنی نشان داده نمی‌شود، فقط نشانِ شنیدن؛
// سر پایان، یک بار، کل متن. شرحش سر session.m.
extern NSString *const ZStopHint;   // «حرفت که تمام شد، یک بار Command راست را بزن»

@interface ZSession : NSObject <ZEngineDelegate>
@property (nonatomic, copy) void (^onFinish)(void);
// هر رندر با همان مدل پنل صدا می‌شود؛ دلیگیت اپ از همین آیتم منوبار را رنگ می‌کند
@property (nonatomic, copy) void (^onModel)(ZPanelModel *m);
@property (nonatomic, strong, readonly) ZEngine *engine;
- (instancetype)initWithEngine:(ZEngine *)engine panel:(ZPanel *)panel;
- (void)start;
- (void)pauseToggle;      // تک‌تپ Command راست و دکمه‌ی مکثِ نوار: پایان
- (void)togglePause;      // فقط Command راست + Space: مکثِ ساده
- (void)copyNow;
- (void)insertHere;       // درج در همین اپ جلویی
- (void)dropPending;      // دور ریختن: در بازبینی متن، وگرنه صدای تا اینجا
- (void)toggleMode;       // جمع ↔ کرسر
- (void)switchLang;       // فارسی/انگلیسی، از سشن بعد
- (void)toggleSensitivity;
- (void)finish;           // پایان: موتور می‌ایستد و متن می‌آید
- (void)finishNow;        // مسیر خروج اپ
@end

// ---------- رونویسی فایل (حالت دسته‌ای، بی‌رابط) ----------
// هر فایلی که AVFoundation باز کند به پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز، تکه‌تکه.
// کل فایل هیچ‌وقت در حافظه نمی‌آید، پس فایل ۹۰ دقیقه‌ای هم به همان چند مگابایت
// فایل کوتاه کار می‌کند.
@interface ZFileDecoder : NSObject
+ (BOOL)supportsPath:(NSString *)path;          // mkv/webm نه: دیمکسر ندارند
// چرا پیام رد شدن هم از همین‌جا: صف رابط باید همان لحظه‌ی افزودن فایل دلیل رد را
// بگوید، نه چند دقیقه بعد وسط اجرا. دو جا نوشتنش یعنی دو پیام واگرا.
+ (NSString *)unsupportedReason:(NSURL *)url;   // نال یعنی قالبش باز می‌شود
@property (nonatomic, readonly) NSTimeInterval duration;
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)err;
- (NSData *)nextChunk:(NSError **)err;          // نال: پایان فایل، یا خطا در err
- (void)cancel;
@end

// یک کار دسته‌ای: چند فایل، به ترتیب، با پیشرفت زنده و لغو تمیز. همان موتور برش و
// سشن و ادغام که مسیر خط فرمان استفاده می‌کند، فقط از بیرون قابل استفاده.
// خروجی هر فایل یک txt کنار خودش است (یا در outDir)؛ متن هر فایل از onFileDone هم
// می‌آید، پس فراخوان می‌تواند یکجا هم سرهمش کند.
@interface ZBatchJob : NSObject
- (instancetype)initWithFiles:(NSArray<NSURL *> *)files lang:(NSString *)lang;
// زبان هر فایل، هم‌ترتیب files؛ نال یا کوتاه‌تر یعنی همان lang کار. صف مخلوط
// (وویس فارسی کنار پادکست انگلیسی) بدون دو بار اجرا همین‌طور ممکن می‌شود.
@property (nonatomic, copy) NSArray<NSString *> *langs;
@property (nonatomic) NSInteger jobs;           // سشن هم‌زمان؛ پیش‌فرض ۲
@property (nonatomic) double speed;             // ضریب تغذیه؛ ۰ یعنی بی‌مکث (پیش‌فرض)
@property (nonatomic) BOOL rawUpload;           // l16 خام به جای FLAC؛ فقط عیب‌یابی
@property (nonatomic) BOOL writeSRT;
@property (nonatomic) BOOL writeTXT;            // پیش‌فرض روشن
@property (nonatomic, copy) NSString *outDir;   // نال: کنار خود فایل
@property (nonatomic, readonly) unsigned long long bytesUp;
@property (nonatomic, readonly) NSInteger degradedCuts;   // برش‌هایی که مکثی پیدا نکردند
@property (nonatomic, copy) void (^onFileProgress)(NSURL *f, double doneSec, double totalSec);
@property (nonatomic, copy) void (^onFileDone)(NSURL *f, NSString *text, NSError *err);
@property (nonatomic, copy) void (^onAllDone)(void);
// جای فایل خروجی، با همان حسابی که خودش می‌کند (برای چاپ مسیر در خط فرمان)
- (NSURL *)outputURLFor:(NSURL *)file ext:(NSString *)ext;
- (void)start;      // نخ پس‌زمینه؛ همه‌ی کال‌بک‌ها روی نخ اصلی
// همین نخ، بلوکه، و کال‌بک‌ها هم همان‌جا. مسیر خط فرمان از این می‌رود: آنجا نه
// NSApplication هست نه ران‌لوپی که بچرخد، پس کال‌بکِ نخ اصلی هیچ‌وقت اجرا نمی‌شد.
- (void)runOnThisThread;
- (void)cancel;     // وسط کار؛ فایلِ در جریان متن نیمه‌اش را برمی‌گرداند و چیزی نوشته نمی‌شود
@end

// خبر «کار دسته‌ای در جریان است/تمام شد» برای آیتم منوبار؛ userInfo[@"running"].
// نوتیفیکیشن و نه دلیگیت، چون پنل نباید چیزی از AppDelegate بداند.
extern NSNotificationName const ZBatchActivity;

// ---------- پنل رونویسی فایل ----------
// پنجره‌ی واقعی (نه نوار شناور): صف فایل با ترتیبِ قابل‌کشیدن، پیشرفت زنده‌ی هر ردیف،
// و متن یکجای قابل ویرایش. یکی بیشتر نیست، چون سه راه دسترسی (منوبار، میان‌بر،
// دکمه‌ی پنل) باید به همان صف و همان کار برسند. بستن پنجره کار در جریان را نمی‌کشد.
@interface ZBatchPanel : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL running;   // کاری در جریان است (برای رنگ منوبار)
- (void)show;
- (void)toggle;    // میان‌بر F: باز اگر بسته، پنهان اگر باز. کارِ در جریان نمی‌ایستد
- (BOOL)isFront;   // پنجره‌ی جلوست؟ تپِ سراسری Esc را از دستش نمی‌گیرد
- (void)addFiles:(NSArray<NSURL *> *)urls;
- (void)makeShots:(NSString *)dir;                                 // حالت‌های نمونه (--uishot)
- (void)makeShots:(NSString *)dir then:(void (^)(void))done;       // پله‌پله، با فرصت رندر
- (void)runShots:(NSString *)dir files:(NSArray<NSURL *> *)files;  // یک اجرای واقعی زیر ذره‌بین
@end

// zemzeme --transcribe <files...> [--lang fa-IR] [--jobs N] [--out DIR] [--srt] [--speed X]
// بی‌رابط و مستقل از اپ منوبار: نه آیتم نوار وضعیت می‌سازد نه اجازه اکسسبیلیتی
// می‌خواهد، و سشن‌هایش (pair های تصادفی خودشان) با دیکته‌ی زنده‌ی در جریان قاطی
// نمی‌شوند. jobs محافظه‌کارانه است که کلید مشترک زیر پای مسیر زنده در نرود.
int ZBatchMain(NSArray<NSString *> *args);

// خودآزمای میکروفن: چند ثانیه از همان مسیر دیکته در یک WAV، برای اندازه گرفتنِ
// بلندی و بریدگی و پهنای باند به‌جای حدس زدنشان.
int ZMicDumpMain(NSString *path, double seconds);
void ZMicDumpReport(NSData *pcm, NSUInteger clipped, NSString *path);
NSString *ZDefaultInputName(void);

// مکِ خودش هم میان‌بر دیکته دارد و می‌شود روی «دو بار Command» گذاشتش، یعنی یک دابل‌تپ
// دو دیکته را باز می‌کند و صدای یک میکروفن بین دو شنونده تقسیم می‌شود. فقط خبر می‌دهیم:
// تنظیمِ سیستم مالِ کاربر است و از تپ هم نمی‌شود بلعیدش بی آنکه Cmd+C را هم ببرد.
BOOL ZMacDictationOnDoubleCommand(void);
void ZMicSetHighSensitivity(BOOL on);   // کشِ اتمیک، تا نخ صدا NSUserDefaults نخواند

// ---------- فونت و سلف‌تست ----------
void ZRegisterFonts(void);
NSFont *ZFont(CGFloat size, BOOL medium);
int ZSelfTest(NSString *file, NSString *lang);
