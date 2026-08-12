// تستِ طلاییِ «رشته‌ی زنده». یک قاعده را می‌سنجد و همان قاعده دو بار متنِ کاربر را برد:
//
//   هیچ‌کس حق ندارد `NSTextView.string` را نگه دارد و بعدا بخواند.
//
// `NSTextView.string` عکسِ لحظه‌ای نیست؛ همان رشته‌ی زنده‌ی پشتِ NSTextStorage است. هر
// خواننده‌ی معوقی محتوای *لحظه‌ی خواندن* را می‌گیرد، نه محتوای لحظه‌ی گرفتن.
//
// این دقیقا آنچه افتاد: در حالت جمع، متنِ تحویل از ادیتور خوانده می‌شد و کپیِ پایانیِ
// کلیپ‌بورد پشتِ صفِ درج می‌نشست، یعنی حدود یک ثانیه بعد. تا آن لحظه Esc پنل را بسته و
// `clearEditor` ادیتور را خالی کرده بود، پس کلیپ‌بورد به‌جای متن، خالی پر می‌شد. در
// لاگ `کلیپ‌بورد پایانی، 0 نویسه` زیرِ یک درجِ ۱۴۹ نویسه‌ای نشسته بود و کسی ندیدش.
//
// چرا فقط در ریموت دسکتاپ به چشم آمد: آنجا و فقط آنجا مسیرِ پیست بلافاصله کپیِ اولِ
// سالم را با نسخه‌ی transient می‌پوشاند، پس مدیر کلیپ‌بورد اصلا فرصت دیدنِ متن را
// نداشت. بقیه‌ی اپ‌ها همان کپیِ اول را در تاریخچه نگه می‌داشتند و خالی شدنِ بعدی
// بی‌صدا رد می‌شد. یعنی باگ همه‌جا بود و تنها یک جا دیده می‌شد.
//
// سه ادعا: رشته‌ی زنده واقعا زنده است (مکانیزم اثبات شود، نه فرض)، کپی مصون است، و
// خودِ `editorText` امروز کپی می‌دهد.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

static int failures = 0;

