// دفتر متن: تنها چیزی که می‌داند روی صفحه چه نوشته‌ایم، و تنها چیزی که اجازه دارد
// پاکش کند.
//
// جای سه دفترِ قبلی را گرفت: `_tail` (حالت کرسر)، `_greyLen` (حالت جمع) و صفِ
// تکه‌های درج‌نشده. هر سه یک کار می‌کردند با سه پیاده‌سازی، و هر سه با شمردن کار
// می‌کردند نه با نگاه کردن. هر باگِ گم شدن و تکرار و پاک شدنِ یک‌دفعه‌ای، واگراییِ
// یکی از آن سه از واقعیت بود.
//
// قرارداد اینجا:
//   ۱. ناحیه‌ی قابلِ بازنویسی دقیقا برابر `pending` موتور است، نه یک نویسه بیشتر.
//      پس هرچه قطعی شد، همان لحظه از دسترسِ پاک‌کن بیرون می‌رود.
//   ۲. هر عملیات مخرب باید `expected` را به مقصد بدهد و مقصد باید ثابتش کند.
//   ۳. نشد ثابت کرد؟ مالکیت رها می‌شود و فقط اضافه می‌کنیم. تکرار برگشت‌پذیر است.
#import "zemzeme.h"

// سقف زمانی بین بروزرسانی‌های دُم. بی این، گوگل چند بار در ثانیه متن خاکستری را
// بازنویسی می‌کند و صف درج پر می‌شود از پاک‌کن و تایپِ نیم‌کاره و متن روی صفحه می‌لرزد.
// تغییرِ committed از این رد می‌شود: تکه‌ی قطعی حق ندارد پشت throttle بماند.
static const NSTimeInterval kZLedgerPendingThrottle = 0.12;

// ---------- ZLedgerStats ----------

@implementation ZLedgerStats
- (NSString *)summary {
    NSUInteger ops = _appends + _replaces;
    double ratio = ops ? (double)_appends * 100.0 / (double)ops : 100.0;
    return [NSString stringWithFormat:
            @"ops=%lu append=%lu (%.1f%%) replace=%lu verified(read=%lu epoch=%lu) "
            @"disown=%lu unavailable=%lu axreads=%lu",
            (unsigned long)ops, (unsigned long)_appends, ratio, (unsigned long)_replaces,
            (unsigned long)_verifiedByRead, (unsigned long)_verifiedByEpoch,
            (unsigned long)_disowns, (unsigned long)_unavailable, (unsigned long)_axReads];
}
@end

// ---------- ZTextLedger ----------

static NSUInteger ZCommonPrefix(NSString *a, NSString *b) {
    NSUInteger n = MIN(a.length, b.length), i = 0;
    while (i < n && [a characterAtIndex:i] == [b characterAtIndex:i]) i++;
    return i;
}

@implementation ZTextLedger {
    // پیشوندی از committed که واقعا به مقصد رسیده. چون پیشوندِ committed قفل است،
    // این عدد فقط جلو می‌رود و هیچ‌وقت لازم نمی‌شود چیزی قبل از آن بازنویسی شود.
    NSString *_sentCommitted;
    // آنچه برای pending نوشته‌ایم و هنوز مال ماست. تنها ناحیه‌ای که پاک‌کن اجازه دارد
    // واردش شود.
    NSString *_owned;
    BOOL _needSep;      // بعد از رها کردن مالکیت، متن تازه نباید به تکه‌ی جامانده بچسبد
    // و تا مرزِ قطعیِ بعدی اصلا دُم رندر نمی‌شود. بی این، تکه‌ی رهاشده روی صفحه است و
    // ما همان حرف‌ها را دوباره پشتش می‌نویسیم؛ هر interim یک تکرار تازه می‌ساخت.
    BOOL _pendingSuspended;

    NSString *_wantC, *_wantP;
    BOOL _dirty, _busy, _pumping;
    NSTimeInterval _lastOpAt;
    NSInteger _throttleGen;
}

- (instancetype)initWithSink:(id<ZTextSink>)sink {
    if ((self = [super init])) {
        _sink = sink;
        _stats = [ZLedgerStats new];
        _sentCommitted = @"";
        _owned = @"";
        _wantC = @"";
        _wantP = @"";
        _pendingThrottle = kZLedgerPendingThrottle;
        if ([sink respondsToSelector:@selector(useStats:)]) [sink useStats:_stats];
    }
    return self;
}

