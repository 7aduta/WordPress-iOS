//
//  PanelNavigationController.m
//  WordPress
//
//  Created by Jorge Bernal on 5/21/12.
//  Copyright (c) 2012 WordPress. All rights reserved.
//

#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import "PanelNavigationController.h"
#import "PanelNavigationConstants.h"
#import "PanelViewWrapper.h"
#import "WordPressComApi.h"
#import "WPToast.h"
#import "NotificationsViewController.h"
#import "Note.h"
#import "Constants.h"
#import "SidebarViewController.h"

#define MENU_BUTTON_WIDTH 38.0f
//#import "SoundUtil.h"

#pragma mark -

@interface PanelNavigationController () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UINavigationController *navigationController;
@property (nonatomic, strong) UIView *detailViewContainer;
@property (weak, nonatomic, readonly) UIView *masterView;
@property (weak, nonatomic, readonly) UIView *rootView;
@property (weak, nonatomic, readonly) UIView *topView;
@property (weak, nonatomic, readonly) UIView *lastVisibleView;
@property (nonatomic, strong) NSMutableArray *detailViewControllers;
@property (nonatomic, strong) NSMutableArray *detailViews;
@property (nonatomic, strong) NSMutableArray *detailViewWidths;
@property (nonatomic, strong) UIButton *detailTapper;
@property (nonatomic, strong) UIPanGestureRecognizer *panner;
@property (nonatomic, strong) UIView *popPanelsView, *menuView;
@property (nonatomic, strong) UIImageView *sidebarBorderView;
@property (nonatomic, strong) UIButton *notificationButton, *menuButton;
@property (nonatomic, strong) UIImageView *dividerImageView, *spacerImageView;
@property (nonatomic, assign) BOOL isShowingPoppedIcon;
@property (nonatomic, assign) BOOL panned;
@property (nonatomic, assign) BOOL pushing;
@property (nonatomic, assign) CGFloat panOrigin;
@property (nonatomic, assign) CGFloat stackOffset;

@end

@interface UIViewController (PanelNavigationController_Internal)

- (void)setPanelNavigationController:(PanelNavigationController *)panelNavigationController;

@end

#pragma mark -

@implementation PanelNavigationController

- (void)dealloc {
    if (self.navigationController) {
        [self.navigationController willMoveToParentViewController:nil];
        [self.navigationController removeFromParentViewController];
    }
    
    self.detailViewController.panelNavigationController = nil;
    self.detailViewController = nil;
    self.masterViewController = nil;
    self.detailViews = nil;
    self.delegate = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)init {
    self = [super init];
    if (self) {
        if (IS_IPHONE) {
            _navigationController = [[UINavigationController alloc] init];
        } else {
            _detailViewControllers = [[NSMutableArray alloc] init];
            _detailViews = [[NSMutableArray alloc] init];
            _detailViewWidths = [[NSMutableArray alloc] init];
        }
    }
    return self;
}

- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.frame = [UIScreen mainScreen].applicationFrame;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view.autoresizesSubviews = YES;
    self.view.clipsToBounds = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"background"]];

    [self setupSidebarAndDetailViewContainer];
    [self setupSidebarRightBorder];
    
    if (IS_IPAD) {
        CGFloat height = UIInterfaceOrientationIsPortrait(self.interfaceOrientation) ? self.view.bounds.size.height: self.view.bounds.size.width;
        //The iOS simulator would pull in the wrong values
        if (UIInterfaceOrientationIsPortrait(self.interfaceOrientation) && height > self.view.bounds.size.width)
            height = self.view.bounds.size.width;
        _popPanelsView = [[UIView alloc] initWithFrame:CGRectMake(SIDEBAR_WIDTH + 10.0f, (height / 2) - 82.0f, 200.0f, 82.0f)];
        [_popPanelsView setBackgroundColor:[UIColor clearColor]];
        
        [_popPanelsView addSubview:[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"panel_icon"]]];
        
        UIImageView *popperImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"panel_icon"]];
        CGRect frame = popperImageView.frame;
        frame.origin.x += 10.0f;
        popperImageView.frame = frame;
        UIImageView *trashIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"UIButtonBarTrash"]];
        trashIcon.center = CGPointMake(popperImageView.bounds.size.width/2,popperImageView.bounds.size.height/2);
        trashIcon.alpha = 0.0f;
        [popperImageView addSubview:trashIcon];
        [_popPanelsView addSubview:popperImageView];
        [_popPanelsView setAlpha:0.0f];
        
        [self.view addSubview:_popPanelsView];
        [self.view sendSubviewToBack:_popPanelsView];
        
        [self showSidebarAnimated:NO];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotesNotification:)
												 name:@"WordPressComUnseenNotes" object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    UIView *viewToPrepare = nil;
    if (self.navigationController) {
        viewToPrepare = self.navigationController.view;
    } else {
        viewToPrepare = [self createWrapViewForViewController:self.detailViewController];
    }

    [self prepareDetailView:viewToPrepare forController:self.detailViewController];

    [self addPanner];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self removePanner];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return [super shouldAutorotateToInterfaceOrientation:interfaceOrientation];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration {
    [super willAnimateRotationToInterfaceOrientation:interfaceOrientation duration:duration];

    [self adjustFramesForRotation];
    
    if (IS_IPAD) {
        [self setStackOffset:[self nearestValidOffsetWithVelocity:0] duration:duration];
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    
    // Redraw shadows. This fixes an issue where the 1..n-1 detail view's shadow can be
    // incorrect when there are more than two detail views on the stack.
    if (self.detailViewController) {
        for (UIView *view in self.detailViews) {
            [self addShadowTo:view];
        }
    }
}

- (void)setupSidebarAndDetailViewContainer {
    _masterViewController = [[SidebarViewController alloc] init];
    
    // The sidebar is the first controller and view
    [self addChildViewController:_masterViewController];
    _masterViewController.view.frame = CGRectMake(0, 0, DETAIL_LEDGE_OFFSET, self.view.frame.size.height);
    _masterViewController.view.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_masterViewController.view];
    [_masterViewController setPanelNavigationController:self];
    [_masterViewController didMoveToParentViewController:self];
    
    // Other panels
    self.detailViewContainer = [[UIView alloc] init];
    
    if (IS_IPAD) {
        self.detailViewContainer.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    } else {
        self.detailViewContainer.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
    }
    
    self.detailViewContainer.autoresizesSubviews = YES;
    self.detailViewContainer.clipsToBounds = YES;
    [self.view addSubview:self.detailViewContainer];
    
    if (self.navigationController) {
        [self addChildViewController:self.navigationController];
        [self.detailViewContainer addSubview:self.navigationController.view];
        [self.navigationController didMoveToParentViewController:self];
    }
    
    self.detailViewContainer.frame = CGRectMake(0, 0, DETAIL_WIDTH, DETAIL_HEIGHT);
    [self.detailViews addObject:self.detailViewContainer];
    [self.detailViewWidths addObject:[NSNumber numberWithFloat:DETAIL_WIDTH]];
    [self.view addSubview:self.detailViewContainer];
}

- (void)setupSidebarRightBorder {
    //Right border view for sidebar
    _sidebarBorderView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"sidebar_border_bg"]];
    _sidebarBorderView.contentMode = UIViewContentModeScaleToFill;
    [_sidebarBorderView setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    _sidebarBorderView.frame = CGRectMake((IS_IPAD) ? SIDEBAR_WIDTH : (SIDEBAR_WIDTH - DETAIL_LEDGE - 4.0f), 0.0f, 2.0f, self.view.bounds.size.height);
    [self.view insertSubview:_sidebarBorderView atIndex:0];
    _sidebarBorderView.hidden = YES;
    
    _stackOffset = 0;
    if (IS_IPHONE) {
        _stackOffset = DETAIL_LEDGE_OFFSET;
    } else {
        _stackOffset = 0;
    }
}

