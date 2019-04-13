/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import <Vuforia/DataSet.h>

#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"
#import "VuMarkEAGLView.h"

@interface VuMarkViewController : UIViewController <SampleApplicationControl, SampleAppMenuDelegate, SampleAppsUIControl>
{
    Vuforia::DataSet*  dataSetCurrent;
    Vuforia::DataSet*  dataSetLoaded;
    
    // menu options
    BOOL deviceTrackerEnabled;
    BOOL continuousAutofocusEnabled;
}

@end
