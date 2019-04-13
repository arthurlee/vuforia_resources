/*===============================================================================
Copyright (c) 2018 PTC Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other
countries.
===============================================================================*/

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>
#import <GLKit/GLKit.h>

#import <Vuforia/AnchorResult.h>
#import <Vuforia/DeviceTrackableResult.h>
#import <Vuforia/HitTestResult.h>
#import <Vuforia/Image.h>
#import <Vuforia/PositionalDeviceTracker.h>
#import <Vuforia/Renderer.h>
#import <Vuforia/SmartTerrain.h>
#import <Vuforia/State.h>
#import <Vuforia/Tool.h>
#import <Vuforia/Trackable.h>
#import <Vuforia/TrackableResult.h>
#import <Vuforia/TrackerManager.h>
#import <Vuforia/VideoBackgroundConfig.h>
#import <Vuforia/Vuforia.h>

#import "GroundPlaneEAGLView.h"
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
// 2) Start the Vuforia Engine camera, which causes Vuforia Engine to locate our
//    EAGLView and start the render thread.
// 3) Vuforia Engine calls our renderFrameVuforia method periodically on the render thread.
//    The first time this happens, the defaultFramebuffer does not exist, so it
//    is created with a call to createFramebuffer.  createFramebuffer is called
//    on the main thread in order to safely allocate the OpenGL ES storage,
//    which is shared with the drawable layer.  The render (background) thread
//    is blocked during the call to createFramebuffer, thus ensuring no
//    concurrent use of the OpenGL ES context.
//
//******************************************************************************


namespace {
    // --- Data private to this unit ---

    // Teapot texture filenames
    const char* textureFilenames[] = {
        "astronaut.png",
        "drone.png",
        "interactive-reticle.png",
        "midair-reticle.png",
        "interactive-reticle-3d.png",
        "shadow.png",
        "translate-reticle.png",
        "rotate-reticle.png",
    };
    
    const char* MID_AIR_ANCHOR_NAME = "midAirAnchor";
    const char* HIT_TEST_ANCHOR_NAME = "hitTestAnchor";
    const char* FURNITURE_ANCHOR_NAME = "furnitureAnchor";
    
    // Define a default, assumed device height above the plane where you'd like to place content.
    // The world coordinate system will be scaled accordingly to meet this device height value
    // once you create the first successful anchor from a HitTestResult. If your users are adults
    // to place something on the floor use appx. 1.4m. For a tabletop experience use appx. 0.5m.
    // In apps targeted for kids reduce the assumptions to ~80% of these values.
    const float DEFAULT_HEIGHT_ABOVE_GROUND = 1.4f;
    
    const float MAX_PRODUCT_SCALE_FACTOR = 2.0f;
    const float MIN_PRODUCT_SCALE_FACTOR = .2f;
    
}


@interface GroundPlaneEAGLView ()

- (void)initShaders;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;

@property (nonatomic, weak) SampleApplicationSession * vapp;
@property (nonatomic, readwrite) UIInterfaceOrientation mARViewOrientation;
@property (nonatomic, weak) id<GroundPlaneUIControl> uiUpdater;

@end


@implementation GroundPlaneEAGLView

@synthesize vapp = vapp;

// You must implement this method, which ensures the view's underlying layer is
// of type CAEAGLLayer
+ (Class) layerClass
{
    return [CAEAGLLayer class];
}

- (unsigned int)getAnchorResultsCount
{
    return mAnchorResultsCount;
}

//------------------------------------------------------------------------------
#pragma mark - Lifecycle

- (id) initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app andUIUpdater:(id<GroundPlaneUIControl>) uiUpdater
{
    self = [super initWithFrame:frame];
    
    if (self)
    {
        self.vapp = app;

        [self setContentScaleFactor:[UIScreen mainScreen].nativeScale];

        self.uiUpdater = uiUpdater;
        [self.uiUpdater setInstructionsState:InstructionsStates::POINT_TO_GROUND];
        
        // Load the augmentation textures
        for (int i = 0; i < kNumAugmentationTextures; ++i)
        {
            augmentationTexture[i] = [[Texture alloc] initWithImageFile:[NSString stringWithCString:textureFilenames[i] encoding:NSASCIIStringEncoding]];
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
        for (int i = 0; i < kNumAugmentationTextures; ++i)
        {
            GLuint textureID;
            glGenTextures(1, &textureID);
            [augmentationTexture[i] setTextureID:textureID];
            glBindTexture(GL_TEXTURE_2D, textureID);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, [augmentationTexture[i] width], [augmentationTexture[i] height], 0, GL_RGBA, GL_UNSIGNED_BYTE, (GLvoid*)[augmentationTexture[i] pngData]);
        }

        sampleAppRenderer = [[SampleAppRenderer alloc]initWithSampleAppRendererControl:self nearPlane:0.01 farPlane:10.0];
        
        mLightIntensity = 0.8f; // Default light intensity for 3d models rendering
        mAstronaut = [self loadModelNamed:@"astronaut" withTransparency:1.f];
        mDrone = [self loadModelNamed:@"drone" withTransparency:1.f];
        mFurniture = [self loadModelNamed:@"chair" withTransparency:0.5f];
        [self initShaders];
        
        // we initialize the rendering method of the SampleAppRenderer
        [sampleAppRenderer initRendering];
        
        mDevicePoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
        mHitTestPoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
        mMidAirPoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
        mReticlePose = SampleApplicationUtils::Matrix44FIdentity();
        mSetDroneNewPosition = NO;
        mSetAnchorPosition = NO;
        mIsFurniturePlaced = NO;
        mIsFurnitureBeingDragged = NO;
        
        mCurrentMode = SAMPLE_APP_FURNITURE_MODE;
        mProductPlacementState = ProductPlacementStates::IDLE;
        mCurrentTouch.x = 0.5f;
        mCurrentTouch.y = 0.5f;
        mProductRotation = 0;
        mPreviousProductRotation = 0;
        mProductScale = 0.5f;
        mPreviousProductScale = 0.5f;
        
        mCurrentStatusInfo = Vuforia::TrackableResult::UNKNOWN;
    }
    
    return self;
}


