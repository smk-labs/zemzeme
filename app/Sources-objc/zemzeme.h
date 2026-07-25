// زمزمه: دیکته فارسی شناور روی مک.
// چرا ObjC؟ سوئیفت روی این دستگاه فعلا بیلد نمی‌شود: CLT نصب‌شده (swiftlang-6.2.0.19.9)
// با ماژول‌های همه SDK های موجود (6.2.0.17.14 و قدیمی‌تر) ناسازگار است و بازسازی
// interface ها هم به برخورد modulemap مربوط به SwiftBridging می‌خورد. clang سالم است.
// پورت سوئیفت همین معماری در app/swift-port/ آماده است؛ بعد از تعمیر CLT قابل استفاده.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------- مسیرها، لاگ، اعداد فارسی ----------
NSURL *ZRes(void);           // خواندنی‌های همراه اپ: serve.py, index.html, polish.py
NSURL *ZSupport(void);       // ~/Library/Application Support/Zemzeme: داده، لاگ، venv
NSURL *ZSessionsDir(void);
void ZLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

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
};
void ZPlay(ZSound s);
NSString *ZFaDigits(NSString *s);
NSString *ZTimestampId(void);

// ---------- تنظیمات ----------
typedef NS_ENUM(NSInteger, ZInsertMode) {
    ZInsertType = 0,     // تایپ مستقیم با رویداد یونیکد
    ZInsertPaste = 1,    // پیست تکه‌ای (برای ریموت دسکتاپ امن‌تر)
};

@interface ZSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *lang;         // fa-IR | en-US
@property (nonatomic, copy) NSString *engineName;   // google | chrome
@property (nonatomic) ZInsertMode insertMode;       // روش درج (تایپ/پیست)
@property (nonatomic) BOOL collectMode;             // جمع در پنل به جای درج زنده
@property (nonatomic) BOOL internalHotkey;
@property (nonatomic) BOOL polishEnabled;           // پاس ویرایش فارسی؛ پیش‌فرض روشن
@property (nonatomic) BOOL latinTerms;              // وام‌واژه فنی به لاتین؛ پیش‌فرض خاموش
@property (nonatomic) BOOL soundsEnabled;           // صدای کارها؛ پیش‌فرض روشن
@property (nonatomic) BOOL upstreamFLAC;            // فشرده‌سازی FLAC آپلود؛ پیش‌فرض روشن، اگر انکودر نساخت خودش l16 خام می‌رود
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

// ادغام دو متن با هم‌پوشانی توکنی: دم best با سر cur جوش داده می‌شود، پس نه کلمه‌ای
// گم می‌شود نه دو بار می‌آید. هم موتور زنده (نجات interim) از آن استفاده می‌کند، هم
// مسیر دسته‌ای (درز دو پاره‌ی هم‌پوشان فایل).
NSString *ZMergeInterim(NSString *best, NSString *cur);

// ---------- موتور pluggable ----------
typedef NS_ENUM(NSInteger, ZEngineState) {
    ZEngineIdle,
    ZEngineConnecting,
    ZEngineListening,
    ZEngineReconnecting,
    ZEngineGaveUp,
    ZEnginePageNeeded,
    ZEnginePaused,
};

@protocol ZEngineDelegate <NSObject>
- (void)engineInterim:(NSString *)text;                          // کل متن خاکستری فعلی
- (void)engineFinal:(NSString *)text;                            // یک تکه قطعی
- (void)engineState:(ZEngineState)state message:(NSString *)msg; // پیام فقط برای GaveUp
- (void)engineLevel:(float)rms;                                  // ۰ تا ۱ برای ضربان
@end

@protocol ZEngine <NSObject>
@property (nonatomic, weak) id<ZEngineDelegate> delegate;
@property (nonatomic, readonly) BOOL paused;
- (void)startWithLang:(NSString *)lang;
- (void)setLang:(NSString *)lang;
- (void)pause;     // شنیدن می‌ایستد؛ میکروفن گرم می‌ماند که ادامه آنی باشد
- (void)resume;
- (void)stop;
// انصراف: متن خاکستری و صدای پشتش دور ریخته می‌شوند و شنیدن از همین لحظه ادامه دارد.
// فقط پاک کردن نمایش کافی نیست: سشن در جریان همان صدا را دارد و متن قطعی‌اش را
// می‌فرستد، پس باید قطع شود.
- (void)dropPending;
@end

