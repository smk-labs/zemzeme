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
    ZSoundPolish,     // پاس ویرایش نشست
};
void ZPlay(ZSound s);
NSString *ZFaDigits(NSString *s);
NSString *ZTimestampId(void);

// ---------- تنظیمات ----------
typedef NS_ENUM(NSInteger, ZInsertMode) {
    ZInsertType = 0,     // تایپ مستقیم با رویداد یونیکد
    ZInsertPaste = 1,    // پیست تکه‌ای (برای ریموت دسکتاپ امن‌تر)
};

// سه حالت دیکته، یک تنظیم. Command راست + E وسط سشن بینشان می‌چرخد، همیشه با حفظ
// متن. عددها عمدا از صفر و یک شروع می‌شوند: تنظیم روی دیسک همان کلید BOOL قدیمی
// «collect» است و NO/YES دقیقا همین دو مقدار را می‌خوانند، پس تنظیم کاربر قدیمی
// بدون هیچ کد مهاجرتی سر جایش می‌ماند.
typedef NS_ENUM(NSInteger, ZMode) {
    ZModeLive = 0,       // درج زنده سر کرسر، با نوار شناور و دُم خاکستری
    ZModeCollect = 1,    // جمع در ادیتور خود پنل، درج یکجا در پایان
    ZModeCursor = 2,     // مثل دیکته‌ی خود مک: بی‌پنل، فقط یک نقطه کنار کرسر. درج همان مسیر زنده است
};

@interface ZSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *lang;         // fa-IR | en-US
@property (nonatomic, copy) NSString *engineName;   // google | chrome
@property (nonatomic) ZInsertMode insertMode;       // روش درج (تایپ/پیست)
@property (nonatomic) ZMode mode;                   // حالتی که سشن بعدی با آن شروع می‌شود
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
// دُم موقت حالت کرسر: n نویسه‌ی آخر پاک، متن تازه تایپ، هر دو پشت سر هم و تجزیه‌ناپذیر.
// n فقط نویسه‌های تایپ‌شده‌ی خودمان است؛ متن کاربر از این راه پاک نمی‌شود.
- (void)replaceLast:(NSUInteger)n with:(NSString *)text delayMicros:(useconds_t)d;
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
// Esc، با اولویت: کارت راهنما باز است ببندش، وگرنه سشن را تمام کن. جواب YES یعنی
// رویداد مصرف شد و به اپ زیرین نمی‌رسد؛ NO یعنی Esc مال ما نبود، دست‌نخورده رد شود
// (بیرون از سشن و بی‌کارتِ باز، Esc نباید از vim و بقیه دزدیده شود). هم‌زمان (نه
// dispatch) صدا زده می‌شود، چون تصمیم «بلعیدن یا نه» تاخیر نمی‌پذیرد؛ تپ خودش روی
// نخ اصلی نشسته، پس امن است.
@property (nonatomic, copy) BOOL (^onEscape)(void);
@property (nonatomic, copy) void (^onHelp)(void);           // H: کارت راهنما، در سشن و بیرونش
@property (nonatomic, copy) void (^onPauseToggle)(void);    // تک‌تپ Command راست، یا Space
@property (nonatomic, copy) void (^onCopyNow)(void);        // C
@property (nonatomic, copy) void (^onInsertHere)(void);     // V
@property (nonatomic, copy) void (^onTrash)(void);          // D
@property (nonatomic, copy) void (^onLangSwitch)(void);     // L
@property (nonatomic, copy) void (^onModeToggle)(void);     // E
@property (nonatomic, copy) void (^onPolishNow)(void);      // P
// F: پنل رونویسی فایل. تنها میان‌بری که بی‌سشن هم کار می‌کند، چون به سشن ربطی ندارد
@property (nonatomic, copy) void (^onFilePanel)(void);      // F
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
@property (nonatomic) ZMode mode;
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
// پنجره‌ی ۲۲ نقطه‌ای بدون قاب که فقط یک دایره‌ی رنگی در خود دارد و بالای کرسرِ اپِ
// فوکس‌دار می‌نشیند. نه فوکس می‌گیرد نه کلیک (`ignoresMouseEvents`)، پس کلیک روی
// همان نقطه به اپ زیرین می‌رسد. جای کرسر با اکسسبیلیتی و روی نخ پس‌زمینه پرسیده
// می‌شود (۶ هرتز)، چون هر فراخوان AX می‌تواند کند باشد یا اصلا جواب ندهد؛ چهار پله
// فروکاست دارد و هیچ‌وقت ناپدید نمی‌شود: تا سشن زنده است باید پیدا باشد.
@interface ZCaretDot : NSObject
- (void)show;                     // پنجره را بالا می‌آورد و دنبال کردن کرسر را شروع می‌کند
- (void)hide;                     // تایمر همان لحظه می‌ایستد
- (void)render:(ZPanelModel *)m;  // فقط رنگ و ضربان وضعیت
- (void)pulseLevel:(float)level;
@end

