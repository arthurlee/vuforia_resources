/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>

#import <Vuforia/UIGLViewProtocol.h>

#import "Texture.h"
#import "SampleApplicationSession.h"
#import "SampleApplication3DModel.h"
#import "SampleGLResourceHandler.h"
#import "SampleAppRenderer.h"
#import "SampleUIUtils.h"

#define kNumAugmentationTextures 1

// EAGLView is a subclass of UIView and conforms to the informal protocol
// UIGLViewProtocol
@interface VuMarkEAGLView : UIView <UIGLViewProtocol, SampleGLResourceHandler, SampleAppRendererControl>
{
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
    GLint texSampler2DHandle;
    GLint calphaHandle;
    
    // Texture used when rendering augmentation
    Texture* augmentationTexture[kNumAugmentationTextures];
    
    BOOL offTargetTrackingEnabled;
    SampleApplication3DModel * buildingModel;
    
    UILabel * cardIdLabel;
    UILabel * cardTypeLabel;
    UIImageView * vuMarkImage;
    NSString * currentVumarkIdOnCard;
    
    CGFloat padding;
    CGFloat textBoxWidth;
    CGFloat textBoxHeight;
    CGFloat textLabelHeight;
    
    UIView * cardView;
    CGRect cardFrameVisible;
    CGRect cardFrameHidden;
    bool cardViewVisible;
    
    SampleAppRenderer * sampleAppRenderer;

}

- (id) initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *)app andSampleUIUpdater:(id<SampleAppsUIControl>)sampleAppsUIControl;

- (void) finishOpenGLESCommands;
- (void) freeOpenGLESResources;

- (void) setOffTargetTrackingMode:(BOOL) enabled;
- (void) configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth viewHeight:(float)viewHeight;
- (void) updateRenderingPrimitives;
@end