- (NSUInteger)undelivered { return _wantC.length - MIN(_wantC.length, _sentCommitted.length); }
- (NSUInteger)ownedLength { return _owned.length; }
- (NSUInteger)deliveredLength { return _sentCommitted.length; }

- (void)applyCommitted:(NSString *)committed pending:(NSString *)pending {
    // copy واجب است، نه ادب: فراخوان می‌تواند NSMutableString بدهد و بعد رشدش دهد.
    // آن‌وقت _sentCommitted و _wantC یک شیء می‌شدند، newC همیشه خالی می‌ماند و دفتر
    // فکر می‌کرد کل متن هنوز دُم است. تست هزار عملیاتی دقیقا همین را گرفت.
    _wantC = [committed copy] ?: @"";
    _wantP = [[(pending ?: @"") stringByTrimmingCharactersInSet:
               NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    _dirty = YES;
    [self pump];
}

- (void)flushNow {
    _lastOpAt = 0;
    _dirty = YES;
    [self pump];
}

// دُم دیگر مال ما نیست. هیچ‌چیز پاک نمی‌شود: «چیزی برای تحویل ندارم» یعنی همین، نه
// «هرچه روی صفحه است را پاک کن».
- (void)adoptSink:(id<ZTextSink>)sink committed:(NSString *)committed
        delivered:(NSUInteger)delivered {
    _sink = sink;
    _wantC = [committed copy] ?: @"";
    if ([sink respondsToSelector:@selector(useStats:)]) [sink useStats:_stats];
    // دُمِ مقصدِ قبلی آنجا ماند و دیگر مال ما نیست؛ اینجا از صفر شروع می‌کنیم
    _owned = @"";
    _needSep = NO;
    _pendingSuspended = NO;
    _sentCommitted = [_wantC substringToIndex:MIN(delivered, _wantC.length)];
    _dirty = YES;
    _wantP = @"";
    _lastOpAt = 0;
    [self pump];
}

- (void)disown {
    if (!_owned.length) return;
    _stats.disowns = _stats.disowns + 1;
    _owned = @"";
    _needSep = YES;
    _pendingSuspended = YES;
}

- (void)dropOwned {
    if (!_owned.length) {
        _wantP = @"";
        return;
    }
    if (!self.sink.canRewrite) {
        [self disown];
        _wantP = @"";
        return;
    }
    NSString *expected = _owned;
    NSUInteger n = expected.length;
    _busy = YES;
    __weak typeof(self) ws = self;
    _stats.replaces = _stats.replaces + 1;
    [self.sink replaceLast:n expecting:expected with:@"" done:^(ZSinkResult r) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        if (r == ZSinkOK) {
            s->_owned = @"";
        } else {
            [s disown];
        }
        s->_wantP = @"";
        s->_busy = NO;
        [s pump];
    }];
}

- (void)pump {
    if (_pumping) return;
    _pumping = YES;
    // سقفِ گردش: مقصدِ همگام می‌تواند done را همان‌جا صدا بزند، پس حلقه اینجا واقعا
    // می‌چرخد. هر قدم یا جلو می‌رود یا می‌ایستد؛ این فقط بیمه‌ی حلقه‌ی بی‌پایان است.
    int guard = 0;
    while (_dirty && !_busy && guard++ < 8) {
        if (![self step]) break;
    }
    if (guard >= 8) ZLog(@"ledger: pump hit its turn cap, state suspect");
    _pumping = NO;
}

// یک قدم. NO یعنی «فعلا کاری نیست»، پس حلقه بایستد.
- (BOOL)step {
    NSString *wantC = _wantC;
    // مرزِ قطعیِ بعدی، تعلیقِ دُم را برمی‌دارد: آنجا دفتر و صفحه دوباره هم‌تراز می‌شوند
    if (_pendingSuspended && !_wantP.length) _pendingSuspended = NO;
    NSString *wantP = (self.sink.rendersPending && !_pendingSuspended) ? _wantP : @"";

    // پیشوندِ committed قفل است. اگر شکست، یعنی باگ بالادستی؛ رک بگو و همان لحظه
    // خودت را با واقعیت هم‌تراز کن، نه اینکه متنِ کاربر را قربانی کنی.
    // hasPrefix:@"" در Foundation نه می‌دهد، نه بله. با آن، *هر* قدمِ اولِ سشن
    // «پیشوند عوض شد» می‌شد و دفتر هر بار از نو می‌نوشت.
    BOOL keepsPrefix = _sentCommitted.length == 0
        || (wantC.length >= _sentCommitted.length
            && [[wantC substringToIndex:_sentCommitted.length] isEqualToString:_sentCommitted]);
    if (!keepsPrefix) {
        ZLog(@"ledger: committed prefix changed under us (%lu -> %lu chars), rebasing",
             (unsigned long)_sentCommitted.length, (unsigned long)wantC.length);
        [self disown];
        _sentCommitted = [wantC substringToIndex:MIN(_sentCommitted.length, wantC.length)];
    }

    NSString *newC = [wantC substringFromIndex:_sentCommitted.length];
    // newC فاصله‌ی جداکننده‌اش را خودش با خود دارد، چون بریدنِ committed سر مرز کلمه
    // است. جداکننده فقط بین committed و pending اضافه می‌شود.
    NSMutableString *target = [NSMutableString stringWithString:newC];
    NSUInteger committedPart = target.length;
    if (wantP.length) {
        if (_sentCommitted.length || target.length) [target appendString:@" "];
        [target appendString:wantP];
    }

    NSUInteger k = ZCommonPrefix(_owned, target);
    BOOL destructive = k < _owned.length;

    // سقف زمانی فقط برای دُم. تکه‌ی قطعی (newC) بی‌معطلی می‌رود.
    if (!newC.length && _pendingThrottle > 0) {
        NSTimeInterval since = CFAbsoluteTimeGetCurrent() - _lastOpAt;
        if (since < _pendingThrottle) {
            [self scheduleThrottledPump:_pendingThrottle - since];
            return NO;
        }
    }

    if (!destructive) {
        NSString *add = [target substringFromIndex:k];
        if (!add.length) {
            _dirty = NO;
            [self markPending:target.length - committedPart];
            return NO;
        }
        // بعد از رها کردن مالکیت، تکه‌ی جامانده روی صفحه است؛ متن تازه نباید بچسبد
        if (_needSep && ![add hasPrefix:@" "] && ![add hasPrefix:@"\n"]) {
            add = [@" " stringByAppendingString:add];
        }
        [self runOp:^(id<ZTextSink> sink, void (^done)(ZSinkResult)) {
            [sink appendText:add done:done];
        } stat:^(ZLedgerStats *st) {
            st.appends = st.appends + 1;
        } commit:wantC owned:[target substringFromIndex:committedPart]];
        return YES;
    }

    NSUInteger n = _owned.length - k;
    if (!self.sink.canRewrite) {
        // مقصدی که بازنویسی نمی‌پذیرد (پیست، یا اپی که تاییدی نمی‌دهد) هیچ‌وقت
        // Backspace نمی‌بیند. متنِ نشسته می‌ماند و بقیه اضافه می‌شود.
        ZLog(@"ledger: sink cannot rewrite, disowning %lu chars", (unsigned long)n);
        [self disown];
        return YES;    // دور بعد به شاخه‌ی append می‌افتد
    }
    NSString *expected = [_owned substringFromIndex:k];
    NSString *with = [target substringFromIndex:k];
    [self runOp:^(id<ZTextSink> sink, void (^done)(ZSinkResult)) {
        [sink replaceLast:n expecting:expected with:with done:done];
    } stat:^(ZLedgerStats *st) {
        st.replaces = st.replaces + 1;
    } commit:wantC owned:[target substringFromIndex:committedPart]];
    return YES;
}

- (void)runOp:(void (^)(id<ZTextSink> sink, void (^done)(ZSinkResult)))op
         stat:(void (^)(ZLedgerStats *st))bump
       commit:(NSString *)wantC
        owned:(NSString *)ownedAfter {
    _busy = YES;
    bump(_stats);
    __weak typeof(self) ws = self;
    op(self.sink, ^(ZSinkResult r) {
        __strong typeof(ws) s = ws;
        if (!s) return;
        s->_busy = NO;
        s->_lastOpAt = CFAbsoluteTimeGetCurrent();
        switch (r) {
            case ZSinkOK:
                s->_sentCommitted = wantC;
                s->_owned = ownedAfter;
                s->_needSep = NO;
                [s markPending:ownedAfter.length];
                break;
            case ZSinkUnavailable:
                // مقصد جلو نیست. هیچ‌چیز جلو نمی‌رود و متن در دفتر می‌ماند؛ همین
                // «صف» است، بی آنکه صفِ جدایی وجود داشته باشد.
                s->_stats.unavailable = s->_stats.unavailable + 1;
                s->_dirty = NO;
                break;
            case ZSinkDisowned:
                // نشد ثابت کنیم دُم مال ماست. آنچه روی صفحه است می‌ماند و متن تازه
                // بعدش اضافه می‌شود. چند کلمه تکرار، در برابر چند کلمه گم‌شده.
                [s disown];
                s->_dirty = YES;
                break;
        }
        [s pump];
    });
}

- (void)markPending:(NSUInteger)n {
    if ([self.sink respondsToSelector:@selector(markPendingLength:)]) {
        [self.sink markPendingLength:n];
    }
}

- (void)scheduleThrottledPump:(NSTimeInterval)delay {
    _throttleGen++;
    NSInteger gen = _throttleGen;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(ws) s = ws;
        if (!s || s->_throttleGen != gen) return;
        [s pump];
    });
}

