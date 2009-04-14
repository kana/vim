/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */
/*
 * MMAppController
 *
 * MMAppController is the delegate of NSApp and as such handles file open
 * requests, application termination, etc.  It sets up a named NSConnection on
 * which it listens to incoming connections from Vim processes.  It also
 * coordinates all MMVimControllers and takes care of the main menu.
 *
 * A new Vim process is started by calling launchVimProcessWithArguments:.
 * When the Vim process is initialized it notifies the app controller by
 * sending a connectBackend:pid: message.  At this point a new MMVimController
 * is allocated.  Afterwards, the Vim process communicates directly with its
 * MMVimController.
 *
 * A Vim process started from the command line connects directly by sending the
 * connectBackend:pid: message (launchVimProcessWithArguments: is never called
 * in this case).
 *
 * The main menu is handled as follows.  Each Vim controller keeps its own main
 * menu.  All menus except the "MacVim" menu are controlled by the Vim process.
 * The app controller also keeps a reference to the "default main menu" which
 * is set up in MainMenu.nib.  When no editor window is open the default main
 * menu is used.  When a new editor window becomes main its main menu becomes
 * the new main menu, this is done in -[MMAppController setMainMenu:].
 *   NOTE: Certain heuristics are used to find the "MacVim", "Windows", "File",
 * and "Services" menu.  If MainMenu.nib changes these heuristics may have to
 * change as well.  For specifics see the find... methods defined in the NSMenu
 * category "MMExtras".
 */

#import "MMAppController.h"
#import "MMPreferenceController.h"
#import "MMVimController.h"
#import "MMWindowController.h"
#import "Miscellaneous.h"

#ifdef MM_ENABLE_PLUGINS
#import "MMPlugInManager.h"
#endif

#import <unistd.h>
#import <CoreServices/CoreServices.h>


#define MM_HANDLE_XCODE_MOD_EVENT 0



// Default timeout intervals on all connections.
static NSTimeInterval MMRequestTimeout = 5;
static NSTimeInterval MMReplyTimeout = 5;

static NSString *MMWebsiteString = @"http://code.google.com/p/macvim/";

#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
// Latency (in s) between FS event occuring and being reported to MacVim.
// Should be small so that MacVim is notified of changes to the ~/.vim
// directory more or less immediately.
static CFTimeInterval MMEventStreamLatency = 0.1;
#endif


#pragma options align=mac68k
typedef struct
{
    short unused1;      // 0 (not used)
    short lineNum;      // line to select (< 0 to specify range)
    long  startRange;   // start of selection range (if line < 0)
    long  endRange;     // end of selection range (if line < 0)
    long  unused2;      // 0 (not used)
    long  theDate;      // modification date/time
} MMSelectionRange;
#pragma options align=reset



@interface MMAppController (MMServices)
- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error;
- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error;
- (void)newFileHere:(NSPasteboard *)pboard userData:(NSString *)userData
              error:(NSString **)error;
@end


@interface MMAppController (Private)
- (MMVimController *)topmostVimController;
- (int)launchVimProcessWithArguments:(NSArray *)args;
- (NSArray *)filterFilesAndNotify:(NSArray *)files;
- (NSArray *)filterOpenFiles:(NSArray *)filenames
               openFilesDict:(NSDictionary **)openFiles;
#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply;
#endif
- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
               replyEvent:(NSAppleEventDescriptor *)reply;
- (int)findLaunchingProcessWithoutArguments;
- (MMVimController *)findUnusedEditor;
- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc;
- (void)scheduleVimControllerPreloadAfterDelay:(NSTimeInterval)delay;
- (void)cancelVimControllerPreloadRequests;
- (void)preloadVimController:(id)sender;
- (int)maxPreloadCacheSize;
- (MMVimController *)takeVimControllerFromCache;
- (void)clearPreloadCacheWithCount:(int)count;
- (void)rebuildPreloadCache;
- (NSDate *)rcFilesModificationDate;
- (BOOL)openVimControllerWithArguments:(NSDictionary *)arguments;
- (void)activateWhenNextWindowOpens;
- (void)startWatchingVimDir;
- (void)stopWatchingVimDir;
- (void)handleFSEvent;
- (void)loadDefaultFont;
- (int)executeInLoginShell:(NSString *)path arguments:(NSArray *)args;
- (void)reapChildProcesses:(id)sender;
- (void)processInputQueues:(id)sender;
- (void)addVimController:(MMVimController *)vc;

#ifdef MM_ENABLE_PLUGINS
- (void)removePlugInMenu;
- (void)addPlugInMenuToMenu:(NSMenu *)mainMenu;
#endif
@end



#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
    static void
fsEventCallback(ConstFSEventStreamRef streamRef,
                void *clientCallBackInfo,
                size_t numEvents,
                void *eventPaths,
                const FSEventStreamEventFlags eventFlags[],
                const FSEventStreamEventId eventIds[])
{
    [[MMAppController sharedInstance] handleFSEvent];
}
#endif

@implementation MMAppController

+ (void)initialize
{
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO],   MMNoWindowKey,
        [NSNumber numberWithInt:64],    MMTabMinWidthKey,
        [NSNumber numberWithInt:6*64],  MMTabMaxWidthKey,
        [NSNumber numberWithInt:132],   MMTabOptimumWidthKey,
        [NSNumber numberWithBool:YES],  MMShowAddTabButtonKey,
        [NSNumber numberWithInt:2],     MMTextInsetLeftKey,
        [NSNumber numberWithInt:1],     MMTextInsetRightKey,
        [NSNumber numberWithInt:1],     MMTextInsetTopKey,
        [NSNumber numberWithInt:1],     MMTextInsetBottomKey,
        @"MMTypesetter",                MMTypesetterKey,
        [NSNumber numberWithFloat:1],   MMCellWidthMultiplierKey,
        [NSNumber numberWithFloat:-1],  MMBaselineOffsetKey,
        [NSNumber numberWithBool:YES],  MMTranslateCtrlClickKey,
        [NSNumber numberWithInt:0],     MMOpenInCurrentWindowKey,
        [NSNumber numberWithBool:NO],   MMNoFontSubstitutionKey,
        [NSNumber numberWithBool:YES],  MMLoginShellKey,
        [NSNumber numberWithBool:NO],   MMAtsuiRendererKey,
        [NSNumber numberWithInt:MMUntitledWindowAlways],
                                        MMUntitledWindowKey,
        [NSNumber numberWithBool:NO],   MMTexturedWindowKey,
        [NSNumber numberWithBool:NO],   MMZoomBothKey,
        @"",                            MMLoginShellCommandKey,
        @"",                            MMLoginShellArgumentKey,
        [NSNumber numberWithBool:YES],  MMDialogsTrackPwdKey,
#ifdef MM_ENABLE_PLUGINS
        [NSNumber numberWithBool:YES],  MMShowLeftPlugInContainerKey,
#endif
        [NSNumber numberWithInt:3],     MMOpenLayoutKey,
        [NSNumber numberWithBool:NO],   MMVerticalSplitKey,
        [NSNumber numberWithInt:0],     MMPreloadCacheSizeKey,
        [NSNumber numberWithInt:0],     MMLastWindowClosedBehaviorKey,
        [NSNumber numberWithBool:YES],  MMLoadDefaultFontKey,
        nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];

    NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
    [NSApp registerServicesMenuSendTypes:types returnTypes:types];

    // NOTE: Set the current directory to user's home directory, otherwise it
    // will default to the root directory.  (This matters since new Vim
    // processes inherit MacVim's environment variables.)
    [[NSFileManager defaultManager] changeCurrentDirectoryPath:
            NSHomeDirectory()];
}

- (id)init
{
    if (!(self = [super init])) return nil;

    [self loadDefaultFont];

    vimControllers = [NSMutableArray new];
    cachedVimControllers = [NSMutableArray new];
    preloadPid = -1;
    pidArguments = [NSMutableDictionary new];
    inputQueues = [NSMutableDictionary new];

#ifdef MM_ENABLE_PLUGINS
    NSString *plugInTitle = NSLocalizedString(@"Plug-In",
                                              @"Plug-In menu title");
    plugInMenuItem = [[NSMenuItem alloc] initWithTitle:plugInTitle
                                                action:NULL
                                         keyEquivalent:@""];
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:plugInTitle];
    [plugInMenuItem setSubmenu:submenu];
    [submenu release];
#endif

    // NOTE: Do not use the default connection since the Logitech Control
    // Center (LCC) input manager steals and this would cause MacVim to
    // never open any windows.  (This is a bug in LCC but since they are
    // unlikely to fix it, we graciously give them the default connection.)
    connection = [[NSConnection alloc] initWithReceivePort:[NSPort port]
                                                  sendPort:nil];
    [connection setRootObject:self];
    [connection setRequestTimeout:MMRequestTimeout];
    [connection setReplyTimeout:MMReplyTimeout];

    // NOTE!  If the name of the connection changes here it must also be
    // updated in MMBackend.m.
    NSString *name = [NSString stringWithFormat:@"%@-connection",
             [[NSBundle mainBundle] bundlePath]];
    //NSLog(@"Registering connection with name '%@'", name);
    if (![connection registerName:name]) {
        NSLog(@"FATAL ERROR: Failed to register connection with name '%@'",
                name);
        [connection release];  connection = nil;
    }

    return self;
}

