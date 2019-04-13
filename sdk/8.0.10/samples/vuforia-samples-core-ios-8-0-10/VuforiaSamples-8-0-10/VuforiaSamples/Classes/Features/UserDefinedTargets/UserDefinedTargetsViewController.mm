/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import "UserDefinedTargetsViewController.h"
#import "VuforiaSamplesAppDelegate.h"
#import <Vuforia/Vuforia.h>
#import <Vuforia/TrackerManager.h>
#import <Vuforia/ObjectTracker.h>
#import <Vuforia/PositionalDeviceTracker.h>
#import <Vuforia/Trackable.h>
#import <Vuforia/TrackableSource.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/CameraDevice.h>

#import "UnwindMenuSegue.h"
#import "PresentMenuSegue.h"
#import "SampleAppMenuViewController.h"

#define TOOLBAR_HEIGHT 53


@interface UserDefinedTargetsViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *ARViewPlaceholder;
@property (strong, nonatomic) ToastView* toastView;
@property (nonatomic, strong) UserDefinedTargetsEAGLView *eaglView;
@property (nonatomic, strong) UITapGestureRecognizer *tapGestureRecognizer;
@property (nonatomic, strong) SampleApplicationSession *vapp;

@property (nonatomic, strong) CustomToolbar *toolbar;

@property (nonatomic, readwrite) BOOL showingMenu;


@end

@implementation UserDefinedTargetsViewController

@synthesize tapGestureRecognizer, vapp, eaglView, toolbar;


- (CGRect)getCurrentARViewFrame
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    return screenBounds;
}

- (void)loadView
{
    // Custom initialization
    self.title = @"Object Reco";
    
    if (self.ARViewPlaceholder != nil) {
        [self.ARViewPlaceholder removeFromSuperview];
        self.ARViewPlaceholder = nil;
    }
    
    dataSetUserDef = nil;
    
    deviceTrackerEnabled = NO;
    continuousAutofocusEnabled = YES;
    flashEnabled = NO;
    
    vapp = [[SampleApplicationSession alloc] initWithDelegate:self];
    
    CGRect viewFrame = [self getCurrentARViewFrame];
    
    refFreeFrame = new RefFreeFrame();
    eaglView = [[UserDefinedTargetsEAGLView alloc] initWithFrame:viewFrame appSession:vapp andSampleUIUpdater:self];
    [eaglView setBackgroundColor:UIColor.clearColor];
    [eaglView setRefFreeFrame: refFreeFrame];
    [self setView:eaglView];
    VuforiaSamplesAppDelegate *appDelegate = (VuforiaSamplesAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.glResourceHandler = eaglView;
    
    // double tap used to also trigger the menu
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(doubleTapGestureAction:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];
    
    // a single tap will trigger a single autofocus operation
    tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(autofocus:)];
    if (doubleTap != NULL) {
        [tapGestureRecognizer requireGestureRecognizerToFail:doubleTap];
    }
    
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeGestureAction:)];
    [swipeRight setDirection:UISwipeGestureRecognizerDirectionRight];
    [self.view addGestureRecognizer:swipeRight];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dismissARViewController)
                                                 name:@"kDismissARViewController"
                                               object:nil];
    
    // we use the iOS notification to pause/resume the AR when the application goes (or come back from) background
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(pauseAR)
     name:UIApplicationWillResignActiveNotification
     object:nil];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(resumeAR)
     name:UIApplicationDidBecomeActiveNotification
     object:nil];

    // initialize AR
    [vapp initAR:Vuforia::GL_20 orientation:[[UIApplication sharedApplication] statusBarOrientation] deviceMode:Vuforia::Device::MODE_AR stereo:false];

    refFreeFrame->stopImageTargetBuilder();
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(goodFrameQuality:)
                                                 name:@"kGoodFrameQuality"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(badFrameQuality:)
                                                 name:@"kBadFrameQuality"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(trackableCreated:)
                                                 name:@"kTrackableCreated"
                                               object:nil];
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

    // show loading animation while AR is being initialized
    [self showLoadingAnimation];
}