- (CGSize) getCurrentARViewBoundsSize
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGSize viewSize = screenBounds.size;
    
    viewSize.width *= [UIScreen mainScreen].nativeScale;
    viewSize.height *= [UIScreen mainScreen].nativeScale;
    return viewSize;
}


- (void) dealloc
{
    [self deleteFramebuffer];
 
    [mAstronaut unloadModel];
    [mDrone unloadModel];
    [mFurniture unloadModel];
    
    // Tear down context
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }

    for (int i = 0; i < kNumAugmentationTextures; ++i) {
        augmentationTexture[i] = nil;
    }
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


- (Modelv3d*) loadModelNamed:(NSString *)modelName withTransparency:(float)transparency
{
    Modelv3d* model = [[Modelv3d alloc] init];
    [model setTransparency:transparency];
    [model loadModel:modelName];
    return model;
}

- (void) updateRenderingPrimitives
{
    [sampleAppRenderer updateRenderingPrimitives];
}

- (void) changeOrientation:(UIInterfaceOrientation)ARViewOrientation
{
    self.mARViewOrientation = ARViewOrientation;
    [self updateRenderingPrimitives];
}


- (void) performTap
{
    if(!(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced))
    {
        mSetAnchorPosition = YES;
    }
}

- (void) setInteractiveMode
{
    mCurrentMode = SAMPLE_APP_INTERACTIVE_MODE;
}

- (void) setMidAirMode
{
    mCurrentMode = SAMPLE_APP_MIDAIR_MODE;
}

- (void) setFurnitureMode
{
    mCurrentMode = SAMPLE_APP_FURNITURE_MODE;
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
    
    if(mResetGroundPlaneStateAndAnchors)
    {
        [self resetGroundPlaneStateAndAnchors];
        mResetGroundPlaneStateAndAnchors = NO;
    }
}

