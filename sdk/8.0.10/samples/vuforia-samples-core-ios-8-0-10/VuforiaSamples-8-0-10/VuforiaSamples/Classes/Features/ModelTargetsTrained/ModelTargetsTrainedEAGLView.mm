/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other 
countries.
===============================================================================*/

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>
#import <GLKit/GLKit.h>
#include <vector>

#import <Vuforia/Vuforia.h>
#import <Vuforia/Image.h>
#import <Vuforia/State.h>
#import <Vuforia/Tool.h>
#import <Vuforia/Renderer.h>
#import <Vuforia/TrackableResult.h>
#import <Vuforia/ModelTargetResult.h>
#import <Vuforia/DeviceTrackableResult.h>

#import <Vuforia/VideoBackgroundConfig.h>
#import <Vuforia/ModelTarget.h>
#import <Vuforia/GuideView.h>

#import "ModelTargetsTrainedEAGLView.h"
#import "Texture.h"
#import "SampleApplicationUtils.h"
#import "SampleApplicationShaderUtils.h"
#import "Quad.h"


//******************************************************************************
// *** OpenGL ES thread safety ***
//
// OpenGL ES on iOS is not thread safe.  We ensure thread safety by following
// this procedure:
// 1) Create the OpenGL ES context on the main thread.
// 2) Start the Vuforia camera, which causes Vuforia to locate our EAGLView and start
//    the render thread.
// 3) Vuforia calls our renderFrameVuforia method periodically on the render thread.
//    The first time this happens, the defaultFramebuffer does not exist, so it
//    is created with a call to createFramebuffer.  createFramebuffer is called
//    on the main thread in order to safely allocate the OpenGL ES storage,
//    which is shared with the drawable layer.  The render (background) thread
//    is blocked during the call to createFramebuffer, thus ensuring no
//    concurrent use of the OpenGL ES context.
//
//******************************************************************************

@interface ModelTargetsTrainedEAGLView ()
{
    // OpenGL ES context
    EAGLContext* context;
    
    // Texture filenames
    NSArray<NSString*>* textureFilenames;

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
    
    // Texture used when rendering augmentation
    std::vector<Texture*> augmentationTextures;
    
    // Reference to the dataset to be used for the guide view
    Vuforia::ModelTarget* mCurrentModelTarget;
    
    // A lock used to synchronize Guide Views updates, since it is possible the render thread
    // uses an outdated target/index while it is being updated by the Target Finder
    NSLock* mGuideViewUpdate;
    
    Modelv3d* mKTMModel;
    Modelv3d* mLanderModel;
    
    SampleAppRenderer* sampleAppRenderer;
    
    Vuforia::Vec2F mGuideViewScale;
    
    // Handle to render the model targetguide view
    // showing the user where to view the object from to recognize it
    int guideViewHandle;
}

- (void)initShaders;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;
- (void)finishOpenGLESCommands;
- (void)freeOpenGLESResources;

@property (nonatomic, weak) SampleApplicationSession* vapp;
@property (nonatomic, readwrite) UIInterfaceOrientation mARViewOrientation;
@property (nonatomic, weak) id<ModelTargetsUIControl> modelTargetsUIUpdater;
@property (atomic, readwrite) BOOL updateGuideView;
@property (nonatomic, readwrite) BOOL isDeviceTrackerRelocalizing;
@property (nonatomic, weak) id<SampleAppsUIControl> uiControl;

@end


@implementation ModelTargetsTrainedEAGLView

@synthesize updateGuideView;

// You must implement this method, which ensures the view's underlying layer is
// of type CAEAGLLayer
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}

//------------------------------------------------------------------------------
#pragma mark - Lifecycle

