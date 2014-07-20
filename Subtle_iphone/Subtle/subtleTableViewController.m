//
//  subtleTableViewController.m
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import "subtleTableViewController.h"
#import "subtleSettingsTableViewCell.h"
#import "subtleSettingsTableViewCell.h"
#import "subtleAPI.h"

@interface subtleTableViewController ()

@end

@implementation subtleTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.server = [[INDANCSServer alloc] initWithUID:@"INDANCSServer"];
	[self.server startAdvertising];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark UITableView
#pragma mark Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1;
    }
    return [self.apps count];
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    subtleSettingsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"settingsCell" forIndexPath:indexPath];
    if (!cell) {
        cell = [[subtleSettingsTableViewCell alloc] init];
    }
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Notifications";
            
            [cell.settingsSwitch setOn:[subtleAPI notificationsEnabled]];
            [cell.settingsSwitch addTarget:self action:@selector(toggleNotifications:) forControlEvents:UIControlEventValueChanged];
        }
    }
    
    return cell;
}

- (void)toggleNotifications:(UISwitch*)settingsSwitch
{
    if (!settingsSwitch.on) {
        [subtleAPI notificationsSetEnabled:NO withTime:nil];
    } else {
        [subtleAPI notificationsSetEnabled:YES withTime:nil];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag == 1) {
        NSString *title = [alertView buttonTitleAtIndex:buttonIndex];
        if ([title isEqualToString:@"Yes"]) {
            
            [subtleAPI notificationsSetEnabled:YES withTime:nil];
            
        } else if ([title isEqualToString:@"Disable until"]) {
            
            NSLog(@"input time.");
            
        } else {
            
            
            
        }
    }
}

- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1 && [self.apps count] > 0) {
        return @"Your Apps";
    }
    return @"";
}

- (NSString*)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        if (![subtleAPI notificationsEnabled]) {
            NSDate *date = [subtleAPI notificationDisabledUntil];
            if (date) {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"MMMM d, yyyy at h:mm a"];
                
                return [NSString stringWithFormat:@"You have disabled notifications until %@.",[formatter stringFromDate:date]];
            }
        }
    }
    return @"";
}

@end
