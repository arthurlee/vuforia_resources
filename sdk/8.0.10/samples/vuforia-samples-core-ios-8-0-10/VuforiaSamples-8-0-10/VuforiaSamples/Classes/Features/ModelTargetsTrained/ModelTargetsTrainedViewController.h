/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import "ModelTargetsTrainedEAGLView.h"
#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"
#import <Vuforia/TargetFinder.h>
#import <Vuforia/ModelTarget.h>
#import <chrono>

@interface ModelTargetsTrainedViewController : UIViewController <SampleApplicationControl, SampleAppMenuDelegate, ModelTargetsUIControl, SampleAppsUIControl> {
    
    Vuforia::TargetFinder* mTargetFinder;
    Vuforia::ModelTarget* mActiveModelTarget;
    
    bool mIsRecoPossible;
    bool mIsRecoSuspended;
    // menu options
    BOOL continuousAutofocusEnabled;
}

-(IBAction) resetTracking:(id)sender;

@property (nonatomic, strong) ModelTargetsTrainedEAGLView* eaglView;
@property (nonatomic, strong) UITapGestureRecognizer * tapGestureRecognizer;
@property (nonatomic, strong) SampleApplicationSession * vapp;

@property (nonatomic, readwrite) BOOL showingMenu;

@end