- (id)initWithFrame:(CGRect)frame
                    appSession:(SampleApplicationSession *)app
         modelTargetsUIUpdater:(id<ModelTargetsUIControl>)modelTargetsUIUpdater
            andSampleUIUpdater:(id<SampleAppsUIControl>)sampleAppsUIControl
{
    self = [super initWithFrame:frame];
    
    if (self)
    {
        self.vapp = app;
        self.uiControl = sampleAppsUIControl;
        
        [self setContentScaleFactor:[UIScreen mainScreen].nativeScale];
        
        self.modelTargetsUIUpdater = modelTargetsUIUpdater;
        
        textureFilenames = [NSArray arrayWithObjects:@"Diffuse_Lander.png",
                                                     @"Diffuse_KTM.png",
                                                     nil];
        // Load the augmentation textures
        for (int i = 0; i < [textureFilenames count]; ++i)
        {
            augmentationTextures.push_back([[Texture alloc] initWithImageFile:textureFilenames[i]]);
        }

        // Create the OpenGL ES context
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        // The EAGLContext must be set for each thread that wishes to use it.
        // Set it the first time this method is called (on the main thread)
        if (context != [EAGLContext currentContext])
        {
            [EAGLContext setCurrentContext:context];
        }
        
        // Generate the OpenGL ES texture and upload the texture data for use
        // when rendering the augmentation
        for (int i = 0; i < [textureFilenames count]; ++i)
        {
            GLuint textureID;
            glGenTextures(1, &textureID);
            [augmentationTextures[i] setTextureID:textureID];
            glBindTexture(GL_TEXTURE_2D, textureID);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [augmentationTextures[i] width], [augmentationTextures[i] height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[augmentationTextures[i] pngData]);
        }

        sampleAppRenderer = [[SampleAppRenderer alloc]initWithSampleAppRendererControl:self nearPlane:0.01 farPlane:5];
        
        mLightIntensity = 0.8f; // Default light intensity for 3d models rendering
        
        [self loadModels];
        [self initShaders];
        
        // we initialize the rendering method of the SampleAppRenderer
        [sampleAppRenderer initRendering];
        
        mGuideViewScale = Vuforia::Vec2F(1.0f, 1.0f);
        guideViewHandle = -1;
        self.updateGuideView = YES;
    }
    
    return self;
}


- (void)setTrackableForGuideView:(Vuforia::ModelTarget *)trackable;
{
    // We use a lock to prevent the case where we use an incorrect guide view in renderFrame
    [mGuideViewUpdate lock];
    
    self.updateGuideView = YES;
    mCurrentModelTarget = trackable;
    
    [mGuideViewUpdate unlock];
}


- (void)resetTracking
{
    [self setTrackableForGuideView:nullptr];
}


- (CGSize)getCurrentARViewBoundsSize
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGSize viewSize = screenBounds.size;
    
    viewSize.width *= [UIScreen mainScreen].nativeScale;
    viewSize.height *= [UIScreen mainScreen].nativeScale;
    return viewSize;
}


- (void)dealloc
{
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == context)
    {
        [EAGLContext setCurrentContext:nil];
    }

    augmentationTextures.clear();
}


- (void) finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  The render loop has
    // been stopped, so we now make sure all OpenGL ES commands complete before
    // we (potentially) go into the background
    if (context)
    {
        [EAGLContext setCurrentContext:context];
        glFinish();
    }
}


- (void) freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Free easily
    // recreated OpenGL ES resources
    [self deleteFramebuffer];
    glFinish();
}


- (void) loadModels
{
    mKTMModel = [[Modelv3d alloc] init];
    [mKTMModel loadModel:@"KTM"];
    
    mLanderModel = [[Modelv3d alloc] init];
    [mLanderModel loadModel:@"Lander"];
}

- (void) updateRenderingPrimitives
{
    [sampleAppRenderer updateRenderingPrimitives];
}

- (void)changeOrientation:(UIInterfaceOrientation)ARViewOrientation
{
    self.mARViewOrientation = ARViewOrientation;
    [self updateRenderingPrimitives];
}


//------------------------------------------------------------------------------
#pragma mark - UIGLViewProtocol methods

// Draw the current frame using OpenGL
//
// This method is called by Vuforia Engine when it wishes to render the current frame to
// the screen.
//
// *** Vuforia Engine will call this method periodically on a background thread ***
- (void) renderFrameVuforia
{
    if (!self.vapp.cameraIsStarted)
    {
        return;
    }
    
    [sampleAppRenderer renderFrameVuforia];
}