- (void) renderFrameWithState:(const Vuforia::State&) state
                projectMatrix:(Vuforia::Matrix44F&) projectionMatrix
{
    [self setFramebuffer];
    
    BOOL render3DReticle = NO;
    BOOL renderFurnitureReticle = NO;
    BOOL renderAstronaut = NO;
    BOOL renderDrone = NO;
    BOOL renderFurniture = NO;
    BOOL isDeviceResultAvailable = NO;
    BOOL isAnchorResultAvailable = NO;
    BOOL allowAnchorCreation = NO;
    BOOL allowMidAirAnchorCreation = NO;

    const int SHADOW_TEXTURE_INDEX = 6;
    const int TRANSLATE_TEXTURE_INDEX = 7;
    const int ROTATE_TEXTURE_INDEX = 8;
    
    mAnchorResultsCount = 0;
    
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

    if(state.getTrackableResults().empty())
    {
        SampleApplicationUtils::checkGlError("Render Frame, no trackables");
        NSLog(@"No trackables");
    }
    else
    {
        Vuforia::Matrix34F devicePoseTemp;

        const auto& trackableResultList = state.getTrackableResults();
        for (const auto* result : trackableResultList)
        {
            Vuforia::Matrix44F modelViewMatrix = Vuforia::Tool::convertPose2GLMatrix(result->getPose());
            if(result->isOfType(Vuforia::DeviceTrackableResult::getClassType()))
            {
                devicePoseTemp = result->getPose();
                mDevicePoseMatrix = SampleApplicationUtils::Matrix44FTranspose(SampleApplicationUtils::Matrix44FInverse(modelViewMatrix));
                isDeviceResultAvailable = YES;

                Vuforia::DeviceTrackableResult::STATUS deviceTrackerResultStatus = result->getStatus();
                Vuforia::DeviceTrackableResult::STATUS_INFO deviceTrackerResultStatusInfo = result->getStatusInfo();
                [self setStatusInfoUpdate:deviceTrackerResultStatusInfo];
                
                allowAnchorCreation = deviceTrackerResultStatus != Vuforia::DeviceTrackableResult::STATUS::NO_POSE;
                
                // It is possible to create mid air anchors even when these conditions are not meet, but here we show the best state to add new anchors
                allowMidAirAnchorCreation = (deviceTrackerResultStatus == Vuforia::DeviceTrackableResult::STATUS::TRACKED ||
                                             deviceTrackerResultStatus == Vuforia::DeviceTrackableResult::STATUS::EXTENDED_TRACKED) &&
                                            (deviceTrackerResultStatusInfo == Vuforia::DeviceTrackableResult::STATUS_INFO::NORMAL);
            }
            // Check if there is an anchor result, compare against the anchor name and render the desired augmentation
            else if(result->isOfType(Vuforia::AnchorResult::getClassType()))
            {
                isAnchorResultAvailable = YES;
                mAnchorResultsCount ++;
                
                if(!strcmp(result->getTrackable().getName(), HIT_TEST_ANCHOR_NAME))
                {
                    renderAstronaut = YES;
                    mHitTestPoseMatrix = modelViewMatrix;
                }
                
                if(!strcmp(result->getTrackable().getName(), MID_AIR_ANCHOR_NAME))
                {
                    renderDrone = YES;
                    mMidAirPoseMatrix = modelViewMatrix;
                }
                
                if(!strcmp(result->getTrackable().getName(), FURNITURE_ANCHOR_NAME))
                {
                    renderFurniture = YES;
                    mIsFurniturePlaced = YES;
                    if(!mIsFurnitureBeingDragged)
                    {
                        mFurniturePoseMatrix = modelViewMatrix;
                    }
                    else
                    {
                        mFurniturePoseMatrix = mFurnitureTranslationPoseMatrix;
                    }
                }
            }
            
        }
        
        // Ensure we have the right status after reset
        if (!renderFurniture && mIsFurniturePlaced)
        {
            mIsFurniturePlaced = NO;
        }
        
        if(isDeviceResultAvailable && allowAnchorCreation)
        {
            if(mSetAnchorPosition)
            {
                if(mCurrentMode == SAMPLE_APP_INTERACTIVE_MODE || mCurrentMode == SAMPLE_APP_FURNITURE_MODE)
                {
                    BOOL shouldHitTestCenteredOnScreen = !(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced);
                    BOOL shouldCreateAnchor = !(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurnitureBeingDragged);
                    
                    float hitTestX = 0.5f;
                    float hitTestY = 0.5f;
                    
                    // Compute hit test point matching screen orientation:
                    UIInterfaceOrientation deviceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
                    
                    if (!shouldHitTestCenteredOnScreen)
                    {
                        if (deviceOrientation == UIInterfaceOrientationPortrait)
                        {
                            hitTestX =  mCurrentTouch.y;
                            hitTestY = 1 - mCurrentTouch.x;
                        }
                        else if (deviceOrientation == UIInterfaceOrientationLandscapeRight)
                        {
                            hitTestX =  mCurrentTouch.x;
                            hitTestY =  mCurrentTouch.y;
                        }
                        else if (deviceOrientation == UIInterfaceOrientationPortraitUpsideDown)
                        {
                            hitTestX =  1 - mCurrentTouch.y;
                            hitTestY = mCurrentTouch.x;
                        }
                        else if (deviceOrientation == UIInterfaceOrientationLandscapeLeft)
                        {
                            hitTestX =  1 - mCurrentTouch.x;
                            hitTestY =  1 - mCurrentTouch.y;
                        }
                    }
                    
                    
                    isAnchorResultAvailable = [self performHitTestWithNormalizedTouchPointX:hitTestX andNormalizedTouchPointY:hitTestY withDeviceHeightInMeters:DEFAULT_HEIGHT_ABOVE_GROUND toCreateAnchor:shouldCreateAnchor andStateToUse:state];
                    
                    // While we drag the product we don't want to create an anchor and use the reticle pose instead which is the result of the hit test
                    if(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurnitureBeingDragged)
                    {
                        mFurniturePoseMatrix = mFurnitureTranslationPoseMatrix;
                    }
                    
                } else {
                    mSetDroneNewPosition = YES;
                }
                mSetAnchorPosition = NO;
            }
            
            // Should we set a new position for the drone?
            if(mSetDroneNewPosition) {
                Vuforia::Matrix34F midAirPose = SampleApplicationUtils::copyMatrix(devicePoseTemp);
                
                // Matrix to translate drone at a given distance in front of the camera
                Vuforia::Matrix34F translationMat;
                translationMat.data[0] = 1;
                translationMat.data[5] = 1;
                translationMat.data[10] = 1;
                Vuforia::Tool::setTranslation(translationMat, Vuforia::Vec3F(0,0,-3));
                
                midAirPose = Vuforia::Tool::multiply(midAirPose, translationMat);

                // We remove the orientation from the device pose to create the anchor
                midAirPose.data[0] = 1;
                midAirPose.data[1] = 0;
                midAirPose.data[2] = 0;
                
                midAirPose.data[4] = 0;
                midAirPose.data[5] = 1;
                midAirPose.data[6] = 0;
                
                midAirPose.data[8] = 0;
                midAirPose.data[9] = 0;
                midAirPose.data[10] = 1;

                // Create an anchor for drone if conditions are met
                if (allowMidAirAnchorCreation)
                {
                    [self createMidAirAnchorWithPose: midAirPose];
                }
                
                mSetDroneNewPosition = NO;
            }

        }
        
        // To render a placement-reticle we need to perform a hit test to get an intersection point
        // with ground plane. Until an anchor from HitTestResult is created successfully the device
        // is assumed to be at deviceHeight along gravity vector above the plane.
        if(!isAnchorResultAvailable || (mCurrentMode == SAMPLE_APP_INTERACTIVE_MODE))
        {
            render3DReticle = [self performHitTestWithNormalizedTouchPointX:.5f andNormalizedTouchPointY:.5f withDeviceHeightInMeters:DEFAULT_HEIGHT_ABOVE_GROUND toCreateAnchor:NO andStateToUse:state];
        }
        
        if(!mIsFurniturePlaced && (mCurrentMode == SAMPLE_APP_FURNITURE_MODE))
        {
            renderFurnitureReticle = [self performHitTestWithNormalizedTouchPointX:.5f andNormalizedTouchPointY:.5f withDeviceHeightInMeters:DEFAULT_HEIGHT_ABOVE_GROUND toCreateAnchor:NO andStateToUse:state];
        }
        
        auto illumination = state.getIllumination();
        if (illumination != nullptr)
        {
            float ambientIntensity = illumination->getAmbientIntensity();
            if (ambientIntensity != Vuforia::Illumination::AMBIENT_INTENSITY_UNAVAILABLE)
            {
                // We set the model lighting considering the min and max lumens values in the sample to 200 - 1500
                // Low brightness is consider in this case to be 200 lumens which could be a dimmed light bulb and
                // as a bright standard light bulb 1500 lumens, higher values can be obtained from brighter sources
                mLightIntensity = fmin(1.5f, .4f + (ambientIntensity - 200.0f) / 1300.0f);
            }
        }

        
        BOOL shouldPointToGround = (!render3DReticle && mCurrentMode == SAMPLE_APP_INTERACTIVE_MODE) ||
                                    (!renderFurniture && !renderFurnitureReticle && !mIsFurniturePlaced && mCurrentMode == SAMPLE_APP_FURNITURE_MODE);
        
        if (!allowMidAirAnchorCreation && mCurrentMode == SAMPLE_APP_MIDAIR_MODE)
        {
            [self.uiUpdater setInstructionsState: InstructionsStates::UNABLE_TO_PLACE_ANCHOR];
        }
        else if (shouldPointToGround)
        {
            [self.uiUpdater setInstructionsState: InstructionsStates::POINT_TO_GROUND];
        }
        else if(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && renderFurniture)
        {
            if(mProductPlacementState == ProductPlacementStates::IDLE)
            {
                [self.uiUpdater setInstructionsState:InstructionsStates::GESTURES_INSTRUCTIONS];
            }
            else
            {
                [self.uiUpdater setInstructionsState:InstructionsStates::PRODUCT_PLACEMENT];
            }
        }
        else
        {
            [self.uiUpdater setInstructionsState:InstructionsStates::TAP_TO_PLACE];
        }
        
        // If we have a device and anchor results we translate and scale the models so they are positioned at the center of the reticle
        // For the drone we want to align it also vertically since it is in mid-air
        if(isDeviceResultAvailable && isAnchorResultAvailable)
        {
            if (renderAstronaut)
            {
                Vuforia::Matrix44F astronautMV = mHitTestPoseMatrix;
                SampleApplicationUtils::translatePoseMatrix(-0.375f, 0, 0, astronautMV);
                SampleApplicationUtils::scalePoseMatrix(10.0f, 10.0f, 10.0f, astronautMV);
                
                [self renderModelV3D:mAstronaut withPoseMatrix:astronautMV projectionMatrix:projectionMatrix andTextureId:0];
            }
            
            if(renderDrone)
            {
                Vuforia::Matrix44F droneMV = mMidAirPoseMatrix;
                SampleApplicationUtils::translatePoseMatrix(-0.75f, -0.375f, -0.75, droneMV);
                SampleApplicationUtils::scalePoseMatrix(10.0f, 10.0f, 10.0f, droneMV);
                
                [self renderModelV3D:mDrone withPoseMatrix:droneMV projectionMatrix:projectionMatrix andTextureId:1];
            }
            
            if(renderFurniture)
            {
                float furnitureMVPMatrix[16];
                
                Vuforia::Matrix44F furnitureMV = mFurniturePoseMatrix;
                Vuforia::Matrix44F shadowMV = mFurniturePoseMatrix;
                Vuforia::Matrix44F gesturesIndicatorMV = mFurniturePoseMatrix;
                
                SampleApplicationUtils::rotatePoseMatrix(mProductRotation, 0, 1.0f, 0, furnitureMV);
                SampleApplicationUtils::scalePoseMatrix(mProductScale, mProductScale, mProductScale, furnitureMV);
                Vuforia::Matrix44F poseMatrix = SampleApplicationUtils::Matrix44FIdentity();
                SampleApplicationUtils::multiplyMatrix(mDevicePoseMatrix, furnitureMV, poseMatrix);
                
                SampleApplicationUtils::multiplyMatrix(&projectionMatrix.data[0], &poseMatrix.data[0], &furnitureMVPMatrix[0]);
       
                float shadowScale = mProductScale * .5f;
                SampleApplicationUtils::rotatePoseMatrix(-90, 1.0, 0.0f, 0, shadowMV);
                SampleApplicationUtils::scalePoseMatrix(shadowScale, shadowScale, shadowScale, shadowMV);

                SampleApplicationUtils::rotatePoseMatrix(-90, 1.0, 0.0f, 0, gesturesIndicatorMV);
                SampleApplicationUtils::scalePoseMatrix(mProductScale, mProductScale, mProductScale, gesturesIndicatorMV);
                
                // Disable depth test so the shadow does not oclude the furniture
                glDisable(GL_DEPTH_TEST);
                [self renderPlaneTexturedWithProjectionMatrix:projectionMatrix MV:shadowMV textureHandle:SHADOW_TEXTURE_INDEX substractColor:YES is2DRender:NO];
                
                if(mProductPlacementState != ProductPlacementStates::IDLE)
                {
                    [self renderPlaneTexturedWithProjectionMatrix:projectionMatrix MV:gesturesIndicatorMV
                                                    textureHandle:(mProductPlacementState == ProductPlacementStates::TRANSLATING) ? TRANSLATE_TEXTURE_INDEX : ROTATE_TEXTURE_INDEX
                                                   substractColor:NO
                                                       is2DRender:NO];
                }

                glEnable(GL_DEPTH_TEST);
                
                float lightColor[] = {mLightIntensity, mLightIntensity, mLightIntensity, 1.0f};
                [mFurniture setLightingColor:lightColor];
                [mFurniture renderWithModelView:&furnitureMV.data[0] modelViewProjMatrix:&furnitureMVPMatrix[0]];
            }
            
        }
    }
    
    // Rendering reticle
    if((!render3DReticle && !isAnchorResultAvailable) || mCurrentMode == SAMPLE_APP_MIDAIR_MODE)
    {
        [self render2dReticle];
    }
    else if(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && renderFurnitureReticle && !mIsFurniturePlaced)
    {
        float furnitureMVPMatrix[16];
        Vuforia::Matrix44F furnitureMV = mReticlePose;
        SampleApplicationUtils::scalePoseMatrix(mProductScale, mProductScale, mProductScale, furnitureMV);
        Vuforia::Matrix44F poseMatrix = SampleApplicationUtils::Matrix44FIdentity();
        SampleApplicationUtils::multiplyMatrix(mDevicePoseMatrix, furnitureMV, poseMatrix);
        
        SampleApplicationUtils::multiplyMatrix(&projectionMatrix.data[0], &poseMatrix.data[0], &furnitureMVPMatrix[0]);
        
        Vuforia::Matrix44F shadowMV = mReticlePose;
        float shadowScale = mProductScale * .5f;
        SampleApplicationUtils::rotatePoseMatrix(-90, 1.0, 0.0f, 0, shadowMV);
        SampleApplicationUtils::scalePoseMatrix(shadowScale, shadowScale, shadowScale, shadowMV);
        
        // Disable depth test so the shadow does not oclude the furniture
        glDisable(GL_DEPTH_TEST);
        [self renderPlaneTexturedWithProjectionMatrix:projectionMatrix MV:shadowMV textureHandle:SHADOW_TEXTURE_INDEX substractColor:YES is2DRender:NO];
        glEnable(GL_DEPTH_TEST);

        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glBlendEquation(GL_FUNC_ADD);
        [mFurniture renderWithModelView:&furnitureMV.data[0] modelViewProjMatrix:&furnitureMVPMatrix[0]];
        
    }
    else if(mCurrentMode == SAMPLE_APP_INTERACTIVE_MODE)
    {
        [self renderReticleWithProjectionMatrix:projectionMatrix isReticle2D:NO];
    }
    
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    [self presentFramebuffer];
}

