/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import "MMWindowController.h"
#import <PSMTabBarControl.h>
#import "MMTextView.h"
#import "MMTextStorage.h"
#import "MMVimController.h"
#import "MacVim.h"
#import "MMAppController.h"
#import "MMTypesetter.h"


// Scroller type; these must match SBAR_* in gui.h
enum {
    MMScrollerTypeLeft = 0,
    MMScrollerTypeRight,
    MMScrollerTypeBottom
};

// NOTE!  This value must match the actual position of the status line
// separator in VimWindow.nib.
static float StatusLineHeight = 16.0f;


// TODO:  Move!
@interface NSTabView (MMExtras)
- (void)removeAllTabViewItems;
@end


// TODO:  Move!
@interface MMScroller : NSScroller {
    long identifier;
    int type;
    NSRange range;
}
- (id)initWithIdentifier:(long)ident type:(int)type;
- (long)identifier;
- (int)type;
- (NSRange)range;
- (void)setRange:(NSRange)newRange;
@end

@interface MMWindowController (Private)
- (NSSize)contentSizeForTextStorageSize:(NSSize)textViewSize;
- (NSRect)textViewRectForContentSize:(NSSize)contentSize;
- (NSSize)textStorageSizeForTextViewSize:(NSSize)textViewSize;
- (void)resizeWindowToFit:(id)sender;
- (NSRect)fitWindowToFrame:(NSRect)frame;
- (void)updateResizeIncrements;
- (NSTabViewItem *)addNewTabViewItem;
- (void)statusTimerFired:(NSTimer *)timer;
- (int)representedIndexOfTabViewItem:(NSTabViewItem *)tvi;
- (IBAction)vimMenuItemAction:(id)sender;
- (MMScroller *)scrollbarForIdentifier:(long)ident index:(unsigned *)idx;
- (BOOL)bottomScrollbarVisible;
- (BOOL)leftScrollbarVisible;
- (BOOL)rightScrollbarVisible;
- (void)placeScrollbars;
- (void)scroll:(id)sender;
- (void)placeViews;
@end



#if 0
NSString *buildMenuItemDescriptor(NSMenu *menu, NSString *tail)
{
    return menu ? buildMenuItemDescriptor([menu supermenu], [[menu title]
                    stringByAppendingString:tail])
                : tail;
}

NSMutableArray *buildMenuAddress(NSMenu *menu)
{
    NSMutableArray *addr;
    if (menu) {
        addr = buildMenuAddress([menu supermenu]);
        [addr addObject:[menu title]];
    } else {
        addr = [NSMutableArray array];
    }

    return addr;
}
#endif


@implementation MMWindowController

- (id)initWithVimController:(MMVimController *)controller
{
    if ((self = [super initWithWindowNibName:@"VimWindow"])) {
        vimController = controller;
        scrollbars = [[NSMutableArray alloc] init];

        // Setup a complete text system.
        textStorage = [[MMTextStorage alloc] init];
        NSLayoutManager *lm = [[NSLayoutManager alloc] init];
        NSTextContainer *tc = [[NSTextContainer alloc] initWithContainerSize:
                NSMakeSize(1.0e7,1.0e7)];

        NSString *typesetterString = [[NSUserDefaults standardUserDefaults]
                stringForKey:MMTypesetterKey];
        if (![typesetterString isEqual:@"NSTypesetter"]) {
            MMTypesetter *typesetter = [[MMTypesetter alloc] init];
            [lm setTypesetter:typesetter];
            [typesetter release];
        } else {
            // Only MMTypesetter supports different cell width multipliers.
            [[NSUserDefaults standardUserDefaults]
                    setFloat:1.0 forKey:MMCellWidthMultiplierKey];
        }

        [tc setWidthTracksTextView:NO];
        [tc setHeightTracksTextView:NO];
        [tc setLineFragmentPadding:0];

        [textStorage addLayoutManager:lm];
        [lm addTextContainer:tc];

        textView = [[MMTextView alloc] initWithFrame:NSZeroRect
                                       textContainer:tc];

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        int left = [ud integerForKey:MMTextInsetLeftKey];
        int top = [ud integerForKey:MMTextInsetTopKey];
        [textView setTextContainerInset:NSMakeSize(left, top)];

        // The text storage retains the layout manager which in turn retains
        // the text container.
        [tc release];
        [lm release];
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"%@ %s", [self className], _cmd);

    // TODO: release tabBarControl and tabView?

    vimController = nil;

    [tabBarControl setDelegate:nil];
    [[self window] setDelegate:nil];

    [tabView removeAllTabViewItems];

    [scrollbars release];
    [textView release];
    [textStorage release];

    [super dealloc];
}