- (void)adjustFramesForRotation {
    // Set the detail view's new width due to the rotation on the iPad if wide panels are expected.
    if (IS_IPAD && [self viewControllerExpectsWidePanel:self.detailViewController]) {
        CGRect frm = self.detailViewContainer.frame;
        frm.size.width = IPAD_WIDE_PANEL_WIDTH;
        self.detailViewContainer.frame = frm;
    }
    
    // When rotated the detailviewwidths may become invalid.
    // Rebuild the array so we have accurate values.
    self.detailViewWidths = [NSMutableArray array];
    	   
    int viewCount = [self.detailViews count];
    for (int i = 0; i < viewCount; i++) {
        UIViewController *vc;
        if (i == 0) {
            vc = self.detailViewController;
        } else {
            vc = [self.detailViewControllers objectAtIndex:i - 1];
        }
        	
        [self setFrameForViewController:vc];
             
        UIView *dview = [self.detailViews objectAtIndex:i];
        CGRect frm = dview.frame;
        [self.detailViewWidths addObject:[NSNumber numberWithFloat:frm.size.width]];
   }
}

#pragma mark - Memory management

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    [self.navigationController didReceiveMemoryWarning];
    [self.masterViewController didReceiveMemoryWarning];
    [self.detailViewController didReceiveMemoryWarning];
    [self.detailViewControllers makeObjectsPerformSelector:@selector(didReceiveMemoryWarning)];
}

#pragma mark - View Wrapping

- (void)clearDetailViewController {
    [self popToRootViewControllerAnimated:YES];
    
    UIView *view = [self viewOrViewWrapper:self.detailViewController.view];
    [view removeFromSuperview];
    self.detailViewController = nil;
    [self removeShadowFrom:self.detailViewContainer];
}

- (PanelViewWrapper *)wrapViewForViewController:(UIViewController *)controller {
    UIView *view = controller.view;
    if ([[view superview] isKindOfClass:[PanelViewWrapper class]]) {
        // Make sure the controller's view's origin is 0,0
        CGRect frame = view.frame;
        frame.origin.x = 0.0f;
        frame.origin.y = 0.0f;
        view.frame = frame;
        return (PanelViewWrapper *)[view superview];
    }
    return nil;
}

- (UIView *)createWrapViewForViewController:(UIViewController *)controller {
    if (self.navigationController) {
        return controller.view;
    }
    UIView *view = [self wrapViewForViewController:controller];
    if (view == nil) {
        return [[PanelViewWrapper alloc] initWithViewController:controller];
    }
    return view;
}

- (UIView *)viewOrViewWrapper:(UIView *)view {
    if ([[view superview] isKindOfClass:[PanelViewWrapper class]]) {
        return [view superview];
    }
    return view;
}


#pragma mark - Toolbar wrangling.

- (UIToolbar *)toolbarForViewController:(UIViewController *)controller {
    return [[self wrapViewForViewController:controller] toolbar];
}

- (BOOL)isToolbarHiddenForViewController:(UIViewController *)controller {
    return [[self wrapViewForViewController:controller] isToolbarHidden];
}

- (void)setToolbarHidden:(BOOL)hidden forViewController:(UIViewController *)controller {
    [self setToolbarHidden:hidden forViewController:controller animated:YES];
}

- (void)setToolbarHidden:(BOOL)hidden forViewController:(UIViewController *)controller animated:(BOOL)animated {
	PanelViewWrapper *wrapView = [self wrapViewForViewController:controller];
    if (!hidden) {
        CGRect frame = controller.view.frame;
		if (wrapView.frame.size.height == frame.size.height) {
			frame.size.height -= 44.0f;
			controller.view.frame = frame;
		}
    }
    [wrapView setToolbarHidden:hidden animated:animated];
}

- (void)viewControllerWantsToBeFullyVisible:(UIViewController *)controller {
    if (IS_IPHONE) {
        return;
    }
    BOOL isChild = NO;
    UIView *view = controller.view;
    while (!isChild && (view = view.superview)) {
        if ([self.detailViews containsObject:view]) {
            isChild = YES;
        }
    }
    if (isChild && [[self partiallyVisibleViews] containsObject:view]) {
        UIView *nextView = [self viewAfter:view];
        CGFloat offset = 0.0;
        if (CGRectGetMaxX(view.frame) > CGRectGetMaxX(self.view.bounds)) {
            // Partly off-screen, move left
            offset = CGRectGetMaxX(view.frame) - CGRectGetMaxX(self.view.bounds);
        } else if (nextView && CGRectGetMinX(nextView.frame) < CGRectGetMaxX(view.frame)) {
            // Covered by another view, move right
            offset = CGRectGetMinX(nextView.frame) - CGRectGetMaxX(view.frame);
        }
        [self setStackOffset:_stackOffset + offset duration:DURATION_FAST];
    }    
}

#pragma mark - Property accessors

- (UIView *)masterView {
    return self.masterViewController.view;
}

- (UIView *)rootView {
    return self.rootViewController.view;
}

- (UIView *)topView {
    if ([self.detailViewControllers count] == 0) {
        return self.detailViewContainer;
    } else {
        return [self viewOrViewWrapper:self.topViewController.view];
    }
}

- (UIView *)lastVisibleView {
    __block UIView *view = self.detailViewContainer;
    [self.detailViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        UIView *vcView = [(UIViewController *)obj view];
        if (CGRectGetMinX(vcView.frame) < self.rootView.bounds.size.width) {
            view = vcView;
        } else {
            *stop = YES;
        }
    }];

    return [self viewOrViewWrapper:view];
}

- (UIViewController *)topViewController {
    if (self.navigationController) {
        return self.navigationController.topViewController;
    } else {
        if ([self.detailViewControllers count] > 0) {
            return [self.detailViewControllers lastObject];
        } else {
            return self.detailViewController;
        }
    }
}

- (UIViewController *)visibleViewController {
    if (self.presentedViewController) {
        return self.presentedViewController;
    } else if (self.navigationController) {
        return self.navigationController.visibleViewController;
    } else {
        return self.detailViewController;
    }
}

-  (UIViewController *)rootViewController {
    if (self.navigationController) {
        return self.navigationController;
    } else {
        return self.detailViewController;
    }
}

- (NSArray *)viewControllers {
    if (self.navigationController) {
        return self.navigationController.viewControllers;
    } else {
        NSMutableArray *arr = [self.detailViewControllers mutableCopy];
        [arr insertObject:self.detailViewController atIndex:0];
        return arr;
    }
}

- (void)setDetailViewController:(UIViewController *)detailViewController {
    [self setDetailViewController:detailViewController closingSidebar:YES];
}


- (BOOL)viewControllerExpectsWidePanel:(UIViewController *)controller {
    if ([controller respondsToSelector:@selector(expectsWidePanel)]) {
        return (BOOL)[controller performSelector:@selector(expectsWidePanel)];
    }
    return NO;
}


