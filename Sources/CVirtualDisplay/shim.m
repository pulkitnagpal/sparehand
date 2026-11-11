// Thin wrapper over CoreGraphics' private CGVirtualDisplay classes (the same API display utilities use).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "CVirtualDisplay.h"

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (copy, nonatomic) void (^terminationHandler)(id, id);
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end
@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

SHVirtualDisplay SHCreateVirtualDisplay(uint32_t width, uint32_t height, uint32_t serial, const char *name) {
    SHVirtualDisplay result = {0, NULL};
    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descClass || !displayClass) return result;   // API gone in this macOS
    CGVirtualDisplayDescriptor *desc = [descClass new];
    desc.queue = dispatch_get_main_queue();
    desc.name = [NSString stringWithUTF8String:name];
    desc.maxPixelsWide = width;
    desc.maxPixelsHigh = height;
    desc.sizeInMillimeters = CGSizeMake(width * 0.2745, height * 0.2745);   // ~92 dpi, like a 24" monitor
    desc.serialNum = serial;
    desc.productID = 0x5348;
    desc.vendorID = 0x5348;
    desc.terminationHandler = ^(id a, id b) {};
    CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:desc];
    if (!display) return result;
    CGVirtualDisplaySettings *settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    settings.hiDPI = 0;
    settings.modes = @[[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:width height:height refreshRate:60]];
    if (![display applySettings:settings]) return result;
    result.displayID = display.displayID;
    result.handle = (__bridge_retained void *)display;
    return result;
}

void SHDestroyVirtualDisplay(SHVirtualDisplay d) {
    if (d.handle) { CFBridgingRelease(d.handle); }
}