- (void)windowDidLoad
{
    // Called after window nib file is loaded.

    [tablineSeparator setHidden:NO];
    [tabBarControl setHidden:YES];

    // NOTE: Size to fit looks good, but not many tabs will fit and there are
    // quite a few drawing bugs in this code, so it is disabled for now.
    //[tabBarControl setSizeCellsToFit:YES];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [tabBarControl setCellMinWidth:[ud integerForKey:MMTabMinWidthKey]];
    [tabBarControl setCellMaxWidth:[ud integerForKey:MMTabMaxWidthKey]];
    [tabBarControl setCellOptimumWidth:[ud integerForKey:MMTabOptimumWidthKey]];

    [tabBarControl setAllowsDragBetweenWindows:NO];
    [tabBarControl setShowAddTabButton:YES];
    [[tabBarControl addTabButton] setTarget:self];
    [[tabBarControl addTabButton] setAction:@selector(addNewTab:)];

    // HACK! remove any tabs present in the nib
    [tabView removeAllTabViewItems];

    // HACK!  These observers used to be set in the designated init of
    // MMVimController, but this occasionally caused exceptions from within the
    // AppKit to be raised.  The problem seemed related to the fact that the
    // window got loaded 'too early'; adding the observers here seems to
    // alleviate this problem.
    [[NSNotificationCenter defaultCenter]
            addObserver:vimController
               selector:@selector(windowWillClose:)
                   name:NSWindowWillCloseNotification
                 object:[self window]];
    [[NSNotificationCenter defaultCenter]
            addObserver:vimController
               selector:@selector(windowDidBecomeMain:)
                   name:NSWindowDidBecomeMainNotification
                 object:[self window]];
}

- (MMVimController *)vimController
{
    return vimController;
}

- (MMTextView *)textView
{
    return textView;
}

- (MMTextStorage *)textStorage
{
    return textStorage;
}

- (void)openWindow
{
    [self addNewTabViewItem];

    // NOTE! This flag is set once the entire text system is set up.
    setupDone = YES;

    [self updateResizeIncrements];
    [self resizeWindowToFit:self];

    [[self window] makeKeyAndOrderFront:self];

    BOOL statusOff = [[NSUserDefaults standardUserDefaults]
                    boolForKey:MMStatuslineOffKey];
    [statusTextField setHidden:statusOff];
    [statusSeparator setHidden:statusOff];
    [self flashStatusText:@"Welcome to MacVim!"];
}

- (void)updateTabsWithData:(NSData *)data
{
    const void *p = [data bytes];
    const void *end = p + [data length];
    int tabIdx = 0;

    // HACK!  Current tab is first in the message.  This way it is not
    // necessary to guess which tab should be the selected one (this can be
    // problematic for instance when new tabs are created).
    int curtabIdx = *((int*)p);  p += sizeof(int);

    NSArray *tabViewItems = [tabBarControl representedTabViewItems];

    while (p < end) {
        //int wincount = *((int*)p);  p += sizeof(int);
        int length = *((int*)p);  p += sizeof(int);

        NSString *label = [[NSString alloc]
                initWithBytesNoCopy:(void*)p
                             length:length
                           encoding:NSUTF8StringEncoding
                       freeWhenDone:NO];
        p += length;

        // Set the label of the tab;  add a new tab when needed.
        NSTabViewItem *tvi = [tabView numberOfTabViewItems] <= tabIdx
                ? [self addNewTabViewItem]
                : [tabViewItems objectAtIndex:tabIdx];

        [tvi setLabel:label];

        [label release];

        ++tabIdx;
    }

    // Remove unused tabs from the NSTabView.  Note that when a tab is closed
    // the NSTabView will automatically select another tab, but we want Vim to
    // take care of which tab to select so set the vimTaskSelectedTab flag to
    // prevent the tab selection message to be passed on to the VimTask.
    vimTaskSelectedTab = YES;
    int i, count = [tabView numberOfTabViewItems];
    for (i = count-1; i >= tabIdx; --i) {
        id tvi = [tabViewItems objectAtIndex:i];
        //NSLog(@"Removing tab with index %d", i);
        [tabView removeTabViewItem:tvi];
    }
    vimTaskSelectedTab = NO;

    [self selectTabWithIndex:curtabIdx];
}

