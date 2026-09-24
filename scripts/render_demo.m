#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Generate the animated terminal demo used by README.md:
//
//   mkdir -p /tmp/histodiff-clang-cache
//   CLANG_MODULE_CACHE_PATH=/tmp/histodiff-clang-cache clang -fobjc-arc \
//     -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
//     scripts/render_demo.m -o /tmp/render-histodiff-demo
//   /tmp/render-histodiff-demo

static const CGFloat canvasWidth = 960;
static const CGFloat canvasHeight = 600;
static const CGFloat lineHeight = 16;
static const NSInteger maxRows = 29;

static NSColor *RGB(CGFloat red, CGFloat green, CGFloat blue) {
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1];
}

static NSDictionary *Span(NSString *text, NSColor *color, BOOL bold) {
    return @{ @"text": text, @"color": color, @"bold": @(bold) };
}

static NSString *captureOutput(void) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    task.arguments = @[
        @"python3", @"-m", @"histodiff",
        @"examples/frobnitz_old.c", @"examples/frobnitz_new.c",
        @"--color-words", @"-U", @"0"
    ];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"PYTHONPATH"] = @"src";
    task.environment = environment;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"Could not launch histodiff: %@", error);
        exit(1);
    }
    [task waitUntilExit];
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (output.length == 0) {
        NSLog(@"histodiff produced no output");
        exit(1);
    }

    // File mtimes add visual noise and make regenerated demos differ.
    NSMutableArray<NSString *> *rawLines = [[output componentsSeparatedByString:@"\n"] mutableCopy];
    for (NSInteger index = 0; index < MIN(2, rawLines.count); index++) {
        NSRange tab = [rawLines[index] rangeOfString:@"\t"];
        if (tab.location != NSNotFound) {
            rawLines[index] = [rawLines[index] substringToIndex:tab.location];
        }
    }
    return [rawLines componentsJoinedByString:@"\n"];
}

static NSArray<NSArray<NSDictionary *> *> *parseANSI(NSString *source) {
    NSColor *foreground = RGB(0.83, 0.87, 0.92);
    NSColor *red = RGB(0.98, 0.43, 0.45);
    NSColor *green = RGB(0.36, 0.82, 0.58);
    NSColor *cyan = RGB(0.35, 0.73, 0.94);
    NSMutableArray *lines = [NSMutableArray arrayWithObject:[NSMutableArray array]];
    NSMutableString *buffer = [NSMutableString string];
    __block NSColor *color = foreground;
    __block BOOL bold = NO;

    void (^flush)(void) = ^{
        if (buffer.length == 0) return;
        [lines.lastObject addObject:Span([buffer copy], color, bold)];
        [buffer setString:@""];
    };

    for (NSUInteger index = 0; index < source.length;) {
        unichar character = [source characterAtIndex:index];
        if (character == 0x1b && index + 1 < source.length) {
            flush();
            NSRange remainder = NSMakeRange(index, source.length - index);
            NSRange end = [source rangeOfString:@"m" options:0 range:remainder];
            if (end.location == NSNotFound) break;
            NSUInteger codeStart = MIN(index + 2, end.location);
            NSString *code = [source substringWithRange:NSMakeRange(codeStart, end.location - codeStart)];
            if ([code isEqualToString:@"0"]) { color = foreground; bold = NO; }
            else if ([code isEqualToString:@"1"]) bold = YES;
            else if ([code isEqualToString:@"31"]) color = red;
            else if ([code isEqualToString:@"32"]) color = green;
            else if ([code isEqualToString:@"36"]) color = cyan;
            index = NSMaxRange(end);
            continue;
        }
        if (character == '\n') {
            flush();
            [lines addObject:[NSMutableArray array]];
        } else {
            [buffer appendFormat:@"%C", character];
        }
        index++;
    }
    flush();
    if ([lines.lastObject count] == 0) [lines removeLastObject];
    return lines;
}

static void drawText(NSString *text, NSPoint point, NSColor *color, NSFont *font) {
    [text drawAtPoint:point withAttributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    }];
}

