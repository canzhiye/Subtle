//
//  subtleTableViewController.h
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "INDANCSServer.h"

@interface subtleTableViewController : UITableViewController <UIAlertViewDelegate>

@property (nonatomic, strong) INDANCSServer *server;
@property (nonatomic, strong) NSMutableArray *apps;

@end