- (void)selectTabWithIndex:(int)idx
{
    //NSLog(@"%s%d", _cmd, idx);

    NSArray *tabViewItems = [tabBarControl representedTabViewItems];
    if (idx < 0 || idx >= [tabViewItems count]) {
        NSLog(@"WARNING: No tab with index %d exists.", idx);
        return;
    }

    // Do not try to select a tab if already selected.
    NSTabViewItem *tvi = [tabViewItems objectAtIndex:idx];
    if (tvi != [tabView selectedTabViewItem]) {
        vimTaskSelectedTab = YES;
        [tabView selectTabViewItem:tvi];
        vimTaskSelectedTab = NO;
    }
}

- (void)setTextDimensionsWithRows:(int)rows columns:(int)cols
{
    //NSLog(@"setTextDimensionsWithRows:%d columns:%d", rows, cols);

    [textStorage setMaxRows:rows columns:cols];

    if (setupDone && ![textView inLiveResize])
        shouldUpdateWindowSize = YES;
}

- (void)setStatusText:(NSString *)text
{
    if (text)
        [statusTextField setStringValue:text];
    else
        [statusTextField setStringValue:@""];
}

- (void)flashStatusText:(NSString *)text
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:MMStatuslineOffKey])
        return;

    [self setStatusText:text];

    if (statusTimer) {
        [statusTimer invalidate];
        [statusTimer release];
    }

    statusTimer = [[NSTimer scheduledTimerWithTimeInterval:3
                              target:self
                            selector:@selector(statusTimerFired:)
                            userInfo:nil
                             repeats:NO] retain];
}

- (void)createScrollbarWithIdentifier:(long)ident type:(int)type
{
    //NSLog(@"Create scroller %d of type %d", ident, type);

    MMScroller *scroller = [[MMScroller alloc] initWithIdentifier:ident
                                                             type:type];
    [scroller setTarget:self];
    [scroller setAction:@selector(scroll:)];

    [[[self window] contentView] addSubview:scroller];
    [scrollbars addObject:scroller];
    [scroller release];
}

- (void)destroyScrollbarWithIdentifier:(long)ident
{
    //NSLog(@"Destroy scroller %d", ident);

    unsigned idx = 0;
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:&idx];
    if (scroller) {
        [scroller removeFromSuperview];
        [scrollbars removeObjectAtIndex:idx];

        if (![scroller isHidden]) {
            // A visible scroller was removed, so the window must resize to
            // fit.
            //NSLog(@"Visible scroller %d was destroyed, resizing window.",
            //        ident);
            shouldUpdateWindowSize = YES;
        }
    }
}

- (void)showScrollbarWithIdentifier:(long)ident state:(BOOL)visible
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    if (!scroller) return;

    BOOL wasVisible = ![scroller isHidden];
    //NSLog(@"%s scroller %d (was %svisible)", visible ? "Show" : "Hide",
    //      ident, wasVisible ? "" : "in");
    [scroller setHidden:!visible];

    if (wasVisible != visible) {
        // A scroller was hidden or shown, so the window must resize to fit.
        //NSLog(@"%s scroller %d and resize.", visible ? "Show" : "Hide",
        //        ident);
        shouldUpdateWindowSize = YES;
    }
}

- (void)setScrollbarPosition:(int)pos length:(int)len identifier:(long)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    NSRange range = NSMakeRange(pos, len);
    if (!NSEqualRanges(range, [scroller range])) {
        //NSLog(@"Set range %@ for scroller %d",
        //        NSStringFromRange(range), ident);
        [scroller setRange:range];
        // TODO!  Should only do this once per update.
        [self placeScrollbars];
    }
}

- (void)setScrollbarThumbValue:(float)val proportion:(float)prop
                    identifier:(long)ident
{
    MMScroller *scroller = [self scrollbarForIdentifier:ident index:NULL];
    //NSLog(@"Set thumb value %.2f proportion %.2f for scroller %d",
    //        val, prop, ident);
    [scroller setFloatValue:val knobProportion:prop];
}