-(void) setStatusInfoUpdate:(Vuforia::TrackableResult::STATUS_INFO)status
{
    if(mCurrentStatusInfo != status)
    {
        mCurrentStatusInfo = status;
        [self.uiUpdater setStatusInfo:status];
    }
}

- (void) render2dReticle
{
    CGSize ARViewBoundsSize = [self getCurrentARViewBoundsSize];
    float aspectRatio = ARViewBoundsSize.width / ARViewBoundsSize.height;
    
    Vuforia::Matrix44F reticleProj = SampleApplicationUtils::Matrix44FIdentity();
    
    float orthoScale = 4.0f;
    SampleApplicationUtils::setOrthoMatrix(-aspectRatio * orthoScale, aspectRatio * orthoScale, -orthoScale, orthoScale, 1, -1, reticleProj);
    
    mReticlePose = SampleApplicationUtils::Matrix44FIdentity();
    
    glDisable(GL_DEPTH_TEST);
    [self renderReticleWithProjectionMatrix:reticleProj isReticle2D:YES];
    glEnable(GL_DEPTH_TEST);
}

- (void) renderReticleWithProjectionMatrix:(Vuforia::Matrix44F&)projectionMatrix
                               isReticle2D:(BOOL)isReticle2D
{
    const int PLANE_2D_RETICLE_TEXTURE_INDEX = 2;
    const int MIDAIR_RETICLE_TEXTURE_INDEX = 3;
    const int PLANE_3D_RETICLE_TEXTURE_INDEX = 4;
    
    unsigned int textureIndex = mCurrentMode != SAMPLE_APP_MIDAIR_MODE ? PLANE_2D_RETICLE_TEXTURE_INDEX : MIDAIR_RETICLE_TEXTURE_INDEX;
    
    if(mCurrentMode == SAMPLE_APP_INTERACTIVE_MODE && !isReticle2D)
        textureIndex = PLANE_3D_RETICLE_TEXTURE_INDEX;
    
    Vuforia::Matrix44F reticleMV = mReticlePose;
    SampleApplicationUtils::scalePoseMatrix(.25f, 0.25f, .25f, reticleMV);

    // We rotate the reticle for it sit on the plane where we intend to render the reticle instead of intersecting it
    SampleApplicationUtils::rotatePoseMatrix(90, -1, 0, 0, reticleMV);

    [self renderPlaneTexturedWithProjectionMatrix:projectionMatrix
                                               MV:reticleMV
                                    textureHandle:augmentationTexture[textureIndex].textureID
                                   substractColor:NO
                                       is2DRender:isReticle2D];
}

