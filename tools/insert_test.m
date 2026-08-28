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
        // همان دو اسمی که در منو نوشته شده، تا خروجی تست و رابط یک زبان داشته باشند
        NSString *want = global == ZInsertType ? @"درج مستقیم" : @"ذخیره در کلیپ‌بورد";
        fprintf(stderr, "روشِ سراسری: %s\n", want.UTF8String);

        ok([s insertModeForBundleId:kZRDPBundleId] == ZInsertPaste,
           @"Windows App باید پیست بگیرد، هر چه روشِ سراسری باشد");
        // کلاینتِ لینوکس باندل آیدی ندارد، پس شناسه‌اش نامِ فایلِ اجرایی است. اگر این
        // خط قرمز شود، درج در سشنِ ousmousa برگشته است به تایپِ یونیکد، یعنی «aaaa».
        ok([s insertModeForBundleId:kZFreeRDPName] == ZInsertPaste,
           @"sdl-freerdp هم باید پیست بگیرد، هر چه روشِ سراسری باشد");
        // یک اپ معمولی باید دقیقا همان چیزی را بگیرد که کاربر سراسری انتخاب کرده،
        // وگرنه استثنای ریموت به بقیه هم سرایت کرده و انتخاب کاربر بی‌معنی شده.
        ok([s insertModeForBundleId:@"com.apple.Safari"] == global,
           @"اپ معمولی باید روشِ سراسری را بگیرد");
        ok([s insertModeForBundleId:nil] == global,
           @"مقصدِ بی‌شناسه هم روشِ سراسری را می‌گیرد، نه چیز دیگری");

        // ---------- انتخابِ مسیرِ نوشتن ----------
        // ادعای دوم، و یک بار بی‌صدا شکست: **متنِ بلندی که نوشتنِ اتمیک را رد کرد باید
        // پیست شود، نه تایپ.** آن روز کد تایپ می‌کرد و رگبار رویداد دقیقا ۱۸ واحد
        // UTF-16 از وسطِ یک فهرست خورد، یعنی یک بولتِ کامل غیب شد. سه خط توضیحِ بالای
        // همان کد وعده‌ی پیست می‌داد؛ توضیح تست نیست.
        const NSUInteger longText = kZEventUnits, shortText = kZEventUnits - 1;

        ok(ZChooseWritePath(NO, NO, longText) == ZWritePaste,
           @"متنِ بلند که AX ردش کرد باید پیست شود، نه رگبار رویداد");
        ok(ZChooseWritePath(NO, YES, longText) == ZWriteAX,
           @"متنِ بلند که AX پذیرفت، همان‌جا نشسته و مسیر دیگری لازم نیست");
        // کوتاه‌تر از یک رویداد نمی‌تواند نصفه بیفتد، پس تایپ می‌ماند: هم امن است هم
        // کلیپ‌بورد را دست نمی‌زند. دُمِ کوتاهِ حالت کرسر از همین‌جا می‌رود.
        ok(ZChooseWritePath(NO, NO, shortText) == ZWriteType,
           @"متنِ کوتاه‌تر از یک رویداد تایپ می‌شود و کلیپ‌بورد را دست نمی‌زند");
        // و ریموت دسکتاپ بی‌قید و شرط، در هر طولی: همان ادعای بالا، از این طرف
        ok(ZChooseWritePath(YES, NO, shortText) == ZWritePaste,
           @"اپی که همیشه پیست می‌خواهد، متنِ کوتاه را هم پیست می‌گیرد");
        ok(ZChooseWritePath(YES, YES, longText) == ZWritePaste,
           @"و هیچ مسیری، حتی AX، نباید از پیستِ اجباری جلو بزند");

        fprintf(stderr, gFail ? "%d ادعا شکست\n" : "همه‌ی ادعاها درست\n", gFail);
        return gFail ? 1 : 0;
    }
}