- (void)setDefaultColorsBackground:(NSColor *)back foreground:(NSColor *)fore
{
    [textStorage setDefaultColorsBackground:back foreground:fore];
    [textView setBackgroundColor:back];
}

- (void)setFont:(NSFont *)font
{
    [textStorage setFont:font];
    [self updateResizeIncrements];
}

- (void)processCommandQueueDidFinish
{
    if (shouldUpdateWindowSize) {
        shouldUpdateWindowSize = NO;
        [self resizeWindowToFit:self];
    }
}

- (IBAction)addNewTab:(id)sender
{
    // NOTE! This can get called a lot if the user holds down the key
    // equivalent for this action, which causes the ports to fill up.  If we
    // wait for the message to be sent then the app might become unresponsive.
    [vimController sendMessage:AddNewTabMsgID data:nil wait:NO];
}

- (IBAction)showTabBar:(id)sender
{
    [tablineSeparator setHidden:YES];
    [tabBarControl setHidden:NO];

    if (setupDone)
        shouldUpdateWindowSize = YES;
}

- (IBAction)hideTabBar:(id)sender
{
    [tablineSeparator setHidden:NO];
    [tabBarControl setHidden:YES];

    if (setupDone)
        shouldUpdateWindowSize = YES;
}




// -- PSMTabBarControl delegate ----------------------------------------------


- (void)tabView:(NSTabView *)theTabView didSelectTabViewItem:
        (NSTabViewItem *)tabViewItem
{
    // HACK!  There seem to be a bug in NSTextView which results in the first
    // responder not being set to the view of the tab item so it is done
    // manually here.
    [[self window] makeFirstResponder:[tabViewItem view]];

    // HACK!  The selection message should not be propagated to the VimTask if
    // the VimTask selected the tab (e.g. as opposed the user clicking the
    // tab).  The delegate method has no way of knowing who initiated the
    // selection so a flag is set when the VimTask initiated the selection.
    if (!vimTaskSelectedTab) {
        // Propagate the selection message to the VimTask.
        int idx = [self representedIndexOfTabViewItem:tabViewItem];
        if (NSNotFound != idx) {
            NSData *data = [NSData dataWithBytes:&idx length:sizeof(int)];
            [vimController sendMessage:SelectTabMsgID data:data wait:YES];
        }
    }
}

- (BOOL)tabView:(NSTabView *)theTabView shouldCloseTabViewItem:
        (NSTabViewItem *)tabViewItem
{
    // HACK!  This method is only called when the user clicks the close button
    // on the tab.  Instead of letting the tab bar close the tab, we return NO
    // and pass a message on to Vim to let it handle the closing.
    int idx = [self representedIndexOfTabViewItem:tabViewItem];
    //NSLog(@"Closing tab with index %d", idx);
    NSData *data = [NSData dataWithBytes:&idx length:sizeof(int)];
    [vimController sendMessage:CloseTabMsgID data:data wait:YES];

    return NO;
}

- (void)tabView:(NSTabView *)theTabView didDragTabViewItem:
        (NSTabViewItem *)tabViewItem toIndex:(int)idx
{
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&idx length:sizeof(int)];

    [vimController sendMessage:DraggedTabMsgID data:data wait:YES];
}




// -- NSWindow delegate ------------------------------------------------------


- (BOOL)windowShouldClose:(id)sender
{
    [vimController sendMessage:VimShouldCloseMsgID data:nil wait:YES];
    return NO;
}

- (void)windowWillClose:(NSNotification *)notification
{
    //NSLog(@"%@ %s", [self className], _cmd);

    // NOTE! There is a bug in PSMTabBarControl in that it retains the delegate
    // (which is the MMWindowController) so reset the delegate here, otherwise
    // the MMWindowController never gets released resulting in a pretty serious
    // memory leak.
    [tabBarControl setDelegate:nil];
}