// ---------- بافر بک‌لاگ صدا ----------
// سقف _pending استریم (stream.m): چقدر صدای خام می‌تواند روی شبکه ضعیف معطل بماند
// قبل از این‌که قدیمی‌ترینش دور ریخته شود.
#define kZBacklogSec 60
#define kZBacklogCapBytes ((NSUInteger)(32000 * kZBacklogSec))

// ---------- بافر بازپخش موتور ----------
// _replay موتور (engines.m) صدای «بعد از آخرین نتیجه» را نگه می‌دارد و سر هر
// ری‌استارت به استریم تازه می‌دهدش. چرا: صدایی که روی سیم رفته ولی گوگل نتیجه‌اش را
// نداده، بدون این بافر برای همیشه گم می‌شود (کاری که _pending نمی‌کند، چون بعد از
// نوشتن روی سیم خالی می‌شود). سر هر نتیجه پاک می‌شود، پس هیچ‌وقت متن تکراری نمی‌سازد.
#define kZReplaySec 12
#define kZReplayCapBytes ((NSUInteger)(32000 * kZReplaySec))

// ---------- چرخش پیش‌دستانه ----------
// اندازه‌گیری روی لاگ واقعی: سشن گوگل حدود ۳۰ ثانیه صدای پیوسته را می‌گیرد و بعد
// بی‌آن‌که اتصال را ببندد از تشخیص می‌افتد. سقف روی «صدای بلعیده‌شده» است نه ساعت
// دیوار: استریمی که با ۸ ثانیه بازپخش شروع شده بود فقط ۱۸ ثانیه دوام آورد، یعنی
// بازپخش از همان بودجه خرج می‌کرد. پس قبل از رسیدن به سقف، نرم و آرام عوضش می‌کنیم:
// آپلود تمام می‌شود، سشن قدیمی برای متن‌های قطعی آخرش زنده می‌ماند، و سشن تازه از صفر
// شروع می‌کند. این‌طور اصلا به گیر کردن نمی‌رسیم و بازپخش برمی‌گردد سر جای واقعی‌اش:
// فقط برای خرابی‌های نادر.
#define kZRotateSec 20.0
#define kZRotateAtFinalSec 12.0

// حرف می‌زند و این‌قدر ثانیه هیچ نتیجه‌ای نمی‌آید: استریم مرده، ولی فریم می‌فرستد.
// واچ‌داگ قدیمی «سکوت رویداد» این حالت را نمی‌دید، چون فریم endpointer/status می‌آمد.
#define kZStallSec 5.0
// و شرط دوم: در همین پنجره دست‌کم این‌قدر ثانیه صدای واقعی بوده باشد. بدون این شرط،
// نویز محیط «آخرین صدا» را تازه نگه می‌داشت و مکث فکر کردن هم ری‌استارت می‌گرفت.
#define kZStallVoiceSec 2.5

// ---------- فشرده‌ساز FLAC برای آپلود ----------
// پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز را با AudioConverter سیستم (AudioToolbox) به
// فریم‌های FLAC می‌فشرد. اگر ساخت کانورتر شکست بخورد، init نال برمی‌گرداند و فراخوان
// (ZGoogleStream) باید بی‌سروصدا به آپلود خام l16 برگردد.
@interface ZFlacEncoder : NSObject
@property (nonatomic, readonly) NSData *streamHeader;   // "fLaC" + بلاک STREAMINFO؛ فقط یک‌بار، اول بدنه
- (NSData *)encode:(NSData *)pcm;   // ممکن است خالی برگردد (هنوز یک فریم کامل جمع نشده)
@end

// ---------- استریم full-duplex گوگل ----------
@interface ZGoogleStream : NSObject
@property (nonatomic, readonly) NSString *pair;
@property (nonatomic, readonly) NSString *codecName;            // "flac" یا "l16"؛ بعد از connect معتبر است
@property (atomic, readonly) unsigned long long bytesFed;        // بایت واقعی نوشته‌شده روی سیم (برای لاگ نرخ)
@property (nonatomic, copy) void (^onEvent)(ZSpeechEvent *ev);   // روی صف دلیگیت URLSession
@property (nonatomic, copy) void (^onClose)(NSString *reason);   // دقیقا یک بار
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

// ---------- میکروفن ----------
@interface ZMic : NSObject
@property (nonatomic, copy) void (^onChunk)(NSData *pcm);        // نخ صدا
@property (nonatomic, copy) void (^onLevel)(float rms);          // نخ صدا
- (BOOL)startWithError:(NSError **)err;
- (void)stop;
@end