- (void)setDetailViewController:(UIViewController *)detailViewController closingSidebar:(BOOL)closingSidebar {
    if (_detailViewController == detailViewController) return;

    BOOL oldWasWide = [self viewControllerExpectsWidePanel:_detailViewController];
    
    UIBarButtonItem *sidebarButton = nil;
    
    [self popToRootViewControllerAnimated:NO];

    if (_detailViewController) {
        if (self.navigationController) {
            [self.navigationController setToolbarHidden:YES animated:YES];
            sidebarButton = _detailViewController.navigationItem.leftBarButtonItem;
        } else {
            [_detailViewController willMoveToParentViewController:nil];
            UIView *view = [self viewOrViewWrapper:_detailViewController.view];
            [view removeFromSuperview];
            
            [_detailViewController setPanelNavigationController:nil];
            [_detailViewController removeFromParentViewController];
        }
    }

    _detailViewController = detailViewController;
    
    if (_sidebarBorderView.hidden)
        _sidebarBorderView.hidden = NO;

    if (_detailViewController) {
        [_detailViewController setPanelNavigationController:self];
        if (self.navigationController) {
            [self.navigationController setViewControllers:[NSArray arrayWithObject:_detailViewController] animated:NO];
            if (sidebarButton == nil) {
                sidebarButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"navbar_toggle"] style:UIBarButtonItemStyleBordered target:self action:@selector(toggleSidebar)];
            }
            sidebarButton.accessibilityLabel = NSLocalizedString(@"Toggle", @"Sidebar toggle button");
            
            _menuView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0, MENU_BUTTON_WIDTH, 30.0f)];
            
            _menuButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 35.0f, 30.0f)];
            [_menuButton setImage:[UIImage imageNamed:@"navbar_toggle"] forState:UIControlStateNormal];
            [_menuButton setImage:[UIImage imageNamed:@"navbar_toggle"] forState:UIControlStateHighlighted];
            [_menuButton setImageEdgeInsets:UIEdgeInsetsMake(0, 3.0f, 0.0f, 0)];
            [_menuButton setBackgroundImage:[[UIImage imageNamed:@"menu_notification_left_bg"] resizableImageWithCapInsets:UIEdgeInsetsMake(3.0f, 3.0f, 3.0f, 0)] forState:UIControlStateNormal];
            [_menuButton setBackgroundImage:[[UIImage imageNamed:@"menu_notification_left_bg_down"] resizableImageWithCapInsets:UIEdgeInsetsMake(3.0f, 3.0f, 3.0f, 0)] forState:UIControlStateHighlighted];
            [_menuButton addTarget:self action:@selector(toggleSidebar) forControlEvents:UIControlEventTouchUpInside];
            [_menuButton addTarget:self action:@selector(highlightMenuButton:) forControlEvents:UIControlEventTouchDown];
            [_menuButton addTarget:self action:@selector(resetMenuButton:) forControlEvents:UIControlEventTouchUpInside];
            [_menuButton addTarget:self action:@selector(resetMenuButton:) forControlEvents:UIControlEventTouchCancel];
            
            _notificationButton = [[UIButton alloc] initWithFrame:CGRectMake(5.0f, 0.0, 33.0f, 30.0f)];
            [_notificationButton setAlpha:1.0f];
            [_notificationButton setImage:[UIImage imageNamed:@"note_icon_comment"] forState:UIControlStateNormal];
            [_notificationButton setBackgroundImage:[[UIImage imageNamed:@"menu_notification_right_bg"] resizableImageWithCapInsets:UIEdgeInsetsMake(3.0f, 0.0f, 3.0f, 3.0f)] forState:UIControlStateNormal];
            [_notificationButton setBackgroundImage:[[UIImage imageNamed:@"menu_notification_right_bg_down"] resizableImageWithCapInsets:UIEdgeInsetsMake(3.0f, 0.0f, 3.0f, 3.0f)] forState:UIControlStateHighlighted];
            [_notificationButton setImageEdgeInsets:UIEdgeInsetsMake(0, 2.0f, 0.0f, 0)];
            [_notificationButton addTarget:self action:@selector(highlightMenuButton:) forControlEvents:UIControlEventTouchDown];
            [_notificationButton addTarget:self action:@selector(notificationButtonTap) forControlEvents:UIControlEventTouchUpInside];
            [_notificationButton addTarget:self action:@selector(resetMenuButton:) forControlEvents:UIControlEventTouchUpInside];
            [_notificationButton addTarget:self action:@selector(resetMenuButton:) forControlEvents:UIControlEventTouchCancel];
            
            _dividerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(37.0f, 1.0f, 1.0f, 27.0f)];
            [_dividerImageView setImage:[UIImage imageNamed:@"menu_button_divider"]];
            [_dividerImageView setAlpha:0.0f];
            
            _spacerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(33.0f, 0.0f, 4.0f, 30.0f)];
            [_spacerImageView setImage:[[UIImage imageNamed:@"menu_notification_spacer"] resizableImageWithCapInsets:UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f)]];
            [_spacerImageView setAlpha:0.0f];
            
            [_menuView addSubview:_notificationButton];
            [_menuView addSubview:_menuButton];
            [_menuView addSubview:_dividerImageView];
            [_menuView addSubview:_spacerImageView];
            
            sidebarButton = [[UIBarButtonItem alloc] initWithCustomView:_menuView];
            _detailViewController.navigationItem.leftBarButtonItem = sidebarButton;

        } else {
            [self addChildViewController:_detailViewController];

            UIView *wrappedView = [self createWrapViewForViewController:_detailViewController];
            BOOL newIsWide = [self viewControllerExpectsWidePanel:_detailViewController];
            
            if (newIsWide != oldWasWide) {
                CGRect frm = self.detailViewContainer.frame;
                if (newIsWide) {
                    frm.origin.x = self.view.bounds.size.width - IPAD_WIDE_PANEL_WIDTH;
                    frm.size.width = IPAD_WIDE_PANEL_WIDTH;
                } else {
                    frm.origin.x = SIDEBAR_WIDTH;
                    frm.size.width = DETAIL_WIDTH;
                }
                // the size changed so update the stored width and the width and position of the detailView controller
                [self.detailViewWidths removeObjectAtIndex:0];
                [self.detailViewWidths insertObject:[NSNumber numberWithFloat:frm.size.width] atIndex:0];
                if(self.detailViewContainer.frame.origin.x != frm.origin.x) {
                    [UIView animateWithDuration:0.3 animations:^{
                        self.detailViewContainer.frame = frm;
                    }];
                    _stackOffset = ABS(SIDEBAR_WIDTH - frm.origin.x);
                } else {
                    self.detailViewContainer.frame = frm; // update the width regardless.
                }
            }
            
            [self prepareDetailView:wrappedView forController:_detailViewController];
            [self.detailViewContainer addSubview:wrappedView];
            [_detailViewController didMoveToParentViewController:self];
        }
    }
    [self addShadowTo:_detailViewContainer];

    if (IS_IPHONE && closingSidebar) {
        [self closeSidebar];
    }
}

#pragma mark - Notifications

- (void)didReceiveNotesNotification: (NSNotification *)notification {
//    if ([self.detailViewController isMemberOfClass:[NotificationsViewController class]]) {
//        NotificationsViewController *notesViewController = (NotificationsViewController *)self.detailViewController;
//        [notesViewController refreshFromPushNotification];
//        return;
//    }
//    
//    NSDictionary *notesDictionary = (NSDictionary *)[notification userInfo];
//    NSMutableArray *unreadNotes = [notesDictionary objectForKey:@"notes"];
//    if ([unreadNotes count] > 0) {
//        NSDictionary *noteData = [unreadNotes objectAtIndex:0];
//        if (noteData)
//            [self showNotificationForNoteType: [noteData objectForKey:@"type"]];
//    }
}

