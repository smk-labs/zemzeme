// نشان زمزمه: حباب گفتار که سه میله‌ی صدا از دلش خالی شده، یعنی «حرف می‌زنی،
// پیام می‌شود». یک تعریف برای همه جا: نقطه‌ی پنل، نشانگر کنار کرسر، منوبار،
// آیکون بسته و عکس‌های طراحی همه از همین دو تابع می‌کشند، پس شکل هیچ دو جایی
// واگرا نمی‌شود. مختصات یکه: x در [0..ZMarkAspect]، y در [0..1]، و رسم فقط با
// ارتفاع مقیاس می‌شود که سوراخ‌ها و گوشه‌ها در هیچ نسبتی له نشوند.
#import "zemzeme.h"

const CGFloat ZMarkAspect = 1.08;

static void ZMarkFill(void) {
    // سوراخ‌ها با even-odd از خود حباب کم می‌شوند؛ دُم جدا پر می‌شود که سوراخی
    // رویش نیفتد و با هم‌پوشانی به بدنه جوش بخورد.
    NSBezierPath *tail = [NSBezierPath bezierPath];
    [tail moveToPoint:NSMakePoint(0.16, 0.30)];
    [tail lineToPoint:NSMakePoint(0.16, 0.02)];
    [tail lineToPoint:NSMakePoint(0.44, 0.24)];
    [tail closePath];
    [tail fill];

    NSBezierPath *p = [NSBezierPath bezierPath];
    p.windingRule = NSWindingRuleEvenOdd;
    [p appendBezierPathWithRoundedRect:NSMakeRect(0.03, 0.22, 1.02, 0.76)
                               xRadius:0.24 yRadius:0.24];
    // میله‌های صدا نسبت به حباب عمدا پهن‌اند: معنا را سوراخ‌ها می‌برند و در ۹
    // نقطه‌ی رتینا (۱۸ پیکسل) باید باز بمانند
    static const CGFloat bar[3][3] = {
        {0.32, 0.47, 0.73}, {0.54, 0.36, 0.84}, {0.76, 0.51, 0.69}};
    for (int i = 0; i < 3; i++) {
        NSRect r = NSMakeRect(bar[i][0] - 0.155 / 2, bar[i][1], 0.155, bar[i][2] - bar[i][1]);
        [p appendBezierPathWithRoundedRect:r xRadius:0.155 / 2 yRadius:0.155 / 2];
    }
    [p fill];
}

static void ZMarkDraw(NSRect box, NSColor *color) {
    CGFloat h = MIN(box.size.height, box.size.width / ZMarkAspect);
    NSGraphicsContext *g = NSGraphicsContext.currentContext;
    CGContextRef ctx = g.CGContext;
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, NSMidX(box) - h * ZMarkAspect / 2, NSMidY(box) - h / 2);
    CGContextScaleCTM(ctx, h, h);
    [color set];
    ZMarkFill();
    CGContextRestoreGState(ctx);
}

@implementation ZMarkView {
    NSColor *_color;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;    // ضربان و مقیاس بلندی صدا روی همین لایه سوارند
        _color = NSColor.systemGrayColor;
    }
    return self;
}

- (NSColor *)color { return _color; }

- (void)setColor:(NSColor *)color {
    if ([_color isEqual:color]) return;
    _color = color;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirty {
    ZMarkDraw(self.bounds, _color);
}

@end

NSImage *ZMarkImage(CGFloat height, NSColor *tint) {
    NSImage *img = [NSImage imageWithSize:NSMakeSize(height * ZMarkAspect, height)
                                  flipped:NO drawingHandler:^BOOL(NSRect r) {
        ZMarkDraw(r, tint ?: NSColor.blackColor);
        return YES;
    }];
    // template فقط برای حالت بی‌رنگ: تصویر template رنگ‌آمیزی را نادیده می‌گیرد،
    // پس نسخه‌ی رنگی باید template نباشد و خودش با همان رنگ کشیده شده باشد.
    img.template = tint == nil;
    return img;
}

// ---------- خروجی‌های فایل: آیکون بسته و عکس طراحی ----------

static NSBitmapImageRep *ZMarkRep(int px) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:px pixelsHigh:px bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
}

static BOOL ZMarkWritePNG(NSBitmapImageRep *rep, NSString *path) {
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES];
}

// یک رنگ ثابت برای آیکون بسته؛ فقط سه جای زنده (پنل، کرسر، منوبار) رنگ وضعیت می‌گیرند
static NSColor *ZMarkBrandColor(void) {
    return [NSColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1];
}