-(void) addToolbar
{
    dispatch_async(dispatch_get_main_queue(), ^{
        //  Init Toolbar
        CGRect toolbarFrame = CGRectMake(0,
                                         self.view.frame.size.height - TOOLBAR_HEIGHT,
                                         self.view.frame.size.width,
                                         TOOLBAR_HEIGHT);
      
        self->toolbar = [[CustomToolbar alloc] initWithFrame:toolbarFrame];
        self->toolbar.delegate = self;
        self->toolbar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;// | UIViewAutoresizingFlexibleWidth;
      
        //  Finally, add toolbar to ViewController's view
        [self.view addSubview:self->toolbar];
    });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view.superview isKindOfClass:[CustomToolbar class]]) return FALSE;
    return YES;
}

- (void) pauseAR {
    NSError * error = nil;
    if (![vapp pauseAR:&error]) {
        NSLog(@"Error pausing AR:%@", [error description]);
    }
}

- (void) resumeAR {
    NSError * error = nil;
    if(! [vapp resumeAR:&error]) {
        NSLog(@"Error resuming AR:%@", [error description]);
    }
    [eaglView updateRenderingPrimitives];
    // on resume, we reset the flash
    Vuforia::CameraDevice::getInstance().setFlashTorchMode(false);
    flashEnabled = NO;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.showingMenu = NO;
    
    // Do any additional setup after loading the view.
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    
    NSLog(@"self.navigationController.navigationBarHidden: %s", self.navigationController.navigationBarHidden ? "Yes" : "No");
    
    self.toastView = [[ToastView alloc] initAndAddToParentView:self.view];
}

- (void)viewWillDisappear:(BOOL)animated
{
    // on iOS 7, viewWillDisappear may be called when the menu is shown
    // but we don't want to stop the AR view in that case
    if (self.showingMenu) {
        return;
    }
    
    refFreeFrame->deInit();

    [vapp stopAR:nil];
    
    // Be a good OpenGL ES citizen: now that Vuforia Engine is paused and the render
    // thread is not executing, inform the root view controller that the
    // EAGLView should finish any OpenGL ES commands
    [self finishOpenGLESCommands];
    
    VuforiaSamplesAppDelegate *appDelegate = (VuforiaSamplesAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.glResourceHandler = nil;
    
    delete refFreeFrame;
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  Inform the EAGLView
    [eaglView finishOpenGLESCommands];
}

- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Inform the EAGLView
    [eaglView freeOpenGLESResources];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - SampleAppsUIControl

- (void) setIsInRelocalizationState:(BOOL)isRelocalizing
{
    // We wait for a few seconds to relocalize, if not we reset the device tracker
    const float SECONDS_TO_RESET_AFTER_RELOCALIZATION_DELAY = 10.0f;
    const float SECONDS_TO_WAIT_TO_SHOW_RELOCALIZATION_MSG = 1.0f;
    
    static NSTimer* showMessageDelay;
    
    if (isRelocalizing)
    {
        if (showMessageDelay == nil || ![showMessageDelay isValid])
        {
            showMessageDelay =
            [NSTimer scheduledTimerWithTimeInterval:SECONDS_TO_WAIT_TO_SHOW_RELOCALIZATION_MSG repeats:NO block:^(NSTimer *timer){
                    const void (^completion)(void) = ^(void){
                        [self.toastView showAndDismissToastWithMessage:@"Device tracker reset"
                                                           andDuration:2.0f];
                    };
                    SEL resetDeviceTrackerSelector = NSSelectorFromString(@"resetDeviceTracker:");
                    
                    if ([self.vapp respondsToSelector:resetDeviceTrackerSelector])
                    {
                        [self.toastView showAndDismissToastWithMessage:@"Point camera to previous position to restore tracking"
                                                           andDuration:SECONDS_TO_RESET_AFTER_RELOCALIZATION_DELAY];
                        
                        [self.vapp performSelector:resetDeviceTrackerSelector
                                        withObject:completion
                                        afterDelay:SECONDS_TO_RESET_AFTER_RELOCALIZATION_DELAY];
                    }
                }
             ];
        }
        
        [[NSRunLoop currentRunLoop] addTimer:showMessageDelay forMode:NSDefaultRunLoopMode];
    }
    else
    {
        [self.toastView hideToast];
        [showMessageDelay invalidate];
        [NSObject cancelPreviousPerformRequestsWithTarget:self.vapp];
    }
}

#pragma mark - loading animation

- (void) showLoadingAnimation {
    CGRect indicatorBounds;
    CGRect mainBounds = [[UIScreen mainScreen] bounds];
    int smallerBoundsSize = MIN(mainBounds.size.width, mainBounds.size.height);
    int largerBoundsSize = MAX(mainBounds.size.width, mainBounds.size.height);
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown ) {
        indicatorBounds = CGRectMake(smallerBoundsSize / 2 - 12,
                                     largerBoundsSize / 2 - 12, 24, 24);
    }
    else {
        indicatorBounds = CGRectMake(largerBoundsSize / 2 - 12,
                                     smallerBoundsSize / 2 - 12, 24, 24);
    }
    
    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc]
                                                  initWithFrame:indicatorBounds];
    
    loadingIndicator.tag  = 1;
    loadingIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    [eaglView addSubview:loadingIndicator];
    [loadingIndicator startAnimating];
}