- (void)dealloc
{
    //NSLog(@"MMAppController dealloc");

    [connection release];  connection = nil;
    [inputQueues release];  inputQueues = nil;
    [pidArguments release];  pidArguments = nil;
    [vimControllers release];  vimControllers = nil;
    [cachedVimControllers release];  cachedVimControllers = nil;
    [openSelectionString release];  openSelectionString = nil;
    [recentFilesMenuItem release];  recentFilesMenuItem = nil;
    [defaultMainMenu release];  defaultMainMenu = nil;
#ifdef MM_ENABLE_PLUGINS
    [plugInMenuItem release];  plugInMenuItem = nil;
#endif
    [appMenuItemTemplate release];  appMenuItemTemplate = nil;

    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Remember the default menu so that it can be restored if the user closes
    // all editor windows.
    defaultMainMenu = [[NSApp mainMenu] retain];

    // Store a copy of the default app menu so we can use this as a template
    // for all other menus.  We make a copy here because the "Services" menu
    // will not yet have been populated at this time.  If we don't we get
    // problems trying to set key equivalents later on because they might clash
    // with items on the "Services" menu.
    appMenuItemTemplate = [defaultMainMenu itemAtIndex:0];
    appMenuItemTemplate = [appMenuItemTemplate copy];

    // Set up the "Open Recent" menu. See
    //   http://lapcatsoftware.com/blog/2007/07/10/
    //     working-without-a-nib-part-5-open-recent-menu/
    // and
    //   http://www.cocoabuilder.com/archive/message/cocoa/2007/8/15/187793
    // for more information.
    //
    // The menu itself is created in MainMenu.nib but we still seem to have to
    // hack around a bit to get it to work.  (This has to be done in
    // applicationWillFinishLaunching at the latest, otherwise it doesn't
    // work.)
    NSMenu *fileMenu = [defaultMainMenu findFileMenu];
    if (fileMenu) {
        int idx = [fileMenu indexOfItemWithAction:@selector(fileOpen:)];
        if (idx >= 0 && idx+1 < [fileMenu numberOfItems])

        recentFilesMenuItem = [fileMenu itemWithTitle:@"Open Recent"];
        [[recentFilesMenuItem submenu] performSelector:@selector(_setMenuName:)
                                        withObject:@"NSRecentDocumentsMenu"];

        // Note: The "Recent Files" menu must be moved around since there is no
        // -[NSApp setRecentFilesMenu:] method.  We keep a reference to it to
        // facilitate this move (see setMainMenu: below).
        [recentFilesMenuItem retain];
    }

#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleXcodeModEvent:replyEvent:)
              forEventClass:'KAHL'
                 andEventID:'MOD '];
#endif

    // Register 'mvim://' URL handler
    [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:self
                andSelector:@selector(handleGetURLEvent:replyEvent:)
              forEventClass:kInternetEventClass
                 andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [NSApp setServicesProvider:self];
#ifdef MM_ENABLE_PLUGINS
    [[MMPlugInManager sharedManager] loadAllPlugIns];
#endif

    if ([self maxPreloadCacheSize] > 0) {
        [self scheduleVimControllerPreloadAfterDelay:2];
        [self startWatchingVimDir];
    }
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSAppleEventManager *aem = [NSAppleEventManager sharedAppleEventManager];
    NSAppleEventDescriptor *desc = [aem currentAppleEvent];

    // The user default MMUntitledWindow can be set to control whether an
    // untitled window should open on 'Open' and 'Reopen' events.
    int untitledWindowFlag = [ud integerForKey:MMUntitledWindowKey];

    BOOL isAppOpenEvent = [desc eventID] == kAEOpenApplication;
    if (isAppOpenEvent && (untitledWindowFlag & MMUntitledWindowOnOpen) == 0)
        return NO;

    BOOL isAppReopenEvent = [desc eventID] == kAEReopenApplication;
    if (isAppReopenEvent
            && (untitledWindowFlag & MMUntitledWindowOnReopen) == 0)
        return NO;

    // When a process is started from the command line, the 'Open' event may
    // contain a parameter to surpress the opening of an untitled window.
    desc = [desc paramDescriptorForKeyword:keyAEPropData];
    desc = [desc paramDescriptorForKeyword:keyMMUntitledWindow];
    if (desc && ![desc booleanValue])
        return NO;

    // Never open an untitled window if there is at least one open window or if
    // there are processes that are currently launching.
    if ([vimControllers count] > 0 || [pidArguments count] > 0)
        return NO;

    // NOTE!  This way it possible to start the app with the command-line
    // argument '-nowindow yes' and no window will be opened by default but
    // this argument will only be heeded when the application is opening.
    if (isAppOpenEvent && [ud boolForKey:MMNoWindowKey] == YES)
        return NO;

    return YES;
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender
{
    [self newWindow:self];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    // Extract ODB/Xcode/Spotlight parameters from the current Apple event,
    // sort the filenames, and then let openFiles:withArguments: do the heavy
    // lifting.

    if (!(filenames && [filenames count] > 0))
        return;

    // Sort filenames since the Finder doesn't take care in preserving the
    // order in which files are selected anyway (and "sorted" is more
    // predictable than "random").
    if ([filenames count] > 1)
        filenames = [filenames sortedArrayUsingSelector:
                @selector(localizedCompare:)];

    // Extract ODB/Xcode/Spotlight parameters from the current Apple event
    NSMutableDictionary *arguments = [self extractArgumentsFromOdocEvent:
            [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent]];

    if ([self openFiles:filenames withArguments:arguments]) {
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    } else {
        // TODO: Notify user of failure?
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return (MMTerminateWhenLastWindowClosed ==
            [[NSUserDefaults standardUserDefaults]
                integerForKey:MMLastWindowClosedBehaviorKey]);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication *)sender
{
    // TODO: Follow Apple's guidelines for 'Graceful Application Termination'
    // (in particular, allow user to review changes and save).
    int reply = NSTerminateNow;
    BOOL modifiedBuffers = NO;

    // Go through windows, checking for modified buffers.  (Each Vim process
    // tells MacVim when any buffer has been modified and MacVim sets the
    // 'documentEdited' flag of the window correspondingly.)
    NSEnumerator *e = [[NSApp windows] objectEnumerator];
    id window;
    while ((window = [e nextObject])) {
        if ([window isDocumentEdited]) {
            modifiedBuffers = YES;
            break;
        }
    }

    if (modifiedBuffers) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert addButtonWithTitle:NSLocalizedString(@"Quit",
                @"Dialog button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel",
                @"Dialog button")];
        [alert setMessageText:NSLocalizedString(@"Quit without saving?",
                @"Quit dialog with changed buffers, title")];
        [alert setInformativeText:NSLocalizedString(
                @"There are modified buffers, "
                "if you quit now all changes will be lost.  Quit anyway?",
                @"Quit dialog with changed buffers, text")];

        if ([alert runModal] != NSAlertFirstButtonReturn)
            reply = NSTerminateCancel;

        [alert release];
    } else {
        // No unmodified buffers, but give a warning if there are multiple
        // windows and/or tabs open.
        int numWindows = [vimControllers count];
        int numTabs = 0;

        // Count the number of open tabs
        e = [vimControllers objectEnumerator];
        id vc;
        while ((vc = [e nextObject]))
            numTabs += [[vc objectForVimStateKey:@"numTabs"] intValue];

        if (numWindows > 1 || numTabs > 1) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setAlertStyle:NSWarningAlertStyle];
            [alert addButtonWithTitle:NSLocalizedString(@"Quit",
                    @"Dialog button")];
            [alert addButtonWithTitle:NSLocalizedString(@"Cancel",
                    @"Dialog button")];
            [alert setMessageText:NSLocalizedString(
                    @"Are you sure you want to quit MacVim?",
                    @"Quit dialog with no changed buffers, title")];

            NSString *info = nil;
            if (numWindows > 1) {
                if (numTabs > numWindows)
                    info = [NSString stringWithFormat:NSLocalizedString(
                            @"There are %d windows open in MacVim, with a "
                            "total of %d tabs. Do you want to quit anyway?",
                            @"Quit dialog with no changed buffers, text"),
                         numWindows, numTabs];
                else
                    info = [NSString stringWithFormat:NSLocalizedString(
                            @"There are %d windows open in MacVim. "
                            "Do you want to quit anyway?",
                            @"Quit dialog with no changed buffers, text"),
                        numWindows];

            } else {
                info = [NSString stringWithFormat:NSLocalizedString(
                        @"There are %d tabs open in MacVim. "
                        "Do you want to quit anyway?",
                        @"Quit dialog with no changed buffers, text"), 
                     numTabs];
            }

            [alert setInformativeText:info];

            if ([alert runModal] != NSAlertFirstButtonReturn)
                reply = NSTerminateCancel;

            [alert release];
        }
    }


    // Tell all Vim processes to terminate now (otherwise they'll leave swap
    // files behind).
    if (NSTerminateNow == reply) {
        e = [vimControllers objectEnumerator];
        id vc;
        while ((vc = [e nextObject])) {
            //NSLog(@"Terminate pid=%d", [vc pid]);
            [vc sendMessage:TerminateNowMsgID data:nil];
        }

        e = [cachedVimControllers objectEnumerator];
        while ((vc = [e nextObject])) {
            //NSLog(@"Terminate pid=%d (cached)", [vc pid]);
            [vc sendMessage:TerminateNowMsgID data:nil];
        }

        // If a Vim process is being preloaded as we quit we have to forcibly
        // kill it since we have not established a connection yet.
        if (preloadPid > 0) {
            //NSLog(@"INCOMPLETE preloaded process: preloadPid=%d", preloadPid);
            kill(preloadPid, SIGKILL);
        }

        // If a Vim process was loading as we quit we also have to kill it.
        e = [[pidArguments allKeys] objectEnumerator];
        NSNumber *pidKey;
        while ((pidKey = [e nextObject])) {
            //NSLog(@"INCOMPLETE process: pid=%d", [pidKey intValue]);
            kill([pidKey intValue], SIGKILL);
        }

        // Sleep a little to allow all the Vim processes to exit.
        usleep(10000);
    }

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self stopWatchingVimDir];