- (void)windowDidResize:(id)sender
{
    if (!setupDone) return;
    [self placeViews];
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)win
                        defaultFrame:(NSRect)frame
{
    // HACK!  For some reason 'frame' is not always constrained to fit on the
    // screen (e.g. it may overlap the menu bar), so first constrain it to the
    // screen; otherwise the new frame we compute may be too large and this
    // will mess up the display after the window resizes.
    frame = [win constrainFrameRect:frame toScreen:[win screen]];

    // HACK!  If the top of 'frame' is lower than the current window frame,
    // increase 'frame' so that their tops align.  Really, 'frame' should
    // already have its top at least as high as the current window frame, but
    // for some reason this is not always the case.
    // (See resizeWindowToFit: for a similar hack.)
    NSRect cur = [win frame];
    if (NSMaxY(cur) > NSMaxY(frame)) {
        frame.size.height = cur.origin.y - frame.origin.y + cur.size.height;
    }

    frame = [self fitWindowToFrame:frame];

    // Keep old width and horizontal position unless user clicked with the
    // Command key is held down.
    NSEvent *event = [NSApp currentEvent];
    if (!([event type] == NSLeftMouseUp
            && [event modifierFlags] & NSCommandKeyMask)) {
        NSRect currentFrame = [win frame];
        frame.size.width = currentFrame.size.width;
        frame.origin.x = currentFrame.origin.x;
    }

    return frame;
}




// -- Services menu delegate -------------------------------------------------

- (id)validRequestorForSendType:(NSString *)sendType
                     returnType:(NSString *)returnType
{
    //NSLog(@"validRequestorForSendType:%@ returnType:%@", sendType, returnType);

    id backendProxy = [vimController backendProxy];

    if ((!sendType || [sendType isEqual:NSStringPboardType])
            && (!returnType || [returnType isEqual:NSStringPboardType]))
    {
        if ((!sendType || [backendProxy starRegisterToPasteboard:nil]) &&
                (!returnType || [backendProxy starRegisterFromPasteboard:nil]))
        {
            return self;
        }
    }

    return [super validRequestorForSendType:sendType returnType:returnType];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray *)types
{
    //NSLog(@"writeSelectionToPasteboard:%@ types:%@", pboard, types);

    if (![types containsObject:NSStringPboardType])
        return NO;

    id backendProxy = [vimController backendProxy];
    return [backendProxy starRegisterToPasteboard:pboard];
}

@end // MMWindowController



@implementation MMWindowController (Private)

- (NSSize)contentSizeForTextStorageSize:(NSSize)textViewSize
{
    NSSize size = textViewSize;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width += [textView textContainerOrigin].x + right;
    size.height += [textView textContainerOrigin].y + bot;

    // A one pixel high separator is shown if tabline is hidden.
    if ([tabBarControl isHidden]) ++size.height;
    else size.height += [tabBarControl frame].size.height;

    if (![ud boolForKey:MMStatuslineOffKey])
        size.height += StatusLineHeight;

    if ([self bottomScrollbarVisible])
        size.height += [NSScroller scrollerWidth];
    if ([self leftScrollbarVisible])
        size.width += [NSScroller scrollerWidth];
    if ([self rightScrollbarVisible])
        size.width += [NSScroller scrollerWidth];

    return size;
}

- (NSRect)textViewRectForContentSize:(NSSize)contentSize
{
    NSRect rect = { 0, 0, contentSize.width, contentSize.height };

    // A one pixel high separator is shown if tabline is hidden.
    if ([tabBarControl isHidden]) --rect.size.height;
    else rect.size.height -= [tabBarControl frame].size.height;

    if (![[NSUserDefaults standardUserDefaults]
            boolForKey:MMStatuslineOffKey]) {
        rect.size.height -= StatusLineHeight;
        rect.origin.y += StatusLineHeight;
    }

    if ([self bottomScrollbarVisible]) {
        rect.size.height -= [NSScroller scrollerWidth];
        rect.origin.y += [NSScroller scrollerWidth];
    }
    if ([self leftScrollbarVisible]) {
        rect.size.width -= [NSScroller scrollerWidth];
        rect.origin.x += [NSScroller scrollerWidth];
    }
    if ([self rightScrollbarVisible])
        rect.size.width -= [NSScroller scrollerWidth];

    return rect;
}

- (NSSize)textStorageSizeForTextViewSize:(NSSize)textViewSize
{
    NSSize size = textViewSize;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int right = [ud integerForKey:MMTextInsetRightKey];
    int bot = [ud integerForKey:MMTextInsetBottomKey];

    size.width -= [textView textContainerOrigin].x + right;
    size.height -= [textView textContainerOrigin].y + bot;

    return size;
}

