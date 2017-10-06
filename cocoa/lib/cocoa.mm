
#import <Cocoa/Cocoa.h>

#include <iostream>
#include <string>
#include <thread>
#include <unordered_map>

#include <json/json.hpp>

using json = nlohmann::json;

@interface WindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation WindowDelegate

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)__unused size {
    // std::cerr << "Resized Window!: " << size.width << " " << size.height << std::endl;

    const auto frame = window.contentView.frame;
    std::cerr << "Resized Window!: " << frame.size.width << " " << frame.size.height << std::endl;

    return size;
}

@end

@interface Action : NSObject {
    std::string identifier;
}
@end

@implementation Action

- (id)initWithID:(std::string)ident {
    if (self = [super init]) {
        self->identifier = ident;
    }
    return self;
}

- (void)click:(id)__unused sender {
    // TODO: formalize as JSON
    std::cout << "click." << self->identifier << std::endl;
}

@end

// TODO: create Label & Button classes
// TODO: split into separate files

@interface TextField : NSTextField <NSTextFieldDelegate> {
    std::string identifier;
}
@end

@implementation TextField

- (id)initWithFrame:(NSRect)frame ID:(std::string)ident {
    if (self = [super initWithFrame:frame]) {
        self->identifier = ident;

        [self setBezeled:YES];
        [self setDrawsBackground:YES];
        [self setEditable:YES];
        [self setSelectable:YES];

        [self setDelegate:self];
    }
    return self;
}

- (void)controlTextDidChange:(NSNotification *)__unused notification {
    std::cerr << "controlTextDidChange!" << std::endl;

    // TODO: send JSON event!
}

@end

extern "C" void run() {
    static_assert(!__has_feature(objc_arc), "verify ARC is NOT enabled!");

    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // build menu for window
    {
        auto menubar = [NSMenu new];

        auto app_menu_item = [NSMenuItem new];
        [menubar addItem:app_menu_item];

        [NSApp setMainMenu:menubar];

        auto app_menu = [NSMenu new];
        auto quit_item = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                    action:@selector(terminate:)
                                             keyEquivalent:@"q"];
        [app_menu addItem:quit_item];
        [app_menu_item setSubmenu:app_menu];
    }

    auto frame = NSMakeRect(0, 0, 500, 500);

#ifdef MAC_OS_X_VERSION_10_12 // macOS >= 10.12 (for WindowMask deprecation)
    auto styleMask = NSWindowStyleMaskResizable | NSWindowStyleMaskTitled |
                     NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskClosable;
#else
    auto styleMask = NSResizableWindowMask | NSTitledWindowMask | NSMiniaturizableWindowMask |
                     NSClosableWindowMask;
#endif

    auto window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];

    [window setDelegate:[[WindowDelegate alloc] init]];

    [window cascadeTopLeftFromPoint:NSMakePoint(0, 0)];
    [window center];
    [window setTitle:@"** cedar **"];
    [window makeKeyAndOrderFront:nil];

    // Bring window to front
    auto app = [NSRunningApplication currentApplication];
    [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];

    std::thread([&] {
        std::unordered_map<std::string, NSView *> widgets;

        std::string line;
        while (std::getline(std::cin, line)) {
            auto event = json::parse(line);

            if (event.count("Create")) {
                auto &create = event["Create"];
                auto &ident = create["id"];
                auto &widget = create["kind"];
                std::string text = create["text"];
                auto &location = create["frame"];

                // Convert left-top to left-bottom coordinates
                const float left = location[0];
                const float top = location[1];
                const float width = location[2];
                const float height = location[3];
                const float bottom = window.contentView.frame.size.height - (top + height);

                const auto frame = NSMakeRect(left, bottom, width, height);

                if (widget == "Button") {
                    auto button = [[NSButton alloc] initWithFrame:frame];
                    button.bezelStyle = NSRoundedBezelStyle;

                    button.title = [NSString stringWithUTF8String:text.c_str()];

                    auto action = [[Action alloc] initWithID:ident];
                    [button setAction:@selector(click:)];
                    [button setTarget:action];

                    widgets[ident] = button;
                    [window.contentView addSubview:button];
                } else if (widget == "Label") {
                    auto label = [[NSTextField alloc] initWithFrame:frame];

                    [label setStringValue:[NSString stringWithUTF8String:text.c_str()]];

                    [label setBezeled:NO];
                    [label setDrawsBackground:NO];
                    [label setEditable:NO];
                    [label setSelectable:NO];

                    [label setAlignment:NSTextAlignmentCenter];

                    widgets[ident] = label;
                    [window.contentView addSubview:label];
                } else if (widget == "Field") {
                    auto field = [[TextField alloc] initWithFrame:frame ID:ident];

                    widgets[ident] = field;
                    [window.contentView addSubview:field];
                } else {
                    std::cerr << "Unknown widget: " << widget << std::endl;
                }

            } else if (event.count("Update")) {
                auto &update = event["Update"];
                auto ident = update[0];
                auto attribute = update[1];
                std::string value = update[2];

                if (attribute == "Text") {
                    auto field = (NSTextField *)(widgets[ident]);
                    [field setStringValue:[NSString stringWithUTF8String:value.c_str()]];
                }
            }
        }
    }).detach();

    [NSApp run];
}
