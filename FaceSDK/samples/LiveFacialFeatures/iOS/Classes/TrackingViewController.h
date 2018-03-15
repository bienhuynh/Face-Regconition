//
//  based on ColorTrackingViewController.h
//  from ColorTracking application
//  The source code for this application is available under a BSD license.
//  See ColorTrackingLicense.txt for details.
//  Created by Brad Larson on 10/7/2010.
//  Modified by Anton Malyshev on 6/21/2013.
//

#import <UIKit/UIKit.h>
#import "TrackingCamera.h"
#import "TrackingGLView.h"
#include "LuxandFaceSDK.h"

#define MAX_FACES 5

#define MAX_NAME_LEN 1024

typedef struct {
    CGImage * image;
    unsigned char * buffer;
    int width, height, scanline;
    float ratio;
} DetectFaceParams;

typedef struct {
    int x1, x2, y1, y2;
} FaceRectangle;


@interface TrackingViewController : UIViewController <TrackingCameraDelegate>
{
	TrackingCamera * camera;
	UIScreen * screenForDisplay;
    
    GLuint directDisplayProgram;
	GLuint videoFrameTexture;
	GLubyte * rawPositionPixels;

    CATextLayer * labels[MAX_FACES];
    CALayer * trackingRects[MAX_FACES];
    CALayer * trackingFeatures[MAX_FACES][FSDK_FACIAL_FEATURE_COUNT];
    CATextLayer * drawFps;
    NSDate * timeStart;
    
    //volatile int processingImage;
    
    NSLock * trackerParamsLock;
    NSLock * faceDataLock;
    FaceRectangle faces[MAX_FACES];
    FSDK_Features features[MAX_FACES];
    long long IDs[MAX_FACES];
    
    volatile int rotating;
    char videoStarted;
    
    UIToolbar * toolbar;
    
    //UIImage * image_for_screenshot;
    
    //NOTE: use locks accessing (volatile int) variables if int is not machine word 
}

@property(readonly) TrackingGLView * glView;
@property(readonly) HTracker tracker;
@property(readwrite) char * templatePath;
@property(readwrite) volatile int closing;
@property(readonly) volatile int processingImage;

// Initialization and teardown
- (id)initWithScreen:(UIScreen *)newScreenForDisplay;

// OpenGL ES 2.0 setup methods
- (BOOL)loadVertexShader:(NSString *)vertexShaderName fragmentShader:(NSString *)fragmentShaderName forProgram:(GLuint *)programPointer;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

// Device rotating support
- (void)relocateSubviewsForOrientation:(UIInterfaceOrientation)orientation;

// Image processing in FaceSDK
- (void)processImageAsyncWith:(NSData *)args;

@end

