//
//  WPNUXSecondaryButton.m
//  WordPress
//
//  Created by Sendhil Panchadsaram on 5/9/13.
//  Copyright (c) 2013 WordPress. All rights reserved.
//

#import "WPNUXSecondaryButton.h"

@implementation WPNUXSecondaryButton

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        UIImage *mainImage = [[UIImage imageNamed:@"btn-secondary"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
        UIImage *tappedImage = [[UIImage imageNamed:@"btn-secondary-tap"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
        self.titleLabel.font = [UIFont fontWithName:@"OpenSans" size:15.0];
        self.titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [self setTitleEdgeInsets:UIEdgeInsetsMake(0, 15.0, 0, 15.0)];
        [self setBackgroundImage:mainImage forState:UIControlStateNormal];
        [self setBackgroundImage:tappedImage forState:UIControlStateHighlighted];
        
        [self setTitleColor:[UIColor colorWithRed:153.0/255.0 green:153.0/255.0 blue:153.0/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self setTitleShadowColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.2] forState:UIControlStateNormal];
        
        [self setTitleColor:[UIColor colorWithRed:153.0/255.0 green:153.0/255.0 blue:153.0/255.0 alpha:0.3] forState:UIControlStateHighlighted];
        [self setTitleShadowColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.1] forState:UIControlStateHighlighted];
        
        [self setTitleColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.5] forState:UIControlStateDisabled];
        [self setTitleShadowColor:[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.8] forState:UIControlStateDisabled];
        
        self.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    }
    return self;
}

- (void)sizeToFit
{
    [super sizeToFit];
    
    // Adjust frame to account for the edge insets
    CGRect frame = self.frame;
    frame.size.width += self.titleEdgeInsets.left + self.titleEdgeInsets.right;
    self.frame = frame;
}

@end
