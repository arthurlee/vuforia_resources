/*===============================================================================
  Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.
 
 Vuforia is a trademark of PTC Inc., registered in the United States and other
 countries.
 ===============================================================================*/

#import "SampleAppAboutViewController.h"

@interface SampleAppAboutViewController ()
{
    UIInterfaceOrientation mNextVCOrientation;
}
@end

@implementation SampleAppAboutViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self loadWebView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dismissAppController:)
                                                 name:@"kDismissAppViewController"
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.navigationController.delegate = (id<UINavigationControllerDelegate>)self;
    
    // We ensure the navigation bar is shown
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    
    mNextVCOrientation = UIInterfaceOrientationPortrait;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    [self setUiWebView:nil];
}

- (IBAction)onStartButton:(id)sender
{
    NSString *appNameNoWhiteSpaces = [self.appTitle stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSString *segueId = [NSString stringWithFormat:@"Push%@", appNameNoWhiteSpaces];
    
    if ([appNameNoWhiteSpaces isEqualToString:@"ModelTargets"] ||
        [appNameNoWhiteSpaces isEqualToString:@"GroundPlane"] ||
        [appNameNoWhiteSpaces isEqualToString:@"ModelTargets(Trained)"])
    {
        mNextVCOrientation = UIInterfaceOrientationLandscapeRight;
    }
    
    [self performSegueWithIdentifier:segueId sender:self];
}


//------------------------------------------------------------------------------
#pragma mark - Autorotation
- (UIInterfaceOrientationMask)navigationControllerSupportedInterfaceOrientations:(UINavigationController *)navigationController
{
    UIInterfaceOrientationMask orientationMask = UIInterfaceOrientationMaskPortrait;
    
    if (mNextVCOrientation == UIInterfaceOrientationLandscapeRight)
    {
        orientationMask = UIInterfaceOrientationMaskLandscapeRight;
    }
    
    return orientationMask;
}

- (UIInterfaceOrientation)navigationControllerPreferredInterfaceOrientationForPresentation:(UINavigationController *)navigationController
{
    return mNextVCOrientation;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    UIInterfaceOrientationMask orientationMask = UIInterfaceOrientationMaskPortrait;
    
    if (mNextVCOrientation == UIInterfaceOrientationLandscapeRight)
    {
        orientationMask = UIInterfaceOrientationMaskLandscapeRight;
    }
    
    return orientationMask;
}

- (BOOL)shouldAutorotate
{
    return NO;
}


//------------------------------------------------------------------------------
#pragma mark - Private

- (void) dismissAppController:(id) sender
{
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)loadWebView
{
    self.uiWebView.delegate = self;
    
    //  Load html from a local file for the about screen
    NSString *aboutFilePath = [[NSBundle mainBundle] pathForResource:self.appAboutPageName
                                                              ofType:@"html"];
    
    NSString* htmlString = [NSString stringWithContentsOfFile:aboutFilePath
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    
    NSString *aPath = [[NSBundle mainBundle] bundlePath];
    NSURL *anURL = [NSURL fileURLWithPath:aPath];
    [self.uiWebView loadHTMLString:htmlString baseURL:anURL];
}


//------------------------------------------------------------------------------
#pragma mark - UIWebViewDelegate

-(BOOL) webView:(UIWebView *)inWeb shouldStartLoadWithRequest:(NSURLRequest *)inRequest navigationType:(UIWebViewNavigationType)inType
{
    //  Opens the links within this UIWebView on a safari web browser
    
    BOOL retVal = NO;
    
    if ( inType == UIWebViewNavigationTypeLinkClicked )
    {
        [[UIApplication sharedApplication] openURL:[inRequest URL]];
    }
    else
    {
        retVal = YES;
    }
    
    return retVal;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    // Uncomment to have the double finger tap show the build number
//    UITapGestureRecognizer *gesture = [[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleTouches:)] autorelease];
//    gesture.numberOfTouchesRequired = 2;
//    [webView addGestureRecognizer:gesture];
}

- (void) handleTouches:(UILongPressGestureRecognizer *)gesture {
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    
    UIAlertController *uiAlertController =
    [UIAlertController alertControllerWithTitle:@"Application Version Number"
                                        message:[NSString stringWithFormat:@"Build number is: %@", version]
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *defaultAction =
    [UIAlertAction actionWithTitle:@"OK"
                             style:UIAlertActionStyleDefault
                           handler:^(UIAlertAction *action) {
                               
                           }];
    
    [uiAlertController addAction:defaultAction];
    [self presentViewController:uiAlertController animated:YES completion:nil];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // We rotate to the intended orientation per each VC
    [[UIDevice currentDevice] setValue:@(mNextVCOrientation) forKey:@"orientation"];
    [UINavigationController attemptRotationToDeviceOrientation];
}

@end