// ---------- موتورها ----------
@interface ZGoogleEngine : NSObject <ZEngine>
@end

@interface ZChromeRelayEngine : NSObject <ZEngine>
+ (void)openPage;    // صفحه موتور کروم را در پس‌زمینه باز می‌کند
@end

// ---------- پاس ویرایش ----------
// پل به دیمن گرم polish.py (پورت ۱۷۶۳۶). قرارداد: polish فقط از نخ اصلی صدا زده
// می‌شود، کال‌بک همیشه روی نخ اصلی و حداکثر تا ~۰٫۴ ثانیه می‌آید؛ دیر یا خطا یعنی
// همان متن خام. جواب دیرتر برای همیشه دور ریخته می‌شود (retro-edit ممنوع).
@interface ZPolish : NSObject
+ (instancetype)shared;
- (void)prepare;    // دیمن را بالا بیاور و مدل را گرم کن (آسنکرون، چندبار صدا زدن بی‌ضرر)
- (void)polish:(NSString *)raw completion:(void (^)(NSString *text))done;
// نسخه بلوکه برای مسیر دسته‌ای: نه روی نخ اصلی است نه در مسابقه با تایپ، پس بودجه‌اش
// سخاوتمندتر است و به قرارداد ۳۰۰ میلی‌ثانیه‌ی مسیر زنده کاری ندارد. دیمن نباشد یا
// دیر کند، همان متن خام برمی‌گردد.
- (NSString *)polishSync:(NSString *)raw lang:(NSString *)lang;
@end

// ---------- درج ----------
@interface ZInjector : NSObject
+ (BOOL)accessibilityOK;
+ (void)promptAccessibility;
+ (BOOL)secureInputActive;
+ (void)copyFinal:(NSString *)text;                     // کپی ماندگار پایانی
- (void)type:(NSString *)text delayMicros:(useconds_t)d;
- (void)paste:(NSString *)text delayMicros:(useconds_t)d;
- (void)copyFinalAfterPending:(NSString *)text;         // پشت صف درج، که مسابقه با پیست نگیرد
@end

// ---------- تپ کیبورد سراسری: Esc، شورتکات‌های ⌥، دابل/تک‌تپ Command راست ----------
// یک CGEventTap واحد برای کل اپ؛ از لانچ تا کوییت زنده می‌ماند (نه هر سشن یک تپ نو).
// دابل‌تپ Command راست (شروع/پایان سشن) در هر حالتی کار می‌کند؛ بقیه (Esc، ⌥ها،
// تک‌تپ، Command راست+C) فقط وقتی sessionActive=YES باشد.
@interface ZHotkeyTap : NSObject
// همه‌ی میان‌برها روی Command راست سوار شده‌اند: تک‌تپ مکث/ادامه، دابل‌تپ شروع/پایان،
// و Command راست + یک حرف برای هر دکمه. همان حروف با ⌥ هم کار می‌کنند (عادت قدیمی
// نشکند)، چون هر دو از یک نقشه‌ی واحد (actionForCode:) می‌خوانند.
@property (nonatomic, copy) void (^onToggle)(void);        // دابل‌تپ Command راست
@property (nonatomic, copy) void (^onEsc)(void);            // Esc: پایان و درج
@property (nonatomic, copy) void (^onPauseToggle)(void);    // تک‌تپ Command راست، یا Space
@property (nonatomic, copy) void (^onCopyNow)(void);        // C
@property (nonatomic, copy) void (^onInsertHere)(void);     // V
@property (nonatomic, copy) void (^onTrash)(void);          // D
@property (nonatomic, copy) void (^onLangSwitch)(void);     // L
@property (nonatomic, copy) void (^onModeToggle)(void);     // E
@property (nonatomic, copy) void (^onPolishNow)(void);      // P
@property (nonatomic) BOOL sessionActive;
@property (nonatomic, readonly) BOOL enabled;   // تپ واقعا بالا است، نه فقط enable صدا خورده
- (void)enable;
- (void)disable;
@end

// ---------- پنل ----------
@interface ZPanelModel : NSObject
@property (nonatomic, copy) NSString *interim;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) NSInteger queued;
@property (nonatomic) BOOL listening;
@property (nonatomic) BOOL paused;
@property (nonatomic) BOOL error;       // gaveUp: دکمه مکث می‌شود «تلاش دوباره»
@property (nonatomic) BOOL trouble;     // قطعی موقت شبکه: نقطه قرمز، ولی سشن زنده است
@property (nonatomic, copy) NSString *lang;
@property (nonatomic) BOOL waitingForTarget;
@property (nonatomic, copy) NSString *targetName;
@property (nonatomic) BOOL collect;     // حالت جمع در پنل (ادیتور)
@end

