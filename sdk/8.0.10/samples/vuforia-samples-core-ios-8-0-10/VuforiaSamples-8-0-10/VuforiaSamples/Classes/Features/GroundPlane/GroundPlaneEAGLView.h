/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>
#import <math.h>

#import <Vuforia/UIGLViewProtocol.h>

#import "Texture.h"
#import "SampleApplicationSession.h"
#import "Modelv3d.h"
#import "SampleGLResourceHandler.h"
#import "SampleAppRenderer.h"
#import <Vuforia/Anchor.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/CameraDevice.h>
#import <Vuforia/TrackableResult.h>

#define kNumAugmentationTextures 8

typedef enum sampleAppModeTypes
{
    SAMPLE_APP_INTERACTIVE_MODE,
    SAMPLE_APP_MIDAIR_MODE,
    SAMPLE_APP_FURNITURE_MODE,
} SampleAppMode;

typedef enum sampleInstructionsStates {
    POINT_TO_GROUND,
    TAP_TO_PLACE,
    GESTURES_INSTRUCTIONS,
    PRODUCT_PLACEMENT,
    UNABLE_TO_PLACE_ANCHOR,
    UNDEFINED
} InstructionsStates;

typedef enum sampleProductPlacementStates{
    TRANSLATING,
    ROTATE_SCALE,
    IDLE
} ProductPlacementStates;

// Required to set UI changes
@protocol GroundPlaneUIControl
@required
// This method is called to notify that ground plane initialization is complete
- (void) setInstructionsState:(InstructionsStates)instructionsState;
- (void) setStatusInfo:(Vuforia::TrackableResult::STATUS_INFO)statusInfo;
@end

// EAGLView is a subclass of UIView and conforms to the informal protocol
// UIGLViewProtocol
@interface GroundPlaneEAGLView : UIView <UIGLViewProtocol, SampleGLResourceHandler, SampleAppRendererControl> {
@private
    // OpenGL ES context
    EAGLContext *context;
    
    // The OpenGL ES names for the framebuffer and renderbuffers used to render
    // to this view
    GLuint defaultFramebuffer;
    GLuint colorRenderbuffer;
    GLuint depthRenderbuffer;

    // Shader handles
    GLuint shaderProgramID;
    GLint vertexHandle;
    GLint normalHandle;
    GLint textureCoordHandle;
    GLint mvpMatrixHandle;
    GLint mvMatrixHandle;
    GLint normalMatrixHandle;
    GLint lightPositionHandle;
    GLint lightColorHandle;
    GLint texSampler2DHandle;
    
    GLuint materialsLightingProgramID;
    GLint materialsLightingVertexHandle;
    GLint materialsLightingNormalHandle;
    GLint materialsLightingMvpMatrixHandle;
    GLint materialsLightingMvMatrixHandle;
    GLint materialsLightingNormalMatrixHandle;
    GLint materialsLightingLightPositionHandle;
    GLint materialsLightingLightColorHandle;
    GLint materialsLightingLightVertexExtraHandle;

    GLuint planeShaderProgramID;
    GLint planeVertexHandle;
    GLint planeNormalHandle;
    GLint planeTextureCoordHandle;
    GLint planeMvpMatrixHandle;
    GLint planeTexSampler2DHandle;
    GLint planeColorHandle;
    
    float mLightIntensity;
    
    // Tracking state confidence & degradation
    Vuforia::TrackableResult::STATUS_INFO mCurrentStatusInfo;
    
    // Texture used when rendering augmentation
    Texture* augmentationTexture[kNumAugmentationTextures];
    
    Modelv3d* mAstronaut;
    Modelv3d* mDrone;
    Modelv3d* mFurniture;
    
    SampleAppRenderer * sampleAppRenderer;
    
    // Device and smart terrain poses
    Vuforia::Matrix44F mDevicePoseMatrix;
    Vuforia::Matrix44F mHitTestPoseMatrix;
    Vuforia::Matrix44F mMidAirPoseMatrix;
    Vuforia::Matrix44F mFurniturePoseMatrix;
    Vuforia::Matrix44F mFurnitureTranslationPoseMatrix;
    Vuforia::Matrix44F mReticlePose;
    
    // Anchor for registering content with latest hit test result
    Vuforia::Anchor* mHitTestAnchor;
    Vuforia::Anchor* mMidAirAnchor;
    Vuforia::Anchor* mFurnitureAnchor;
    BOOL mSetDroneNewPosition;
    BOOL mSetAnchorPosition;
    BOOL mResetGroundPlaneStateAndAnchors;
    unsigned int mAnchorResultsCount;
    BOOL mIsFurniturePlaced;
    BOOL mIsFurnitureBeingDragged;
    
    SampleAppMode mCurrentMode;
    ProductPlacementStates mProductPlacementState;
    CGPoint mCurrentTouch;
    float mProductScale;
    float mProductRotation;
    float mPreviousProductScale;
    float mPreviousProductRotation;
}

- (id)initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app andUIUpdater:(id<GroundPlaneUIControl>) uiUpdater;

- (void)finishOpenGLESCommands;
- (void)freeOpenGLESResources;

- (void) configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth viewHeight:(float)viewHeight;
- (void) changeOrientation:(UIInterfaceOrientation) ARViewOrientation;
- (void) updateRenderingPrimitives;
- (void) performTap;
- (BOOL) performHitTestWithNormalizedTouchPointX: (float)normalizedTouchPointX andNormalizedTouchPointY: (float)normalizedTouchPointY withDeviceHeightInMeters: (float) deviceHeightInMeters  toCreateAnchor: (BOOL)createAnchor andStateToUse: (const Vuforia::State&) state;
- (void) setInteractiveMode;
- (void) setMidAirMode;
- (void) setFurnitureMode;
- (void) rotateBy: (float)rotationDelta andGestureFinished:(BOOL)isGestureFinished;
- (void) scaleBy: (float)scaleDelta andGestureFinished:(BOOL)isGestureFinished;
- (unsigned int) getAnchorResultsCount;
- (void)setResetGroundPlaneStateAndAnchors;
@end
