/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import "ModelTargetsTrainedViewController.h"
#import "VuforiaSamplesAppDelegate.h"
#import <Vuforia/Vuforia.h>
#import <Vuforia/TrackerManager.h>
#import <Vuforia/ObjectTracker.h>
#import <Vuforia/Trackable.h>
#import <Vuforia/ModelTargetResult.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/CameraDevice.h>
#import <Vuforia/PositionalDeviceTracker.h>

#import "UnwindMenuSegue.h"
#import "PresentMenuSegue.h"
#import "SampleAppMenuViewController.h"

@interface ModelTargetsTrainedViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *ARViewPlaceholder;
@property (weak, nonatomic) IBOutlet UIView *ResetButton;
@property (weak, nonatomic) IBOutlet UIView *InitialScreenView;
@property (weak, nonatomic) IBOutlet UIView *MainARView;
@property (weak, nonatomic) IBOutlet UIView *AllModelsDetectedView;
@property (weak, nonatomic) IBOutlet UIImageView *SearchingReticle;
@property (weak, nonatomic) IBOutlet UIImageView *LanderStatusView;
@property (weak, nonatomic) IBOutlet UIImageView *BikeStatusView;

@property (strong, nonatomic) ToastView* toastView;

@end

@implementation ModelTargetsTrainedViewController
{
    GuideViewStatus mBikeGuideViewStatus;
    GuideViewStatus mLanderGuideViewStatus;
}

@synthesize tapGestureRecognizer, vapp, eaglView;

- (CGRect) getCurrentARViewFrame
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    return screenBounds;
}

- (void) loadView
{
    [super loadView];
    
    // Custom initialization
    self.title = @"Model Targets";
    
    if (self.ARViewPlaceholder != nil)
    {
        [self.ARViewPlaceholder removeFromSuperview];
        self.ARViewPlaceholder = nil;
    }
    
    continuousAutofocusEnabled = YES;
    
    vapp = [[SampleApplicationSession alloc] initWithDelegate:self];
    
    CGRect viewFrame = [self getCurrentARViewFrame];
    
    eaglView = [[ModelTargetsTrainedEAGLView alloc] initWithFrame:viewFrame appSession:vapp modelTargetsUIUpdater:self andSampleUIUpdater:self];
    [eaglView setBackgroundColor:UIColor.clearColor];
    
    [self.view addSubview:eaglView];
    [self.view sendSubviewToBack:eaglView];

    VuforiaSamplesAppDelegate *appDelegate = (VuforiaSamplesAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.glResourceHandler = eaglView;
    
    // double tap used to also trigger the menu
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget: self action:@selector(doubleTapGestureAction:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];
    
    // a single tap will trigger a single autofocus operation
    tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(autofocus:)];
    if (doubleTap != nil)
    {
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

    mBikeGuideViewStatus = PASSIVE;
    mLanderGuideViewStatus = PASSIVE;
    
    [self showSearchReticle:YES];
    [self showMainARView:NO];
    [self showInitialScreen:YES];
    [self showAllModelsDetectedView:NO];
    
    // show loading animation while AR is being initialized
    [self showLoadingAnimation];
}

- (void) pauseAR
{
    [self doStopTrackers];
    
    NSError * error = nil;
    if (![vapp pauseAR:&error])
    {
        NSLog(@"Error pausing AR:%@", [error description]);
    }
}

- (void) resumeAR
{
    [self doStartTrackers];
    
    NSError * error = nil;
    if (![vapp resumeAR:&error])
    {
        NSLog(@"Error resuming AR:%@", [error description]);
    }
    
    [eaglView updateRenderingPrimitives];
}


- (void) viewDidLoad
{
    [super viewDidLoad];
    
    self.showingMenu = NO;
    
    // Do any additional setup after loading the view.
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.view addGestureRecognizer:tapGestureRecognizer];
    
    self.toastView = [[ToastView alloc] initAndAddToParentView:self.view];
}

- (void) viewWillDisappear:(BOOL)animated
{
    // viewWillDisappear may be called when the menu is shown
    // but we don't want to stop the AR view in that case
    if (self.showingMenu)
    {
        return;
    }
    
    [vapp stopAR:nil];
    
    // Be a good OpenGL ES citizen: now that Vuforia is paused and the render
    // thread is not executing, inform the root view controller that the
    // EAGLView should finish any OpenGL ES commands
    [self finishOpenGLESCommands];
    
    VuforiaSamplesAppDelegate *appDelegate = (VuforiaSamplesAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.glResourceHandler = nil;
    
    [super viewWillDisappear:animated];
}

- (void) viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [self handleRotation:[[UIApplication sharedApplication] statusBarOrientation]];
}

