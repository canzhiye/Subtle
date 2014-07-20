//
//  subtleAPI.m
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import "subtleAPI.h"

@implementation subtleAPI

#pragma mark - Defaults

+ (BOOL)defaultsContainKey:(NSString*)key
{
    if ([[NSUserDefaults standardUserDefaults] objectForKey:key]) {
        return YES;
    }
    return NO;
}

#pragma mark - Enabled/Disabled

+ (BOOL)notificationsEnabled
{
    if (![subtleAPI defaultsContainKey:@"notifications"]) {
        return NO;
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"notifications"];
}

+ (NSDate*)notificationDisabledUntil
{
    if ([subtleAPI notificationsEnabled] || ![subtleAPI defaultsContainKey:@"notifications_until"]) {
        return nil;
    }
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"notifications_until"];
}

+ (void)notificationsSetEnabled:(BOOL)enabled withTime:(NSDate*)date
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled
                                            forKey:@"notifications"];
    if (enabled)
        date = nil;
    
    [[NSUserDefaults standardUserDefaults] setObject:date forKey:@"notifications_until"];
}

@end