- (void)resizeWindowToFit:(id)sender
{
    if (!setupDone) return;

    NSWindow *win = [self window];
    NSRect frame = [win frame];
    NSRect contentRect = [win contentRectForFrameRect:frame];
    NSSize newSize = [self contentSizeForTextStorageSize:[textStorage size]];

    // Keep top-left corner of the window fixed when resizing.
    contentRect.origin.y -= newSize.height - contentRect.size.height;
    contentRect.size = newSize;

    frame = [win frameRectForContentRect:contentRect];
    NSRect maxFrame = [win constrainFrameRect:frame toScreen:[win screen]];

    // HACK!  Assuming the window frame cannot already be placed too high,
    // adjust 'maxFrame' so that it at least as high up as the current frame.
    // The reason for doing this is that constrainFrameRect:toScreen: does not
    // always seem to utilize as much area as possible.
    if (NSMaxY(frame) > NSMaxY(maxFrame)) {
        maxFrame.size.height = frame.origin.y - maxFrame.origin.y
                + frame.size.height;
    }

    if (!NSEqualRects(maxFrame, frame)) {
        // The new window frame is too big to fit on the screen, so fit the
        // text storage to the biggest frame which will fit on the screen.
        //NSLog(@"Proposed window frame does not fit on the screen!");
        frame = [self fitWindowToFrame:maxFrame];
    }

    //NSLog(@"%s %@", _cmd, NSStringFromRect(frame));

    // HACK! If the window does resize, then windowDidResize is called which in
    // turn calls placeViews.  In case the computed new size of the window is
    // no different from the current size, then we need to call placeViews
    // manually.
    if (NSEqualRects(frame, [win frame])) {
        [self placeViews];
    } else {
        [win setFrame:frame display:YES];
    }
}

- (NSRect)fitWindowToFrame:(NSRect)frame
{
    if (!setupDone) return frame;

    NSWindow *win = [self window];
    NSRect contentRect = [win contentRectForFrameRect:frame];
    NSSize size = [self textViewRectForContentSize:contentRect.size].size;
    size = [self textStorageSizeForTextViewSize:size];
    size = [textStorage fitToSize:size];
    size = [self contentSizeForTextStorageSize:size];

    // Keep top-left corner of 'frame' fixed.
    contentRect.origin.y -= size.height - contentRect.size.height;
    contentRect.size = size;

    return [win frameRectForContentRect:contentRect];
}

- (void)updateResizeIncrements
{
    if (!setupDone) return;

    NSSize size = [textStorage calculateAverageFontSize];
    [[self window] setContentResizeIncrements:size];
}

- (NSTabViewItem *)addNewTabViewItem
{
    // NOTE!  A newly created tab is not by selected by default; the VimTask
    // decides which tab should be selected at all times.  However, the AppKit
    // will automatically select the first tab added to a tab view.

    NSTabViewItem *tvi = [[NSTabViewItem alloc] initWithIdentifier:nil];
    [tvi setView:textView];

    // BUG!  This call seems to have no effect; see comment in
    // tabView:didSelectTabViewItem:.
    //[tvi setInitialFirstResponder:textView];

    // NOTE: If this is the first tab it will be automatically selected.
    vimTaskSelectedTab = YES;
    [tabView addTabViewItem:tvi];
    vimTaskSelectedTab = NO;

    [tvi release];

    return tvi;
}

- (void)statusTimerFired:(NSTimer *)timer
{
    [self setStatusText:@""];
    [statusTimer release];
    statusTimer = nil;
}

- (int)representedIndexOfTabViewItem:(NSTabViewItem *)tvi
{
    NSArray *tabViewItems = [tabBarControl representedTabViewItems];
    return [tabViewItems indexOfObject:tvi];
}

- (IBAction)vimMenuItemAction:(id)sender
{
    int tag = [sender tag];

    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&tag length:sizeof(int)];

    [vimController sendMessage:ExecuteMenuMsgID data:data wait:NO];
}

- (MMScroller *)scrollbarForIdentifier:(long)ident index:(unsigned *)idx
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller identifier] == ident) {
            if (idx) *idx = i;
            return scroller;
        }
    }

    return nil;
}

- (BOOL)bottomScrollbarVisible
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeBottom && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)leftScrollbarVisible
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeLeft && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (BOOL)rightScrollbarVisible
{
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller type] == MMScrollerTypeRight && ![scroller isHidden])
            return YES;
    }

    return NO;
}

