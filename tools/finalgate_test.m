// تست جدولِ «پاس نهایی شدنی است یا نه». بی‌شبکه، بی‌کلید، بی‌میکروفن.
//
// چرا تست دارد: این شرط سه مشتری دارد (دکمه‌ی نوار پنل، میان‌بر N، پانویس کارت راهنما)
// و وقتی هر کدام شرط خودش را داشت، دکمه در حالت زنده دیده می‌شد ولی کار نمی‌کرد:
// زدنش سشن را تمام می‌کرد و هیچ پاسی نمی‌داد. رگرسیون‌اش اینجا میخ شده است.
//
// اجرا: bash tools/finalgate_test.sh
#import <Foundation/Foundation.h>
#import "zemzeme.h"

static int gFail;

static void expect(BOOL got, BOOL want, NSString *what) {
    if (got == want) {
        printf("ok   %s\n", what.UTF8String);
        return;
    }
    gFail++;
    printf("  FAIL  %s (انتظار %s، گرفت %s)\n",
           what.UTF8String, want ? "بله" : "نه", got ? "بله" : "نه");
}

// همان شرطی که دکمه‌ی نوار دارد: از میان‌بر سخت‌گیرتر است و تاگل را هم می‌خواهد
static BOOL buttonShows(ZMode mode, BOOL on, BOOL rec, BOOL audio) {
    return on && ZFinalPassPossible(mode, on, rec, audio);
}

int main(void) {
    printf("\n-- میان‌بر N --\n");

    // رگرسیونِ اصلی: تاگل روشن، ضبط خاموش، حالت دیکته. پیش از این، N سشن را تمام
    // می‌کرد و بعد می‌گفت «صدایی ضبط نشده». حالا سشن دست‌نخورده می‌ماند.
    expect(ZFinalPassPossible(ZModeLive, YES, NO, NO), NO,
           @"زنده با ضبط خاموش: صدایی نیست، پس شدنی نیست");
    expect(ZFinalPassPossible(ZModeCollect, YES, NO, NO), NO,
           @"جمع با ضبط خاموش: شدنی نیست");
    expect(ZFinalPassPossible(ZModeCursor, YES, NO, NO), NO,
           @"کرسر با ضبط خاموش: شدنی نیست");

    // معیار پذیرش: با ضبط روشن، هر سه حالت دیکته شدنی‌اند
    expect(ZFinalPassPossible(ZModeLive, YES, YES, NO), YES, @"زنده با ضبط روشن: شدنی");
    expect(ZFinalPassPossible(ZModeCollect, YES, YES, NO), YES, @"جمع با ضبط روشن: شدنی");
    expect(ZFinalPassPossible(ZModeCursor, YES, YES, NO), YES, @"کرسر با ضبط روشن: شدنی");

    // یادداشت همیشه ضبط می‌کند، پس به تاگل ضبط کاری ندارد
    expect(ZFinalPassPossible(ZModeNote, YES, NO, NO), YES, @"یادداشت با ضبط خاموش: باز هم شدنی");
    // و بی‌تاگلِ پاس نهایی هم شدنی است، چون مسیر مجانی تشخیص گفتار هست
    expect(ZFinalPassPossible(ZModeNote, NO, NO, NO), YES,
           @"یادداشت بی‌تاگل: مسیر مجانی هست، پس N کار می‌کند");

    // تاگل خاموش یعنی رفتار قبل، عینا: سه حالت دیکته هیچ‌کاری نمی‌کنند
    expect(ZFinalPassPossible(ZModeLive, NO, YES, YES), NO,
           @"تاگل خاموش در زنده: با صدا هم نه");
    expect(ZFinalPassPossible(ZModeCollect, NO, YES, YES), NO, @"تاگل خاموش در جمع: نه");

    // صدای مانده از استینت قبلی: یادداشت ← E ← زنده. حالت فعلی ضبط نمی‌کند ولی صدا هست
    expect(ZFinalPassPossible(ZModeLive, YES, NO, YES), YES,
           @"زنده با صدای مانده از یادداشت: همان صدا باید شنیده شود");

    printf("\n-- دکمه‌ی نوار پنل --\n");

    // دکمه هیچ‌وقت جایی دیده نمی‌شود که کار نکند
    expect(buttonShows(ZModeLive, YES, NO, NO), NO, @"زنده با ضبط خاموش: دکمه نباشد");
    expect(buttonShows(ZModeLive, YES, YES, NO), YES, @"زنده با ضبط روشن: دکمه باشد");
    expect(buttonShows(ZModeCollect, YES, YES, NO), YES, @"جمع با ضبط روشن: دکمه باشد");
    // و در یادداشتِ بی‌تاگل، دکمه‌ای که قبلا نبود حالا هم نیست
    expect(buttonShows(ZModeNote, NO, NO, NO), NO, @"یادداشت بی‌تاگل: دکمه مثل قبل نباشد");
    expect(buttonShows(ZModeNote, YES, NO, NO), YES, @"یادداشت با تاگل: دکمه باشد");

    if (gFail) {
        printf("\n%d تست شکست\n\n", gFail);
        return 1;
    }
    printf("\nهمه‌ی تست‌های دروازه‌ی پاس نهایی قبول شدند\n\n");
    return 0;
}
