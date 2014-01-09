/*
 * StatsBarGraphCell.m
 *
 * Copyright (c) 2014 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import "StatsViewsVisitorsBarGraphCell.h"

static CGFloat AxisPadding = 18.0f;
static CGFloat InitialBarWidth = 30.0f;
static CGFloat const AxisPaddingIpad = 39.0f;
static CGFloat const InitialBarWidthIpad = 60.0f;

@interface WPBarGraphView : UIView

@property (nonatomic, strong) NSMutableDictionary *categoryBars;
@property (nonatomic, strong) NSMutableDictionary *categoryColors;
@property (nonatomic, strong) UIImage *cachedImage;

// Builds legend and determines graph layers
- (void)addCategory:(NSString *)categoryName color:(UIColor *)color;

// Add bars to the graph.
// Limitation: if N x-axis names are used between the N categories, the last takes precendence
// If category A has N points and category B has M points, where N < M, then M points are displayed,
// with M - N points drawn without layers. The x-axis is extended to the last Mth point
/*
 @[
    @{@"name": @"Jan 10",
      @"count": @10},
    @{@"name": @"Jan 11",
      @"count": @20},
    ...
 ]
 */
- (void)setBarsWithCount:(NSArray *)pointToCount category:(NSString *)category;

@end

@implementation WPBarGraphView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (IS_IPAD) {
            InitialBarWidth = InitialBarWidthIpad;
            AxisPadding = AxisPaddingIpad;
        }
        
        _categoryBars = [NSMutableDictionary dictionary];
        _categoryColors = [NSMutableDictionary dictionary];
        
        self.backgroundColor = [UIColor whiteColor];
    }
    return self;
}

- (void)addCategory:(NSString *)categoryName color:(UIColor *)color {
    _cachedImage = nil;
    _categoryColors[categoryName] = color;
}

- (void)setBarsWithCount:(NSArray *)pointToCount category:(NSString *)category {
    _cachedImage = nil;
    _categoryBars[category] = pointToCount;
    
    [self setNeedsDisplay];
}

- (void)calculateYAxisScale:(CGFloat *)yAxisScale xAxisScale:(CGFloat *)xAxisStepWidth maxXPointCount:(NSUInteger *)maxXAxisPointCount maxYPoint:(NSUInteger *)maxYPoint {
    // Max X/Y Points
    [_categoryBars enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *points, BOOL *stop) {
        *maxXAxisPointCount = MAX(points.count, *maxXAxisPointCount);
        
        [points enumerateObjectsUsingBlock:^(NSDictionary *point, NSUInteger idx, BOOL *stop) {
            *maxYPoint = MAX(*maxYPoint, [point[@"count"] unsignedIntegerValue]);
        }];
    }];
    
    *xAxisStepWidth = (self.frame.size.width-3*AxisPadding)/(*maxXAxisPointCount);
    
    *yAxisScale = *maxYPoint > 0 ? (self.frame.size.height-4*AxisPadding)/(*maxYPoint) : 1;
}