- (void)showNotificationForNoteType:(NSString *)noteType {
    UIImage *noteIcon = [UIImage imageNamed: [NSString stringWithFormat:@"note_navbar_icon_%@", noteType]];
    if (noteIcon == nil)
        noteIcon = [UIImage imageNamed:@"note_navbar_icon_comment"];
    
    if ([self isShowingNotificationButton]) {
        //already showing a notification in the button
        [UIView animateWithDuration:0.3f delay:0 options: 0 animations:^{
            [_notificationButton.imageView setAlpha:0.0f];
        } completion:^(BOOL finished){
            [_notificationButton setImage:noteIcon forState:UIControlStateNormal];
            [UIView animateWithDuration:0.3f delay:0 options: 0 animations:^{
                [_notificationButton.imageView setAlpha:1.0f];
            } completion:^(BOOL finished){ }];
        }];
    } else {
        [_notificationButton setImage:noteIcon forState:UIControlStateNormal];
        [UIView animateWithDuration:0.3f delay:0 options: 0 animations:^{
            [self completeButtonAnimation];
        } completion:^(BOOL finished){
            [UIView animateWithDuration:1.0f delay:0 options: 0 animations:^{
                [_dividerImageView setAlpha:1.0f];
            } completion:^(BOOL finished){ }];
        }];
    }
}

- (void)completeButtonAnimation {
    [UIView animateWithDuration:0.4f delay:0 options: UIViewAnimationOptionCurveEaseOut animations:^{
        CGFloat newSizeX = MENU_BUTTON_WIDTH;
        CGFloat newNotificationButtonX = 5.0f;
        if (![self isShowingNotificationButton]) {
            newSizeX += 30.0f;
            newNotificationButtonX += 30.0f;
            [_menuButton setBackgroundImage:[UIImage imageNamed:@"menu_notification_left_bg"] forState:UIControlStateNormal];
        } else {
            [UIView animateWithDuration:0.3f delay:0 options: 0 animations:^{
                [_dividerImageView setAlpha:0.0f];
            } completion:^(BOOL finished){ }];
        }
        [_menuView setFrame:CGRectMake(_menuView.frame.origin.x, _menuView.frame.origin.y, newSizeX, _menuView.frame.size.height)];
        [_notificationButton setFrame:CGRectMake(newNotificationButtonX, _notificationButton.frame.origin.y, _notificationButton.frame.size.width, _notificationButton.frame.size.height)];
    }  completion:^(BOOL finished){
        if ([self isShowingNotificationButton]) {
            [UIView animateWithDuration:0.5f delay:0.5f options: 0 animations:^{
                [_notificationButton.imageView setAlpha:0.0f];
            } completion:^(BOOL finished){
                //Blink button here
                [UIView beginAnimations:@"notification" context:nil];
                [UIView setAnimationDuration:0.5f];
                [UIView setAnimationDelay:0.0f];
                //[UIView setAnimationRepeatAutoreverses:YES];
                [UIView setAnimationRepeatCount:1.0f];
                [UIView setAnimationDelegate:self];
                //[UIView setAnimationDidStopSelector:@selector(showNotificationButton)];
                [_notificationButton.imageView setAlpha:1.0f];
                [UIView commitAnimations];
            }];
        }
    }];
}

- (void)highlightMenuButton: (id)sender {
    if (![self isShowingNotificationButton]) {
        [_notificationButton setHighlighted:YES];
        [_menuButton setHighlighted:YES];
    } else {
        if (sender == _notificationButton) {
            [_spacerImageView setImage:[[UIImage imageNamed:@"menu_notification_spacer"] resizableImageWithCapInsets:UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f)]];
        } else {
            [_spacerImageView setImage:[[UIImage imageNamed:@"menu_notification_spacer_down"] resizableImageWithCapInsets:UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f)]];
        }
        [_spacerImageView setAlpha:1.0f];
    }
    [_dividerImageView setHidden: YES];
}

- (void)resetMenuButton: (id)sender {
    [_notificationButton setHighlighted:NO];
    [_menuButton setHighlighted:NO];
    [_dividerImageView setHidden: NO];
    [_spacerImageView setAlpha:0.0f];
}

- (void)showNotificationButton {
    [_notificationButton.imageView setAlpha:1.0f];
}

- (void)notificationButtonTap {
    [self showNotificationsView:NO];
}

- (void)showNotificationsView: (BOOL)isFromPushNotification {
    // Break if we're already looking at the notifications view
    if ([self.detailViewController isMemberOfClass:[NotificationsViewController class]]) {
        NotificationsViewController *notificationsViewController = (NotificationsViewController *)self.detailViewController;
        [notificationsViewController refreshFromPushNotification];
        if ([self isShowingNotificationButton]) {
            [self completeButtonAnimation];
        }
        else if (!isFromPushNotification) {
            [self toggleSidebar];
        }
        return;
    }
    
    if ([self isShowingNotificationButton] || isFromPushNotification) {
        if ([self isShowingNotificationButton])
            [self completeButtonAnimation];
        NotificationsViewController *notificationsViewController = [[NotificationsViewController alloc] init];
        [self setDetailViewController:notificationsViewController];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectNotificationsRow"
                                                            object:nil
                                                          userInfo:nil];
    } else {
        [self toggleSidebar];
    }
}

- (BOOL)isShowingNotificationButton {
    return _menuView.frame.size.width > MENU_BUTTON_WIDTH;
}


#pragma mark - Sidebar control

- (void)showSidebar {
    if (_panned == YES) return;
    [self showSidebarAnimated:YES];
}

- (void)showSidebarAnimated:(BOOL)animated {
//    [SoundUtil playSwipeSound];
    
    [UIView animateWithDuration:OPEN_SLIDE_DURATION(animated) delay:0 options:0 | UIViewAnimationOptionLayoutSubviews | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self setStackOffset:0 duration:0];
        [self disableDetailView];
    } completion:^(BOOL finished) {
    }];
}

- (void)showSidebarWithVelocity:(CGFloat)velocity {
//    [SoundUtil playSwipeSound];

    [self disableDetailView];
    [self setStackOffset:0.f withVelocity:velocity];
}


- (void)closeSidebar {
    [self closeSidebarAnimated:YES];
}

- (void)closeSidebarAnimated:(BOOL)animated {
    [UIView animateWithDuration:OPEN_SLIDE_DURATION(animated) delay:0 options:0 | UIViewAnimationOptionLayoutSubviews | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [self setStackOffset:(DETAIL_LEDGE_OFFSET - DETAIL_OFFSET) duration:0];
    } completion:^(BOOL finished) {
        [self enableDetailView];
    }];
    
    if(IS_IPHONE && !self.presentedViewController) {
//        [SoundUtil playSwipeSound];
    }
}

- (void)closeSidebarWithVelocity:(CGFloat)velocity {
    [self enableDetailView];
    [self setStackOffset:(DETAIL_LEDGE_OFFSET - DETAIL_OFFSET) withVelocity:velocity];
    
    if(IS_IPHONE) {
//        [SoundUtil playSwipeSound];
    }
}

- (void)toggleSidebar {
    if (!self.detailTapper) {
        [self showSidebar];
    } else {
        [self closeSidebar];
    }
}