- (void) handleRotation:(UIInterfaceOrientation)interfaceOrientation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // ensure overlay size and AR orientation is correct for screen orientation
        [self handleARViewRotation: interfaceOrientation];
        [self->vapp  changeOrientation: interfaceOrientation];
        [self->eaglView changeOrientation: interfaceOrientation];
    });
}

- (void) handleARViewRotation:(UIInterfaceOrientation)interfaceOrientation
{
    // Retrieve up-to-date view frame.
    // Note that, while on iOS 7 and below, the frame size does not change
    // with rotation events,
    // on the contray, on iOS 8 the frame size is orientation-dependent,
    // i.e. width and height get swapped when switching from
    // landscape to portrait and vice versa.
    // This requires that the latest (current) view frame is retrieved.
    CGRect viewBounds = [[UIScreen mainScreen] bounds];
    
    int smallerSize = MIN(viewBounds.size.width, viewBounds.size.height);
    int largerSize = MAX(viewBounds.size.width, viewBounds.size.height);
    
    if (interfaceOrientation == UIInterfaceOrientationPortrait ||
        interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)
    {
        NSLog(@"AR View: Rotating to Portrait");
        
        CGRect viewBounds;
        viewBounds.origin.x = 0;
        viewBounds.origin.y = 0;
        viewBounds.size.width = smallerSize;
        viewBounds.size.height = largerSize;
        
        [eaglView setFrame:viewBounds];
    }
    else if (interfaceOrientation == UIInterfaceOrientationLandscapeLeft ||
             interfaceOrientation == UIInterfaceOrientationLandscapeRight)
    {
        NSLog(@"AR View: Rotating to Landscape");
        
        CGRect viewBounds;
        viewBounds.origin.x = 0;
        viewBounds.origin.y = 0;
        viewBounds.size.width = largerSize;
        viewBounds.size.height = smallerSize;
        
        [eaglView setFrame:viewBounds];
    }
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  Inform the EAGLView
    [eaglView finishOpenGLESCommands];
}

- (void) freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Inform the EAGLView
    [eaglView freeOpenGLESResources];
}

- (void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction) dismissInitialScreen:(id)sender
{
    [self showInitialScreen:NO];
    [self showSearchReticle:YES];
    [self showMainARView:YES];
}

- (IBAction) dismissDetectedAllTargetsView:(id)sender
{
    [self showAllModelsDetectedView:NO];
    [self showMainARView:YES];
}

// Resets the object tracker, target finder and device tracker so we start the detection from our initial state
- (IBAction) resetTracking:(id)sender
{
    Vuforia::TrackerManager& tManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(tManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*>(tManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    
    if (objectTracker != nullptr)
    {
        objectTracker->stop();
        
        if (mTargetFinder != nullptr)
        {
            mTargetFinder->clearTrackables();
            mTargetFinder->stop();
            mTargetFinder->startRecognition();
            mIsRecoSuspended = false;
            mIsRecoPossible = true;
        }
        
        objectTracker->start();
    }
    
    if (deviceTracker != nullptr)
    {
        deviceTracker->reset();
    }
    
    [self showInitialScreen:YES];
    [self showSearchReticle:YES];
    [self showMainARView:NO];
    [self showAllModelsDetectedView:NO];
    [eaglView resetTracking];
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

- (void) showLoadingAnimation
{
    CGRect indicatorBounds;
    CGRect mainBounds = [[UIScreen mainScreen] bounds];
    int smallerBoundsSize = MIN(mainBounds.size.width, mainBounds.size.height);
    int largerBoundsSize = MAX(mainBounds.size.width, mainBounds.size.height);
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown)
    {
        indicatorBounds = CGRectMake(smallerBoundsSize / 2 - 12,
                                     largerBoundsSize / 2 - 12, 24, 24);
    }
    else
    {
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


- (void) hideLoadingAnimation
{
    UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[eaglView viewWithTag:1];
    [loadingIndicator removeFromSuperview];
}


- (void) showInitialScreen:(BOOL)show
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.InitialScreenView setHidden:!show];
    });
}


- (void) showSearchReticle:(BOOL)show
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.SearchingReticle setHidden:!show];
    });
}


- (void) showAllModelsDetectedView:(BOOL)show
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.AllModelsDetectedView setHidden:!show];
    });
}


- (void) showMainARView:(BOOL)show
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.MainARView isHidden] == show)
        {
            [self setStatusImageForModel:LANDER withState:GuideViewStatus::PASSIVE];
            [self setStatusImageForModel:BIKE withState:PASSIVE];
            [self.MainARView setHidden:!show];
        }
    });
}


