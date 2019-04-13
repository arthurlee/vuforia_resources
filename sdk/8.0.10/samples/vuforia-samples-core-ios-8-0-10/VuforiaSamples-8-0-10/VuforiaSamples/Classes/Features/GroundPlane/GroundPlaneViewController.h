/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import "GroundPlaneEAGLView.h"
#import "SampleApplicationSession.h"
#import "SampleAppMenuViewController.h"
#import "ToastView.h"
#import <Vuforia/DataSet.h>

@interface GroundPlaneViewController : UIViewController <SampleApplicationControl, SampleAppMenuDelegate, GroundPlaneUIControl, UIGestureRecognizerDelegate>
{
    
    // menu options
    BOOL continuousAutofocusEnabled;

    // Enable/disable scaling, disabled by default unless modified in the code
    BOOL enableProductScaling;
}

-(IBAction) resetTracking:(id)sender;
-(IBAction) setInteractiveMode:(id)sender;
-(IBAction) setMidAirMode:(id)sender;

@property (weak, nonatomic) IBOutlet UIButton *interactiveModeButton;
@property (weak, nonatomic) IBOutlet UIButton *midAirModeButton;
@property (weak, nonatomic) IBOutlet UIButton *furnitureModeButton;
@property (weak, nonatomic) IBOutlet UIView *instructionView;
@property (weak, nonatomic) IBOutlet UILabel *instructionLabel;
@property (weak, nonatomic) IBOutlet UILabel *currentModeLabel;
@property (weak, nonatomic) IBOutlet UIImageView *currentModeImage;
@property (weak, nonatomic) IBOutlet UIButton *resetButton;
@property (weak, nonatomic) IBOutlet ToastView *toastView;

@property (nonatomic, strong) GroundPlaneEAGLView* eaglView;
@property (nonatomic, strong) UITapGestureRecognizer * tapGestureRecognizer;
@property (nonatomic, strong) SampleApplicationSession * vapp;

@property (nonatomic, readwrite) BOOL showingMenu;
@property (nonatomic, readwrite) InstructionsStates mInstructionsState;

@end