- (void)teaseSidebar {
    if (IS_IPAD)
        return;

    [self closeSidebarAnimated:NO];
    CGRect previousFrame = self.detailViewContainer.frame;
    [UIView animateWithDuration:0.5f
                          delay:DURATION_FAST
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         CGRect frame = previousFrame;
                         frame.origin.x += DETAIL_LEDGE;
                         self.detailViewContainer.frame = frame;
                     } completion:^(BOOL finished) {
                         [UIView animateWithDuration:DURATION_FAST
                                               delay:0.f
                                             options:UIViewAnimationOptionCurveEaseInOut
                                          animations:^{
                                              self.detailViewContainer.frame = previousFrame;
                                          } completion:nil];
                     }];
}

- (void)centerTapped {
    [self closeSidebar];
}

- (void)disableDetailView {
    if (IS_IPAD) return;

    if (!self.detailTapper) {
        self.detailTapper = [UIButton buttonWithType:UIButtonTypeCustom];
        self.detailTapper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.detailTapper.frame = self.detailViewContainer.bounds;
        [self.detailViewContainer addSubview:self.detailTapper];
        [self.detailTapper addTarget:self action:@selector(centerTapped) forControlEvents:UIControlEventTouchUpInside];
        self.detailTapper.backgroundColor = [UIColor clearColor];
        UIPanGestureRecognizer *panner = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        panner.cancelsTouchesInView = YES;
        panner.delegate = self;
        [self.detailTapper addGestureRecognizer:panner];
    }
    
    CGRect tapFrame = self.detailViewContainer.bounds;
    tapFrame.origin.y = 44.0f;
    self.detailTapper.frame = tapFrame;

    // Switch scroll to top behavior to master view
    [self setScrollsToTop:NO forView:[self viewOrViewWrapper:self.detailViewController.view]];
    [self setScrollsToTop:YES forView:self.masterView];
}

- (void)enableDetailView {
    if (IS_IPAD) return;

    if (self.detailTapper) {
        [self.detailTapper removeTarget:self action:@selector(centerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.detailTapper removeFromSuperview];
    }

    self.detailTapper = nil;

    // Restore scroll to top behavior to detail view
    [self setScrollsToTop:NO forView:self.masterView];
    [self setScrollsToTop:YES forView:[self viewOrViewWrapper:self.detailViewController.view]];
}

- (void)prepareDetailView:(UIView *)view forController:(UIViewController *)controller {
    CGFloat newPanelWidth = DETAIL_WIDTH;
    
    if (IS_IPAD && [self viewControllerExpectsWidePanel:controller]) {
        newPanelWidth = IPAD_WIDE_PANEL_WIDTH;
    }
    CGFloat originX = view.frame.origin.x;
    if (controller == _detailViewController)
        originX = 0.0f;
    view.frame = CGRectMake(originX, 0.0f, newPanelWidth, DETAIL_HEIGHT);
}

- (void)addShadowTo:(UIView *)view {
    view.layer.masksToBounds = NO;
    view.layer.shadowRadius = 6.0f;
    view.layer.shadowOpacity = 0.8f;
    view.layer.shadowColor = [[UIColor blackColor] CGColor];
    view.layer.shadowOffset = CGSizeZero;
    view.layer.shadowPath = [[UIBezierPath bezierPathWithRect:view.bounds] CGPath];
}

- (void)removeShadowFrom:(UIView *)view {
    view.layer.shadowOpacity = 0.0f;
}

- (void)setScrollsToTop:(BOOL)scrollsToTop forView:(UIView *)view {
    if ([view respondsToSelector:@selector(setScrollsToTop:)]) {
        [(UIScrollView *)view setScrollsToTop:scrollsToTop];
    } else {
        // Search for a subview that will respond
        [view.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj respondsToSelector:@selector(setScrollsToTop:)]) {
                [(UIScrollView *)obj setScrollsToTop:scrollsToTop];
                *stop = YES;
            }
        }];
    }
}

#pragma mark - Panning

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.panner || gestureRecognizer.view == self.detailTapper) {
        _panOrigin = _stackOffset;
        _panned = NO;
    }
    return YES;
}

- (void)panned:(UIPanGestureRecognizer *)sender {
    /*
     _stackOffset is how many pixels the views are dragged to the left from the initial (sidebar open) position
     
     Limits:
     * Min: 0 [soft], - ( width - DETAIL_LEDGE_OFFSET) [hard]
     * Max (1 panel): 0 [soft], (sidebar width - ledge) [hard]
     * Max (2+ panels: (v[n]-v[n-1]) + v[n-2] + ... + v[0]) [soft],
                       sum(v[0..n-1]) [hard]
     Note that v[0] is only used if n > 2.
     
     When a soft limit is reached, we add elasticity
     Views can't move over hard limits

     */
    if (sender.state == UIGestureRecognizerStateBegan) {
        _panned = YES;
    }
    CGPoint p = [sender translationInView:self.rootViewController.view];
    CGFloat offset = _panOrigin - p.x;
    
    /*
     Step 1: setup boundaries
     */
    CGFloat minSoft = [self minOffsetSoft];
    CGFloat minHard = [self minOffsetHard];
    CGFloat maxSoft = [self maxOffsetSoft];
    CGFloat maxHard = [self maxOffsetHard];
    CGFloat limitOffset = MAX(minSoft, MIN(maxSoft, offset));
    CGFloat diff = ABS(ABS(offset) - ABS(limitOffset));
    // if we're outside the allowed bounds
    if (diff > 0) {
        // Reduce the dragged distance
        diff = diff / logf(diff + 1) * 2;
        offset = limitOffset + (offset < limitOffset ? -diff : diff);
    }
    offset = MAX(minHard, MIN(maxHard, offset));
    
    if (IS_IPAD) {
        if (offset < 0 && offset <= -120.0f) {
            if (!_isShowingPoppedIcon) {
                _isShowingPoppedIcon = YES;
            UIImageView *popIcon = (UIImageView*) [[_popPanelsView subviews] objectAtIndex:1];
            UIImageView *trashIcon = (UIImageView*) [[popIcon subviews] objectAtIndex:0];
            [UIView animateWithDuration:0.3f delay: 0.0f options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                                 popIcon.frame = CGRectMake(popIcon.frame.origin.x + 50.0f,popIcon.frame.origin.y, popIcon.frame.size.width, popIcon.frame.size.height);
                                 popIcon.alpha = 0.7f;
                             }
                             completion:nil];
                [UIView animateWithDuration:0.5f
                                 animations:^{
                                     trashIcon.alpha = 1.0f;
                                 }
                                 completion:nil];
            }
        } else if (offset > -120.0f && _isShowingPoppedIcon) {
            [self animatePoppedIcon];
            _isShowingPoppedIcon = NO;
        }
    }
    
    /*
     Step 2: calculate each view position
     */
    [self setStackOffset:offset duration:0];

    /*
     Step 3: when released, calculate final positions
     */
    if (sender.state == UIGestureRecognizerStateEnded) {
        CGFloat velocity = [sender velocityInView:self.view].x;
        if (IS_IPAD) {
            CGFloat nearestOffset = [self nearestValidOffsetWithVelocity:-velocity];
            //[self setStackOffset:nearestOffset duration:DURATION_FAST];
            [self setStackOffset:nearestOffset withVelocity:velocity];
            //pop all extra view controllers if user dragged stack to the right
            if (offset < 0 && offset <= -120.0f && [self.detailViews count] > 1) {
                [self animatePoppedIcon];
                _isShowingPoppedIcon = NO;
                [self popToRootViewControllerAnimated:YES];
//                [SoundUtil playDiscardSound];
                [self.delegate resetView];
            }
        } else {
            if (ABS(velocity) < 300) {
                if (offset < DETAIL_LEDGE_OFFSET / 3) {
                    [self showSidebarWithVelocity:velocity];
                } else {
                    [self closeSidebar];
                }
            } else if (velocity > 0) {
                // Going right
                [self showSidebarWithVelocity:velocity];
            } else {
                [self closeSidebarWithVelocity:velocity];
            }
        }
    }
}

