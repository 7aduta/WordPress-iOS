/*
 * StatsBarGraphCell.m
 *
 * Copyright (c) 2014 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import "StatsViewsVisitorsBarGraphCell.h"

static CGFloat const AxisPadding = 18.0f;
static CGFloat InitialBarWidth = 30.0f;
static NSString *const CategoryKey = @"category";
static NSString *const PointsKey = @"points";

@interface WPStyleGuide (WPBarGraphView)
+ (UIFont *)axisLabelFont;
@end

@implementation WPStyleGuide (WPBarGraphView)
+ (UIFont *)axisLabelFont {
    return [UIFont fontWithName:@"OpenSans" size:8.0f];
}
@end

@interface WPBarGraphView : UIView

@property (nonatomic, strong) NSMutableArray *categoryBars;
@property (nonatomic, strong) NSMutableDictionary *categoryColors;

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
- (void)setBarsWithCount:(NSArray *)pointToCount forCategory:(NSString *)category;

@end

@implementation WPBarGraphView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _categoryBars = [NSMutableArray arrayWithCapacity:2];
        _categoryColors = [NSMutableDictionary dictionaryWithCapacity:2];
        
        self.backgroundColor = [UIColor whiteColor];
    }
    return self;
}

- (void)addCategory:(NSString *)categoryName color:(UIColor *)color {
    _categoryColors[categoryName] = color;
}

- (void)setBarsWithCount:(NSArray *)pointToCount forCategory:(NSString *)category {
    [_categoryBars addObject:@{CategoryKey: category, PointsKey: pointToCount}];
    
    [self setNeedsDisplay];
}

- (void)calculateYAxisScale:(CGFloat *)yAxisScale xAxisScale:(CGFloat *)xAxisStepWidth
             maxXPointCount:(NSUInteger *)maxXAxisPointCount maxYPoint:(NSUInteger *)maxYPoint {
    [_categoryBars enumerateObjectsUsingBlock:^(NSDictionary *categoryToPoints, NSUInteger idx, BOOL *stop) {
        *maxXAxisPointCount = MAX(((NSArray *)categoryToPoints[PointsKey]).count, *maxXAxisPointCount);
        
        [categoryToPoints[PointsKey] enumerateObjectsUsingBlock:^(NSDictionary *point, NSUInteger idx, BOOL *stop) {
            *maxYPoint = MAX(*maxYPoint, [point[StatsPointCountKey] unsignedIntegerValue]);
        }];
    }];
    
    *xAxisStepWidth = (self.frame.size.width-3*AxisPadding)/(*maxXAxisPointCount);
    
    *yAxisScale = *maxYPoint > 0 ? (self.frame.size.height-3*AxisPadding)/(*maxYPoint) : 1;
}

- (void)drawRect:(CGRect)rect {
    NSUInteger maxYPoint = 0;   // The tallest bar 'point'
    CGFloat yAxisScale = 0;     // rounded integer scale to use up y axis
    CGFloat xAxisStepWidth = 0;
    NSUInteger maxXAxisPointCount = 0; // # points along the x axis
    
    CGFloat xAxisStartPoint = AxisPadding*2;
    CGFloat xAxisWidth = rect.size.width - AxisPadding;
    CGFloat yAxisStartPoint = 10.0f;
    CGFloat yAxisHeight = rect.size.height - AxisPadding*2;
    
    [self calculateYAxisScale:&yAxisScale xAxisScale:&xAxisStepWidth maxXPointCount:&maxXAxisPointCount maxYPoint:&maxYPoint];
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, 1.0f);
    
    // Axes ticks and labels
    CGContextSetGrayStrokeColor(context, 0.90, 1.0f);
    CGFloat const tickHeight = 6.0f;
    for (NSInteger i = 0; i < maxXAxisPointCount; i++) {
        CGFloat xOffset = xAxisStartPoint - xAxisStepWidth/2 + xAxisStepWidth*(i+1);
        CGContextMoveToPoint(context, xOffset, yAxisStartPoint+yAxisHeight-tickHeight/2);
        CGContextAddLineToPoint(context, xOffset, yAxisStartPoint+yAxisHeight+tickHeight/2);
        CGContextStrokePath(context);
    }
    
    NSUInteger yAxisTicks = 7;
    NSUInteger tick = 0;
    CGFloat s = (CGFloat)maxYPoint/(CGFloat)(yAxisTicks+1);
    NSInteger len = log10(s);
    CGFloat div = pow(10, len);
    NSUInteger step = ceil(s / div) * div;
    
    do {
        CGContextMoveToPoint(context, xAxisStartPoint, yAxisStartPoint+(yAxisHeight/yAxisTicks)*(yAxisTicks-tick));
        CGContextAddLineToPoint(context, xAxisStartPoint+xAxisWidth-2*AxisPadding, yAxisStartPoint+(yAxisHeight/yAxisTicks)*(yAxisTicks-tick));
        CGContextStrokePath(context);
        
        // Steps
        UILabel *increment = [[UILabel alloc] init];
        increment.text = [@(step*(yAxisTicks-tick-1)) stringValue];
        increment.font = [WPStyleGuide axisLabelFont];
        increment.textColor = [WPStyleGuide allTAllShadeGrey];
        [increment sizeToFit];
        increment.center = CGPointMake(xAxisStartPoint-CGRectGetMidX(increment.frame)-6.0f, yAxisStartPoint+(yAxisHeight/yAxisTicks)*(tick+1));
        [self addSubview:increment];
        tick++;
    } while (tick < yAxisTicks);
    
    // Bars
    __block CGFloat currentXPoint = 0;
    __block NSInteger iteration = 0;
    __block CGFloat legendXOffset = self.frame.size.width - AxisPadding;
    [_categoryBars enumerateObjectsUsingBlock:^(NSDictionary *categoryToPoints, NSUInteger idx, BOOL *stop) {
        NSString *category = categoryToPoints[CategoryKey];
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
        
        [categoryToPoints[PointsKey] enumerateObjectsUsingBlock:^(NSDictionary *point, NSUInteger idx, BOOL *stop) {
            // Bar
            CGContextMoveToPoint(context, currentXPoint, yAxisStartPoint+yAxisHeight);
            CGFloat barHeight = [point[StatsPointCountKey] unsignedIntegerValue]*yAxisScale;
            CGContextAddLineToPoint(context, currentXPoint, yAxisStartPoint+yAxisHeight-barHeight);
            CGContextStrokePath(context);
            
            // Label
            UILabel *pointLabel = [[UILabel alloc] init];
            pointLabel.text = point[StatsPointNameKey];
            pointLabel.font = [WPStyleGuide axisLabelFont];
            pointLabel.textColor = [WPStyleGuide allTAllShadeGrey];
            [pointLabel sizeToFit];
            pointLabel.center = CGPointMake(currentXPoint, yAxisStartPoint+yAxisHeight+pointLabel.frame.size.height);
            [self addSubview:pointLabel];
            
            // Move to next spot
            currentXPoint += xAxisStepWidth;
        }];
        iteration += 1;
    }];
}

@end

@interface StatsViewsVisitorsBarGraphCell ()

@property (nonatomic, weak) WPBarGraphView *barGraph;
@property (nonatomic, assign) StatsViewsVisitorsUnit currentUnit;
@property (nonatomic, strong) StatsViewsVisitors *viewsVisitorsData;

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
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    [self.barGraph removeFromSuperview];

    NSDictionary *categoryData = [_viewsVisitorsData viewsVisitorsForUnit:_currentUnit];
    WPBarGraphView *barGraph = [[WPBarGraphView alloc] initWithFrame:self.bounds];
    self.barGraph = barGraph;
    [self.barGraph addCategory:StatsViewsCategory color:[WPStyleGuide baseLighterBlue]];
    [self.barGraph addCategory:StatsVisitorsCategory color:[WPStyleGuide midnightBlue]];
    if (categoryData) {
        [self.barGraph setBarsWithCount:categoryData[StatsViewsCategory] forCategory:StatsViewsCategory];
        [self.barGraph setBarsWithCount:categoryData[StatsVisitorsCategory] forCategory:StatsVisitorsCategory];
    }
    [self.contentView addSubview:self.barGraph];
}

- (void)setViewsVisitors:(StatsViewsVisitors *)viewsVisitors {
    _viewsVisitorsData = viewsVisitors;
}

- (void)showGraphForUnit:(StatsViewsVisitorsUnit)unit {
    _currentUnit = unit;
    [self setNeedsDisplay];
}

@end
