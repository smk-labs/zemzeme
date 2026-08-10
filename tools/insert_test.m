// تست طلاییِ روشِ درج: یک ادعا، همانی که دو بار شکست و متن را در ریموت خراب کرد.
//
// **Windows App همیشه پیست می‌گیرد.** هیچ تنظیمی، هیچ طولی و هیچ مسیرِ دیگری نباید
// بتواند آن را به تایپ ببرد. چرا این‌قدر جدی: رویدادِ تایپِ ما کیکد صفر است (همان A) با
// متنِ یونیکد چسبیده به آن، و کلاینت ریموت روی Keyboard Mode = Scancode محتوای یونیکد را
// نمی‌خواند و فقط اسکن‌کد را می‌فرستد. نتیجه‌اش روی صفحه‌ی ویندوز یک مشت a است.
//
// تنظیمات از طریق آرگومان‌های خط فرمان تزریق می‌شود (دامنه‌ی NSArgumentDomain): بالاترین
// اولویت را دارد و روی دیسک هیچ‌جا نمی‌نشیند، پس تست به تنظیماتِ واقعیِ کاربر دست نمی‌زند.
#import <Foundation/Foundation.h>
#import "zemzeme.h"

static int gFail = 0;

static void ok(BOOL cond, NSString *what) {
    if (cond) return;
    gFail++;
    fprintf(stderr, "  ✗ %s\n", what.UTF8String);
}

// core.m فقط همین یک نماد را از بیرون می‌خواهد. تست میکروفن ندارد، پس تهی است.
void ZMicSetHighSensitivity(BOOL on) { (void)on; }

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        ZSettings *s = ZSettings.shared;
        ZInsertMode global = s.insertMode;
        NSString *want = global == ZInsertType ? @"تایپ" : @"چسباندن";
        fprintf(stderr, "روشِ سراسری: %s\n", want.UTF8String);

        ok([s insertModeForBundleId:kZRDPBundleId] == ZInsertPaste,
           @"Windows App باید پیست بگیرد، هر چه روشِ سراسری باشد");
        // یک اپ معمولی باید دقیقا همان چیزی را بگیرد که کاربر سراسری انتخاب کرده،
        // وگرنه استثنای ریموت به بقیه هم سرایت کرده و انتخاب کاربر بی‌معنی شده.
        ok([s insertModeForBundleId:@"com.apple.Safari"] == global,
           @"اپ معمولی باید روشِ سراسری را بگیرد");
        ok([s insertModeForBundleId:nil] == global,
           @"مقصدِ بی‌شناسه هم روشِ سراسری را می‌گیرد، نه چیز دیگری");

        fprintf(stderr, gFail ? "%d ادعا شکست\n" : "همه‌ی ادعاها درست\n", gFail);
        return gFail ? 1 : 0;
    }
}
