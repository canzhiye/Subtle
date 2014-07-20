//
//  AppDelegate.h
//  Subtle
//
//  Created by Canzhi Ye on 7/19/14.
//  Copyright (c) 2014 Canzhi Ye. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (strong, nonatomic) IBOutlet NSMenu *statusMenu;
@property (strong, nonatomic) NSStatusItem *statusItem;

@end