#ifdef MM_ENABLE_PLUGINS
    [[MMPlugInManager sharedManager] unloadAllPlugIns];
#endif

#if MM_HANDLE_XCODE_MOD_EVENT
    [[NSAppleEventManager sharedAppleEventManager]
            removeEventHandlerForEventClass:'KAHL'
                                 andEventID:'MOD '];
#endif

    // This will invalidate all connections (since they were spawned from this
    // connection).
    [connection invalidate];

    // Deactivate the font we loaded from the app bundle.
    // NOTE: This can take quite a while (~500 ms), so termination will be
    // noticeably faster if loading of the default font is disabled.
    if (fontContainerRef) {
        ATSFontDeactivate(fontContainerRef, NULL, kATSOptionFlagsDefault);
        fontContainerRef = 0;
    }

    [NSApp setDelegate:nil];

    // Try to wait for all child processes to avoid leaving zombies behind (but
    // don't wait around for too long).
    NSDate *timeOutDate = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([timeOutDate timeIntervalSinceNow] > 0) {
        [self reapChildProcesses:nil];
        if (numChildProcesses <= 0)
            break;

        //NSLog(@"%d processes still left, sleep a bit...", numChildProcesses);

        // Run in NSConnectionReplyMode while waiting instead of calling e.g.
        // usleep().  Otherwise incoming messages may clog up the DO queues and
        // the outgoing TerminateNowMsgID sent earlier never reaches the Vim
        // process.
        // This has at least one side-effect, namely we may receive the
        // annoying "dropping incoming DO message".  (E.g. this may happen if
        // you quickly hit Cmd-n several times in a row and then immediately
        // press Cmd-q, Enter.)
        while (CFRunLoopRunInMode((CFStringRef)NSConnectionReplyMode,
                0.05, true) == kCFRunLoopRunHandledSource)
            ;   // do nothing
    }

    if (numChildProcesses > 0)
        NSLog(@"%d ZOMBIES left behind", numChildProcesses);
}

+ (MMAppController *)sharedInstance
{
    // Note: The app controller is a singleton which is instantiated in
    // MainMenu.nib where it is also connected as the delegate of NSApp.
    id delegate = [NSApp delegate];
    return [delegate isKindOfClass:self] ? (MMAppController*)delegate : nil;
}

- (NSMenu *)defaultMainMenu
{
    return defaultMainMenu;
}

- (NSMenuItem *)appMenuItemTemplate
{
    return appMenuItemTemplate;
}

- (void)removeVimController:(id)controller
{
    int idx = [vimControllers indexOfObject:controller];
    if (NSNotFound == idx)
        return;

    [controller cleanup];

    [vimControllers removeObjectAtIndex:idx];

    if (![vimControllers count]) {
        // The last editor window just closed so restore the main menu back to
        // its default state (which is defined in MainMenu.nib).
        [self setMainMenu:defaultMainMenu];

        BOOL hide = (MMHideWhenLastWindowClosed ==
                    [[NSUserDefaults standardUserDefaults]
                        integerForKey:MMLastWindowClosedBehaviorKey]);
        if (hide)
            [NSApp hide:self];
    }

    // There is a small delay before the Vim process actually exits so wait a
    // little before trying to reap the child process.  If the process still
    // hasn't exited after this wait it won't be reaped until the next time
    // reapChildProcesses: is called (but this should be harmless).
    [self performSelector:@selector(reapChildProcesses:)
               withObject:nil
               afterDelay:0.1];
}

- (void)windowControllerWillOpen:(MMWindowController *)windowController
{
    NSPoint topLeft = NSZeroPoint;
    NSWindow *topWin = [[[self topmostVimController] windowController] window];
    NSWindow *win = [windowController window];

    if (!win) return;

    // If there is a window belonging to a Vim process, cascade from it,
    // otherwise use the autosaved window position (if any).
    if (topWin) {
        NSRect frame = [topWin frame];
        topLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
    } else {
        NSString *topLeftString = [[NSUserDefaults standardUserDefaults]
            stringForKey:MMTopLeftPointKey];
        if (topLeftString)
            topLeft = NSPointFromString(topLeftString);
    }

    if (!NSEqualPoints(topLeft, NSZeroPoint)) {
        NSPoint oldTopLeft = topLeft;
        if (topWin)
            topLeft = [win cascadeTopLeftFromPoint:topLeft];

        [win setFrameTopLeftPoint:topLeft];

        if ([win screen]) {
            NSPoint screenOrigin = [[win screen] frame].origin;
            if ([win frame].origin.y < screenOrigin.y) {
                // Try to avoid shifting the new window downwards if it means
                // that the bottom of the window will be off the screen.  E.g.
                // if the user has set windows to open maximized in the
                // vertical direction then the new window will cascade
                // horizontally only.
                topLeft.y = oldTopLeft.y;
                [win setFrameTopLeftPoint:topLeft];
            }

            if ([win frame].origin.y < screenOrigin.y) {
                // Move the window to the top of the screen if the bottom of
                // the window is still obscured.
                topLeft.y = NSMaxY([[win screen] frame]);
                [win setFrameTopLeftPoint:topLeft];
            }
        } else {
            NSLog(@"[%s] WINDOW NOT ON SCREEN, don't constrain position", _cmd);
        }
    }

    if (1 == [vimControllers count]) {
        // The first window autosaves its position.  (The autosaving
        // features of Cocoa are not used because we need more control over
        // what is autosaved and when it is restored.)
        [windowController setWindowAutosaveKey:MMTopLeftPointKey];
    }

    if (openSelectionString) {
        // TODO: Pass this as a parameter instead!  Get rid of
        // 'openSelectionString' etc.
        //
        // There is some text to paste into this window as a result of the
        // services menu "Open selection ..." being used.
        [[windowController vimController] dropString:openSelectionString];
        [openSelectionString release];
        openSelectionString = nil;
    }

    if (shouldActivateWhenNextWindowOpens) {
        [NSApp activateIgnoringOtherApps:YES];
        shouldActivateWhenNextWindowOpens = NO;
    }
}

- (void)setMainMenu:(NSMenu *)mainMenu
{
    if ([NSApp mainMenu] == mainMenu) return;

    // If the new menu has a "Recent Files" dummy item, then swap the real item
    // for the dummy.  We are forced to do this since Cocoa initializes the
    // "Recent Files" menu and there is no way to simply point Cocoa to a new
    // item each time the menus are swapped.
    NSMenu *fileMenu = [mainMenu findFileMenu];
    if (recentFilesMenuItem && fileMenu) {
        int dummyIdx =
                [fileMenu indexOfItemWithAction:@selector(recentFilesDummy:)];
        if (dummyIdx >= 0) {
            NSMenuItem *dummyItem = [[fileMenu itemAtIndex:dummyIdx] retain];
            [fileMenu removeItemAtIndex:dummyIdx];

            NSMenu *recentFilesParentMenu = [recentFilesMenuItem menu];
            int idx = [recentFilesParentMenu indexOfItem:recentFilesMenuItem];
            if (idx >= 0) {
                [[recentFilesMenuItem retain] autorelease];
                [recentFilesParentMenu removeItemAtIndex:idx];
                [recentFilesParentMenu insertItem:dummyItem atIndex:idx];
            }

            [fileMenu insertItem:recentFilesMenuItem atIndex:dummyIdx];
            [dummyItem release];
        }
    }

    // Now set the new menu.  Notice that we keep one menu for each editor
    // window since each editor can have its own set of menus.  When swapping
    // menus we have to tell Cocoa where the new "MacVim", "Windows", and
    // "Services" menu are.
    [NSApp setMainMenu:mainMenu];

    // Setting the "MacVim" (or "Application") menu ensures that it is typeset
    // in boldface.  (The setAppleMenu: method used to be public but is now
    // private so this will have to be considered a bit of a hack!)
    NSMenu *appMenu = [mainMenu findApplicationMenu];
    [NSApp performSelector:@selector(setAppleMenu:) withObject:appMenu];

    NSMenu *servicesMenu = [mainMenu findServicesMenu];
    [NSApp setServicesMenu:servicesMenu];

    NSMenu *windowsMenu = [mainMenu findWindowsMenu];
    if (windowsMenu) {
        // Cocoa isn't clever enough to get rid of items it has added to the
        // "Windows" menu so we have to do it ourselves otherwise there will be
        // multiple menu items for each window in the "Windows" menu.
        //   This code assumes that the only items Cocoa add are ones which
        // send off the action makeKeyAndOrderFront:.  (Cocoa will not add
        // another separator item if the last item on the "Windows" menu
        // already is a separator, so we needen't worry about separators.)
        int i, count = [windowsMenu numberOfItems];
        for (i = count-1; i >= 0; --i) {
            NSMenuItem *item = [windowsMenu itemAtIndex:i];
            if ([item action] == @selector(makeKeyAndOrderFront:))
                [windowsMenu removeItem:item];
        }
    }
    [NSApp setWindowsMenu:windowsMenu];

#ifdef MM_ENABLE_PLUGINS
    // Move plugin menu from old to new main menu.
    [self removePlugInMenu];
    [self addPlugInMenuToMenu:mainMenu];
#endif
}

