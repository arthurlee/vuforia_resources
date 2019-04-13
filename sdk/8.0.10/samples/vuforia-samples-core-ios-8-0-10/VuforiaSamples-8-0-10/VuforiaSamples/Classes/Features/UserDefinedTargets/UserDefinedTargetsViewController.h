/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import "UserDefinedTargetsEAGLView.h"
#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"
#import "CustomToolbar.h"
#import <Vuforia/DataSet.h>

@interface UserDefinedTargetsViewController : UIViewController <SampleApplicationControl, CustomToolbarDelegateProtocol, SampleAppMenuDelegate, SampleAppsUIControl>
{
    Vuforia::DataSet *dataSetUserDef;
    RefFreeFrame *refFreeFrame;
    
    // menu options
    BOOL deviceTrackerEnabled;
    BOOL continuousAutofocusEnabled;
    BOOL flashEnabled;
}

@end