- (void) renderPlaneTexturedWithProjectionMatrix:(Vuforia::Matrix44F&)projectionMatrix
                                              MV:(Vuforia::Matrix44F&)mvMatrix
                                   textureHandle:(int)textureHandle
                                  substractColor:(BOOL)isSubstractingColors
                                      is2DRender:(BOOL)is2DRender
{
    Vuforia::Matrix44F modelViewProjection;
     
    Vuforia::Matrix44F poseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    
    if(!is2DRender)
        SampleApplicationUtils::multiplyMatrix(mDevicePoseMatrix, mvMatrix, poseMatrix);
     
    SampleApplicationUtils::multiplyMatrix(&projectionMatrix.data[0], &poseMatrix.data[0], &modelViewProjection.data[0]);
     
    glEnable(GL_BLEND);
    if(!isSubstractingColors)
    {
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glBlendEquation(GL_FUNC_ADD);
    }
    else
    {
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_DST_ALPHA, GL_SRC_ALPHA, GL_DST_ALPHA);
        glBlendEquationSeparate(GL_FUNC_REVERSE_SUBTRACT, GL_FUNC_ADD);
    }
    
    glUseProgram(planeShaderProgramID);
     
    glVertexAttribPointer(planeVertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)quadVertices);
    glVertexAttribPointer(planeTextureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)quadTexCoords);
     
    glEnableVertexAttribArray(vertexHandle);
    glEnableVertexAttribArray(textureCoordHandle);
     
    glActiveTexture(GL_TEXTURE0);
     
    glBindTexture(GL_TEXTURE_2D, textureHandle);
     
    glUniformMatrix4fv(planeMvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjection.data[0]);
    glUniform4f(planeColorHandle, 1, 1, 1, 1);
    glUniform1i(planeTexSampler2DHandle, 0);
     
    glDrawElements(GL_TRIANGLES, kNumQuadIndices, GL_UNSIGNED_SHORT, quadIndices);
     
    glDisableVertexAttribArray(vertexHandle);
    glDisableVertexAttribArray(textureCoordHandle);
     
    glDisable(GL_BLEND);
     
    SampleApplicationUtils::checkGlError("EAGLView renderPlaneTextured");
}