@end

// ---------- ZMemorySink ----------
// مقصدِ در حافظه. بازپخش و تست‌ها از این می‌خوانند، پس همان خط لوله‌ای که در اپ
// می‌دود اینجا هم می‌دود، بی‌میکروفن و بی‌شبکه و قطعی.

@implementation ZMemorySink {
    BOOL _touched;      // کسی جز ما دست زده: تاییدِ «دستِ نخورده» دیگر معتبر نیست
    NSMutableArray<NSString *> *_ops;
    ZLedgerStats *_stats;
}

@synthesize text = _text;

- (instancetype)init {
    if ((self = [super init])) {
        _text = [NSMutableString string];
        _ops = [NSMutableArray array];
        _rendersPendingFlag = YES;
        _rewritable = YES;
        _readable = YES;
        _available = YES;
    }
    return self;
}

- (NSArray<NSString *> *)ops { return _ops; }
- (void)useStats:(ZLedgerStats *)stats { _stats = stats; }

- (BOOL)rendersPending { return _rendersPendingFlag; }
- (BOOL)canRewrite { return _rewritable; }

- (void)userTyped:(NSString *)s {
    [_text appendString:s];
    _touched = YES;
}

- (void)appendText:(NSString *)text done:(void (^)(ZSinkResult))done {
    if (!_available) {
        done(ZSinkUnavailable);
        return;
    }
    [_ops addObject:[@"+" stringByAppendingString:text]];
    [_text appendString:text];
    _touched = NO;
    done(ZSinkOK);
}

- (void)replaceLast:(NSUInteger)n expecting:(NSString *)expected with:(NSString *)text
               done:(void (^)(ZSinkResult))done {
    if (!_available) {
        done(ZSinkUnavailable);
        return;
    }
    if (_readable) {
        // تاییدِ سطح یک: واقعا همان چیزی آنجاست که فکر می‌کنیم؟
        if (_text.length < n ||
            ![[_text substringFromIndex:_text.length - n] isEqualToString:expected]) {
            done(ZSinkDisowned);
            return;
        }
        _stats.verifiedByRead = _stats.verifiedByRead + 1;
    } else if (_touched) {
        // تاییدِ سطح دو نشد: از آخرین نوشتنِ ما کسی دست زده
        done(ZSinkDisowned);
        return;
    } else {
        _stats.verifiedByEpoch = _stats.verifiedByEpoch + 1;
    }
    [_ops addObject:[NSString stringWithFormat:@"-%lu+%@", (unsigned long)n, text]];
    [_text deleteCharactersInRange:NSMakeRange(_text.length - n, n)];
    [_text appendString:text];
    _touched = NO;
    done(ZSinkOK);
}

@end