// Set the guide views status image showing if it has been recognized or snapped
- (void) setStatusImageForModel:(GuideViewModels)guideViewModel withState:(GuideViewStatus)status
{
    // We check if the status was already set
    if (guideViewModel == LANDER && mLanderGuideViewStatus == status)
    {
        return;
    }
    
    if (guideViewModel == BIKE && mBikeGuideViewStatus == status)
    {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIImageView* imageView;

        // If this is the first time both models have been 'snapped', show the 'detected all models' dialog
        if (guideViewModel == LANDER)
        {
            if( self->mLanderGuideViewStatus != status && status == SNAPPED && self->mBikeGuideViewStatus == status)
            {
                [self showAllModelsDetectedView:YES];
            }
            imageView = self.LanderStatusView;
            self->mLanderGuideViewStatus = status;
        }
        else
        {
            if (self->mBikeGuideViewStatus != status && status == SNAPPED && self->mLanderGuideViewStatus == status)
            {
                [self showAllModelsDetectedView:YES];
            }
            imageView = self.BikeStatusView;
            self->mBikeGuideViewStatus = status;
        }
        
        NSMutableString * guideViewImageString = [NSMutableString stringWithString:(guideViewModel == LANDER ? @"LanderStatus" : @"BikeStatus")];
        switch (status)
        {
            case PASSIVE:
                [guideViewImageString appendString:@"Passive"];
                break;
                
            case RECOGNIZED:
                [guideViewImageString appendString:@"Recognized"];
                break;
                
            case SNAPPED:
                [guideViewImageString appendString:@"Snapped"];
                break;
                
            default:
                NSLog(@"Should not reach this point");
                break;
        }
        
        [imageView setImage:[UIImage imageNamed:guideViewImageString]];
    });
}


#pragma mark - SampleApplicationControl

// Initialize the application trackers
- (BOOL) doInitTrackers
{
    // Initialize the object tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* trackerBase = trackerManager.initTracker(Vuforia::ObjectTracker::getClassType());
    if (trackerBase == nullptr)
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

    return YES;
}

// load the data associated to the trackers
- (BOOL) doLoadTrackersData
{
    mTargetFinder = [self loadTargetFinder:@"Vuforia_Motorcycle_Marslander.xml"];
    if (mTargetFinder == nullptr)
    {
        NSLog(@"Failed to load datasets");
        return NO;
    }
    
    mIsRecoPossible = false;
    mIsRecoSuspended = false;
    if (![self activateDataSet: nullptr])
    {
        NSLog(@"Failed to activate dataset");
        return NO;
    }
    
    return YES;
}

// start the application trackers
- (BOOL) doStartTrackers
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
    
    // Start device tracker
    [self setDeviceTrackerEnabled:YES];
    
    return YES;
}

// callback called when the initailization of the AR is done
- (void) onInitARDone:(NSError *)initError
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityIndicatorView *loadingIndicator = (UIActivityIndicatorView *)[self->eaglView viewWithTag:1];
        [loadingIndicator removeFromSuperview];
    });
    
    if (initError == nil)
    {
        NSError * error = nil;
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

- (void) dismissARViewController
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

- (void) onVuforiaUpdate: (Vuforia::State *) state
{
    if (!mTargetFinder || !mIsRecoPossible)
    {
        return;
    }
    
    auto targetFinderQuery = mTargetFinder->updateQueryResults(); //always consume recos so that we don't get them on later frames

    
    bool foundModelTargetResult = false;
    
    for (auto* res : state->getTrackableResults())
    {
        if (res->isOfType(Vuforia::ModelTargetResult::getClassType()) && res->getStatus() == Vuforia::TrackableResult::TRACKED)
        {
            foundModelTargetResult = true;
            
            break;
        }
    }
    

    if (foundModelTargetResult)
    {
        if (!mIsRecoSuspended)
        {
            mTargetFinder->stop();
            mIsRecoSuspended = true;
        }
        return; // don't change while tracking
    }
    
    if (!foundModelTargetResult && mIsRecoSuspended)
    {
        mTargetFinder->startRecognition();
        mIsRecoSuspended = false;
    }
    
    // If we get a result from the Target Finder we will enable tracking for the first result,
    // then we show the guide view which corresponds to that result so the user can snap and track that target
    if (targetFinderQuery.status == Vuforia::TargetFinder::UPDATE_RESULTS_AVAILABLE && !targetFinderQuery.results.empty())
    {
        auto* objectTarget = mTargetFinder->enableTracking(*targetFinderQuery.results[0]);
        mActiveModelTarget = static_cast< Vuforia::ModelTarget* >(objectTarget);
        
        [eaglView setTrackableForGuideView:mActiveModelTarget];
        
        [self showInitialScreen:NO];
        [self showSearchReticle:NO];
        [self showMainARView:YES];
        
        // Depending on the result we update the UI indicating the target finder recognized that model
        GuideViewModels guideViewUIToUpdate = GuideViewModels::BIKE;
        if (strstr((mActiveModelTarget->getName()), "MarsLander"))
        {
            guideViewUIToUpdate = GuideViewModels::LANDER;
        }
        
        [self setStatusImageForModel:guideViewUIToUpdate withState:GuideViewStatus::RECOGNIZED];
    }
}

// Load the image tracker data set
- (Vuforia::TargetFinder *) loadTargetFinder:(NSString*)dataFile
{
    NSLog(@"loadTargetFinder (%@)", dataFile);
    Vuforia::TargetFinder * targetFinder = nullptr;
    
    // Get the Vuforia tracker manager image tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == nullptr)
    {
        NSLog(@"ERROR: failed to get the ObjectTracker from the tracker manager");
        return nullptr;
    }
    else
    {
        targetFinder = objectTracker->getTargetFinder(Vuforia::ObjectTracker::TargetFinderType::MODEL_RECO);

        if (targetFinder == nullptr)
        {
            NSLog(@"ERROR: failed to get target finder.");
            return nullptr;
        }         
      
        targetFinder->startInit([dataFile cStringUsingEncoding:NSASCIIStringEncoding], Vuforia::STORAGE_APPRESOURCE);
        
        targetFinder->waitUntilInitFinished();
        
        int resultCode = targetFinder->getInitState();
        
        if (resultCode != Vuforia::TargetFinder::INIT_SUCCESS)
        {
            NSLog(@"ERROR: failed to init target finder.");
            return nullptr;
        }
       
        NSLog(@"INFO: successfully loaded data set");
    }
    
    return targetFinder;
}


- (BOOL) doStopTrackers
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
    }
    
    return YES;
}

