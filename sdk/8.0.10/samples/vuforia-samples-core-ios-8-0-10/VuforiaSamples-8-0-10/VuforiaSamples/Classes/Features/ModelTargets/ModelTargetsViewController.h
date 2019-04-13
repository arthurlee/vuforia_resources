/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>

#import <Vuforia/DataSet.h>

#import "ModelTargetsEAGLView.h"
#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"

@interface ModelTargetsViewController : UIViewController <SampleApplicationControl, SampleAppMenuDelegate, SampleAppsUIControl>
{
    
    Vuforia::DataSet*  dataSetCurrent;
    
    // menu options
    BOOL continuousAutofocusEnabled;
}

-(IBAction) resetTracking:(id)sender;

@end