static CGImageRef makeFrame(NSString *commandPrefix, NSArray *visibleOutput, BOOL cursorVisible) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:(NSInteger)canvasWidth pixelsHigh:(NSInteger)canvasHeight
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;

    [RGB(0.035, 0.047, 0.067) setFill];
    NSRectFill(NSMakeRect(0, 0, canvasWidth, canvasHeight));
    NSRect terminalRect = NSMakeRect(28, 28, 904, 544);
    NSBezierPath *window = [NSBezierPath bezierPathWithRoundedRect:terminalRect xRadius:12 yRadius:12];
    [RGB(0.071, 0.086, 0.118) setFill];
    [window fill];
    [RGB(0.18, 0.22, 0.29) setStroke];
    window.lineWidth = 1;
    [window stroke];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.045] setFill];
    NSRectFill(NSMakeRect(29, 530, 902, 41));
    NSArray *lights = @[
        @{ @"x": @52, @"color": NSColor.systemRedColor },
        @{ @"x": @73, @"color": NSColor.systemYellowColor },
        @{ @"x": @94, @"color": NSColor.systemGreenColor }
    ];
    for (NSDictionary *light in lights) {
        [light[@"color"] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect([light[@"x"] doubleValue], 545, 11, 11)] fill];
    }

    NSFont *titleFont = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    NSString *title = @"histodiff — human-readable diffs";
    CGFloat titleWidth = [title sizeWithAttributes:@{NSFontAttributeName: titleFont}].width;
    drawText(title, NSMakePoint(480 - titleWidth / 2, 543), RGB(0.50, 0.56, 0.65), titleFont);

    NSColor *foreground = RGB(0.83, 0.87, 0.92);
    NSFont *regularFont = [NSFont fontWithName:@"Menlo" size:12.5];
    NSFont *boldFont = [NSFont fontWithName:@"Menlo-Bold" size:12.5];
    NSMutableArray *commandSpans = [NSMutableArray arrayWithArray:@[
        Span(@"❯ ", RGB(0.72, 0.57, 0.95), YES),
        Span(commandPrefix, foreground, NO)
    ]];
    if (cursorVisible) [commandSpans addObject:Span(@"▌", RGB(0.36, 0.82, 0.58), NO)];

    NSMutableArray *rows = [NSMutableArray arrayWithObject:commandSpans];
    [rows addObjectsFromArray:visibleOutput];
    if (rows.count > maxRows) {
        rows = [[rows subarrayWithRange:NSMakeRange(rows.count - maxRows, maxRows)] mutableCopy];
    }
    for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
        CGFloat x = 52;
        CGFloat y = 506 - rowIndex * lineHeight;
        for (NSDictionary *span in rows[rowIndex]) {
            NSFont *font = [span[@"bold"] boolValue] ? boldFont : regularFont;
            NSString *text = span[@"text"];
            drawText(text, NSMakePoint(x, y), span[@"color"], font);
            x += [text sizeWithAttributes:@{NSFontAttributeName: font}].width;
        }
    }

    [NSGraphicsContext restoreGraphicsState];
    return CGImageCreateCopy(rep.CGImage);
}

static void addFrame(CGImageDestinationRef destination, NSString *command, NSArray *output, BOOL cursor, double delay) {
    CGImageRef image = makeFrame(command, output, cursor);
    NSDictionary *properties = @{
        (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
            (__bridge NSString *)kCGImagePropertyGIFDelayTime: @(delay)
        }
    };
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)properties);
    CGImageRelease(image);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *outputPath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"assets/demo.gif";
        NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
        [NSFileManager.defaultManager createDirectoryAtURL:outputURL.URLByDeletingLastPathComponent
                               withIntermediateDirectories:YES attributes:nil error:nil];

        NSArray *output = parseANSI(captureOutput());
        NSString *command = @"histodiff examples/frobnitz_old.c examples/frobnitz_new.c --color-words -U 0";
        NSInteger typingFrames = (command.length + 4) / 5;
        NSInteger outputFrames = (output.count + 1) / 2;
        NSInteger frameCount = 1 + typingFrames + outputFrames + 1;
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)outputURL,
            (__bridge CFStringRef)UTTypeGIF.identifier,
            frameCount,
            NULL
        );
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImagePropertyGIFDictionary: @{
                (__bridge NSString *)kCGImagePropertyGIFLoopCount: @0
            }
        });

        addFrame(destination, @"", @[], YES, 0.8);
        for (NSUInteger count = 5; count < command.length; count += 5) {
            addFrame(destination, [command substringToIndex:count], @[], YES, 0.09);
        }
        addFrame(destination, command, @[], YES, 0.45);
        for (NSUInteger count = 2; count < output.count; count += 2) {
            addFrame(destination, command, [output subarrayWithRange:NSMakeRange(0, count)], NO, 0.11);
        }
        addFrame(destination, command, output, NO, 0.11);
        addFrame(destination, command, output, YES, 2.8);

        if (!CGImageDestinationFinalize(destination)) {
            NSLog(@"Could not finalize GIF");
            CFRelease(destination);
            return 1;
        }
        CFRelease(destination);
        printf("Wrote %s\n", outputPath.UTF8String);
    }
    return 0;
}