- (NSArray *)filterOpenFiles:(NSArray *)filenames
{
    return [self filterOpenFiles:filenames openFilesDict:nil];
}

- (BOOL)openFiles:(NSArray *)filenames withArguments:(NSDictionary *)args
{
    // Opening files works like this:
    //  a) filter out any already open files
    //  b) open any remaining files
    //
    // A file is opened in an untitled window if there is one (it may be
    // currently launching, or it may already be visible), otherwise a new
    // window is opened.
    //
    // Each launching Vim process has a dictionary of arguments that are passed
    // to the process when in checks in (via connectBackend:pid:).  The
    // arguments for each launching process can be looked up by its PID (in the
    // pidArguments dictionary).

    NSMutableDictionary *arguments = (args ? [[args mutableCopy] autorelease]
                                           : [NSMutableDictionary dictionary]);

    //
    // a) Filter out any already open files
    //
    NSString *firstFile = [filenames objectAtIndex:0];
    MMVimController *firstController = nil;
    NSDictionary *openFilesDict = nil;
    filenames = [self filterOpenFiles:filenames openFilesDict:&openFilesDict];

    // Pass arguments to vim controllers that had files open.
    id key;
    NSEnumerator *e = [openFilesDict keyEnumerator];

    // (Indicate that we do not wish to open any files at the moment.)
    [arguments setObject:[NSNumber numberWithBool:YES] forKey:@"dontOpen"];

    while ((key = [e nextObject])) {
        NSArray *files = [openFilesDict objectForKey:key];
        [arguments setObject:files forKey:@"filenames"];

        MMVimController *vc = [key pointerValue];
        [vc passArguments:arguments];

        // If this controller holds the first file, then remember it for later.
        if ([files containsObject:firstFile])
            firstController = vc;
    }

    // The meaning of "layout" is defined by the WIN_* defines in main.c.
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int layout = [ud integerForKey:MMOpenLayoutKey];
    BOOL splitVert = [ud boolForKey:MMVerticalSplitKey];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];

    if (splitVert && MMLayoutHorizontalSplit == layout)
        layout = MMLayoutVerticalSplit;
    if (layout < 0 || (layout > MMLayoutTabs && openInCurrentWindow))
        layout = MMLayoutTabs;

    if ([filenames count] == 0) {
        // Raise the window containing the first file that was already open,
        // and make sure that the tab containing that file is selected.  Only
        // do this when there are no more files to open, otherwise sometimes
        // the window with 'firstFile' will be raised, other times it might be
        // the window that will open with the files in the 'filenames' array.
        firstFile = [firstFile stringByEscapingSpecialFilenameCharacters];

        NSString *bufCmd = @"tab sb";
        switch (layout) {
            case MMLayoutHorizontalSplit: bufCmd = @"sb"; break;
            case MMLayoutVerticalSplit:   bufCmd = @"vert sb"; break;
            case MMLayoutArglist:         bufCmd = @"b"; break;
        }

        NSString *input = [NSString stringWithFormat:@"<C-\\><C-N>"
                ":let oldswb=&swb|let &swb=\"useopen,usetab\"|"
                "%@ %@|let &swb=oldswb|unl oldswb|"
                "cal foreground()<CR>", bufCmd, firstFile];

        [firstController addVimInput:input];

        return YES;
    }

    // Add filenames to "Recent Files" menu, unless they are being edited
    // remotely (using ODB).
    if ([arguments objectForKey:@"remoteID"] == nil) {
        [[NSDocumentController sharedDocumentController]
                noteNewRecentFilePaths:filenames];
    }

    //
    // b) Open any remaining files
    //

    [arguments setObject:[NSNumber numberWithInt:layout] forKey:@"layout"];
    [arguments setObject:filenames forKey:@"filenames"];
    // (Indicate that files should be opened from now on.)
    [arguments setObject:[NSNumber numberWithBool:NO] forKey:@"dontOpen"];

    MMVimController *vc;
    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        // Open files in an already open window.
        [[[vc windowController] window] makeKeyAndOrderFront:self];
        [vc passArguments:arguments];
        return YES;
    }

    BOOL openOk = YES;
    int numFiles = [filenames count];
    if (MMLayoutWindows == layout && numFiles > 1) {
        // Open one file at a time in a new window, but don't open too many at
        // once (at most cap+1 windows will open).  If the user has increased
        // the preload cache size we'll take that as a hint that more windows
        // should be able to open at once.
        int cap = [self maxPreloadCacheSize] - 1;
        if (cap < 4) cap = 4;
        if (cap > numFiles) cap = numFiles;

        int i;
        for (i = 0; i < cap; ++i) {
            NSArray *a = [NSArray arrayWithObject:[filenames objectAtIndex:i]];
            [arguments setObject:a forKey:@"filenames"];

            // NOTE: We have to copy the args since we'll mutate them in the
            // next loop and the below call may retain the arguments while
            // waiting for a process to start.
            NSDictionary *args = [[arguments copy] autorelease];

            openOk = [self openVimControllerWithArguments:args];
            if (!openOk) break;
        }

        // Open remaining files in tabs in a new window.
        if (openOk && numFiles > cap) {
            NSRange range = { i, numFiles-cap };
            NSArray *a = [filenames subarrayWithRange:range];
            [arguments setObject:a forKey:@"filenames"];
            [arguments setObject:[NSNumber numberWithInt:MMLayoutTabs]
                          forKey:@"layout"];

            openOk = [self openVimControllerWithArguments:arguments];
        }
    } else {
        // Open all files at once.
        openOk = [self openVimControllerWithArguments:arguments];
    }

    return openOk;
}

#ifdef MM_ENABLE_PLUGINS
- (void)addItemToPlugInMenu:(NSMenuItem *)item
{
    NSMenu *menu = [plugInMenuItem submenu];
    [menu addItem:item];
    if ([menu numberOfItems] == 1)
        [self addPlugInMenuToMenu:[NSApp mainMenu]];
}

- (void)removeItemFromPlugInMenu:(NSMenuItem *)item
{
    NSMenu *menu = [plugInMenuItem submenu];
    [menu removeItem:item];
    if ([menu numberOfItems] == 0)
        [self removePlugInMenu];
}
#endif

- (IBAction)newWindow:(id)sender
{
    // A cached controller requires no loading times and results in the new
    // window popping up instantaneously.  If the cache is empty it may take
    // 1-2 seconds to start a new Vim process.
    MMVimController *vc = [self takeVimControllerFromCache];
    if (vc) {
        [[vc backendProxy] acknowledgeConnection];
    } else {
        [self launchVimProcessWithArguments:nil];
    }
}

- (IBAction)newWindowAndActivate:(id)sender
{
    [self activateWhenNextWindowOpens];
    [self newWindow:sender];
}

- (IBAction)fileOpen:(id)sender
{
    NSString *dir = nil;
    BOOL trackPwd = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMDialogsTrackPwdKey];
    if (trackPwd) {
        MMVimController *vc = [self keyVimController];
        if (vc) dir = [vc objectForVimStateKey:@"pwd"];
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
    [panel setAccessoryView:showHiddenFilesView()];

    int result = [panel runModalForDirectory:dir file:nil types:nil];
    if (NSOKButton == result)
        [self application:NSApp openFiles:[panel filenames]];
}

- (IBAction)selectNextWindow:(id)sender
{
    unsigned i, count = [vimControllers count];
    if (!count) return;

    NSWindow *keyWindow = [NSApp keyWindow];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isEqual:keyWindow])
            break;
    }

    if (i < count) {
        if (++i >= count)
            i = 0;
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [[vc windowController] showWindow:self];
    }
}

- (IBAction)selectPreviousWindow:(id)sender
{
    unsigned i, count = [vimControllers count];
    if (!count) return;

    NSWindow *keyWindow = [NSApp keyWindow];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];
        if ([[[vc windowController] window] isEqual:keyWindow])
            break;
    }

    if (i < count) {
        if (i > 0) {
            --i;
        } else {
            i = count - 1;
        }
        MMVimController *vc = [vimControllers objectAtIndex:i];
        [[vc windowController] showWindow:self];
    }
}

- (IBAction)orderFrontPreferencePanel:(id)sender
{
    [[MMPreferenceController sharedPrefsWindowController] showWindow:self];
}

- (IBAction)openWebsite:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:
            [NSURL URLWithString:MMWebsiteString]];
}

- (IBAction)showVimHelp:(id)sender
{
    // Open a new window with the help window maximized.
    [self launchVimProcessWithArguments:[NSArray arrayWithObjects:
            @"-c", @":h gui_mac", @"-c", @":res", nil]];
}