- (void) hideLoadingAnimation {
    UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
    [loadingIndicator removeFromSuperview];
}


-(void)setCameraMode
{
    refFreeFrame->startImageTargetBuilder();
    
    toolbar.isCancelButtonHidden = YES;
    toolbar.shouldRotateActionButton = YES;
    toolbar.actionImage = [UIImage imageNamed:@"icon_camera.png"];
}

#pragma mark - Notifications
- (void)goodFrameQuality:(NSNotification *)aNotification
{
    //NSLog(@">> goodFrameQuality");
}

- (void)badFrameQuality:(NSNotification *)aNotification
{
    //NSLog(@">> badFrameQuality");
}

- (void)trackableCreated:(NSNotification *)aNotification
{
    // we restart the camera mode once a target has been added
    [self setCameraMode];
}

#pragma mark - CustomToolbarDelegateProtocol

-(void)actionButtonWasPressed
{
    //  Camera button was pressed
    if (refFreeFrame->isImageTargetBuilderRunning())
    {
        if (!refFreeFrame->startBuild())
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                UIAlertController *uiAlertController =
                [UIAlertController alertControllerWithTitle:@"Low Quality Image"
                                                    message:@"The image has very little detail, please try another."
                                             preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *defaultAction =
                [UIAlertAction actionWithTitle:@"OK"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                           
                                       }];
                
                [uiAlertController addAction:defaultAction];
                
                [self presentViewController:uiAlertController animated:YES completion:nil];
            });
        }
    }
}

-(void)cancelButtonWasPressed
{
    // No cancel button
}


#pragma mark - SampleApplicationControl

// Initialize the application trackers
- (BOOL)doInitTrackers
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    
    // Initialize the object tracker
    Vuforia::Tracker* objectTracker = trackerManager.initTracker(Vuforia::ObjectTracker::getClassType());
    if (objectTracker == nullptr)
    {
        NSLog(@"Failed to initialize ObjectTracker.");
        return NO;
    }
    
    // Initialize the device tracker
    Vuforia::Tracker* deviceTracker = trackerManager.initTracker(Vuforia::PositionalDeviceTracker::getClassType());
    if (deviceTracker == nullptr)
    {
        NSLog(@"Failed to initialize DeviceTracker.");
    }
    
    NSLog(@"Initialized trackers");
    return YES;
}

- (BOOL)doLoadTrackersData
{
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    if (objectTracker != nullptr)
    {
        // Create the data set:
        dataSetUserDef = objectTracker->createDataSet();
        if (dataSetUserDef != nullptr)
        {
            if (!objectTracker->activateDataSet(dataSetUserDef))
            {
                NSLog(@"Failed to activate data set.");
                return NO;
            }
        }
    }
    return YES;
}

// start the application trackers
- (BOOL)doStartTrackers
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    
    // Start object tracker
    Vuforia::Tracker* objectTracker = trackerManager.getTracker(Vuforia::ObjectTracker::getClassType());
    
    if(objectTracker != nullptr && objectTracker->start())
    {
        NSLog(@"Successfully started object tracker");
    }
    else
    {
        NSLog(@"ERROR: Failed to start object tracker");
        return NO;
    }
    
    // Start device tracker if enabled
    if (deviceTrackerEnabled)
    {
        [self setDeviceTrackerEnabled:YES];
    }
    
    return YES;
}

