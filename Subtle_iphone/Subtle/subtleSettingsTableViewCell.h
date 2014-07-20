//
//  subtleSettingsTableViewCell.h
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface subtleSettingsTableViewCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UISwitch *settingsSwitch;
@property (nonatomic, strong) IBOutlet UILabel *settingsLabel;

@end