- (void)animatePoppedIcon {
    UIImageView *popIcon = (UIImageView*) [[_popPanelsView subviews] objectAtIndex:1];
    UIImageView *trashIcon = (UIImageView*) [[popIcon subviews] objectAtIndex:0];
    [UIView animateWithDuration:0.3f delay: 0.0f options: UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         trashIcon.alpha = 0.0f;
                         popIcon.frame = CGRectMake(popIcon.frame.origin.x - 50.0f,popIcon.frame.origin.y, popIcon.frame.size.width, popIcon.frame.size.height);
                         popIcon.alpha = 1.0f;
                     }
                     completion:nil];
    
}

- (void)addPanner {
    [self removePanner];
    
    UIPanGestureRecognizer *panner = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    panner.cancelsTouchesInView = YES;
    panner.delegate = self;
    self.panner = panner;
    if (self.navigationController) {
        [self.navigationController.navigationBar addGestureRecognizer:panner];
    } else {
        [self.view addGestureRecognizer:panner];
    }
}

- (void)removePanner {
    if (self.panner) {
        [self.panner.view removeGestureRecognizer:self.panner];
    }
    self.panner = nil;
}

- (void)setFrameForViewController:(UIViewController *)viewController {
    CGFloat newPanelWidth = DETAIL_WIDTH;
    CGRect frame;
    
    if (IS_IPAD && [self viewControllerExpectsWidePanel:viewController]) {
        newPanelWidth = IPAD_WIDE_PANEL_WIDTH;
    }
    
    UIView *view = nil;
    if (self.navigationController) {
        frame = viewController.view.frame;
        frame.size.width = newPanelWidth;
        view = viewController.view;
    } else {
        view = [self viewOrViewWrapper:viewController.view];
        frame = view.frame;
        frame.size.width = newPanelWidth;
    }
    view.frame = frame;
    [self prepareDetailView:view forController:viewController]; // Call this again to fix the masking bounds set for rounded corners.
}

- (void)setViewOffset:(CGFloat)offset forView:(UIView *)view {
    view = [self viewOrViewWrapper:view];

    CGRect frame = view.frame;
    frame.origin.x = MAX(0, MIN(offset, self.view.bounds.size.width));

    view.frame = frame;
}

- (void)setStackOffset:(CGFloat)offset duration:(CGFloat)duration {
    CGFloat remainingOffset = offset;
    
    BOOL expectsWidePanels = [self viewControllerExpectsWidePanel:self.detailViewController];
    
    CGFloat usedOffset = MIN(DETAIL_LEDGE_OFFSET - DETAIL_OFFSET, remainingOffset);
    CGFloat viewX = DETAIL_LEDGE_OFFSET - usedOffset;
    if (duration > 0) {
        [UIView beginAnimations:@"stackOffset" context:nil];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
        [UIView setAnimationDuration:duration];
    }
    [self setViewOffset:viewX forView:self.detailViewContainer];
    remainingOffset -= usedOffset;

    NSInteger viewCount = [self.detailViews count];
    for (NSInteger i = 1; i < viewCount; i++) {        
        UIView *view = [self.detailViews objectAtIndex:i];
        UIView *previousView = [self.detailViews objectAtIndex:(i - 1)];
        usedOffset = MIN(previousView.frame.size.width, remainingOffset);
        viewX += previousView.frame.size.width;
        viewX -= usedOffset;
        
        // ZOMG this is horrible, but without it the secondary detail does not position correctly.
        if (offset >= 956.0f && i == viewCount -1 && expectsWidePanels && UIInterfaceOrientationIsPortrait(self.interfaceOrientation)) {
            viewX += 44.0f;
        }
        
        [self setViewOffset:viewX forView:view];
        remainingOffset -= usedOffset;
    }
    [UIView commitAnimations];
    _stackOffset = offset - remainingOffset;
    [self partiallyVisibleViews];
}

- (void)animateView:(UIView *)view toOffset:(CGFloat)offset withVelocity:(CGFloat)velocity {
    view = [self viewOrViewWrapper:view];
    CALayer *viewLayer = view.layer;
    [viewLayer removeAllAnimations];
    float viewOffset = MAX(0, MIN(offset, self.view.bounds.size.width));
    
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position.x"];
    
    CGPoint startPosition = viewLayer.position;
    CGPoint endPosition = CGPointMake(viewOffset+(viewLayer.frame.size.width * 0.5f), startPosition.y);
    CGFloat distance = ABS(startPosition.x - endPosition.x);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:4];
    NSMutableArray *timingFunctions = [NSMutableArray arrayWithCapacity:3];
    NSMutableArray *keyTimes = [NSMutableArray arrayWithCapacity:4];
    [keyTimes addObject:[NSNumber numberWithFloat:0.f]];
    [values addObject:[NSNumber numberWithFloat:startPosition.x]];
    CGFloat overShot = 0, duration = ABS(distance/velocity);
    CAMediaTimingFunction *easeInOut = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [timingFunctions addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    
    if(ABS(velocity) > PANEL_MINIMUM_OVERSHOT_VELOCITY && (!IS_IPAD || distance > 10.f)){
        [timingFunctions addObject:easeInOut];
        velocity *= 0.25f;

        overShot = 22.f * (velocity * PANEL_OVERSHOT_FRICTION);
        CGFloat overShotDuration = ABS(overShot/(velocity * (1-PANEL_OVERSHOT_FRICTION))) * 1.25;
        [keyTimes addObject:[NSNumber numberWithFloat:(duration/(duration+overShotDuration))]];
        duration += overShotDuration;
        [values addObject:[NSNumber numberWithFloat:endPosition.x + overShot]];
    } else {
        // nothing special, just slide
        duration = 0.2f;
        
    }
    [keyTimes addObject:[NSNumber numberWithFloat:1.f]];
    
    [values addObject:[NSNumber numberWithFloat:endPosition.x]];
    
    animation.values = values;
    animation.timingFunctions = timingFunctions;
    animation.keyTimes = keyTimes;
    animation.duration = duration;
        
    [viewLayer addAnimation:animation forKey:@"position"];
    viewLayer.position = endPosition;
}

- (void)setStackOffset:(CGFloat)offset withVelocity:(CGFloat)velocity{
    velocity = MAX(-1000, MIN(1000, velocity * 0.3)); // limit the velocity
    CALayer *viewLayer = self.detailViewContainer.layer;
    [viewLayer removeAllAnimations];
    
    CGFloat remainingOffset = offset;
    
    BOOL expectsWidePanels = [self viewControllerExpectsWidePanel:self.detailViewController];

    CGFloat usedOffset = MIN(DETAIL_LEDGE_OFFSET - DETAIL_OFFSET, remainingOffset);
    CGFloat viewX = DETAIL_LEDGE_OFFSET - usedOffset;
    
    [self animateView:self.detailViewContainer toOffset:viewX withVelocity:velocity];
    remainingOffset -= usedOffset;
    
    NSInteger viewCount = [self.detailViews count];
    for (NSInteger i = 1; i < viewCount; i++) {
        UIView *view = [self.detailViews objectAtIndex:i];
        UIView *previousView = [self.detailViews objectAtIndex:(i - 1)];
        usedOffset = MIN(previousView.frame.size.width, remainingOffset);
        viewX += previousView.frame.size.width;
        viewX -= usedOffset;
        
        // ZOMG this is horrible, but without it the secondary detail does not position correctly.
        if (offset >= 956.0f && i == viewCount -1 && expectsWidePanels && UIInterfaceOrientationIsPortrait(self.interfaceOrientation)) {
            viewX += 44.0f;
        }
        
        [self animateView:view toOffset:viewX withVelocity:velocity];
        remainingOffset -= usedOffset;
    }
    _stackOffset = offset - remainingOffset;
    [self partiallyVisibleViews];
}