// callback called when the initailization of the AR is done
- (void)onInitARDone:(NSError *)initError
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[self->eaglView viewWithTag:1];
        [loadingIndicator removeFromSuperview];
    });
    
    if (initError == nil)
    {
        NSError * error = nil;
        
        //  Add bottom toolbar
        [self addToolbar];
        
        [self setCameraMode];
        
        [vapp startAR:Vuforia::CameraDevice::CAMERA_DIRECTION_BACK error:&error];
        
        [eaglView updateRenderingPrimitives];

        // by default, we try to set the continuous auto focus mode
        continuousAutofocusEnabled = Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO);
        
    }
    else
    {
        NSLog(@"Error initializing AR:%@", [initError description]);
        
        dispatch_async( dispatch_get_main_queue(), ^{
            
            [SampleUIUtils showAlertWithTitle:@"Error"
                                      message:[initError localizedDescription]
                                   completion:^{
                                       [[NSNotificationCenter defaultCenter] postNotificationName:@"kDismissARViewController" object:nil];
                                   }];

        });
    }
}


- (void)dismissARViewController
{
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [self.navigationController popToRootViewControllerAnimated:NO];
}

- (void)configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth andHeight:(float)viewHeight
{
    [eaglView configureVideoBackgroundWithCameraMode:cameraMode
                                           viewWidth:viewWidth
                                          viewHeight:viewHeight];
}

- (void) onVuforiaUpdate: (Vuforia::State *) state {
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (refFreeFrame->hasNewTrackableSource())
    {
        Vuforia::Trackable * lastCreated;
        
        NSLog(@"Attempting to transfer the trackable source to the dataset");
        
        // Deactiveate current dataset
        objectTracker->deactivateDataSet(objectTracker->getActiveDataSets().at(0));
        
        // Clear the oldest target if the dataset is full or the dataset
        // already contains five user-defined targets.
        if (dataSetUserDef->hasReachedTrackableLimit()
            || dataSetUserDef->getTrackables().size() >= 5)
            dataSetUserDef->destroy(dataSetUserDef->getTrackables().at(0));
        
        // Add new trackable source
        lastCreated = dataSetUserDef->createTrackable(refFreeFrame->getNewTrackableSource());
        
        // Reactivate current dataset
        objectTracker->activateDataSet(dataSetUserDef);
    }
}


// stop your trackerts
- (BOOL)doStopTrackers
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    
    // Stop the object tracker
    Vuforia::Tracker* objectTracker = trackerManager.getTracker(Vuforia::ObjectTracker::getClassType());
    
    if (objectTracker != nullptr)
    {
        objectTracker->stop();
        NSLog(@"INFO: successfully stopped object tracker");
    }
    else
    {
        NSLog(@"ERROR: failed to get the object tracker from the tracker manager");
        return NO;
    }
    
    // Stop the device tracker
    if(deviceTrackerEnabled)
    {
        Vuforia::Tracker* deviceTracker = trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType());
        
        if (deviceTracker != nullptr)
        {
            deviceTracker->stop();
            NSLog(@"INFO: successfully stopped devicetracker");
        }
        else
        {
            NSLog(@"ERROR: failed to get the device tracker from the tracker manager");
        }
    }
    
    return YES;
}

// unload the data associated to your trackers
- (BOOL)doUnloadTrackersData
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    if (objectTracker == nullptr)
    {
        NSLog(@"Failed to destroy the tracking data set because the ObjectTracker has not been initialized.");
        return false;
    }
    
    if (dataSetUserDef != nullptr)
    {
        if (objectTracker->getActiveDataSets().at(0) && !objectTracker->deactivateDataSet(dataSetUserDef))
        {
            NSLog(@"Failed to destroy the tracking data set because the data set could not be deactivated.");
            return NO;
        }
        if (!objectTracker->destroyDataSet(dataSetUserDef))
        {
            NSLog(@"Failed to destroy the tracking data set.");
            return NO;
        }
    }
    deviceTrackerEnabled = NO;
    dataSetUserDef = nullptr;
    return YES;
}