- (void)placeScrollbars
{
    if (!setupDone) return;

    NSRect tabViewFrame = [tabView frame];
    NSView *contentView = [[self window] contentView];
    BOOL lsbVisible = [self leftScrollbarVisible];
    BOOL statusVisible = ![[NSUserDefaults standardUserDefaults]
            boolForKey:MMStatuslineOffKey];

    // HACK!  Find the lowest left&right vertical scrollbars, as well as the
    // leftmost horizontal scrollbar.  This hack continues further down.
    //
    // TODO!  Can there be no more than one horizontal scrollbar?  If so, the
    // code can be simplified.
    unsigned lowestLeftSbIdx = (unsigned)-1;
    unsigned lowestRightSbIdx = (unsigned)-1;
    unsigned leftmostSbIdx = (unsigned)-1;
    unsigned rowMaxLeft = 0, rowMaxRight = 0, colMax = 0;
    unsigned i, count = [scrollbars count];
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if (![scroller isHidden]) {
            NSRange range = [scroller range];
            if ([scroller type] == MMScrollerTypeLeft
                    && range.location >= rowMaxLeft) {
                rowMaxLeft = range.location;
                lowestLeftSbIdx = i;
            } else if ([scroller type] == MMScrollerTypeRight
                    && range.location >= rowMaxRight) {
                rowMaxRight = range.location;
                lowestRightSbIdx = i;
            } else if ([scroller type] == MMScrollerTypeBottom
                    && range.location >= colMax) {
                colMax = range.location;
                leftmostSbIdx = i;
            }
        }
    }

    // Place the scrollbars.
    for (i = 0; i < count; ++i) {
        MMScroller *scroller = [scrollbars objectAtIndex:i];
        if ([scroller isHidden])
            continue;

        NSRect rect;
        if ([scroller type] == MMScrollerTypeBottom) {
            rect = [textStorage rectForColumnsInRange:[scroller range]];
            rect.size.height = [NSScroller scrollerWidth];
            if (statusVisible)
                rect.origin.y += StatusLineHeight;
            if (lsbVisible)
                rect.origin.x += [NSScroller scrollerWidth];

            // HACK!  Make sure the leftmost horizontal scrollbar covers the
            // text view all the way to the right, otherwise it looks ugly when
            // the user drags the window to resize.
            if (i == leftmostSbIdx) {
                float w = NSMaxX(tabViewFrame) - NSMaxX(rect);
                if (w > 0)
                    rect.size.width += w;
            }

            // Make sure scrollbar rect is bounded by the tab view frame.
            if (rect.origin.x < tabViewFrame.origin.x)
                rect.origin.x = tabViewFrame.origin.x;
            else if (rect.origin.x > NSMaxX(tabViewFrame))
                rect.origin.x = NSMaxX(tabViewFrame);
            if (NSMaxX(rect) > NSMaxX(tabViewFrame))
                rect.size.width -= NSMaxX(rect) - NSMaxX(tabViewFrame);
            if (rect.size.width < 0)
                rect.size.width = 0;
        } else {
            rect = [textStorage rectForRowsInRange:[scroller range]];
            // Adjust for the fact that text layout is flipped.
            rect.origin.y = NSMaxY(tabViewFrame) - rect.origin.y
                    - rect.size.height;
            rect.size.width = [NSScroller scrollerWidth];
            if ([scroller type] == MMScrollerTypeRight)
                rect.origin.x = NSMaxX(tabViewFrame);

            // HACK!  Make sure the lowest vertical scrollbar covers the text
            // view all the way to the bottom.  This is done because Vim only
            // makes the scrollbar cover the (vim-)window it is associated with
            // and this means there is always an empty gap in the scrollbar
            // region next to the command line.
            // TODO!  Find a nicer way to do this.
            if (i == lowestLeftSbIdx || i == lowestRightSbIdx) {
                float h = rect.origin.y + rect.size.height
                          - tabViewFrame.origin.y;
                if (rect.size.height < h) {
                    rect.origin.y = tabViewFrame.origin.y;
                    rect.size.height = h;
                }
            }

            // Vertical scrollers must not cover the resize box in the
            // bottom-right corner of the window.
            if (rect.origin.y < [NSScroller scrollerWidth]) {
                rect.size.height -= [NSScroller scrollerWidth] - rect.origin.y;
                rect.origin.y = [NSScroller scrollerWidth];
            }

            // Make sure scrollbar rect is bounded by the tab view frame.
            if (rect.origin.y < tabViewFrame.origin.y) {
                rect.size.height -= tabViewFrame.origin.y - rect.origin.y;
                rect.origin.y = tabViewFrame.origin.y;
            } else if (rect.origin.y > NSMaxY(tabViewFrame))
                rect.origin.y = NSMaxY(tabViewFrame);
            if (NSMaxY(rect) > NSMaxY(tabViewFrame))
                rect.size.height -= NSMaxY(rect) - NSMaxY(tabViewFrame);
            if (rect.size.height < 0)
                rect.size.height = 0;
        }

        //NSLog(@"set scroller #%d frame = %@", i, NSStringFromRect(rect));
        NSRect oldRect = [scroller frame];
        if (!NSEqualRects(oldRect, rect)) {
            [scroller setFrame:rect];
            // Clear behind the old scroller frame, or parts of the old
            // scroller might still be visible after setFrame:.
            [contentView setNeedsDisplayInRect:oldRect];
            [scroller setNeedsDisplay:YES];
        }
    }
}