@interface ZPanel : NSObject
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onPauseToggle)(void);
@property (nonatomic, copy) void (^onCopyNow)(void);
@property (nonatomic, copy) void (^onTrash)(void);      // انصراف از هرچه هنوز درج نشده
@property (nonatomic, copy) void (^onInsertAll)(void);  // درج هرچه در پنل جمع شده
@property (nonatomic, copy) void (^onLangSwitch)(void); // چرخش زبان
@property (nonatomic, copy) void (^onModeToggle)(void); // چرخش حالت: زنده ← جمع ← کرسر
@property (nonatomic, copy) void (^onPolishNow)(void);  // اعمال پاس فارسی روی متن جمع‌شده
@property (nonatomic, copy) void (^onFilePanel)(void);  // باز کردن پنل رونویسی فایل
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
// هر رندر با همان مدل پنل صدا می‌شود؛ دلیگیت اپ از همین آیتم منوبار را رنگ می‌کند
@property (nonatomic, copy) void (^onModel)(ZPanelModel *m);
@property (nonatomic, strong, readonly) id<ZEngine> engine;
- (instancetype)initWithEngine:(id<ZEngine>)engine panel:(ZPanel *)panel;
- (void)start;
- (void)pauseToggle;      // مکث/ادامه؛ بعد از خطا یعنی تلاش دوباره
- (void)copyNow;          // کپی متن تا اینجا
- (void)insertHere;       // درج در همین اپ جلویی
- (void)dropPending;      // دور ریختن هرچه هنوز درج نشده
- (void)toggleMode;       // چرخش زنده ← جمع ← کرسر، با حفظ متن
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
@property (nonatomic) NSInteger jobs;           // سشن هم‌زمان؛ پیش‌فرض ۲
@property (nonatomic) double speed;             // ضریب تغذیه؛ ۰ یعنی بی‌مکث (پیش‌فرض)
@property (nonatomic) BOOL rawUpload;           // l16 خام به جای FLAC؛ فقط عیب‌یابی
@property (nonatomic) BOOL writeSRT;
@property (nonatomic) BOOL writeTXT;            // پیش‌فرض روشن
// پاس ویرایش روی متن هر فایل، قبل از نوشتن txt. مسیر خط فرمان روشنش می‌کند (آنجا
// یک فایل یعنی یک خروجی)، رابط خاموش: آنجا پاس نهایی روی متن یکجا می‌نشیند.
@property (nonatomic) BOOL polishFiles;
@property (nonatomic, copy) NSString *outDir;   // نال: کنار خود فایل
@property (nonatomic, readonly) unsigned long long bytesUp;
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

// پاس ویرایش فارسی روی یک متن بلند، تکه‌تکه (~۴۰ کلمه). ترتیب مهم است و دلیلش سر
// خود تابع نوشته شده: اول جوش خام، بعد ویرایش. بلوکه است، پس نخ پس‌زمینه.
NSString *ZBatchPolishText(NSString *raw, NSString *lang);

// ---------- پنل رونویسی فایل ----------
// پنجره‌ی واقعی (نه نوار شناور): صف فایل با ترتیبِ قابل‌کشیدن، پیشرفت زنده‌ی هر ردیف،
// و متن یکجای قابل ویرایش. یکی بیشتر نیست، چون سه راه دسترسی (منوبار، میان‌بر،
// دکمه‌ی پنل) باید به همان صف و همان کار برسند. بستن پنجره کار در جریان را نمی‌کشد.
@interface ZBatchPanel : NSObject
+ (instancetype)shared;
- (void)show;
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

// ---------- فونت و سلف‌تست ----------
void ZRegisterFonts(void);
NSFont *ZFont(CGFloat size, BOOL medium);
int ZSelfTest(NSString *file, NSString *lang);