static void ok(BOOL cond, const char *what) {
    printf("%s %s\n", cond ? "ok  " : "FAIL", what);
    if (!cond) failures++;
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    NSString *sample = @"متنی که کاربر گفته و نباید گم شود";

    // ادعای یک: خودِ مکانیزم. رشته را می‌گیریم، ادیتور را خالی می‌کنیم، دوباره
    // می‌خوانیمش. اگر این ادعا روزی بیفتد یعنی AppKit عوض شده و بقیه‌ی تست بی‌معنی است.
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:sample];
    NSString *live = tv.string;
    ok(live.length == sample.length, "رشته‌ی زنده سرِ گرفتن درست است");
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:@""];
    ok(live.length == 0, "رشته‌ی زنده با خالی شدنِ ادیتور خالی می‌شود (پس باگ واقعی بود)");

    // ادعای دو: کپی، همان لحظه. این تنها چیزی است که یک ثانیه بعد هنوز متن دارد.
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:sample];
    NSString *snap = [tv.string copy];
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:@""];
    ok([snap isEqualToString:sample], "کپی بعد از خالی شدنِ ادیتور هم متن را دارد");

    // ادعای سه: تحویلِ معوق، همان‌طور که واقعا اتفاق می‌افتد. متن گرفته می‌شود، پنل
    // بسته می‌شود، و یک صفِ دیگر یک ثانیه بعد آن را می‌نویسد.
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:sample];
    NSString *keep = [tv.string copy];
    dispatch_queue_t q = dispatch_queue_create("test.deferred", DISPATCH_QUEUE_SERIAL);
    __block NSString *delivered = nil;
    dispatch_async(q, ^{
        usleep(200000);
        delivered = keep;
    });
    [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:@""];
    dispatch_sync(q, ^{});
    ok(delivered.length > 0, "تحویلِ معوق دست خالی برنمی‌گردد");

    // ادعای چهار: خودِ قاعده روی سورس. تستِ رفتاری بالا `editorText` را صدا نمی‌زند
    // (panel.m به کلِ اپ وصل است)، پس همین یک خط را همین‌جا می‌سنجیم: کسی که فردا
    // `copy` را بردارد باید اینجا قرمز ببیند، نه در کلیپ‌بوردِ کاربر.
    NSString *src = [NSString stringWithContentsOfFile:@"app/Sources-objc/panel.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok([src containsString:@"return [_editor.string copy]"],
       "editorText هنوز کپی می‌دهد، نه رشته‌ی زنده");

    // ---------- تایپِ کاربر نباید گم شود ----------
    // مسیر تحویل در حالت جمع **اول** متنِ خام را روی ادیتور می‌نوشت و **بعد** همان را
    // پس می‌خواند، پس هر چه کاربر تایپ کرده بود بی‌صدا پاک می‌شد. کامنتِ بالای همان
    // شرط از روز اول می‌گفت «متنِ ادیتور مرجع است»، و از روز اول هم غلط بود؛ فقط چون
    // ادیتور فوکوس نمی‌گرفت هیچ‌کس نمی‌توانست ببیندش.
    //
    // قاعده با NSTextView واقعی مدل می‌شود، همان‌طور که ادعاهای بالا: هرچه نوشته‌ایم را
    // به یاد داریم، و متنِ زنده که دیگر همان نبود، یعنی متن مالِ کاربر است.
    {
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
        NSString *wrote = @"متنِ دیکته‌شده";
        [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:wrote];
        ok(![tv.string isEqualToString:wrote] == NO, "نوشتنِ ما همان است که نوشتیم");

        // کاربر تایپ می‌کند
        [tv.textStorage replaceCharactersInRange:NSMakeRange(tv.string.length, 0)
                                     withString:@" و یک اضافه‌ی دستی"];
        ok(![tv.string isEqualToString:wrote], "تایپِ کاربر از متنِ نوشته‌ی ما جدا تشخیص داده می‌شود");

        // و بندِ اصلی: اگر **اول** بنویسیم و بعد بخوانیم، همان تایپ نابود می‌شود
        NSString *userText = [tv.string copy];
        [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:wrote];
        ok(![[tv.string copy] isEqualToString:userText],
           "نوشتن پیش از خواندن، تایپِ کاربر را پاک می‌کند؛ همین بود باگ");

        // دُمِ خاکستریِ خودمان نباید «تایپِ کاربر» خوانده شود
        NSString *tail = @" دُمِ پیش‌نمایش";
        [tv.textStorage replaceCharactersInRange:NSMakeRange(0, tv.string.length) withString:wrote];
        [tv.textStorage replaceCharactersInRange:NSMakeRange(tv.string.length, 0) withString:tail];
        NSString *live = tv.string;
        if ([live hasSuffix:tail]) live = [live substringToIndex:live.length - tail.length];
        ok([live isEqualToString:wrote], "دُمِ پیش‌نمایش کنار گذاشته می‌شود، پس آژیرِ الکی نمی‌زند");
    }

    // و ترتیب، روی خودِ سورس: در شاخه‌ی حالت جمع باید **اول** editorTouched پرسیده شود
    // و بعد شاید setEditorText. کسی که فردا ترتیب را برگرداند باید اینجا قرمز ببیند.
    NSString *ses = [NSString stringWithContentsOfFile:@"app/Sources-objc/session.m"
                                              encoding:NSUTF8StringEncoding error:nil];
    ok(ses.length > 0, "session.m خوانده شد");
    NSRange touched = [ses rangeOfString:@"if ([_panel editorTouched])"];
    NSRange writes  = [ses rangeOfString:@"[_panel setEditorText:all]"];
    ok(touched.location != NSNotFound && writes.location != NSNotFound
       && touched.location < writes.location,
       "تحویل اول می‌پرسد کاربر تایپ کرده یا نه، بعد می‌نویسد");

    printf(failures ? "\nlivestring: %d ادعا افتاد\n" : "\nlivestring: همه‌ی ادعاها درست\n", failures);
    return failures ? 1 : 0;
} }