- (BOOL) doUnloadTrackersData
{
    
    [self deactivateDataSet: nullptr];
    
    // Destroy the data sets:
    if (mTargetFinder != nullptr)
    {
        mTargetFinder->deinit();
        mTargetFinder = nullptr;
    }
    NSLog(@"datasets destroyed");
    return YES;
}

- (BOOL) activateDataSet:(Vuforia::DataSet *)theDataSet
{
    BOOL success = NO;
    
    if (mTargetFinder->startRecognition())
    {
        mIsRecoPossible = true;
        mIsRecoSuspended = false;
        success = YES;
    }
    
    return success;
}

- (BOOL) deactivateDataSet:(Vuforia::DataSet *)theDataSet
{
    BOOL success = NO;
    if (mTargetFinder && mTargetFinder->stop())
    {
        success = YES;
        mIsRecoPossible = false;
        mIsRecoSuspended = false;
    }
    return success;
}

- (BOOL) doDeinitTrackers
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    trackerManager.deinitTracker(Vuforia::ObjectTracker::getClassType());
    trackerManager.deinitTracker(Vuforia::PositionalDeviceTracker::getClassType());
    return YES;
}

- (void) autofocus:(UITapGestureRecognizer *)sender
{
    [self performSelector:@selector(cameraPerformAutoFocus) withObject:nil afterDelay:.4];
}

- (void) cameraPerformAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_TRIGGERAUTO);
    
    // After triggering an autofocus event,
    // we must restore the previous focus mode
    if (continuousAutofocusEnabled)
    {
        [self performSelector:@selector(restoreContinuousAutoFocus) withObject:nil afterDelay:2.0];
    }
}

- (void) restoreContinuousAutoFocus
{
    Vuforia::CameraDevice::getInstance().setFocusMode(Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO);
}

- (void) doubleTapGestureAction:(UITapGestureRecognizer*)theGesture
{
    if (!self.showingMenu)
    {
        [self performSegueWithIdentifier: @"PresentMenu" sender: self];
    }
}

- (void) swipeGestureAction:(UISwipeGestureRecognizer*)gesture
{
    if (!self.showingMenu)
    {
        [self performSegueWithIdentifier:@"PresentMenu" sender:self];
    }
}

- (BOOL) setDeviceTrackerEnabled:(BOOL)enable
{
    BOOL result = YES;
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*>
    (Vuforia::TrackerManager::getInstance().getTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    
    if (deviceTracker == nullptr)
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
    return false;
}

- (void) menuDidExit
{
    self.showingMenu = NO;
}


#pragma mark - Navigation

- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue isKindOfClass:[PresentMenuSegue class]])
    {
        UIViewController *dest = [segue destinationViewController];
        if ([dest isKindOfClass:[SampleAppMenuViewController class]])
        {
            self.showingMenu = YES;
            
            SampleAppMenuViewController *menuVC = (SampleAppMenuViewController *)dest;
            menuVC.menuDelegate = self;
            menuVC.sampleAppFeatureName = @"Model Targets";
            menuVC.dismissItemName = @"Vuforia Samples";
            menuVC.backSegueId = @"BackToModelTargetsTrained";
            
            // initialize menu item values (ON / OFF)
            [menuVC setValue:continuousAutofocusEnabled forMenuItem:@"Autofocus"];
        }
    }
}

@end