- (void)scroll:(id)sender
{
    NSMutableData *data = [NSMutableData data];
    long ident = [(MMScroller*)sender identifier];
    int hitPart = [sender hitPart];
    float value = [sender floatValue];

    [data appendBytes:&ident length:sizeof(long)];
    [data appendBytes:&hitPart length:sizeof(int)];
    [data appendBytes:&value length:sizeof(float)];

    [vimController sendMessage:ScrollbarEventMsgID data:data wait:NO];
}

- (void)placeViews
{
    if (!setupDone) return;

    // NOTE!  It is assumed that the window has been resized so that it will
    // exactly fit the text storage (possibly after resizing it).  If this is
    // not the case the display might be messed up.
    NSWindow *win = [self window];
    NSRect contentRect = [win contentRectForFrameRect:[win frame]];
    NSRect textViewRect = [self textViewRectForContentSize:contentRect.size];
    NSSize tsSize = [self textStorageSizeForTextViewSize:textViewRect.size];

    int dim[2], rows, cols;
    [textStorage getMaxRows:&rows columns:&cols];
    [textStorage fitToSize:tsSize rows:&dim[0] columns:&dim[1]];

    if (dim[0] != rows || dim[1] != cols) {
        NSString *sdim = [NSString stringWithFormat:@"%dx%d", dim[1], dim[0]];
        [self flashStatusText:sdim];

        //NSLog(@"Notify Vim that text storage dimensions changed to %dx%d",
        //        dim[0], dim[1]);
        NSData *data = [NSData dataWithBytes:dim length:2*sizeof(int)];

        // NOTE! This can get called a lot when in live resize, which causes
        // the connection buffers to fill up.  If we wait for the message to be
        // sent then the app might become unresponsive.
        [vimController sendMessage:SetTextDimensionsMsgID data:data
                     wait:![textView inLiveResize]];
    }

    [tabView setFrame:textViewRect];

    [self placeScrollbars];
}

@end // MMWindowController (Private)



@implementation NSTabView (MMExtras)

- (void)removeAllTabViewItems
{
    NSArray *existingItems = [self tabViewItems];
    NSEnumerator *e = [existingItems objectEnumerator];
    NSTabViewItem *item;
    while (item = [e nextObject]){
        [self removeTabViewItem:item];
    }
}

@end // NSTabView (MMExtras)




@implementation MMScroller

- (id)initWithIdentifier:(long)ident type:(int)theType
{
    // HACK! NSScroller creates a horizontal scroller if it is init'ed with a
    // frame whose with exceeds its height; so create a bogus rect and pass it
    // to initWithFrame.
    NSRect frame = theType == MMScrollerTypeBottom
            ? NSMakeRect(0, 0, 1, 0)
            : NSMakeRect(0, 0, 0, 1);

    if ((self = [super initWithFrame:frame])) {
        identifier = ident;
        type = theType;
        [self setHidden:YES];
        [self setEnabled:YES];
    }

    return self;
}

- (long)identifier
{
    return identifier;
}

- (int)type
{
    return type;
}

- (NSRange)range
{
    return range;
}

- (void)setRange:(NSRange)newRange
{
    range = newRange;
}

@end // MMScroller