// کاشی به سبک آیکون‌های خود مک: بوم ۱۰ درصد حاشیه، کاشی گرد با شعاع ~۲۲ درصد.
// نشان وسط کاشی، سبزِ همان «دارد می‌شنود» روی زمینه‌ی تیره.
static void ZMarkDrawIcon(int px) {
    CGFloat inset = px * 0.098;
    NSRect tile = NSMakeRect(inset, inset, px - 2 * inset, px - 2 * inset);
    CGFloat r = tile.size.width * 0.224;
    [[NSColor colorWithWhite:0.10 alpha:1] set];
    [[NSBezierPath bezierPathWithRoundedRect:tile xRadius:r yRadius:r] fill];
    CGFloat mh = tile.size.height * 0.52;
    ZMarkDraw(NSMakeRect(NSMidX(tile) - mh * ZMarkAspect / 2, NSMidY(tile) - mh / 2,
                         mh * ZMarkAspect, mh),
              ZMarkBrandColor());
}

// build.sh: zemzeme --appicon <dir> پوشه‌ی iconset را پر می‌کند و iconutil بقیه‌اش را
// می‌سازد. قبل از NSApplication اجرا می‌شود و به اپ در حال اجرا دست نمی‌زند.
int ZMarkIconMain(NSString *dir) {
    [NSFileManager.defaultManager createDirectoryAtPath:dir
                            withIntermediateDirectories:YES attributes:nil error:nil];
    static const int sizes[] = {16, 32, 128, 256, 512};
    for (unsigned k = 0; k < sizeof(sizes) / sizeof(*sizes); k++) {
        for (int scale = 1; scale <= 2; scale++) {
            int px = sizes[k] * scale;
            NSBitmapImageRep *rep = ZMarkRep(px);
            NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = g;
            ZMarkDrawIcon(px);
            [NSGraphicsContext restoreGraphicsState];
            NSString *name = scale == 1
                ? [NSString stringWithFormat:@"icon_%dx%d.png", sizes[k], sizes[k]]
                : [NSString stringWithFormat:@"icon_%dx%d@2x.png", sizes[k], sizes[k]];
            if (!ZMarkWritePNG(rep, [dir stringByAppendingPathComponent:name])) {
                fprintf(stderr, "appicon: cannot write %s\n", name.UTF8String);
                return 1;
            }
        }
    }
    return 0;
}

// عکس طراحی برای --uishot: همان نشان در اندازه‌های واقعی کار (۹، ۱۴، ۱۸ در 1x و
// 2x)، در چهار رنگ وضعیت، روی نیمه‌ی روشن و تیره، به‌اضافه‌ی آیکون بسته. رنگ‌ها از
// خود ZStatusColor می‌آیند نه کپی، پس عکس همیشه با اپ هم‌رنگ است.
void ZMarkShot(NSString *dir) {
    ZPanelModel *listening = [ZPanelModel new];
    listening.listening = YES;
    ZPanelModel *trouble = [ZPanelModel new];
    trouble.error = YES;
    ZPanelModel *connecting = [ZPanelModel new];
    ZPanelModel *paused = [ZPanelModel new];
    paused.paused = YES;
    NSArray<ZPanelModel *> *models = @[listening, trouble, connecting, paused];

    const int W = 760, H = 340;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = g;
    static const CGFloat pts[] = {9, 14, 18};
    for (int half = 0; half < 2; half++) {
        NSRect bg = NSMakeRect(half * (W / 2.0), 0, W / 2.0, H);
        [[NSColor colorWithWhite:half ? 0.11 : 0.97 alpha:1] set];
        NSRectFill(bg);
        for (int mi = 0; mi < 4; mi++) {
            NSColor *c = ZStatusColor(models[mi]);
            CGFloat x = NSMinX(bg) + 24 + mi * 86;
            CGFloat y = H - 40;
            for (unsigned pi = 0; pi < sizeof(pts) / sizeof(*pts); pi++) {
                for (int scale = 1; scale <= 2; scale++) {
                    CGFloat h = pts[pi] * scale;
                    y -= h + 10;
                    ZMarkDraw(NSMakeRect(x, y, h * ZMarkAspect, h), c);
                }
            }
        }
        // آیکون بسته، کوچک‌شده، برای یک نگاه
        NSImage *icon = [NSImage imageWithSize:NSMakeSize(96, 96) flipped:NO
                                drawingHandler:^BOOL(NSRect r) {
            ZMarkDrawIcon(96);
            return YES;
        }];
        [icon drawInRect:NSMakeRect(NSMinX(bg) + W / 2.0 - 120, 18, 96, 96)
                fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    }
    [NSGraphicsContext restoreGraphicsState];
    ZMarkWritePNG(rep, [dir stringByAppendingPathComponent:@"mark.png"]);
}