- (CGFloat)nearestValidOffsetWithVelocity:(CGFloat)velocity {
    CGFloat offset = 0;

    // If we're working with wide panels we need to adjust the offset for the wide panel
    // This makes sure the lefthand side of the panel is correctly positioned over the sidebar.
    if ([self viewControllerExpectsWidePanel:_detailViewController]) {
        if (UIInterfaceOrientationIsPortrait(self.interfaceOrientation)) {
            if (velocity < 0) {
                return offset;
            } else {
                offset = DETAIL_LEDGE_OFFSET - (self.view.bounds.size.width - IPAD_WIDE_PANEL_WIDTH);
                
            }
        }
    }
    // if we have a single panel, transition back to its starting offset.
    if ([self.detailViews count] <= 1) {
        if (IS_IPHONE) {
            return DETAIL_LEDGE_OFFSET - DETAIL_OFFSET;
        } else {
            return offset;
        }
    }
    
    CGFloat remainingVelocity = velocity;
    CGFloat velocityFactor = 10.0f;
    CGFloat diff = ABS(_stackOffset + remainingVelocity / velocityFactor - offset);
    CGFloat previousOffset = offset;
    CGFloat previousDiff = diff;
    
    // View 0
    offset += DETAIL_LEDGE_OFFSET - DETAIL_OFFSET;
    diff = ABS(_stackOffset + remainingVelocity / velocityFactor - offset);
    remainingVelocity -= remainingVelocity / velocityFactor;
    if (diff > previousDiff) {
        return previousOffset;
    } else {
        previousOffset = offset;
        previousDiff = diff;
    }

    if (self.detailViews) {
        NSUInteger viewCount = [self.detailViews count];
        for (int i = 0; i < viewCount-2; i++) {
            UIView *view = [self.detailViews objectAtIndex:i];
            offset += view.frame.size.width;
            diff = ABS(_stackOffset + remainingVelocity / velocityFactor - offset);
            remainingVelocity -= remainingVelocity / velocityFactor;
            if (diff > previousDiff) {
                return previousOffset;
            } else {
                previousOffset = offset;
                previousDiff = diff;
            }
        }
    
        offset += DETAIL_LEDGE;
        offset += [[self.detailViewWidths objectAtIndex:(viewCount - 1)] floatValue];
        offset += [[self.detailViewWidths objectAtIndex:(viewCount - 2)] floatValue];
        offset -= self.view.bounds.size.width;
        diff = ABS(_stackOffset + remainingVelocity / velocityFactor - offset);
        if (diff > previousDiff) {
            return previousOffset;
        } else {
            previousOffset = offset;
        }
    }
    
    return previousOffset;
}

- (CGFloat)maxOffsetSoft {
    CGFloat maxSoft;
    NSUInteger viewCount = [self.detailViewWidths count];
    if (IS_IPHONE) {
        maxSoft = DETAIL_LEDGE_OFFSET;
    } else if (viewCount <= 1) {
        maxSoft = 0.0f;
        if ([self viewControllerExpectsWidePanel:_detailViewController] && UIInterfaceOrientationIsPortrait(self.interfaceOrientation)) {
            maxSoft = DETAIL_LEDGE_OFFSET - (self.view.bounds.size.width - IPAD_WIDE_PANEL_WIDTH);
        }
    } else {
        maxSoft = DETAIL_LEDGE_OFFSET - DETAIL_OFFSET;
        maxSoft+= DETAIL_LEDGE;
        maxSoft+= [[self.detailViewWidths objectAtIndex:(viewCount - 1)] floatValue];
        maxSoft+= [[self.detailViewWidths objectAtIndex:(viewCount - 2)] floatValue];
        maxSoft-= self.view.bounds.size.width;
        for (int i = viewCount - 3; i >= 0; i--) {
            maxSoft += [[self.detailViewWidths objectAtIndex:i] floatValue];
        }
    }
    return maxSoft;
}

- (CGFloat)maxOffsetHard {
    CGFloat maxHard;
    NSUInteger viewCount = [self.detailViewWidths count];
    if (IS_IPHONE) {
        maxHard = DETAIL_LEDGE_OFFSET;
    } else if (viewCount <= 1) {
        maxHard = DETAIL_LEDGE_OFFSET;
    } else {
        maxHard = DETAIL_LEDGE_OFFSET - DETAIL_OFFSET;
        for (int i = 0; i < viewCount; i++) {
            maxHard += [[self.detailViewWidths objectAtIndex:i] floatValue];
        }
    }
    return maxHard;
}

- (CGFloat)minOffsetSoft {
    return 0.0f;
}

- (CGFloat)minOffsetHard {
    return DETAIL_LEDGE_OFFSET - self.view.bounds.size.width;
}

- (NSInteger)indexForView:(UIView *)view {
    if (view == self.detailViewContainer) {
        return 0;
    }
    __block NSInteger index = -1;
    [self.detailViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if (view == [obj view]) {
            index = idx + 1;
            *stop = YES;
        }
    }];
    return index;
}

- (UIView *)viewForIndex:(NSUInteger)index {
    if (index == 0) {
        return self.detailViewContainer;
    } else {
        if (index > [self.detailViewControllers count]) {
            return nil;
        }
        return [self viewOrViewWrapper:[[self.detailViewControllers objectAtIndex:(index - 1)] view]];
    }
}

- (UIView *)viewBefore:(UIView *)view {
    if (view == self.detailViewContainer) {
        return nil;
    }

    NSInteger index = [self indexForView:view];
    return [self viewForIndex:index - 1];
}

- (UIView *)viewAfter:(UIView *)view {
    return [self viewForIndex:[self indexForView:view] + 1];
}