- (void) renderModelV3D:(Modelv3d*)model
         withPoseMatrix:(Vuforia::Matrix44F&)modelPoseMatrix
       projectionMatrix:(Vuforia::Matrix44F&)projectionMatrix
           andTextureId:(int)targetIndex
{
    Vuforia::Matrix44F modelViewProjection;
    
    Vuforia::Matrix44F poseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    SampleApplicationUtils::multiplyMatrix(mDevicePoseMatrix, modelPoseMatrix, poseMatrix);
    
    SampleApplicationUtils::multiplyMatrix(&projectionMatrix.data[0], &poseMatrix.data[0], &modelViewProjection.data[0]);
    
    glUseProgram(shaderProgramID);
    
    glVertexAttribPointer(vertexHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)model.vertices);
    glVertexAttribPointer(normalHandle, 3, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)model.normals);
    glVertexAttribPointer(textureCoordHandle, 2, GL_FLOAT, GL_FALSE, 0, (const GLvoid*)model.texCoords);
    
    glEnableVertexAttribArray(vertexHandle);
    glEnableVertexAttribArray(normalHandle);
    glEnableVertexAttribArray(textureCoordHandle);
    
    glActiveTexture(GL_TEXTURE0);
    
    glBindTexture(GL_TEXTURE_2D, augmentationTexture[targetIndex].textureID);
    
    glUniformMatrix4fv(mvpMatrixHandle, 1, GL_FALSE, (const GLfloat*)&modelViewProjection.data[0]);
    glUniformMatrix4fv(mvMatrixHandle, 1, GL_FALSE, (const GLfloat*)&poseMatrix.data[0]);
    
    GLKMatrix4 mvMatrix4 = GLKMatrix4MakeWithArray(&poseMatrix.data[0]);
    bool isInvertible;
    GLKMatrix4 normalMatrix = GLKMatrix4InvertAndTranspose ( mvMatrix4, &isInvertible );
    glUniformMatrix4fv(normalMatrixHandle, 1, GL_FALSE, normalMatrix.m);
    
    glUniform4f(lightPositionHandle, 0.0f, 0.0f, 0.0f, -1.0f);
    glUniform4f(lightColorHandle, mLightIntensity, mLightIntensity, mLightIntensity, 1.0f);
    
    glUniform1i(texSampler2DHandle, 0);
    
    glDrawArrays(GL_TRIANGLES, 0, (int)model.nbVertices);
    
    glDisableVertexAttribArray(vertexHandle);
    glDisableVertexAttribArray(normalHandle);
    glDisableVertexAttribArray(textureCoordHandle);
    
    SampleApplicationUtils::checkGlError("EAGLView renderFrameVuforia");
}

