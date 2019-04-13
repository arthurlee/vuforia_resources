/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <UIKit/UIKit.h>

#import <Vuforia/CameraDevice.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/UIGLViewProtocol.h>

#import "Modelv3d.h"
#import "SampleApplicationSession.h"
#import "SampleAppRenderer.h"
#import "SampleGLResourceHandler.h"
#import "SampleUIUtils.h"
#import "Texture.h"

// EAGLView is a subclass of UIView and conforms to the informal protocol
// UIGLViewProtocol
@interface ModelTargetsEAGLView : UIView <UIGLViewProtocol, SampleGLResourceHandler, SampleAppRendererControl> {
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
    GLint objMtlGroupDiffuseColorsHandle;
    
    GLuint planeShaderProgramID;
    GLint planeVertexHandle;
    GLint planeNormalHandle;
    GLint planeTextureCoordHandle;
    GLint planeMvpMatrixHandle;
    GLint planeTexSampler2DHandle;
    GLint planeColorHandle;
    
    float mLightIntensity;
    
    // Reference to the dataset to be used for the guide view
    Vuforia::DataSet *mDataset;
    
    Modelv3d * mLanderModel;
    
    SampleAppRenderer * sampleAppRenderer;
}

- (id)initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app andSampleUIUpdater:(id<SampleAppsUIControl>)sampleAppsUIControl;
- (void)setDatasetForGuideView:(Vuforia::DataSet *)dataset;

- (void)finishOpenGLESCommands;
- (void)freeOpenGLESResources;

- (void) configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth viewHeight:(float)viewHeight;
- (void) changeOrientation:(UIInterfaceOrientation) ARViewOrientation;
- (void) updateRenderingPrimitives;
- (void) updateGuideView;
@end
