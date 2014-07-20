//
//  INDAppDelegate.h
//  INDANCSMac
//
//  Created by Indragie Karunaratne on 12/11/2013.
//  Copyright (c) 2013 Indragie Karunaratne. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <HueSDK_OSX/HueSDK.h>

#define NSAppDelegate  ((AppDelegate *)[[NSApplication sharedApplication] delegate])


@interface INDAppDelegate : NSObject <NSApplicationDelegate>
@property (assign) IBOutlet NSWindow *window;

/**
 Starts the local heartbeat
 */
- (void)enableLocalHeartbeat;

/**
 Stops the local heartbeat
 */
- (void)disableLocalHeartbeat;

/**
 Starts a search for a bridge
 */
- (void)searchForBridgeLocal;


@end
