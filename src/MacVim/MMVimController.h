/* vi:set ts=8 sts=4 sw=4 ft=objc:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *				MacVim GUI port by Bjorn Winckler
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

#import <Cocoa/Cocoa.h>
#import "MacVim.h"

#ifdef MM_ENABLE_PLUGINS
#import "PlugInImpl.h"
#endif


@class MMWindowController;



@interface MMVimController : NSObject <MMFrontendProtocol>
{
    BOOL                isInitialized;
    MMWindowController  *windowController;
    id                  backendProxy;
    BOOL                inProcessCommandQueue;
    NSMutableArray      *sendQueue;
    NSMutableArray      *receiveQueue;
    NSMenu              *mainMenu;
    NSMutableArray      *popupMenuItems;
    NSToolbar           *toolbar;
    NSMutableDictionary *toolbarItemDict;
    int                 pid;
    NSString            *serverName;
    NSDictionary        *vimState;
#ifdef MM_ENABLE_PLUGINS
    MMPlugInInstanceMediator *instanceMediator;
#endif
}

- (id)initWithBackend:(id)backend pid:(int)processIdentifier;
- (id)backendProxy;
- (int)pid;
- (void)setServerName:(NSString *)name;
- (NSString *)serverName;
- (MMWindowController *)windowController;
- (NSDictionary *)vimState;
- (NSMenu *)mainMenu;
- (void)cleanup;
- (void)dropFiles:(NSArray *)filenames forceOpen:(BOOL)force;
- (void)dropString:(NSString *)string;
- (void)odbEdit:(NSArray *)filenames server:(OSType)theID path:(NSString *)path
          token:(NSAppleEventDescriptor *)token;
- (void)sendMessage:(int)msgid data:(NSData *)data;
- (BOOL)sendMessageNow:(int)msgid data:(NSData *)data
               timeout:(NSTimeInterval)timeout;
- (void)addVimInput:(NSString *)string;
- (NSString *)evaluateVimExpression:(NSString *)expr;
- (id)evaluateVimExpressionCocoa:(NSString *)expr errorString:(NSString **)errstr;
#ifdef MM_ENABLE_PLUGINS
- (MMPlugInInstanceMediator *)instanceMediator;
#endif
@end