- (void) renderFrameWithState:(const Vuforia::State&)state
                projectMatrix:(Vuforia::Matrix44F&)projectionMatrix
{
    [self setFramebuffer];
    
    // Clear colour and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
 
    // Render video background and retrieve tracking state
    [sampleAppRenderer renderVideoBackgroundWithState:state];
    
    glEnable(GL_DEPTH_TEST);
    // We must detect if background reflection is active and adjust the culling direction.
    // If the reflection is active, this means the pose matrix has been reflected as well,
    // therefore standard counter clockwise face culling will result in "inside out" models.
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    Vuforia::ModelTarget * modelTarget;
    const Vuforia::GuideView* activeGuideView = nullptr;
    const Vuforia::Image *textureImage = nullptr;
    BOOL updateGuideViewTexture;
    
    // If the active guide view is not being updated then proceed
    [mGuideViewUpdate lock];

    modelTarget = mCurrentModelTarget;
    updateGuideViewTexture = guideViewHandle == -1 || self.updateGuideView;
    self.updateGuideView = NO;
    
    [mGuideViewUpdate unlock];
    
    // If a new guide view has to be rendered due to a target finder update we update the guide view texture
    if(updateGuideViewTexture)
    {
        if (modelTarget && !modelTarget->getGuideViews().empty())
        {
            const auto activeGuideViewIndex = modelTarget->getActiveGuideViewIndex();
            activeGuideView = modelTarget->getGuideViews().at(activeGuideViewIndex);

            if (activeGuideView && activeGuideView->getImage())
            {
                textureImage = activeGuideView->getImage();
                [self updateGuideViewTexture:textureImage];
            }
        }
    }

    // Set the device pose matrix as identity
    Vuforia::Matrix44F devicePoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    
    // Get the device pose and
    if (state.getDeviceTrackableResult() != nullptr)
    {
        if (state.getDeviceTrackableResult()->getStatus() != Vuforia::TrackableResult::NO_POSE)
        {
            devicePoseMatrix = Vuforia::Tool::convertPose2GLMatrix(state.getDeviceTrackableResult()->getPose());
            devicePoseMatrix = SampleApplicationUtils::Matrix44FTranspose(SampleApplicationUtils::Matrix44FInverse(devicePoseMatrix));
        }
        
        Vuforia::TrackableResult::STATUS_INFO currentStatusInfo = state.getDeviceTrackableResult()->getStatusInfo();
        // If the current status and the previous do not match then we update the state and UI
        if (self.isDeviceTrackerRelocalizing ^ (currentStatusInfo == Vuforia::TrackableResult::STATUS_INFO::RELOCALIZING))
        {
            self.isDeviceTrackerRelocalizing = !self.isDeviceTrackerRelocalizing;
            [self.uiControl setIsInRelocalizationState:self.isDeviceTrackerRelocalizing];
        }
    }
    
    bool foundModelTargetResult = false;
    
    // We set the UI status to snapped if the target is being tracked
    auto trackableResults = state.getTrackableResults();
    for (auto* res : trackableResults)
    {
        if (res->isOfType(Vuforia::ModelTargetResult::getClassType()) && res->getStatus() == Vuforia::TrackableResult::TRACKED)
        {
            foundModelTargetResult = true;
            
            if (modelTarget != nullptr)
            {
                GuideViewModels guideViewUIToUpdate = GuideViewModels::BIKE;
                if (strstr((modelTarget->getName()), "MarsLander"))
                {
                    guideViewUIToUpdate = GuideViewModels::LANDER;
                }
                
                [self.modelTargetsUIUpdater setStatusImageForModel:guideViewUIToUpdate withState:GuideViewStatus::SNAPPED];
            }
            
            break;
        }
    }

    // If we are not tracking a target then we render the guide view
    if (!foundModelTargetResult && modelTarget != nullptr)
    {
        const int matrixSize = 16; //4x4 matrix
        float modelMatrix[matrixSize];
        SampleApplicationUtils::setIdentityMatrix(modelMatrix);
        
        if(self.mARViewOrientation == UIInterfaceOrientationPortraitUpsideDown ||
           self.mARViewOrientation == UIInterfaceOrientationLandscapeLeft)
        {
            mGuideViewScale.data[0] *= -1.0f;
            mGuideViewScale.data[1] *= -1.0f;
        }
        
        Vuforia::Vec4F color = Vuforia::Vec4F(1.0f, 1.0f, 1.0f, 1.0f);
        
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);

        float orthoProjMatrix[matrixSize];
        SampleApplicationUtils::setOrthoMatrix(-1.f, 1.f, -1.f, 1.f, 0, 1, orthoProjMatrix);
        
        [self renderPlaneTexturedWithProjectionMatrix:orthoProjMatrix MVP:modelMatrix Scale:mGuideViewScale Colour:color andTextureHandle:guideViewHandle];
         
        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);
        
        SampleApplicationUtils::checkGlError("Render Frame, no trackables");
        
    }
    // If a target is being tracked we render the augmentation
    else if (foundModelTargetResult)
    {
        auto illumination = state.getIllumination();
        if (illumination != nullptr)
        {
            float ambientIntensity = illumination->getAmbientIntensity();
            if (ambientIntensity != Vuforia::Illumination::AMBIENT_INTENSITY_UNAVAILABLE)
            {
                // We set the model lighting considering the min and max lumens values in the sample to 200 - 1500
                // In our sample 200 lumens is considered low brightness, 200 lumens in real life is similar to a dimmed light bulb;
                // 1500 lumens is considered bright, in real life as bright as a standard light bulb.
                // These values are used specifically for the samples but higher values could be obtained from brighter sources
                mLightIntensity = fmin(1.5f, .4f + (ambientIntensity - 200.0f) / 1300.0f);
            }
        }
        
        BOOL isKTMCurrentModel = YES;
        if(modelTarget && strstr((modelTarget->getName()), "MarsLander"))
        {
            isKTMCurrentModel = NO;
        }
        Modelv3d *currentModel = isKTMCurrentModel ? mKTMModel : mLanderModel;
        int textureId = augmentationTextures[isKTMCurrentModel ? 1 : 0].textureID;

        Vuforia::Matrix44F modelMatrix = SampleApplicationUtils::Matrix44FIdentity();
        
        for (auto* result : trackableResults)
        {
            if (! result->isOfType(Vuforia::ModelTargetResult::getClassType()))
            {
                continue;
            }
            modelMatrix = Vuforia::Tool::convertPose2GLMatrix(result->getPose());
            
            [self renderModel: currentModel withTextureId: textureId andProjection:&projectionMatrix.data[0] andViewMatrix:&devicePoseMatrix.data[0] andModelMatrix:&modelMatrix.data[0]];
            
            SampleApplicationUtils::checkGlError("EAGLView renderFrameVuforia");
        }
    }
    
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    [self presentFramebuffer];
}