- (IBAction)zoomAll:(id)sender
{
    [NSApp makeWindowsPerform:@selector(performZoom:) inOrder:YES];
}

- (IBAction)atsuiButtonClicked:(id)sender
{
    // This action is called when the user clicks the "use ATSUI renderer"
    // button in the advanced preferences pane.
    [self rebuildPreloadCache];
}

- (IBAction)loginShellButtonClicked:(id)sender
{
    // This action is called when the user clicks the "use login shell" button
    // in the advanced preferences pane.
    [self rebuildPreloadCache];
}

- (IBAction)quickstartButtonClicked:(id)sender
{
    if ([self maxPreloadCacheSize] > 0) {
        [self scheduleVimControllerPreloadAfterDelay:1.0];
        [self startWatchingVimDir];
    } else {
        [self cancelVimControllerPreloadRequests];
        [self clearPreloadCacheWithCount:-1];
        [self stopWatchingVimDir];
    }
}

- (MMVimController *)keyVimController
{
    NSWindow *keyWindow = [NSApp keyWindow];
    if (keyWindow) {
        unsigned i, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if ([[[vc windowController] window] isEqual:keyWindow])
                return vc;
        }
    }

    return nil;
}

- (unsigned)connectBackend:(byref in id <MMBackendProtocol>)proxy pid:(int)pid
{
    //NSLog(@"[%s] pid=%d", _cmd, pid);

    [(NSDistantObject*)proxy setProtocolForProxy:@protocol(MMBackendProtocol)];

    // NOTE: Allocate the vim controller now but don't add it to the list of
    // controllers since this is a distributed object call and as such can
    // arrive at unpredictable times (e.g. while iterating the list of vim
    // controllers).
    // (What if input arrives before the vim controller is added to the list of
    // controllers?  This should not be a problem since the input isn't
    // processed immediately (see processInput:forIdentifier:).)
    MMVimController *vc = [[MMVimController alloc] initWithBackend:proxy
                                                               pid:pid];
    [self performSelector:@selector(addVimController:)
               withObject:vc
               afterDelay:0];

    [vc release];

    return [vc identifier];
}

- (oneway void)processInput:(in bycopy NSArray *)queue
              forIdentifier:(unsigned)identifier
{
    // NOTE: Input is not handled immediately since this is a distribued object
    // call and as such can arrive at unpredictable times.  Instead, queue the
    // input and process it when the run loop is updated.

    if (!(queue && identifier)) {
        NSLog(@"[%s] Bad input for identifier=%d", _cmd, identifier);
        return;
    }

    //NSLog(@"[%s] QUEUE for identifier=%d: <<< %@>>>", _cmd, identifier,
    //        debugStringForMessageQueue(queue));

    NSNumber *key = [NSNumber numberWithUnsignedInt:identifier];
    NSArray *q = [inputQueues objectForKey:key];
    if (q) {
        q = [q arrayByAddingObjectsFromArray:queue];
        [inputQueues setObject:q forKey:key];
    } else {
        [inputQueues setObject:queue forKey:key];
    }

    // NOTE: We must use "event tracking mode" as well as "default mode",
    // otherwise the input queue will not be processed e.g. during live
    // resizing.
    [self performSelector:@selector(processInputQueues:)
               withObject:nil
               afterDelay:0
                  inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode,
                                            NSEventTrackingRunLoopMode, nil]];
}

- (NSArray *)serverList
{
    NSMutableArray *array = [NSMutableArray array];

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count; ++i) {
        MMVimController *controller = [vimControllers objectAtIndex:i];
        if ([controller serverName])
            [array addObject:[controller serverName]];
    }

    return array;
}

@end // MMAppController




@implementation MMAppController (MMServices)

- (void)openSelection:(NSPasteboard *)pboard userData:(NSString *)userData
                error:(NSString **)error
{
    if (![[pboard types] containsObject:NSStringPboardType]) {
        NSLog(@"WARNING: Pasteboard contains no object of type "
                "NSStringPboardType");
        return;
    }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        [vc sendMessage:AddNewTabMsgID data:nil];
        [vc dropString:[pboard stringForType:NSStringPboardType]];
    } else {
        // Save the text, open a new window, and paste the text when the next
        // window opens.  (If this is called several times in a row, then all
        // but the last call may be ignored.)
        if (openSelectionString) [openSelectionString release];
        openSelectionString = [[pboard stringForType:NSStringPboardType] copy];

        [self newWindow:self];
    }
}

- (void)openFile:(NSPasteboard *)pboard userData:(NSString *)userData
           error:(NSString **)error
{
    if (![[pboard types] containsObject:NSStringPboardType]) {
        NSLog(@"WARNING: Pasteboard contains no object of type "
                "NSStringPboardType");
        return;
    }

    // TODO: Parse multiple filenames and create array with names.
    NSString *string = [pboard stringForType:NSStringPboardType];
    string = [string stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    string = [string stringByStandardizingPath];

    NSArray *filenames = [self filterFilesAndNotify:
            [NSArray arrayWithObject:string]];
    if ([filenames count] == 0)
        return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        [vc dropFiles:filenames forceOpen:YES];
    } else {
        [self openFiles:filenames withArguments:nil];
    }
}

- (void)newFileHere:(NSPasteboard *)pboard userData:(NSString *)userData
              error:(NSString **)error
{
    if (![[pboard types] containsObject:NSStringPboardType]) {
        NSLog(@"WARNING: Pasteboard contains no object of type "
              "NSStringPboardType");
        return;
    }

    NSString *path = [pboard stringForType:NSStringPboardType];

    BOOL dirIndicator;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path
                                              isDirectory:&dirIndicator]) {
        NSLog(@"Invalid path. Cannot open new document at: %@", path);
        return;
    }

    if (!dirIndicator)
        path = [path stringByDeletingLastPathComponent];

    path = [path stringByEscapingSpecialFilenameCharacters];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL openInCurrentWindow = [ud boolForKey:MMOpenInCurrentWindowKey];
    MMVimController *vc;

    if (openInCurrentWindow && (vc = [self topmostVimController])) {
        NSString *input = [NSString stringWithFormat:@"<C-\\><C-N>"
                ":tabe|cd %@<CR>", path];
        [vc addVimInput:input];
    } else {
        NSString *input = [NSString stringWithFormat:@":cd %@", path];
        [self launchVimProcessWithArguments:[NSArray arrayWithObjects:
                                             @"-c", input, nil]];
    }
}

@end // MMAppController (MMServices)




@implementation MMAppController (Private)

- (MMVimController *)topmostVimController
{
    // Find the topmost visible window which has an associated vim controller.
    NSEnumerator *e = [[NSApp orderedWindows] objectEnumerator];
    id window;
    while ((window = [e nextObject]) && [window isVisible]) {
        unsigned i, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if ([[[vc windowController] window] isEqual:window])
                return vc;
        }
    }

    return nil;
}

- (int)launchVimProcessWithArguments:(NSArray *)args
{
    int pid = -1;
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"Vim"];

    if (!path) {
        NSLog(@"ERROR: Vim executable could not be found inside app bundle!");
        return -1;
    }

    NSArray *taskArgs = [NSArray arrayWithObjects:@"-g", @"-f", nil];
    if (args)
        taskArgs = [taskArgs arrayByAddingObjectsFromArray:args];

    BOOL useLoginShell = [[NSUserDefaults standardUserDefaults]
            boolForKey:MMLoginShellKey];
    if (useLoginShell) {
        // Run process with a login shell, roughly:
        //   echo "exec Vim -g -f args" | ARGV0=-`basename $SHELL` $SHELL [-l]
        pid = [self executeInLoginShell:path arguments:taskArgs];
    } else {
        // Run process directly:
        //   Vim -g -f args
        NSTask *task = [NSTask launchedTaskWithLaunchPath:path
                                                arguments:taskArgs];
        pid = task ? [task processIdentifier] : -1;
    }

    if (-1 != pid) {
        // The 'pidArguments' dictionary keeps arguments to be passed to the
        // process when it connects (this is in contrast to arguments which are
        // passed on the command line, like '-f' and '-g').
        // If this method is called with nil arguments we take this as a hint
        // that this is an "untitled window" being launched and add a null
        // object to the 'pidArguments' dictionary.  This way we can detect if
        // an untitled window is being launched by looking for null objects in
        // this dictionary.
        // If this method is called with non-nil arguments then it is assumed
        // that the caller takes care of adding items to 'pidArguments' as
        // necessary (only some arguments are passed on connect, e.g. files to
        // open).
        if (!args)
            [pidArguments setObject:[NSNull null]
                             forKey:[NSNumber numberWithInt:pid]];
    } else {
        NSLog(@"WARNING: %s%@ failed (useLoginShell=%d)", _cmd, args,
                useLoginShell);
    }

    return pid;
}

