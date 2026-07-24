// زمزمه: دیکته فارسی شناور روی مک.
// چرا ObjC؟ سوئیفت روی این دستگاه فعلا بیلد نمی‌شود: CLT نصب‌شده (swiftlang-6.2.0.19.9)
// با ماژول‌های همه SDK های موجود (6.2.0.17.14 و قدیمی‌تر) ناسازگار است و بازسازی
// interface ها هم به برخورد modulemap مربوط به SwiftBridging می‌خورد. clang سالم است.
// پورت سوئیفت همین معماری در app/swift-port/ آماده است؛ بعد از تعمیر CLT قابل استفاده.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------- مسیرها، لاگ، اعداد فارسی ----------
NSURL *ZRoot(void);          // پوشه dictate (کنار serve.py)
NSURL *ZSessionsDir(void);
void ZLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *ZFaDigits(NSString *s);
NSString *ZTimestampId(void);

// ---------- تنظیمات ----------
typedef NS_ENUM(NSInteger, ZInsertMode) {
    ZInsertType = 0,     // تایپ مستقیم با رویداد یونیکد
    ZInsertPaste = 1,    // پیست تکه‌ای (برای ریموت دسکتاپ امن‌تر)
    ZInsertCollect = 2,  // فقط جمع کن؛ درج نکن
};

@interface ZSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *lang;         // fa-IR | en-US
@property (nonatomic, copy) NSString *engineName;   // google | chrome
@property (nonatomic) ZInsertMode insertMode;
@property (nonatomic) BOOL internalHotkey;
- (ZInsertMode)insertModeForBundleId:(NSString *)bundleId;
- (useconds_t)typeDelayMicros;
- (useconds_t)pasteDelayMicros;
@end

// ---------- رویداد گفتار (پارس‌شده از protobuf گوگل) ----------
@interface ZSpeechEvent : NSObject
@property (nonatomic) NSInteger status;        // -1 یعنی نیامده
@property (nonatomic) NSInteger endpoint;      // -1 یعنی نیامده
@property (nonatomic, strong) NSMutableArray<NSString *> *finals;
@property (nonatomic, copy) NSString *interim;
@end

ZSpeechEvent *ZProtoDecodeEvent(NSData *body);

// ---------- موتور pluggable ----------
typedef NS_ENUM(NSInteger, ZEngineState) {
    ZEngineIdle,
    ZEngineConnecting,
    ZEngineListening,
    ZEngineReconnecting,
    ZEngineGaveUp,
    ZEnginePageNeeded,
};

@protocol ZEngineDelegate <NSObject>
- (void)engineInterim:(NSString *)text;                          // کل متن خاکستری فعلی
- (void)engineFinal:(NSString *)text;                            // یک تکه قطعی
- (void)engineState:(ZEngineState)state message:(NSString *)msg; // پیام فقط برای GaveUp
- (void)engineLevel:(float)rms;                                  // ۰ تا ۱ برای ضربان
@end

@protocol ZEngine <NSObject>
@property (nonatomic, weak) id<ZEngineDelegate> delegate;
- (void)startWithLang:(NSString *)lang;
- (void)setLang:(NSString *)lang;
- (void)stop;
@end

// ---------- استریم full-duplex گوگل ----------
@interface ZGoogleStream : NSObject
@property (nonatomic, readonly) NSString *pair;
@property (nonatomic, copy) void (^onEvent)(ZSpeechEvent *ev);   // روی صف دلیگیت URLSession
@property (nonatomic, copy) void (^onClose)(NSString *reason);   // دقیقا یک بار
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

// ---------- درج ----------
@interface ZInjector : NSObject
+ (BOOL)accessibilityOK;
+ (void)promptAccessibility;
+ (BOOL)secureInputActive;
+ (void)copyFinal:(NSString *)text;                     // کپی ماندگار پایانی
- (void)type:(NSString *)text delayMicros:(useconds_t)d;
- (void)paste:(NSString *)text delayMicros:(useconds_t)d;
@end

// ---------- تپ‌های کیبورد ----------
@interface ZEscTap : NSObject
@property (nonatomic, copy) void (^onEsc)(void);
- (void)enable;
- (void)disable;
@end

@interface ZRCmdTap : NSObject
@property (nonatomic, copy) void (^onDoubleTap)(void);
- (void)enable;
- (void)disable;
@end

// ---------- پنل ----------
@interface ZPanelModel : NSObject
@property (nonatomic, copy) NSString *interim;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) NSInteger queued;
@property (nonatomic) BOOL locked;
@property (nonatomic) BOOL listening;
@property (nonatomic) BOOL error;
@property (nonatomic, copy) NSString *lang;
@property (nonatomic) BOOL waitingForTarget;
@property (nonatomic, copy) NSString *targetName;
@end

@interface ZPanel : NSObject
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onToggleLock)(void);
@property (nonatomic, copy) void (^onRetarget)(void);
@property (nonatomic, copy) void (^onToggleLang)(void);
- (void)show;
- (void)hide;
- (void)render:(ZPanelModel *)m;
- (void)pulseLevel:(float)level;
- (void)makeShots:(NSString *)dir;
@end

// ---------- سشن تسمه‌نقاله ----------
@interface ZSession : NSObject <ZEngineDelegate>
@property (nonatomic, copy) void (^onFinish)(void);
@property (nonatomic, strong, readonly) id<ZEngine> engine;
- (instancetype)initWithEngine:(id<ZEngine>)engine panel:(ZPanel *)panel;
- (void)start;
- (void)finish;
@end

// ---------- فونت و سلف‌تست ----------
void ZRegisterFonts(void);
NSFont *ZFont(CGFloat size, BOOL medium);
int ZSelfTest(NSString *file, NSString *lang);
