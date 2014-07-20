//
//  subtleAPI.h
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface subtleAPI : NSObject

+ (BOOL)defaultsContainKey:(NSString*)key;

+ (BOOL)notificationsEnabled;
+ (NSDate*)notificationDisabledUntil;
+ (void)notificationsSetEnabled:(BOOL)enabled withTime:(NSDate*)date;

@end