- (void)drawRect:(CGRect)rect {
    if (_cachedImage) {
        // Yes, performance hit, but we're serving a cached image
        [self addSubview:([[UIImageView alloc] initWithImage:_cachedImage])];
        return;
    }
    
    NSUInteger maxYPoint = 0;       // The tallest bar 'point'
    CGFloat yAxisScale = 0;      // rounded integer scale to use up y axis
    CGFloat xAxisStepWidth = 0;
    NSUInteger maxXAxisPointCount = 0; // # points along the x axis
    
    CGFloat xAxisStartPoint = AxisPadding*2;
    CGFloat xAxisWidth = rect.size.width - AxisPadding;
    CGFloat yAxisHeight = rect.size.height - AxisPadding*2;
    
    [self calculateYAxisScale:&yAxisScale xAxisScale:&xAxisStepWidth maxXPointCount:&maxXAxisPointCount maxYPoint:&maxYPoint];
    
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetLineWidth(context, 1.0f);
    
    // Axes ticks and labels
    CGContextSetGrayStrokeColor(context, 0.90, 1.0f);
    CGFloat const tickHeight = 6.0f;
    for (NSInteger i = 0; i < maxXAxisPointCount; i++) {
        CGFloat xOffset = xAxisStartPoint - xAxisStepWidth/2 + xAxisStepWidth*(i+1);
        CGContextMoveToPoint(context, xOffset, yAxisHeight-tickHeight/2);
        CGContextAddLineToPoint(context, xOffset, yAxisHeight+tickHeight/2);
        CGContextStrokePath(context);
    }
    NSUInteger yAxisTicks = 7;
    NSUInteger tick = 0;

    CGFloat s = (CGFloat)maxYPoint/(CGFloat)yAxisTicks;
    NSInteger len = log10(s);
    CGFloat div = pow(10, len);
    NSUInteger step = ceil(s / div) * div;
    
    do {
        CGContextMoveToPoint(context, xAxisStartPoint, (yAxisHeight/yAxisTicks)*(yAxisTicks-tick));
        CGContextAddLineToPoint(context, xAxisStartPoint+xAxisWidth-2*AxisPadding, (yAxisHeight/yAxisTicks)*(yAxisTicks-tick));
        CGContextStrokePath(context);
        
        // Steps
        UILabel *increment = [[UILabel alloc] init];
        increment.text = [@(step*(yAxisTicks-tick-1)) stringValue];
        increment.font = [UIFont fontWithName:@"OpenSans" size:8.0f];
        increment.textColor = [WPStyleGuide allTAllShadeGrey];
        [increment sizeToFit];
        increment.center = CGPointMake(xAxisStartPoint-CGRectGetMidX(increment.frame)-6.0f, (yAxisHeight/yAxisTicks)*(tick+1));
        [self addSubview:increment];
        tick++;
    } while (tick < yAxisTicks);
    
    // Bars
    __block CGFloat currentXPoint = 0;
    __block NSInteger iteration = 0;
    __block CGFloat legendXOffset = self.frame.size.width - AxisPadding;
    [_categoryBars enumerateKeysAndObjectsUsingBlock:^(NSString *category, NSArray *points, BOOL *stop) {
        CGColorRef categoryColor = ((UIColor *)_categoryColors[category]).CGColor;
        CGContextSetLineWidth(context, InitialBarWidth-iteration*6.0f);
        CGContextSetStrokeColorWithColor(context, categoryColor);
        currentXPoint = xAxisStartPoint + xAxisStepWidth/2;
        
        // Legend
        UILabel *legendName = [[UILabel alloc] init];
        legendName.text = category;
        legendName.font = [WPStyleGuide subtitleFont];
        legendName.textColor = [WPStyleGuide allTAllShadeGrey];
        [legendName sizeToFit];
        legendXOffset = legendXOffset - CGRectGetMaxX(legendName.frame);
        CGRect f = legendName.frame; f.origin.x = legendXOffset;
        f.origin.y = AxisPadding/2;
        legendName.frame = f;
        [self addSubview:legendName];
        CGFloat iconWidth = legendName.frame.size.height - 3.0f;
        CGContextSetFillColorWithColor(context, categoryColor);
        legendXOffset -= iconWidth+5.0f;
        CGContextFillRect(context, CGRectMake(legendXOffset, legendName.frame.origin.y+2.0f, iconWidth, iconWidth));
        legendXOffset -= iconWidth + 15.0f;
        
        [points enumerateObjectsUsingBlock:^(NSDictionary *point, NSUInteger idx, BOOL *stop) {
            // Bar
            CGContextMoveToPoint(context, currentXPoint, yAxisHeight);
            CGFloat barHeight = [point[@"count"] unsignedIntegerValue]*yAxisScale;
            CGContextAddLineToPoint(context, currentXPoint, yAxisHeight-barHeight);
            CGContextStrokePath(context);
            
            // Label
            UILabel *pointLabel = [[UILabel alloc] init];
            pointLabel.text = point[@"name"];
            pointLabel.font = [UIFont fontWithName:@"OpenSans" size:8.0f];
            pointLabel.textColor = [WPStyleGuide allTAllShadeGrey];
            [pointLabel sizeToFit];
            pointLabel.center = CGPointMake(currentXPoint, yAxisHeight+pointLabel.frame.size.height);
            [self addSubview:pointLabel];
            
            // Move to next spot
            currentXPoint += xAxisStepWidth;
        }];
        iteration += 1;
    }];
    
    // Generate UIImage
    _cachedImage = UIGraphicsGetImageFromCurrentImageContext();
}

@end

NSString *const StatsViewsCategory = @"Views";
NSString *const StatsVisitorsCategory = @"Visitors";

@interface StatsViewsVisitorsBarGraphCell ()

@property (nonatomic, weak) WPBarGraphView *barGraph;
@property (nonatomic, strong) NSMutableDictionary *unitsToData;
@property (nonatomic, assign) StatsViewsVisitorsUnit currentUnit;

@end

@implementation StatsViewsVisitorsBarGraphCell

+ (CGFloat)heightForRow {
    return 250.0f;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _unitsToData = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)layoutSubviews {
    [self.barGraph removeFromSuperview];
    
    NSDictionary *categoryData = _unitsToData[@(_currentUnit)];
    WPBarGraphView *barGraph = [[WPBarGraphView alloc] initWithFrame:self.bounds];
    self.barGraph = barGraph;
    [categoryData enumerateKeysAndObjectsUsingBlock:^(NSString *category, NSArray *data, BOOL *stop) {
        UIColor *color = [category isEqualToString:StatsViewsCategory] ? [WPStyleGuide baseLighterBlue] : [WPStyleGuide baseDarkerBlue];
        [self.barGraph addCategory:category color:color];
        [self.barGraph setBarsWithCount:data category:category];
    }];
    [self.contentView addSubview:self.barGraph];
}

- (void)setData:(NSArray *)data forUnit:(StatsViewsVisitorsUnit)unit category:(NSString *)category {
    _unitsToData[@(unit)] = @{NSLocalizedString(category, nil): data};
}

- (void)showGraphForUnit:(StatsViewsVisitorsUnit)unit {
    _currentUnit = unit;
    [self setNeedsDisplay];
}

@end
