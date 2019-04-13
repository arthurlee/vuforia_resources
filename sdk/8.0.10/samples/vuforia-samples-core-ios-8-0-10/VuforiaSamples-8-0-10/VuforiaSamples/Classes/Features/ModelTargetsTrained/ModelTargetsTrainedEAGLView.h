/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import <Vuforia/CameraDevice.h>
#import <Vuforia/ModelTarget.h>
#import <Vuforia/UIGLViewProtocol.h>

#import "Modelv3d.h"
#import "SampleApplicationSession.h"
#import "SampleAppRenderer.h"
#import "SampleGLResourceHandler.h"
#import "SampleUIUtils.h"
#import "Texture.h"

typedef enum guideViewStatus
{
    PASSIVE,
    RECOGNIZED,
    SNAPPED
} GuideViewStatus;

typedef enum guideViewModels
{
    LANDER,
    BIKE
} GuideViewModels;

// Required to set UI changes
@protocol ModelTargetsUIControl
@required
// This method is called to update the guide view status UI of the recognized/snapped target
- (void)setStatusImageForModel:(GuideViewModels)guideViewModel withState:(GuideViewStatus)status;
@end

// EAGLView is a subclass of UIView and conforms to the informal protocol
// UIGLViewProtocol
@interface ModelTargetsTrainedEAGLView : UIView <UIGLViewProtocol, SampleGLResourceHandler, SampleAppRendererControl> {
}

- (id)initWithFrame:(CGRect)frame
                appSession:(SampleApplicationSession *)app
     modelTargetsUIUpdater:(id<ModelTargetsUIControl>)uiUpdater
        andSampleUIUpdater:(id<SampleAppsUIControl>)sampleAppsUIControl;

- (void)setTrackableForGuideView:(Vuforia::ModelTarget *)trackable;
- (void)resetTracking;

- (void) configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth viewHeight:(float)viewHeight;
- (void) changeOrientation:(UIInterfaceOrientation)ARViewOrientation;
- (void) updateRenderingPrimitives;
@end