@interface ZPanel : NSObject
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onPauseToggle)(void);
@property (nonatomic, copy) void (^onCopyNow)(void);
@property (nonatomic, copy) void (^onTrash)(void);      // انصراف از هرچه هنوز درج نشده
@property (nonatomic, copy) void (^onInsertAll)(void);  // درج هرچه در پنل جمع شده
@property (nonatomic, copy) void (^onLangSwitch)(void); // چرخش زبان
@property (nonatomic, copy) void (^onModeToggle)(void); // جمع در پنل ↔ درج زنده
@property (nonatomic, copy) void (^onPolishNow)(void);  // اعمال پاس فارسی روی متن جمع‌شده
- (void)show;
- (void)hide;
- (void)render:(ZPanelModel *)m;
- (void)pulseLevel:(float)level;
// ادیتور حالت جمع: متن قطعی قابل ویرایش داخل خود پنل
- (void)appendFinalToEditor:(NSString *)chunk;
- (NSString *)editorText;
- (void)setEditorText:(NSString *)text;
- (void)clearEditor;
- (void)flash:(NSString *)msg;    // فیدبک کوتاه کار روی خط وضعیت
// متن خاکستری دنبال متن سفید در همان ادیتور (حالت جمع)
- (void)showInterimInEditor:(NSString *)interim;
- (void)makeShots:(NSString *)dir;
@end

// ---------- سشن تسمه‌نقاله ----------
@interface ZSession : NSObject <ZEngineDelegate>
@property (nonatomic, copy) void (^onFinish)(void);
@property (nonatomic, strong, readonly) id<ZEngine> engine;
- (instancetype)initWithEngine:(id<ZEngine>)engine panel:(ZPanel *)panel;
- (void)start;
- (void)pauseToggle;      // مکث/ادامه؛ بعد از خطا یعنی تلاش دوباره
- (void)copyNow;          // کپی متن تا اینجا
- (void)insertHere;       // درج در همین اپ جلویی
- (void)dropPending;      // دور ریختن هرچه هنوز درج نشده
- (void)toggleMode;       // جمع در پنل ↔ درج زنده، با حفظ متن
- (void)switchLang;       // چرخش فارسی/انگلیسی
- (void)polishCollected;  // پاس فارسی روی متن جمع‌شده، به خواست خودِ کاربر
- (void)finish;           // ممکن است منتظر پاس پایانی بماند، بعد ببندد
- (void)finishNow;        // بدون معطلی؛ مسیر خروج اپ از این می‌رود
@end

// ---------- رونویسی فایل (حالت دسته‌ای، بی‌رابط) ----------
// هر فایلی که AVFoundation باز کند به پی‌سی‌ام خام s16le مونو ۱۶ کیلوهرتز، تکه‌تکه.
// کل فایل هیچ‌وقت در حافظه نمی‌آید، پس فایل ۹۰ دقیقه‌ای هم به همان چند مگابایت
// فایل کوتاه کار می‌کند.
@interface ZFileDecoder : NSObject
+ (BOOL)supportsPath:(NSString *)path;          // ogg/opus/mkv/webm نه: دیمکسر ندارند
@property (nonatomic, readonly) NSTimeInterval duration;
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)err;
- (NSData *)nextChunk:(NSError **)err;          // نال: پایان فایل، یا خطا در err
- (void)cancel;
@end

// zemzeme --transcribe <files...> [--lang fa-IR] [--jobs N] [--out DIR] [--srt] [--speed X]
// بی‌رابط و مستقل از اپ منوبار: نه آیتم نوار وضعیت می‌سازد نه اجازه اکسسبیلیتی
// می‌خواهد، و سشن‌هایش (pair های تصادفی خودشان) با دیکته‌ی زنده‌ی در جریان قاطی
// نمی‌شوند. jobs محافظه‌کارانه است که کلید مشترک زیر پای مسیر زنده در نرود.
int ZBatchMain(NSArray<NSString *> *args);

// ---------- فونت و سلف‌تست ----------
void ZRegisterFonts(void);
NSFont *ZFont(CGFloat size, BOOL medium);
int ZSelfTest(NSString *file, NSString *lang);