- (NSArray *)filterFilesAndNotify:(NSArray *)filenames
{
    // Go trough 'filenames' array and make sure each file exists.  Present
    // warning dialog if some file was missing.

    NSString *firstMissingFile = nil;
    NSMutableArray *files = [NSMutableArray array];
    unsigned i, count = [filenames count];

    for (i = 0; i < count; ++i) {
        NSString *name = [filenames objectAtIndex:i];
        if ([[NSFileManager defaultManager] fileExistsAtPath:name]) {
            [files addObject:name];
        } else if (!firstMissingFile) {
            firstMissingFile = name;
        }
    }

    if (firstMissingFile) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
                @"Dialog button")];

        NSString *text;
        if ([files count] >= count-1) {
            [alert setMessageText:NSLocalizedString(@"File not found",
                    @"File not found dialog, title")];
            text = [NSString stringWithFormat:NSLocalizedString(
                    @"Could not open file with name %@.",
                    @"File not found dialog, text"), firstMissingFile];
        } else {
            [alert setMessageText:NSLocalizedString(@"Multiple files not found",
                    @"File not found dialog, title")];
            text = [NSString stringWithFormat:NSLocalizedString(
                    @"Could not open file with name %@, and %d other files.",
                    @"File not found dialog, text"),
                firstMissingFile, count-[files count]-1];
        }

        [alert setInformativeText:text];
        [alert setAlertStyle:NSWarningAlertStyle];

        [alert runModal];
        [alert release];

        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    }

    return files;
}

- (NSArray *)filterOpenFiles:(NSArray *)filenames
               openFilesDict:(NSDictionary **)openFiles
{
    // Filter out any files in the 'filenames' array that are open and return
    // all files that are not already open.  On return, the 'openFiles'
    // parameter (if non-nil) will point to a dictionary of open files, indexed
    // by Vim controller.

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSMutableArray *files = [filenames mutableCopy];

    // TODO: Escape special characters in 'files'?
    NSString *expr = [NSString stringWithFormat:
            @"map([\"%@\"],\"bufloaded(v:val)\")",
            [files componentsJoinedByString:@"\",\""]];

    unsigned i, count = [vimControllers count];
    for (i = 0; i < count && [files count] > 0; ++i) {
        MMVimController *vc = [vimControllers objectAtIndex:i];

        // Query Vim for which files in the 'files' array are open.
        NSString *eval = [vc evaluateVimExpression:expr];
        if (!eval) continue;

        NSIndexSet *idxSet = [NSIndexSet indexSetWithVimList:eval];
        if ([idxSet count] > 0) {
            [dict setObject:[files objectsAtIndexes:idxSet]
                     forKey:[NSValue valueWithPointer:vc]];

            // Remove all the files that were open in this Vim process and
            // create a new expression to evaluate.
            [files removeObjectsAtIndexes:idxSet];
            expr = [NSString stringWithFormat:
                    @"map([\"%@\"],\"bufloaded(v:val)\")",
                    [files componentsJoinedByString:@"\",\""]];
        }
    }

    if (openFiles != nil)
        *openFiles = dict;

    return files;
}

#if MM_HANDLE_XCODE_MOD_EVENT
- (void)handleXcodeModEvent:(NSAppleEventDescriptor *)event
                 replyEvent:(NSAppleEventDescriptor *)reply
{
#if 0
    // Xcode sends this event to query MacVim which open files have been
    // modified.
    NSLog(@"reply:%@", reply);
    NSLog(@"event:%@", event);

    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        DescType type = [reply descriptorType];
        unsigned len = [[type data] length];
        NSMutableData *data = [NSMutableData data];

        [data appendBytes:&type length:sizeof(DescType)];
        [data appendBytes:&len length:sizeof(unsigned)];
        [data appendBytes:[reply data] length:len];

        [vc sendMessage:XcodeModMsgID data:data];
    }
#endif
}
#endif

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event
               replyEvent:(NSAppleEventDescriptor *)reply
{
    NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject]
        stringValue];
    NSURL *url = [NSURL URLWithString:urlString];

    // We try to be compatible with TextMate's URL scheme here, as documented
    // at http://blog.macromates.com/2007/the-textmate-url-scheme/ . Currently,
    // this means that:
    //
    // The format is: mvim://open?<arguments> where arguments can be:
    //
    // * url — the actual file to open (i.e. a file://… URL), if you leave
    //         out this argument, the frontmost document is implied.
    // * line — line number to go to (one based).
    // * column — column number to go to (one based).
    //
    // Example: mvim://open?url=file:///etc/profile&line=20

    if ([[url host] isEqualToString:@"open"]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];

        // Parse query ("url=file://...&line=14") into a dictionary
        NSArray *queries = [[url query] componentsSeparatedByString:@"&"];
        NSEnumerator *enumerator = [queries objectEnumerator];
        NSString *param;
        while( param = [enumerator nextObject] ) {
            NSArray *arr = [param componentsSeparatedByString:@"="];
            if ([arr count] == 2) {
                [dict setValue:[[arr lastObject]
                            stringByReplacingPercentEscapesUsingEncoding:
                                NSUTF8StringEncoding]
                        forKey:[[arr objectAtIndex:0]
                            stringByReplacingPercentEscapesUsingEncoding:
                                NSUTF8StringEncoding]];
            }
        }

        // Actually open the file.
        NSString *file = [dict objectForKey:@"url"];
        if (file != nil) {
            NSURL *fileUrl= [NSURL URLWithString:file];
            // TextMate only opens files that already exist.
            if ([fileUrl isFileURL]
                    && [[NSFileManager defaultManager] fileExistsAtPath:
                           [fileUrl path]]) {
                // Strip 'file://' path, else application:openFiles: might think
                // the file is not yet open.
                NSArray *filenames = [NSArray arrayWithObject:[fileUrl path]];

                // Look for the line and column options.
                NSDictionary *args = nil;
                NSString *line = [dict objectForKey:@"line"];
                if (line) {
                    NSString *column = [dict objectForKey:@"column"];
                    if (column)
                        args = [NSDictionary dictionaryWithObjectsAndKeys:
                                line, @"cursorLine",
                                column, @"cursorColumn",
                                nil];
                    else
                        args = [NSDictionary dictionaryWithObject:line
                                forKey:@"cursorLine"];
                }

                [self openFiles:filenames withArguments:args];
            }
        }
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"OK",
            @"Dialog button")];

        [alert setMessageText:NSLocalizedString(@"Unknown URL Scheme",
            @"Unknown URL Scheme dialog, title")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(
            @"This version of MacVim does not support \"%@\""
            @" in its URL scheme.",
            @"Unknown URL Scheme dialog, text"),
            [url host]]];

        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
        [alert release];
    }
}


- (int)findLaunchingProcessWithoutArguments
{
    NSArray *keys = [pidArguments allKeysForObject:[NSNull null]];
    if ([keys count] > 0) {
        //NSLog(@"found launching process without arguments");
        return [[keys objectAtIndex:0] intValue];
    }

    return -1;
}

- (MMVimController *)findUnusedEditor
{
    NSEnumerator *e = [vimControllers objectEnumerator];
    id vc;
    while ((vc = [e nextObject])) {
        if ([[vc objectForVimStateKey:@"unusedEditor"] boolValue])
            return vc;
    }

    return nil;
}

- (NSMutableDictionary *)extractArgumentsFromOdocEvent:
    (NSAppleEventDescriptor *)desc
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // 1. Extract ODB parameters (if any)
    NSAppleEventDescriptor *odbdesc = desc;
    if (![odbdesc paramDescriptorForKeyword:keyFileSender]) {
        // The ODB paramaters may hide inside the 'keyAEPropData' descriptor.
        odbdesc = [odbdesc paramDescriptorForKeyword:keyAEPropData];
        if (![odbdesc paramDescriptorForKeyword:keyFileSender])
            odbdesc = nil;
    }

    if (odbdesc) {
        NSAppleEventDescriptor *p =
                [odbdesc paramDescriptorForKeyword:keyFileSender];
        if (p)
            [dict setObject:[NSNumber numberWithUnsignedInt:[p typeCodeValue]]
                     forKey:@"remoteID"];

        p = [odbdesc paramDescriptorForKeyword:keyFileCustomPath];
        if (p)
            [dict setObject:[p stringValue] forKey:@"remotePath"];

        p = [odbdesc paramDescriptorForKeyword:keyFileSenderToken];
        if (p) {
            [dict setObject:[NSNumber numberWithUnsignedLong:[p descriptorType]]
                     forKey:@"remoteTokenDescType"];
            [dict setObject:[p data] forKey:@"remoteTokenData"];
        }
    }

    // 2. Extract Xcode parameters (if any)
    NSAppleEventDescriptor *xcodedesc =
            [desc paramDescriptorForKeyword:keyAEPosition];
    if (xcodedesc) {
        NSRange range;
        MMSelectionRange *sr = (MMSelectionRange*)[[xcodedesc data] bytes];

        if (sr->lineNum < 0) {
            // Should select a range of lines.
            range.location = sr->startRange + 1;
            range.length = sr->endRange - sr->startRange + 1;
        } else {
            // Should only move cursor to a line.
            range.location = sr->lineNum + 1;
            range.length = 0;
        }

        [dict setObject:NSStringFromRange(range) forKey:@"selectionRange"];
    }

    // 3. Extract Spotlight search text (if any)
    NSAppleEventDescriptor *spotlightdesc = 
            [desc paramDescriptorForKeyword:keyAESearchText];
    if (spotlightdesc)
        [dict setObject:[spotlightdesc stringValue] forKey:@"searchText"];

    return dict;
}

#ifdef MM_ENABLE_PLUGINS
- (void)removePlugInMenu
{
    if ([plugInMenuItem menu])
        [[plugInMenuItem menu] removeItem:plugInMenuItem];
}