- (void)updateGuideViewTexture:(const Vuforia::Image*)guideViewTextureImage
{
    if (guideViewHandle > 0)
    {
        SampleApplicationUtils::updateTexture(guideViewHandle, guideViewTextureImage);
    }
    else
    {
        guideViewHandle = SampleApplicationUtils::createTexture(guideViewTextureImage);
    }

    float guideViewAspectRatio = (float)guideViewTextureImage->getWidth() / guideViewTextureImage->getHeight();
    float cameraAspectRatio = (float)self.frame.size.width / self.frame.size.height;
    
    // doing this calculatio in world space, at an assumed camera near plane distance of 0.01f;
    // this is also what the Unity rendering code does
    float planeDistance = 0.01f;
    float fieldOfView = Vuforia::CameraDevice::getInstance().getCameraCalibration().getFieldOfViewRads().data[1];
    float nearPlaneHeight = 2.0f * planeDistance * tanf(fieldOfView * 0.5f);
    float nearPlaneWidth = nearPlaneHeight * cameraAspectRatio;
    
    float planeWidth;
    float planeHeight;
    
    if(guideViewAspectRatio >= 1.0f && cameraAspectRatio >= 1.0f) // guideview landscape, camera landscape
    {
        // scale so that the long side of the camera (width)
        // is the same length as guideview width
        planeWidth = nearPlaneWidth;
        planeHeight = planeWidth / guideViewAspectRatio;
    }
    
    else if(guideViewAspectRatio < 1.0f && cameraAspectRatio < 1.0f) // guideview portrait, camera portrait
    {
        // scale so that the long side of the camera (height)
        // is the same length as guideview height
        planeHeight = nearPlaneHeight;
        planeWidth = planeHeight * guideViewAspectRatio;
    }
    else if (cameraAspectRatio < 1.0f) // guideview landscape, camera portrait
    {
        // scale so that the long side of the camera (height)
        // is the same length as guideview width
        planeWidth = nearPlaneHeight;
        planeHeight = planeWidth / guideViewAspectRatio;
        
    }
    else // guideview portrait, camera landscape
    {
        // scale so that the long side of the camera (width)
        // is the same length as guideview height
        planeHeight = nearPlaneWidth;
        planeWidth = planeHeight * guideViewAspectRatio;
    }
    
    // normalize world space plane sizes into view space again
    mGuideViewScale = Vuforia::Vec2F(planeWidth / nearPlaneWidth, -planeHeight / nearPlaneHeight);
}