// deinitialize your trackers
- (BOOL)doDeinitTrackers
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    trackerManager.deinitTracker(Vuforia::ObjectTracker::getClassType());
    trackerManager.deinitTracker(Vuforia::PositionalDeviceTracker::getClassType());
    return YES;
}

- (void)autofocus:(UITapGestureRecognizer *)sender
{
    [self performSelector:@selector(cameraPerformAutoFocus) withObject:nil afterDelay:.4];
}

- (void)cameraPerformAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_TRIGGERAUTO);
    
    // After triggering an autofocus event,
    // we must restore the previous focus mode
    if (continuousAutofocusEnabled)
    {
        [self performSelector:@selector(restoreContinuousAutoFocus) withObject:nil afterDelay:2.0];
    }
}

- (void)restoreContinuousAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO);
}

- (void)doubleTapGestureAction:(UITapGestureRecognizer*)theGesture
{
    if (!self.showingMenu) {
        [self performSegueWithIdentifier: @"PresentMenu" sender: self];
    }
}

- (void)swipeGestureAction:(UISwipeGestureRecognizer*)gesture
{
    if (!self.showingMenu) {
        [self performSegueWithIdentifier:@"PresentMenu" sender:self];
    }
}


- (BOOL)activateDataSet:(Vuforia::DataSet *)theDataSet
{
    BOOL success = NO;
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == NULL) {
        NSLog(@"Failed to load tracking data set because the ObjectTracker has not been initialized.");
    }
    else
    {
        // Activate the data set:
        if (!objectTracker->activateDataSet(theDataSet))
        {
            NSLog(@"Failed to activate data set.");
        }
        else
        {
            NSLog(@"Successfully activated data set.");
            success = YES;
        }
    }
    
    return success;
}

- (BOOL)deactivateDataSet:(Vuforia::DataSet *)theDataSet
{
    BOOL success = NO;
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == NULL)
    {
        NSLog(@"Failed to unload tracking data set because the ObjectTracker has not been initialized.");
    }
    else
    {
        // Activate the data set:
        if (!objectTracker->deactivateDataSet(theDataSet))
        {
            NSLog(@"Failed to deactivate data set.");
        }
        else
        {
            success = YES;
        }
    }
    
    return success;
}

- (BOOL) setDeviceTrackerEnabled:(BOOL) enable
{
    BOOL result = YES;
    
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*>(
            Vuforia::TrackerManager::getInstance()
            .getTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    
    if (deviceTracker == NULL)
    {
        NSLog(@"ERROR: Could not toggle device tracker state");
        return NO;
    }
    
    if (enable)
    {
        if (deviceTracker->start())
        {
            NSLog(@"Successfully started device tracker");
        }
        else
        {
            result = NO;
            NSLog(@"Failed to start device tracker");
        }
    }
    else
    {
        deviceTracker->stop();
        NSLog(@"Successfully stopped device tracker");
    }
    
    return result;
}


#pragma mark - menu delegate protocol implementation

- (BOOL) menuProcess:(NSString *)itemName value:(BOOL)value
{
    if ([@"Device Tracker" isEqualToString:itemName])
    {
        BOOL result = [self setDeviceTrackerEnabled:value];
        
        if (result)
        {
            [eaglView setOffTargetTrackingMode:value];
            // we keep track of the state of the Device Tracker
            deviceTrackerEnabled = value;
        }
        return result;
    }
    return NO;
}

- (void) menuDidExit
{
    self.showingMenu = NO;
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue isKindOfClass:[PresentMenuSegue class]]) {
        UIViewController *dest = [segue destinationViewController];
        if ([dest isKindOfClass:[SampleAppMenuViewController class]]) {
            self.showingMenu = YES;
            
            SampleAppMenuViewController *menuVC = (SampleAppMenuViewController *)dest;
            menuVC.menuDelegate = self;
            menuVC.sampleAppFeatureName = @"User Defined Targets";
            menuVC.dismissItemName = @"Vuforia Samples";
            menuVC.backSegueId = @"BackToUserDefinedTargets";
            
            // initialize menu item values (ON / OFF)
            [menuVC setValue:deviceTrackerEnabled forMenuItem:@"Device Tracker"];
        }
    }
}

@end