- (NSArray *)partiallyVisibleViews {
    NSMutableArray *views = [NSMutableArray arrayWithCapacity:[self.detailViews count]];    
    for (int idx=0;idx < [self.detailViews count];idx++) {
        UIView *view = (UIView *)[self.detailViews objectAtIndex:idx];
        if (CGRectContainsRect(self.view.bounds, view.frame)) {
            // Fully inside, check for overlapping views
            if (idx + 1 < [self.detailViews count]) {
                UIView *nextView = [self.detailViews objectAtIndex:idx+1];
                
                //get the correct overlay view, if it's the first panel (detailView), it's in a subview
                UIView *alphaView = view;
                if (view == self.detailViewContainer && [view.subviews count] >= 1) {
                    alphaView = [view.subviews objectAtIndex:0];
                }
                
                if (nextView && CGRectIntersectsRect(view.frame, nextView.frame) && nextView.frame.origin.x > view.frame.origin.x) {
                    if ([alphaView isKindOfClass: [PanelViewWrapper class]]) {
                        CGRect intersection = CGRectIntersection(alphaView.frame, nextView.frame);
                        if (alphaView.frame.size.width != 0) {
                            CGFloat fadeAlpha = 1.0f - (intersection.origin.x / alphaView.frame.size.width);
                            fadeAlpha /= 2.0f;
                            if (fadeAlpha > 0.15f) {
                                fadeAlpha = 0.15f;
                            }
                            if (fadeAlpha < 0.f) {
                                fadeAlpha = 0.f;
                            }
                            CGFloat alphaDifference = ((PanelViewWrapper*) alphaView).overlay.alpha - fadeAlpha;
                            if ((alphaDifference > 0.01f || alphaDifference < -0.01f) && !_pushing) {
                                [UIView beginAnimations:@"fadeAnimation" context:nil];
                                [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
                                [UIView setAnimationDuration:0.3f];
                                ((PanelViewWrapper*) alphaView).overlay.alpha = fadeAlpha;
                                [UIView commitAnimations];
                            } else {
                                ((PanelViewWrapper*) alphaView).overlay.alpha = fadeAlpha;
                            }
                        }
                    }
                    [views addObject:view];
                } else if ([alphaView isKindOfClass: [PanelViewWrapper class]] && nextView.frame.origin.x != view.frame.origin.x) {
                    ((PanelViewWrapper*) alphaView).overlay.alpha = 0.0f;
                }
            }
        } else if (CGRectIntersectsRect(self.view.bounds, view.frame)) {
            // Intersects, so partly visible
            [views addObject:view];
        }
    }
    
    // Ensure that the detailView is not faded if it is the only view.
    if ([self.detailViews count] == 1 && [[self.detailViewContainer subviews] count] > 1) {
        UIView *aView = [[self.detailViewContainer subviews] objectAtIndex:1]; // This should be the PanelViewWrapper.
        if ([aView isKindOfClass:[PanelViewWrapper class]]) {
            PanelViewWrapper *wrapperView = (PanelViewWrapper *)aView;
            wrapperView.overlay.alpha = 0.0f;            
        }
    }
    
    return [NSArray arrayWithArray:views];
}

#pragma mark - Navigation methods

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    WPFLogMethod();
    // Set the panelNavigation before any of the view methods are relayed for iOS4.
    [viewController setPanelNavigationController:self];
    
    if (self.navigationController) {
        [self.navigationController pushViewController:viewController animated:animated];
    } else {
        UIView *topView;
        if ([self.detailViewControllers count] == 0) {
            [self closeSidebar];
            topView = self.detailViewContainer;
        } else {
            topView = [self viewOrViewWrapper:self.topViewController.view];
        }
        CGRect topViewFrame = topView.frame;
        CGFloat newPanelWidth = IPAD_DETAIL_SECONDARY_WIDTH;
        
        if ([self viewControllerExpectsWidePanel:viewController]) {
            newPanelWidth = IPAD_WIDE_PANEL_WIDTH;
        }
        
        if (CGRectGetMaxX(topViewFrame) + newPanelWidth > self.view.bounds.size.width) {
            // Move previous controller to the left
            topViewFrame.origin.x = MAX(DETAIL_OFFSET, self.view.bounds.size.width - newPanelWidth - topViewFrame.size.width);
            viewController.view.frame = CGRectMake(self.view.bounds.size.width - newPanelWidth, 0.0f, newPanelWidth, DETAIL_HEIGHT);
        } else {
            viewController.view.frame = CGRectMake(CGRectGetMaxX(topViewFrame), 0.0f, newPanelWidth, DETAIL_HEIGHT);
        }
                
        [self addChildViewController:viewController];

        UIView *wrappedView = [self createWrapViewForViewController:viewController];
        [self.view addSubview:wrappedView];

        [self.detailViews addObject:wrappedView];
        [self.detailViewWidths addObject:[NSNumber numberWithFloat:newPanelWidth]];

        [self addShadowTo:wrappedView];
        
        [UIView animateWithDuration:CLOSE_SLIDE_DURATION(animated) animations:^{
            topView.frame = topViewFrame;
        }];
        [_popPanelsView setAlpha:1.0f];

        [viewController didMoveToParentViewController:self];
        [self.detailViewControllers addObject:viewController];
        
        [self setStackOffset:[self maxOffsetSoft] duration:0];
    }
}

- (void)pushViewController:(UIViewController *)viewController fromViewController:(UIViewController *)fromViewController animated:(BOOL)animated {
    WPFLogMethod();
    _pushing = YES;
    [self popToViewController:fromViewController animated:NO];
    [self pushViewController:viewController animated:animated];
    _pushing = NO;
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    UIViewController *viewController = nil;
    WPFLogMethod();
    if (self.navigationController) {
        return [self.navigationController popViewControllerAnimated:animated];
    } else {
        if (self.topViewController != self.detailViewController) {
            viewController = self.topViewController;
            [viewController willMoveToParentViewController:nil];
            [viewController viewWillDisappear:animated];
            [viewController removeFromParentViewController];

            UIView *view = [self viewOrViewWrapper:viewController.view];
            [view removeFromSuperview];
            
            [self.detailViewControllers removeLastObject];
            [self.detailViews removeLastObject];
            [self.detailViewWidths removeLastObject];
        }
    }
    return viewController;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated {
    WPFLogMethod();
    if (self.navigationController) {
        return [self.navigationController popToViewController:viewController animated:animated];
    } else {
        NSMutableArray *poppedControllers = [NSMutableArray array];
        __block BOOL found = NO;        
        [self.detailViewControllers enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if (obj == viewController) {
                *stop = YES;
                found = YES;
            } else {
                [poppedControllers addObject:obj];
                [self popViewControllerAnimated:animated];
            }
        }];
        if (!found && viewController != self.detailViewController) {
            [poppedControllers addObject:self.detailViewController];
            [self setDetailViewController:viewController];
        }
        // make sure the overlay is not visible.
        [self wrapViewForViewController:viewController].overlay.alpha = 0.0;
        
        return [NSArray arrayWithArray:poppedControllers];
    }
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated {
    WPFLogMethod();
    NSMutableArray *viewControllers = [NSMutableArray array];
    if (self.navigationController) {
        return [self.navigationController popToRootViewControllerAnimated:animated];
    } else {
        NSInteger count = [self.detailViewControllers count];
        for (int i = 0; i < count; i++) {
            [viewControllers addObject:[self popViewControllerAnimated:animated]];
        }
        if (_stackOffset != 0 && !(UIDeviceOrientationIsPortrait(self.interfaceOrientation) && [self viewControllerExpectsWidePanel:self.detailViewController])) {
            _stackOffset = 0;
            [self showSidebar];
        }
        //make sure there's no tint on the detailView overlay any longer
        if ([_detailViewContainer.subviews count] >= 1){
            PanelViewWrapper *overlayView = [_detailViewContainer.subviews objectAtIndex:0];
            overlayView.overlay.alpha = 0.0f;
        }
        if (self.detailViewController)
            [self addShadowTo: _detailViewContainer];
        [UIView animateWithDuration:0.5f
                         animations:^{
                             [_popPanelsView setAlpha:0.0f];
                         }
                         completion:nil];
    }
    return [NSArray arrayWithArray:viewControllers];
}


@end

@implementation UIViewController (PanelNavigationController)

@dynamic panelNavigationController;

static const char *panelNavigationControllerKey = "PanelNavigationController";

- (PanelNavigationController *)panelNavigationController {
    return objc_getAssociatedObject(self, panelNavigationControllerKey);
}

- (void)setPanelNavigationController:(PanelNavigationController *)panelNavigationController {
    objc_setAssociatedObject(self, panelNavigationControllerKey, panelNavigationController, OBJC_ASSOCIATION_ASSIGN);
}

@end