- (void)renderModel: (Modelv3d*) model withTextureId: (int) textureId andProjection: (float*) projectionMatrix andViewMatrix: (float*) viewMatrix andModelMatrix: (float*) modelMatrix
{
    // OpenGL 2
    Vuforia::Matrix44F modelViewProjection;
    
    // Combine device pose (view matrix) with model matrix
    SampleApplicationUtils::multiplyMatrix(viewMatrix, modelMatrix,  modelMatrix);
    
    // Do the final combination with the projection matrix
    SampleApplicationUtils::multiplyMatrix(projectionMatrix, modelMatrix, &modelViewProjection.data[0]);
    
    // Activate the shader program and bind the vertex/normal/tex coords
    glUseProgram(shaderProgramID);
    
    glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)model.vertices);
    glVertexAttribPointer(normalHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)model.normals);
    glVertexAttribPointer(textureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)model.texCoords);
    
    glEnableVertexAttribArray(vertexHandle);
    glEnableVertexAttribArray(normalHandle);
    glEnableVertexAttribArray(textureCoordHandle);
    
    // Choose the texture based on the target name
    
    glActiveTexture(GL_TEXTURE0);
    
    glBindTexture(GL_TEXTURE_2D, textureId);
    
    // Pass the model view matrix to the shader
    glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjection.data[0]);
    glUniformMatrix4fv(mvMatrixHandle, 1, GL_FALSE, (const GLfloat*)modelMatrix);
    
    GLKMatrix4 mvMatrix = GLKMatrix4MakeWithArray(modelMatrix);
    bool isInvertible;
    GLKMatrix4 normalMatrix = GLKMatrix4InvertAndTranspose ( mvMatrix, &isInvertible );
    glUniformMatrix4fv(normalMatrixHandle, 1, GL_FALSE, normalMatrix.m);
    
    glUniform4f(lightPositionHandle, 0.2f, 1.0f, -0.5f, 1.0f);
    glUniform4f(lightColorHandle, mLightIntensity, mLightIntensity, mLightIntensity, 1.0f);
    
    GLfloat groupDiffuseColors[] = {0.64f, 0.64f, 0.64f, 1.0f};
    glUniform4fv(objMtlGroupDiffuseColorsHandle, 1, groupDiffuseColors);
    
    glUniform1i(texSampler2DHandle, 0 /*GL_TEXTURE0*/);
    
    // Draw the model
    glDrawArrays(GL_TRIANGLES, 0, (int)model.nbVertices);
    
    // Disable the enabled arrays
    glDisableVertexAttribArray(vertexHandle);
    glDisableVertexAttribArray(normalHandle);
    glDisableVertexAttribArray(textureCoordHandle);
}

-(void)renderPlaneTexturedWithProjectionMatrix:(float *)projectionMatrix MVP:(float *)modelViewMatrix Scale:(Vuforia::Vec2F)scale Colour:(Vuforia::Vec4F)colour andTextureHandle:(int)textureHandle
{
    float modelViewProjectionMatrix[16];
    float scaledModelMatrixArray[16];
    
    for(int i=0; i<16; i++) {
        scaledModelMatrixArray[i] = modelViewMatrix[i];
    }
    
    SampleApplicationUtils::scalePoseMatrix(scale.data[0], scale.data[1], 1.0, scaledModelMatrixArray);
    SampleApplicationUtils::multiplyMatrix(projectionMatrix, scaledModelMatrixArray, modelViewProjectionMatrix);
    
    //glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureHandle);
    
    glEnableVertexAttribArray(planeVertexHandle);
    glVertexAttribPointer(planeVertexHandle, 3, GL_FLOAT, false, 0, quadVertices);
    
    glEnableVertexAttribArray(planeTextureCoordHandle);
    glVertexAttribPointer(planeTextureCoordHandle, 2, GL_FLOAT, false, 0, quadTexCoords);
    
    glUseProgram(planeShaderProgramID);
    glUniformMatrix4fv(planeMvpMatrixHandle, 1, false, modelViewProjectionMatrix);
    glUniform4f(planeColorHandle, colour.data[0], colour.data[1], colour.data[2], colour.data[3]);
    glUniform1i(planeTexSampler2DHandle, 0);
    
    // Draw
    glDrawElements(GL_TRIANGLES, kNumQuadIndices, GL_UNSIGNED_SHORT, quadIndices);
    
    // disable input data structures
    
    glDisableVertexAttribArray(planeTextureCoordHandle);
    glDisableVertexAttribArray(planeVertexHandle);
    glUseProgram(0);
    
    glBindTexture(GL_TEXTURE_2D, 0);
    
    glDisable(GL_BLEND);
}

