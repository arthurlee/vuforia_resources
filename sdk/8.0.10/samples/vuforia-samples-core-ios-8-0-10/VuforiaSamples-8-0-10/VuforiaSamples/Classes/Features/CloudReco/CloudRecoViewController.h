/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import "CloudRecoEAGLView.h"
#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"
#import <Vuforia/DataSet.h>
#import <Vuforia/TargetFinder.h>

@interface CloudRecoViewController : UIViewController <SampleApplicationControl, SampleAppMenuDelegate, UIAlertViewDelegate, SampleAppsUIControl>
{
    
    BOOL scanningMode;
    BOOL isVisualSearchOn;
    BOOL resetTargetFinderTrackables;
    
    int lastErrorCode;
    
    // menu options
    BOOL deviceTrackerEnabled;
    BOOL continuousAutofocusEnabled;
    BOOL flashEnabled;
    Vuforia::TargetFinder* mTargetFinder;
}

- (BOOL) isVisualSearchOn;
- (void) toggleVisualSearch;

@end
