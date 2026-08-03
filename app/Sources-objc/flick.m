// ---------- فلیکِ پنجره‌ی کلید ----------
// یک پنجره‌ی ۱×۱ نامرئی برای یک لحظه کلید را می‌گیرد و همان‌جا پس می‌دهد، بی این‌که
// اپِ جلو عوض شود. چرا چنین چیزِ عجیبی لازم است، سرِ پیستِ ریموت در inject.m نوشته شده:
// کلاینت ریموت دسکتاپ کلیپ‌بورد مک را فقط سرِ عوض شدنِ پنجره‌ی کلید به سرور می‌فرستد.
//
// عمدا هیچ وابستگی‌ای جز AppKit ندارد، پس تستِ طلایی‌اش (tools/flick_test.sh) تنهایی
// کامپایلش می‌کند و رفتار واقعی سیستم‌عامل را می‌سنجد، نه یک ادای آن را.
#import "zemzeme.h"
#import <unistd.h>

// مهلتِ نگه داشتنِ کلید. باید به اپِ آن‌طرف برسد که کلید را از دست داده (رویداد از
// سرور پنجره می‌آید و در حلقه‌ی خودِ آن اپ پردازش می‌شود)، و برای کاربر دیده نشود.
static const useconds_t kZFlickHold = 80000;

// پنلِ بوردرلس به‌خودی‌خود کلید می‌گیرد، ولی این‌جا صریح نوشته می‌شود: تنها کارِ این
// پنجره همین است و نباید به یک پیش‌فرضِ ضمنی بند باشد. مِین نمی‌شود، که اپ جلو نیاید.
@interface ZFlickPanel : NSPanel
@end

@implementation ZFlickPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

static void zOnMain(dispatch_block_t b) {
    if (NSThread.isMainThread) b();
    else dispatch_sync(dispatch_get_main_queue(), b);
}

@implementation ZKeyFlick

// nonactivating یعنی پنجره کلید می‌گیرد ولی اپِ صاحبش فعال نمی‌شود؛ همان چیزی که
// نوار شناور زمزمه از روز اول رویش بنا شده. آلفای صفر هم جلوی کلید گرفتن را نمی‌گیرد:
// شفافیت فقط کارِ ترکیب تصویر است، نه کارِ سرورِ پنجره.
+ (NSPanel *)panel {
    static ZFlickPanel *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        p = [[ZFlickPanel alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
                                           styleMask:NSWindowStyleMaskBorderless
                                                     | NSWindowStyleMaskNonactivatingPanel
                                             backing:NSBackingStoreBuffered defer:NO];
        p.level = NSStatusWindowLevel;    // سشنِ ریموت اغلب فول‌اسکرین است
        p.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                             | NSWindowCollectionBehaviorFullScreenAuxiliary
                             | NSWindowCollectionBehaviorIgnoresCycle;
        p.floatingPanel = YES;
        p.opaque = NO;
        p.hasShadow = NO;
        p.backgroundColor = NSColor.clearColor;
        p.alphaValue = 0;
        p.ignoresMouseEvents = YES;
        p.hidesOnDeactivate = NO;
        p.releasedWhenClosed = NO;
        p.becomesKeyOnlyIfNeeded = NO;    // بی‌قید کلید بگیرد؛ هیچ ویویی اینجا کلید نمی‌خواهد
    });
    return p;
}

// بلوکه است: بین گرفتن و پس دادن باید نخ آزاد شود تا حلقه‌ی اصلی رویدادِ پنجره را
// پردازش کند. پس نباید روی نخ اصلی صدا زده شود (صف درج، جایی که پیست از آن می‌رود).
+ (void)flick {
    // ساختنِ پنجره هم باید روی نخ اصلی باشد، نه فقط نشان دادنش: AppKit سرِ ساختنِ
    // NSWindow روی نخ دیگر استثنا می‌اندازد و اپ همان‌جا می‌افتد. تستِ طلایی همین را
    // سر اولین اجرا گرفت، پس این کامنت جای همان باگ است.
    __block NSPanel *p = nil;
    zOnMain(^{
        p = [self panel];
        [p makeKeyAndOrderFront:nil];
    });
    usleep(kZFlickHold);
    // با orderOut کلید به پنجره‌ی کلیدِ اپِ فعال برمی‌گردد؛ اپِ فعال هیچ‌وقت عوض نشد،
    // پس همان پنجره‌ای که کلید داشت پسش می‌گیرد و Cmd+V بعدی سرِ جای درست می‌نشیند.
    zOnMain(^{ [p orderOut:nil]; });
}

@end