- (void)addPlugInMenuToMenu:(NSMenu *)mainMenu
{
    NSMenu *windowsMenu = [mainMenu findWindowsMenu];

    if ([[plugInMenuItem submenu] numberOfItems] > 0) {
        int idx = windowsMenu ? [mainMenu indexOfItemWithSubmenu:windowsMenu]
                              : -1;
        if (idx > 0) {
            [mainMenu insertItem:plugInMenuItem atIndex:idx];
        } else {
            [mainMenu addItem:plugInMenuItem];
        }
    }
}
#endif

- (void)scheduleVimControllerPreloadAfterDelay:(NSTimeInterval)delay
{
    [self performSelector:@selector(preloadVimController:)
               withObject:nil
               afterDelay:delay];
}

- (void)cancelVimControllerPreloadRequests
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
            selector:@selector(preloadVimController:)
              object:nil];
}

- (void)preloadVimController:(id)sender
{
    // We only allow preloading of one Vim process at a time (to avoid hogging
    // CPU), so schedule another preload in a little while if necessary.
    if (-1 != preloadPid) {
        [self scheduleVimControllerPreloadAfterDelay:2];
        return;
    }

    if ([cachedVimControllers count] >= [self maxPreloadCacheSize])
        return;

    preloadPid = [self launchVimProcessWithArguments:
            [NSArray arrayWithObject:@"--mmwaitforack"]];
}

- (int)maxPreloadCacheSize
{
    // The maximum number of Vim processes to keep in the cache can be
    // controlled via the user default "MMPreloadCacheSize".
    int maxCacheSize = [[NSUserDefaults standardUserDefaults]
            integerForKey:MMPreloadCacheSizeKey];
    if (maxCacheSize < 0) maxCacheSize = 0;
    else if (maxCacheSize > 10) maxCacheSize = 10;

    return maxCacheSize;
}

- (MMVimController *)takeVimControllerFromCache
{
    // NOTE: After calling this message the backend corresponding to the
    // returned vim controller must be sent an acknowledgeConnection message,
    // else the vim process will be stuck.
    //
    // This method may return nil even though the cache might be non-empty; the
    // caller should handle this by starting a new Vim process.

    int i, count = [cachedVimControllers count];
    if (0 == count) return nil;

    // Locate the first Vim controller with up-to-date rc-files sourced.
    NSDate *rcDate = [self rcFilesModificationDate];
    for (i = 0; i < count; ++i) {
        MMVimController *vc = [cachedVimControllers objectAtIndex:i];
        NSDate *date = [vc creationDate];
        if ([date compare:rcDate] != NSOrderedAscending)
            break;
    }

    if (i > 0) {
        // Clear out cache entries whose vimrc/gvimrc files were sourced before
        // the latest modification date for those files.  This ensures that the
        // latest rc-files are always sourced for new windows.
        [self clearPreloadCacheWithCount:i];
    }

    if ([cachedVimControllers count] == 0) {
        [self scheduleVimControllerPreloadAfterDelay:2.0];
        return nil;
    }

    MMVimController *vc = [cachedVimControllers objectAtIndex:0];
    [vimControllers addObject:vc];
    [cachedVimControllers removeObjectAtIndex:0];
    [vc setIsPreloading:NO];

    // If the Vim process has finished loading then the window will displayed
    // now, otherwise it will be displayed when the OpenWindowMsgID message is
    // received.
    [[vc windowController] showWindow];

    // Since we've taken one controller from the cache we take the opportunity
    // to preload another.
    [self scheduleVimControllerPreloadAfterDelay:1];

    return vc;
}

- (void)clearPreloadCacheWithCount:(int)count
{
    // Remove the 'count' first entries in the preload cache.  It is assumed
    // that objects are added/removed from the cache in a FIFO manner so that
    // this effectively clears the 'count' oldest entries.
    // If 'count' is negative, then the entire cache is cleared.

    if ([cachedVimControllers count] == 0 || count == 0)
        return;

    if (count < 0)
        count = [cachedVimControllers count];

    // Make sure the preloaded Vim processes get killed or they'll just hang
    // around being useless until MacVim is terminated.
    NSEnumerator *e = [cachedVimControllers objectEnumerator];
    MMVimController *vc;
    int n = count;
    while ((vc = [e nextObject]) && n-- > 0) {
        [[NSNotificationCenter defaultCenter] removeObserver:vc];
        [vc sendMessage:TerminateNowMsgID data:nil];

        // Since the preloaded processes were killed "prematurely" we have to
        // manually tell them to cleanup (it is not enough to simply release
        // them since deallocation and cleanup are separated).
        [vc cleanup];
    }

    n = count;
    while (n-- > 0 && [cachedVimControllers count] > 0)
        [cachedVimControllers removeObjectAtIndex:0];

    // There is a small delay before the Vim process actually exits so wait a
    // little before trying to reap the child process.  If the process still
    // hasn't exited after this wait it won't be reaped until the next time
    // reapChildProcesses: is called (but this should be harmless).
    [self performSelector:@selector(reapChildProcesses:)
               withObject:nil
               afterDelay:0.1];
}

- (void)rebuildPreloadCache
{
    if ([self maxPreloadCacheSize] > 0) {
        [self clearPreloadCacheWithCount:-1];
        [self cancelVimControllerPreloadRequests];
        [self scheduleVimControllerPreloadAfterDelay:1.0];
    }
}

- (NSDate *)rcFilesModificationDate
{
    // Check modification dates for ~/.vimrc and ~/.gvimrc and return the
    // latest modification date.  If ~/.vimrc does not exist, check ~/_vimrc
    // and similarly for gvimrc.
    // Returns distantPath if no rc files were found.

    NSDate *date = [NSDate distantPast];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *path = [@"~/.vimrc" stringByExpandingTildeInPath];
    NSDictionary *attr = [fm fileAttributesAtPath:path traverseLink:YES];
    if (!attr) {
        path = [@"~/_vimrc" stringByExpandingTildeInPath];
        attr = [fm fileAttributesAtPath:path traverseLink:YES];
    }
    NSDate *modDate = [attr objectForKey:NSFileModificationDate];
    if (modDate)
        date = modDate;

    path = [@"~/.gvimrc" stringByExpandingTildeInPath];
    attr = [fm fileAttributesAtPath:path traverseLink:YES];
    if (!attr) {
        path = [@"~/_gvimrc" stringByExpandingTildeInPath];
        attr = [fm fileAttributesAtPath:path traverseLink:YES];
    }
    modDate = [attr objectForKey:NSFileModificationDate];
    if (modDate)
        date = [date laterDate:modDate];

    return date;
}

- (BOOL)openVimControllerWithArguments:(NSDictionary *)arguments
{
    MMVimController *vc = [self findUnusedEditor];
    if (vc) {
        // Open files in an already open window.
        [[[vc windowController] window] makeKeyAndOrderFront:self];
        [vc passArguments:arguments];
    } else if ((vc = [self takeVimControllerFromCache])) {
        // Open files in a new window using a cached vim controller.  This
        // requires virtually no loading time so the new window will pop up
        // instantaneously.
        [vc passArguments:arguments];
        [[vc backendProxy] acknowledgeConnection];
    } else {
        // Open files in a launching Vim process or start a new process.  This
        // may take 1-2 seconds so there will be a visible delay before the
        // window appears on screen.
        int pid = [self findLaunchingProcessWithoutArguments];
        if (-1 == pid) {
            pid = [self launchVimProcessWithArguments:nil];
            if (-1 == pid)
                return NO;
        }

        // TODO: If the Vim process fails to start, or if it changes PID,
        // then the memory allocated for these parameters will leak.
        // Ensure that this cannot happen or somehow detect it.

        if ([arguments count] > 0)
            [pidArguments setObject:arguments
                             forKey:[NSNumber numberWithInt:pid]];
    }

    return YES;
}

- (void)activateWhenNextWindowOpens
{
    shouldActivateWhenNextWindowOpens = YES;
}

- (void)startWatchingVimDir
{
    //NSLog(@"%s", _cmd);
#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
    if (fsEventStream)
        return;
    if (NULL == FSEventStreamStart)
        return; // FSEvent functions are weakly linked

    NSString *path = [@"~/.vim" stringByExpandingTildeInPath];
    NSArray *pathsToWatch = [NSArray arrayWithObject:path];
 
    fsEventStream = FSEventStreamCreate(NULL, &fsEventCallback, NULL,
            (CFArrayRef)pathsToWatch, kFSEventStreamEventIdSinceNow,
            MMEventStreamLatency, kFSEventStreamCreateFlagNone);

    FSEventStreamScheduleWithRunLoop(fsEventStream,
            [[NSRunLoop currentRunLoop] getCFRunLoop],
            kCFRunLoopDefaultMode);

    FSEventStreamStart(fsEventStream);
    //NSLog(@"Started FS event stream");
#endif
}

- (void)stopWatchingVimDir
{
    //NSLog(@"%s", _cmd);
#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
    if (NULL == FSEventStreamStop)
        return; // FSEvent functions are weakly linked

    if (fsEventStream) {
        FSEventStreamStop(fsEventStream);
        FSEventStreamInvalidate(fsEventStream);
        FSEventStreamRelease(fsEventStream);
        fsEventStream = NULL;
        //NSLog(@"Stopped FS event stream");
    }
#endif

}