- (void) configureVideoBackgroundWithCameraMode:(Vuforia::CameraDevice::MODE)cameraMode viewWidth:(float)viewWidth viewHeight:(float)viewHeight
{
    [self deleteFramebuffer];
    [sampleAppRenderer configureVideoBackgroundWithCameraMode:[vapp getCameraMode]
                                                    viewWidth:viewWidth
                                                   viewHeight:viewHeight];
}

- (void) createMidAirAnchorWithPose:(Vuforia::Matrix34F&)anchorPoseMatrix
{
    NSLog(@"createMidAirAnchor");
    
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*> (trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType()));

    if(mMidAirAnchor != nullptr)
    {
        NSLog(@"Destroying hit test anchor with name '%s'", MID_AIR_ANCHOR_NAME);
        bool result = deviceTracker->destroyAnchor(mMidAirAnchor);
        NSLog(@"%s hit test anchor", (result ? "Successfully destroyed" : "Failed to destroy"));
    }
    
    mMidAirAnchor = deviceTracker->createAnchor(MID_AIR_ANCHOR_NAME, anchorPoseMatrix);
    
    if (mMidAirAnchor != nullptr)
    {
        NSLog(@"Successfully created hit test anchor with name '%s'", mMidAirAnchor->getName());
    }
    else
    {
        NSLog(@"Failed to create hit test anchor");
    }
}

- (BOOL) performHitTestWithNormalizedTouchPointX:(float)normalizedTouchPointX
                        andNormalizedTouchPointY:(float)normalizedTouchPointY
                        withDeviceHeightInMeters:(float) deviceHeightInMeters
                                  toCreateAnchor:(BOOL)createAnchor
                                   andStateToUse:(const Vuforia::State&) state
{
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*> (trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    Vuforia::SmartTerrain* smartTerrain = static_cast<Vuforia::SmartTerrain*>(trackerManager.getTracker(Vuforia::SmartTerrain::getClassType()));
    
    if (deviceTracker == nullptr || smartTerrain == nullptr)
    {
        NSLog(@"Failed to perform hit test, trackers not initialized");
        return NO;
    }
    
    Vuforia::Vec2F hitTestPoint(normalizedTouchPointX, normalizedTouchPointY);
    Vuforia::SmartTerrain::HITTEST_HINT hitTestHint = Vuforia::SmartTerrain::HITTEST_HINT_NONE; // hit test hint is currently unused
    
    // A hit test is performed for a given State at normalized screen coordinates.
    // The deviceHeight is an developer provided assumption as explained on
    // definition of DEFAULT_HEIGHT_ABOVE_GROUND.
    const auto& hitTestResults = smartTerrain->hitTest(hitTestPoint, hitTestHint, state, deviceHeightInMeters);
    if (!hitTestResults.empty())
    {
        // Use first HitTestResult
        const Vuforia::HitTestResult* hitTestResult = hitTestResults.at(0);
        
        if (createAnchor)
        {
            if(mCurrentMode == SAMPLE_APP_INTERACTIVE_MODE)
            {
                // Destroy previous hit test anchor if needed
                if (mHitTestAnchor != nullptr)
                {
                    NSLog(@"Destroying hit test anchor with name '%s'", HIT_TEST_ANCHOR_NAME);
                    bool result = deviceTracker->destroyAnchor(mHitTestAnchor);
                    NSLog(@"%s hit test anchor", (result ? "Successfully destroyed" : "Failed to destroy"));
                }
                
                mHitTestAnchor = deviceTracker->createAnchor(HIT_TEST_ANCHOR_NAME, *hitTestResult);
                if (mHitTestAnchor != nullptr)
                {
                    NSLog(@"Successfully created hit test anchor with name '%s'", mHitTestAnchor->getName());
                }
                else
                {
                    NSLog(@"Failed to create hit test anchor");
                }
            }
            else if(mCurrentMode == SAMPLE_APP_FURNITURE_MODE)
            {
                // Destroy previous hit test anchor if needed
                if (mFurnitureAnchor != nullptr)
                {
                    NSLog(@"Destroying hit test anchor with name '%s'", FURNITURE_ANCHOR_NAME);
                    bool result = deviceTracker->destroyAnchor(mFurnitureAnchor);
                    NSLog(@"%s hit test anchor", (result ? "Successfully destroyed" : "Failed to destroy"));
                }
                
                mFurnitureAnchor = deviceTracker->createAnchor(FURNITURE_ANCHOR_NAME, *hitTestResult);
                if (mFurnitureAnchor != nullptr)
                {
                    NSLog(@"Successfully created hit test anchor with name '%s'", mFurnitureAnchor->getName());
                    
                    [mFurniture setTransparency:1.0f];
                }
                else
                {
                    NSLog(@"Failed to create hit test anchor");
                }

                mIsFurnitureBeingDragged = NO;
            }
        }
        
        if(mCurrentMode == SAMPLE_APP_FURNITURE_MODE)
            mFurnitureTranslationPoseMatrix = Vuforia::Tool::convertPose2GLMatrix(hitTestResult->getPose());

        mReticlePose = Vuforia::Tool::convertPose2GLMatrix(hitTestResult->getPose());
        return YES;
    }
    else
    {
        NSLog(@"Hit test returned no results");
        return NO;
    }
}

- (void) resetGroundPlaneStateAndAnchors
{
    mDevicePoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    mMidAirPoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    mHitTestPoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    mFurniturePoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    mFurnitureTranslationPoseMatrix = SampleApplicationUtils::Matrix44FIdentity();
    mReticlePose = SampleApplicationUtils::Matrix44FIdentity();
    
    mSetDroneNewPosition = NO;
    mIsFurniturePlaced = NO;
    mIsFurnitureBeingDragged = NO;
    
    mPreviousProductScale = 0.5f;
    mProductScale = 0.5f;
    mPreviousProductRotation = 0;
    mProductRotation = 0;
    
    [self setFurnitureMode];
    [mFurniture setTransparency:0.5f];

    [self destroyAnchors];
    
    mCurrentStatusInfo = Vuforia::TrackableResult::UNKNOWN;
}

- (void) setResetGroundPlaneStateAndAnchors
{
    mResetGroundPlaneStateAndAnchors = YES;
}

- (void) destroyAnchors
{
    NSLog(@"destroyAnchors");
    
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::PositionalDeviceTracker* deviceTracker = static_cast<Vuforia::PositionalDeviceTracker*> (trackerManager.getTracker(Vuforia::PositionalDeviceTracker::getClassType()));
    
    if(mMidAirAnchor != nullptr)
    {
        NSLog(@"Destroying hit test anchor with name '%s'", MID_AIR_ANCHOR_NAME);
        bool result = deviceTracker->destroyAnchor(mMidAirAnchor);
        NSLog(@"%s mid air anchor", (result ? "Successfully destroyed" : "Failed to destroy"));
    }
    mMidAirAnchor = nullptr;
    
    if (mHitTestAnchor != nullptr)
    {
        NSLog(@"Destroying hit test anchor with name '%s'", HIT_TEST_ANCHOR_NAME);
        bool result = deviceTracker->destroyAnchor(mHitTestAnchor);
        NSLog(@"%s hit test anchor", (result ? "Successfully destroyed" : "Failed to destroy"));
    }
    mHitTestAnchor = nullptr;
    
    if(mFurnitureAnchor != nullptr)
    {
        NSLog(@"Destroying hit test anchor with name '%s'", FURNITURE_ANCHOR_NAME);
        bool result = deviceTracker->destroyAnchor(mFurnitureAnchor);
        NSLog(@"%s furniture anchor", (result ? "Successfully destroyed" : "Failed to destroy"));
    }
    mFurnitureAnchor = nullptr;
}

//------------------------------------------------------------------------------
#pragma mark - OpenGL ES management

- (void) initShaders
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


- (void) createFramebuffer
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


- (void) deleteFramebuffer
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


- (void) setFramebuffer
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


- (BOOL) presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    
    return [context presentRenderbuffer:GL_RENDERBUFFER];
}


