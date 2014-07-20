//
//  subtleTableViewController.m
//  Subtle
//
//  Created by Coulton Vento on 7/19/14.
//  Copyright (c) 2014 Subtle. All rights reserved.
//

#import "subtleTableViewController.h"
#import "INDANCSServer.h"

@interface subtleTableViewController ()
@property (nonatomic, strong) INDANCSServer *server;
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
    // Dispose of any resources that can be recreated.
}

#pragma mark UITableView
#pragma mark Data Source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] init];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    return cell;
}

@end
