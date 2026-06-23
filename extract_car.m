// extract_car.m — compile with:
// clang -fobjc-arc -o extract_car extract_car.m -framework Foundation -framework CoreGraphics -framework ImageIO -F /System/Library/PrivateFrameworks -framework CoreUI
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>
#import <objc/runtime.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "Usage: extract_car <input.car> <output_dir>\n");
            return 1;
        }

        NSString *carPath  = [NSString stringWithUTF8String:argv[1]];
        NSString *outDir   = [NSString stringWithUTF8String:argv[2]];

        // Load CoreUI private framework via dlopen
        dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_LAZY | RTLD_GLOBAL);

        Class CUICatalog = NSClassFromString(@"CUICatalog");
        if (!CUICatalog) {
            fprintf(stderr, "ERROR: CUICatalog not found in CoreUI\n");
            return 1;
        }

        NSURL *carURL = [NSURL fileURLWithPath:carPath];
        NSError *error = nil;
        id catalog = [[CUICatalog alloc] initWithURL:carURL error:&error];
        if (!catalog || error) {
            fprintf(stderr, "ERROR: Could not load .car: %s\n",
                    error ? error.localizedDescription.UTF8String : "unknown");
            return 1;
        }

        NSArray<NSString *> *names = [catalog performSelector:@selector(allImageNames)];
        if (!names) {
            fprintf(stderr, "ERROR: allImageNames returned nil\n");
            return 1;
        }
        NSLog(@"Found %lu named images", (unsigned long)names.count);

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSUInteger count = 0;
        for (NSString *name in names) {
            id themed = [catalog performSelector:@selector(imageWithName:scaleFactor:)
                                     withObject:name
                                     withObject:@(2.0)];
            if (!themed) { themed = [catalog performSelector:@selector(imageWithName:scaleFactor:)
                                                  withObject:name
                                                  withObject:@(1.0)]; }
            if (!themed) continue;

            // CUINamedImage → CGImageRef via -image selector
            SEL imageSel = @selector(image);
            if (![themed respondsToSelector:imageSel]) continue;

            // Use IMP to avoid ARC/pointer-type issues
            IMP imp = [themed methodForSelector:imageSel];
            CGImageRef (*imageFunc)(id, SEL) = (CGImageRef (*)(id, SEL))imp;
            CGImageRef cgImage = imageFunc(themed, imageSel);
            if (!cgImage) continue;

            NSString *safeName = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            NSString *outPath  = [NSString stringWithFormat:@"%@/%@.png", outDir, safeName];
            NSURL   *outURL    = [NSURL fileURLWithPath:outPath];

            CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
                (__bridge CFURLRef)outURL, CFSTR("public.png"), 1, NULL);
            if (!dst) continue;
            CGImageDestinationAddImage(dst, cgImage, NULL);
            CGImageDestinationFinalize(dst);
            CFRelease(dst);
            count++;
        }

        printf("Extracted %lu / %lu images\n", count, (unsigned long)names.count);
    }
    return 0;
}