- (void) configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth viewHeight:(float)viewHeight
{
    [self deleteFramebuffer];
    [sampleAppRenderer configureVideoBackgroundWithCameraMode:[self.vapp getCameraMode]
                                                    viewWidth:viewWidth
                                                   viewHeight:viewHeight];
}

//------------------------------------------------------------------------------
#pragma mark - OpenGL ES management

- (void)initShaders
{
    shaderProgramID = [SampleApplicationShaderUtils createProgramWithVertexShaderFileName:@"DiffuseLight.vertsh"
                                                   fragmentShaderFileName:@"DiffuseLight.fragsh"];

    if (0 < shaderProgramID) {
        vertexHandle = glGetAttribLocation(shaderProgramID, "vertexPosition");
        normalHandle = glGetAttribLocation(shaderProgramID, "vertexNormal");
        textureCoordHandle = glGetAttribLocation(shaderProgramID, "vertexTexCoord");
        mvpMatrixHandle = glGetUniformLocation(shaderProgramID, "u_mvpMatrix");
        mvMatrixHandle = glGetUniformLocation(shaderProgramID,"u_mvMatrix");
        normalMatrixHandle = glGetUniformLocation(shaderProgramID,"u_normalMatrix");
        lightPositionHandle = glGetUniformLocation(shaderProgramID,"u_lightPos");
        lightColorHandle = glGetUniformLocation(shaderProgramID,"u_lightColor");
        texSampler2DHandle  = glGetUniformLocation(shaderProgramID,"texSampler2D");
        objMtlGroupDiffuseColorsHandle = glGetUniformLocation(shaderProgramID, "u_groupDiffuseColors");
        
    }
    else {
        NSLog(@"Could not initialise augmentation shader");
    }

    planeShaderProgramID = [SampleApplicationShaderUtils createProgramWithVertexShaderFileName:@"Simple.vertsh"
                                                                   fragmentShaderFileName:@"SimpleTexturedColor.fragsh"];
    
    if (0 < planeShaderProgramID) {
        planeVertexHandle = glGetAttribLocation(planeShaderProgramID, "vertexPosition");
        planeNormalHandle = glGetAttribLocation(planeShaderProgramID, "vertexNormal");
        planeTextureCoordHandle = glGetAttribLocation(planeShaderProgramID, "vertexTexCoord");
        planeMvpMatrixHandle = glGetUniformLocation(planeShaderProgramID, "modelViewProjectionMatrix");
        planeTexSampler2DHandle  = glGetUniformLocation(planeShaderProgramID,"texSampler2D");
        planeColorHandle = glGetUniformLocation(planeShaderProgramID,"color");
    }
    else {
        NSLog(@"Could not initialise viewpoint shader");
    }
}


- (void)createFramebuffer
{
    if (context) {
        // Create default framebuffer object
        glGenFramebuffers(1, &defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        GLint framebufferWidth;
        GLint framebufferHeight;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    }
}


- (void)deleteFramebuffer
{
    if (context) {
        [EAGLContext setCurrentContext:context];
        
        if (defaultFramebuffer) {
            glDeleteFramebuffers(1, &defaultFramebuffer);
            defaultFramebuffer = 0;
        }
        
        if (colorRenderbuffer) {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
            colorRenderbuffer = 0;
        }
        
        if (depthRenderbuffer) {
            glDeleteRenderbuffers(1, &depthRenderbuffer);
            depthRenderbuffer = 0;
        }
    }
}


- (void)setFramebuffer
{
    // The EAGLContext must be set for each thread that wishes to use it.  Set
    // it the first time this method is called (on the render thread)
    if (context != [EAGLContext currentContext]) {
        [EAGLContext setCurrentContext:context];
    }
    
    if (!defaultFramebuffer) {
        // Perform on the main thread to ensure safe memory allocation for the
        // shared buffer.  Block until the operation is complete to prevent
        // simultaneous access to the OpenGL context
        [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
}


- (BOOL)presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    return [context presentRenderbuffer:GL_RENDERBUFFER];
}

@end
