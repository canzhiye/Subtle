//
//  subtleSettingsTableViewCell.m
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import "subtleSettingsTableViewCell.h"

@implementation subtleSettingsTableViewCell

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.textLabel.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)awakeFromNib
{
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
}

@end