- (void)handleFSEvent
{
    //NSLog(@"%s", _cmd);
    [self clearPreloadCacheWithCount:-1];

    // Several FS events may arrive in quick succession so make sure to cancel
    // any previous preload requests before making a new one.
    [self cancelVimControllerPreloadRequests];
    [self scheduleVimControllerPreloadAfterDelay:0.5];
}

- (void)loadDefaultFont
{
    // It is possible to set a user default to avoid loading the default font
    // (this cuts down on startup time).
    if (![[NSUserDefaults standardUserDefaults] boolForKey:MMLoadDefaultFontKey]
            || fontContainerRef)
        return;

    // Load all fonts in the Resouces folder of the app bundle.
    NSString *fontsFolder = [[NSBundle mainBundle] resourcePath];
    if (fontsFolder) {
        NSURL *fontsURL = [NSURL fileURLWithPath:fontsFolder];
        if (fontsURL) {
            FSRef fsRef;
            CFURLGetFSRef((CFURLRef)fontsURL, &fsRef);

#if (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
            // This is the font activation API for OS X 10.5.  Only compile
            // this code if we're building on OS X 10.5 or later.
            if (NULL != ATSFontActivateFromFileReference) { // Weakly linked
                ATSFontActivateFromFileReference(&fsRef, kATSFontContextLocal,
                                                 kATSFontFormatUnspecified,
                                                 NULL, kATSOptionFlagsDefault,
                                                 &fontContainerRef);
            }
#endif
#if (MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4)
            // The following font activation API was deprecated in OS X 10.5.
            // Don't compile this code unless we're targeting OS X 10.4.
            FSSpec fsSpec;
            if (fontContainerRef == 0 &&
                    FSGetCatalogInfo(&fsRef, kFSCatInfoNone, NULL, NULL,
                                     &fsSpec, NULL) == noErr) {
                ATSFontActivateFromFileSpecification(&fsSpec,
                        kATSFontContextLocal, kATSFontFormatUnspecified, NULL,
                        kATSOptionFlagsDefault, &fontContainerRef);
            }
#endif
        }
    }

    if (!fontContainerRef)
        NSLog(@"WARNING: Failed to activate the default font (the app bundle "
                "may be incomplete)");
}

- (int)executeInLoginShell:(NSString *)path arguments:(NSArray *)args
{
    // Start a login shell and execute the command 'path' with arguments 'args'
    // in the shell.  This ensures that user environment variables are set even
    // when MacVim was started from the Finder.

    int pid = -1;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    // Determine which shell to use to execute the command.  The user
    // may decide which shell to use by setting a user default or the
    // $SHELL environment variable.
    NSString *shell = [ud stringForKey:MMLoginShellCommandKey];
    if (!shell || [shell length] == 0)
        shell = [[[NSProcessInfo processInfo] environment]
            objectForKey:@"SHELL"];
    if (!shell)
        shell = @"/bin/bash";

    //NSLog(@"shell = %@", shell);

    // Bash needs the '-l' flag to launch a login shell.  The user may add
    // flags by setting a user default.
    NSString *shellArgument = [ud stringForKey:MMLoginShellArgumentKey];
    if (!shellArgument || [shellArgument length] == 0) {
        if ([[shell lastPathComponent] isEqual:@"bash"])
            shellArgument = @"-l";
        else
            shellArgument = nil;
    }

    //NSLog(@"shellArgument = %@", shellArgument);

    // Build input string to pipe to the login shell.
    NSMutableString *input = [NSMutableString stringWithFormat:
            @"exec \"%@\"", path];
    if (args) {
        // Append all arguments, making sure they are properly quoted, even
        // when they contain single quotes.
        NSEnumerator *e = [args objectEnumerator];
        id obj;

        while ((obj = [e nextObject])) {
            NSMutableString *arg = [NSMutableString stringWithString:obj];
            [arg replaceOccurrencesOfString:@"'" withString:@"'\"'\"'"
                                    options:NSLiteralSearch
                                      range:NSMakeRange(0, [arg length])];
            [input appendFormat:@" '%@'", arg];
        }
    }

    // Build the argument vector used to start the login shell.
    NSString *shellArg0 = [NSString stringWithFormat:@"-%@",
             [shell lastPathComponent]];
    char *shellArgv[3] = { (char *)[shellArg0 UTF8String], NULL, NULL };
    if (shellArgument)
        shellArgv[1] = (char *)[shellArgument UTF8String];

    // Get the C string representation of the shell path before the fork since
    // we must not call Foundation functions after a fork.
    const char *shellPath = [shell fileSystemRepresentation];

    // Fork and execute the process.
    int ds[2];
    if (pipe(ds)) return -1;

    pid = fork();
    if (pid == -1) {
        return -1;
    } else if (pid == 0) {
        // Child process

        if (close(ds[1]) == -1) exit(255);
        if (dup2(ds[0], 0) == -1) exit(255);

        // Without the following call warning messages like this appear on the
        // console:
        //     com.apple.launchd[69] : Stray process with PGID equal to this
        //                             dead job: PID 1589 PPID 1 Vim
        setsid();

        execv(shellPath, shellArgv);

        // Never reached unless execv fails
        exit(255);
    } else {
        // Parent process
        if (close(ds[0]) == -1) return -1;

        // Send input to execute to the child process
        [input appendString:@"\n"];
        int bytes = [input lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (write(ds[1], [input UTF8String], bytes) != bytes) return -1;
        if (close(ds[1]) == -1) return -1;

        ++numChildProcesses;
        //NSLog(@"new process pid=%d (count=%d)", pid, numChildProcesses);
    }

    return pid;
}

- (void)reapChildProcesses:(id)sender
{
    // NOTE: numChildProcesses (currently) only counts the number of Vim
    // processes that have been started with executeInLoginShell::.  If other
    // processes are spawned this code may need to be adjusted (or
    // numChildProcesses needs to be incremented when such a process is
    // started).
    while (numChildProcesses > 0) {
        int status = 0;
        int pid = waitpid(-1, &status, WNOHANG);
        if (pid <= 0)
            break;

        //NSLog(@"WAIT for pid=%d complete", pid);
        --numChildProcesses;
    }
}

- (void)processInputQueues:(id)sender
{
    // NOTE: Because we use distributed objects it is quite possible for this
    // function to be re-entered.  This can cause all sorts of unexpected
    // problems so we guard against it here so that the rest of the code does
    // not need to worry about it.

    // The processing flag is > 0 if this function is already on the call
    // stack; < 0 if this function was also re-entered.
    if (processingFlag != 0) {
        NSLog(@"[%s] BUSY!", _cmd);
        processingFlag = -1;
        return;
    }

    // NOTE: Be _very_ careful that no exceptions can be raised between here
    // and the point at which 'processingFlag' is reset.  Otherwise the above
    // test could end up always failing and no input queues would ever be
    // processed!
    processingFlag = 1;

    // NOTE: New input may arrive while we're busy processing; we deal with
    // this by putting the current queue aside and creating a new input queue
    // for future input.
    NSDictionary *queues = inputQueues;
    inputQueues = [NSMutableDictionary new];

    // Pass each input queue on to the vim controller with matching
    // identifier (and note that it could be cached).
    NSEnumerator *e = [queues keyEnumerator];
    NSNumber *key;
    while ((key = [e nextObject])) {
        unsigned ukey = [key unsignedIntValue];
        int i = 0, count = [vimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [vimControllers objectAtIndex:i];
            if (ukey == [vc identifier]) {
                [vc processInputQueue:[queues objectForKey:key]]; // !exceptions
                break;
            }
        }

        if (i < count) continue;

        count = [cachedVimControllers count];
        for (i = 0; i < count; ++i) {
            MMVimController *vc = [cachedVimControllers objectAtIndex:i];
            if (ukey == [vc identifier]) {
                [vc processInputQueue:[queues objectForKey:key]]; // !exceptions
                break;
            }
        }

        if (i == count)
            NSLog(@"[%s] WARNING: No Vim controller for identifier=%d",
                    _cmd, ukey);
    }

    [queues release];

    // If new input arrived while we were processing it would have been
    // blocked so we have to schedule it to be processed again.
    if (processingFlag < 0)
        [self performSelector:@selector(processInputQueues:)
                   withObject:nil
                   afterDelay:0
                      inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode,
                                            NSEventTrackingRunLoopMode, nil]];

    processingFlag = 0;
}

- (void)addVimController:(MMVimController *)vc
{
    int pid = [vc pid];
    NSNumber *pidKey = [NSNumber numberWithInt:pid];

    if (preloadPid == pid) {
        // This controller was preloaded, so add it to the cache and
        // schedule another vim process to be preloaded.
        preloadPid = -1;
        [vc setIsPreloading:YES];
        [cachedVimControllers addObject:vc];
        [self scheduleVimControllerPreloadAfterDelay:1];
    } else {
        [vimControllers addObject:vc];

        id args = [pidArguments objectForKey:pidKey];
        if (args && [NSNull null] != args)
            [vc passArguments:args];

        // HACK!  MacVim does not get activated if it is launched from the
        // terminal, so we forcibly activate here unless it is an untitled
        // window opening.  Untitled windows are treated differently, else
        // MacVim would steal the focus if another app was activated while the
        // untitled window was loading.
        if (!args || args != [NSNull null])
            [self activateWhenNextWindowOpens];

        if (args)
            [pidArguments removeObjectForKey:pidKey];
    }
}

@end // MMAppController (Private)
