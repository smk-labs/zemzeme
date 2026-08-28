// بازنویسی، و بس. هیچ حالتی اینجا نمی‌ماند: دو تابعِ خالص که ورودی‌شان جاهای صف و
// یک لایه است و خروجی‌شان متن.
//
// چرا بیرون از session.m: تصمیمِ «متنِ یکتا کدام است» تا امروز سه جا تکرار شده بود
// (متنِ زنده، متنِ کرسر، و شاخه‌ی ویرایش در تحویل) و شاخه‌ی سوم با آن دو تا یکی
// نبود. شبِ ۲۶ اوت ۲۰۲۶ نتیجه‌اش را کاربر دید: در سشن ۲۰۲۶-۰۸-۲۶-۰۳-۲۳-۵۷ سر کرسر
// ۱۰۵۷ نویسه‌ی خام نشست و در کلیپ‌بورد ۲۵۹ نویسه‌ی ویرایش‌شده، و هیچ‌کدام حرفِ کامل و
// ویرایش‌شده نبود. یک تصمیم که سه جا نوشته شود، دیر یا زود سه جواب می‌دهد.
#import "zemzeme.h"
#import "rewrite.h"

static BOOL ZCovered(NSIndexSet *covers, NSInteger seq) {
    return seq >= 0 && [covers containsIndex:(NSUInteger)seq];
}

NSString *ZRewriteText(NSString *rewrite, NSIndexSet *covers,
                       NSArray<ZSlot *> *slots, BOOL settled) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (rewrite.length) [parts addObject:rewrite];
    for (ZSlot *s in slots) {
        // پاس دومِ انگلیسی هیچ‌وقت تحویل کاربر نمی‌شود، و جایی که بازنویسی جایش را
        // گرفته دو بار نمی‌آید.
        if (s.extra || ZCovered(covers, s.seq)) continue;
        if (s.state == ZSlotWaiting) {
            // سر کرسر اینجا خط پایان است: درج کردنِ متنِ بعد از یک جای خالی یعنی
            // وقتی آن جا پر شد، حرف‌ها جابه‌جا سر کرسر نشسته باشند.
            if (settled) break;
            continue;
        }
        if (s.state == ZSlotDone && s.text.length) [parts addObject:s.text];
    }
    return [parts componentsJoinedByString:@" "];
}

NSIndexSet *ZRewriteCovers(NSIndexSet *covers, NSArray<ZSlot *> *slots) {
    NSMutableIndexSet *out = covers ? [covers mutableCopy] : [NSMutableIndexSet indexSet];
    for (ZSlot *s in slots) {
        // «حرفی نبود» هم قطعی است و سهمش برای همیشه هیچ. بیرون گذاشتنش یعنی یک جای
        // مرده که تا ابد دُم حساب می‌شود.
        if (s.extra || s.state == ZSlotWaiting || s.seq < 0) continue;
        [out addIndex:(NSUInteger)s.seq];
    }
    return [out copy];
}