// The user touched the screen
- (void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
}


- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
    if(event.allTouches.count > 1 || !(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced))
        return;
    
    UITouch* touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    CGRect rect = [self bounds];

    mCurrentTouch.x = (point.x / rect.size.width);
    mCurrentTouch.y = (point.y / rect.size.height);
    mSetAnchorPosition = YES;
    
    if(event.allTouches.count == 1)
    {
        mIsFurnitureBeingDragged = YES;
        mProductPlacementState = ProductPlacementStates::TRANSLATING;
    }
}


- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    if(event.allTouches.count == 1 && mIsFurnitureBeingDragged  && (mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced))
    {
        mSetAnchorPosition = YES;
        mProductPlacementState = ProductPlacementStates::IDLE;
    }
}


- (void) touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    if(event.allTouches.count == 1 && mIsFurnitureBeingDragged && (mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced))
    {
        mSetAnchorPosition = YES;
        mProductPlacementState = ProductPlacementStates::IDLE;
    }
    
}


// Rotate product if we are in product placement state
- (void) rotateBy: (float)rotationDelta andGestureFinished:(BOOL)isGestureFinished
{
    if(!(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced))
        return;
    
    mProductPlacementState = ProductPlacementStates::ROTATE_SCALE;
    
    // Rotation in degrees, we multiply by 3 so rotation is smoother and does not require real 360 gesture to do a complete rotation
    mProductRotation = mPreviousProductRotation - (rotationDelta * 3 * 180 / M_PI);
    
    if(isGestureFinished)
    {
        mProductPlacementState = ProductPlacementStates::IDLE;
        
        if(mProductRotation < 0)
            mProductRotation += 360;
        
        if(mProductRotation > 360)
            mProductRotation -= 360;

        mPreviousProductRotation = mProductRotation;
    }
    
}


// Scale product if we are in product placement state
- (void) scaleBy: (float)scaleDelta andGestureFinished:(BOOL)isGestureFinished
{
    if(!(mCurrentMode == SAMPLE_APP_FURNITURE_MODE && mIsFurniturePlaced))
        return;
    
    mProductPlacementState = ProductPlacementStates::ROTATE_SCALE;
    
    mProductScale = mPreviousProductScale * scaleDelta;
    
    mProductScale = MIN(mProductScale, MAX_PRODUCT_SCALE_FACTOR);
    mProductScale = MAX(mProductScale, MIN_PRODUCT_SCALE_FACTOR);
    
    if(isGestureFinished)
    {
        mProductPlacementState = ProductPlacementStates::IDLE;
        mPreviousProductScale = mProductScale;
    }
}


@end
