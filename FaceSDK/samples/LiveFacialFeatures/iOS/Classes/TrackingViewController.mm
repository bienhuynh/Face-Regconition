//
//  based on ColorTrackingViewController.m
//  from ColorTracking application
//  The source code for this application is available under a BSD license.
//  See ColorTrackingLicense.txt for details.
//  Created by Brad Larson on 10/7/2010.
//  Modified by Anton Malyshev on 09/22/2015.
//

#import "TrackingViewController.h"

int FSDK_SwapRedAndBlueChannels(unsigned char * buffer, int scanline, int width, int height, int channelsCount);

// GL attribute index.
enum {
    ATTRIB_VERTEX,
    ATTRIB_TEXTUREPOSITON,
    NUM_ATTRIBUTES
};

@implementation TrackingViewController

@synthesize glView = _glView;
@synthesize tracker = _tracker;
@synthesize templatePath = _templatePath;
@synthesize closing = _closing;
@synthesize processingImage = _processingImage;

//#define DEBUG

const NSString * help_text = @"LiveFacialFeatures is as much a developer tool as it is a conceptual proof of technology showcasing Luxand FaceSDK, an innovative way to have fun. Demonstrating the high-tech features found in Luxand’s FaceSDK, LiveFacialFeatures detects and displays some 70 facial features in real time.\n\nThe SDK is available for mobile developers: www.luxand.com/facesdk";

volatile BOOL show_fps = NO;
static volatile BOOL texturesGenerated = NO;
static int glerr = GL_NO_ERROR;


#pragma mark -
#pragma mark Face frame functions 

inline bool PointInRectangle(int point_x, int point_y, int rect_x1, int rect_y1, int rect_x2, int rect_y2)
{
    return (point_x >= rect_x1) && (point_x <= rect_x2) && (point_y >= rect_y1) && (point_y <= rect_y2);  
}

int GetFaceFrame(const FSDK_Features * Features, int * x1, int * y1, int * x2, int * y2)
{
	if (!Features || !x1 || !y1 || !x2 || !y2)
		return FSDKE_INVALID_ARGUMENT;
    
    float u1 = (float)(*Features)[0].x;
    float v1 = (float)(*Features)[0].y;
    float u2 = (float)(*Features)[1].x;
    float v2 = (float)(*Features)[1].y;
    float xc = (u1 + u2) / 2;
    float yc = (v1 + v2) / 2;
    int w = (int)pow((u2 - u1) * (u2 - u1) + (v2 - v1) * (v2 - v1), 0.5f);
    
    *x1 = (int)(xc - w * 1.6 * 0.9);
    *y1 = (int)(yc - w * 1.1 * 0.9);
    *x2 = (int)(xc + w * 1.6 * 0.9);
    *y2 = (int)(yc + w * 2.1 * 0.9);
    if (*x2 - *x1 > *y2 - *y1) {
        *x2 = *x1 + *y2 - *y1;
    } else {
        *y2 = *y1 + *x2 - *x1;
    }
	return 0;
}



#pragma mark -
#pragma mark TrackingViewController initialization, initializing face tracker

- (id)initWithScreen:(UIScreen *)newScreenForDisplay
{
    // for screenshot for App Store {
    /*
    NSString * stringURL = @"http://luxand.com/facesdk/iPhoneScreen.png";
    NSURL  * url = [NSURL URLWithString:stringURL];
    NSData * urlData = [NSData dataWithContentsOfURL:url];
    if (urlData){
        NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString * documentsDirectory = [paths objectAtIndex:0];  
        
        NSString * filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory, @"iPhoneScreen.png"];
        [urlData writeToFile:filePath atomically:YES];
        image_for_screenshot = [[UIImage alloc] initWithContentsOfFile:filePath];
        CGSize sz = image_for_screenshot.size;
        NSLog(@"%f %f", sz.width, sz.height);
    }
    */
    //}

    faceDataLock = [[NSLock alloc] init];
    trackerParamsLock = [[NSLock alloc] init];
    
    if ((self = [super initWithNibName:nil bundle:nil])) {
        FSDK_CreateTracker(&_tracker);
        
        char parameters[1024];
        sprintf(parameters, "RecognizeFaces=false;DetectFacialFeatures=true;ContinuousVideoFeed=true;ThresholdFeed=0.97;MemoryLimit=1000;HandleArbitraryRotations=false;DetermineFaceRotationAngle=false;InternalResizeWidth=70;FaceDetectionThreshold=3;FacialFeatureJitterSuppression=1;");
        
        int errpos = 0;
        FSDK_SetTrackerMultipleParameters(_tracker, parameters, &errpos);
#if defined(DEBUG)
        if (errpos)
            NSLog(@"FSDK_SetTrackerMultipleParameters returned errpos = %d", errpos);
#endif
        
		screenForDisplay = newScreenForDisplay;
		        
		_processingImage = NO;
        rotating = NO;
        videoStarted = 0;
        
        memset(faces, 0, sizeof(FaceRectangle)*MAX_FACES);        
    }
    return self;
}

//init view, glview and camera
- (void)loadView 
{
	CGRect mainScreenFrame = [[UIScreen mainScreen] applicationFrame];
	UIView *primaryView = [[UIView alloc] initWithFrame:mainScreenFrame];
	self.view = primaryView;
	[primaryView release]; //now self is responsible for the view

    //CGRect applicationFrame = [screenForDisplay applicationFrame];
    //_glView = [[TrackingGLView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, applicationFrame.size.width, applicationFrame.size.height)];
    
    _glView = [[TrackingGLView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 256.0f, 256.0f)];
    //_glView will be re-initialized in (void)drawFrame with proper size

	[self.view addSubview:_glView];
	[_glView release]; //now self.view is responsible for the view

	
    // Set up the toolbar at the bottom of the screen
	toolbar = [UIToolbar new];
	toolbar.barStyle = UIBarStyleBlackTranslucent;
	
    UIBarButtonItem * fpsItem = [[UIBarButtonItem alloc] initWithTitle:@"Fps"
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(fpsAction:)];
    
    UIBarButtonItem * flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    
    UIBarButtonItem * helpItem = [[UIBarButtonItem alloc] initWithTitle:@"  ?  "
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(helpAction:)];
    
    
    toolbar.items = [NSArray arrayWithObjects: fpsItem, flexibleSpace, helpItem, nil];
    
    [fpsItem release];
    [flexibleSpace release];
    [helpItem release];
    
	// size up the toolbar and set its frame, note that it will work only for views without Navigation toolbars. 
	[toolbar sizeToFit];
    CGFloat toolbarHeight = [toolbar frame].size.height;
	CGRect mainViewBounds = self.view.bounds;
	[toolbar setFrame:CGRectMake(CGRectGetMinX(mainViewBounds),
								 CGRectGetMinY(mainViewBounds) + CGRectGetHeight(mainViewBounds) - (toolbarHeight),
								 CGRectGetWidth(mainViewBounds),
								 toolbarHeight)];
	[self.view addSubview:toolbar];
    [toolbar release];
    
    
    [self loadVertexShader:@"DirectDisplayShader" fragmentShader:@"DirectDisplayShader" forProgram:&directDisplayProgram];
     
    // Creating MAX_FACES number of face tracking rectangles
    for (int i=0; i<MAX_FACES; ++i) {
        trackingRects[i] = [[CALayer alloc] init];
        trackingRects[i].bounds = CGRectMake(0.0f, 0.0f, 0.0f, 0.0f);
        trackingRects[i].cornerRadius = 0.0f;
        trackingRects[i].borderColor = [[UIColor blueColor] CGColor];
        trackingRects[i].borderWidth = 2.0f;
        trackingRects[i].position = CGPointMake(100.0f, 100.0f);
        trackingRects[i].opacity = 0.0f;
        trackingRects[i].anchorPoint = CGPointMake(0.0f, 0.0f); //for position to be the top-left corner
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            trackingFeatures[i][j] = [[CALayer alloc] init];
            trackingFeatures[i][j].bounds = CGRectMake(0.0f, 0.0f, 0.0f, 0.0f);
            trackingFeatures[i][j].cornerRadius = 3.0f;
            trackingFeatures[i][j].borderColor = [[UIColor greenColor] CGColor];
            trackingFeatures[i][j].borderWidth = 2.0f;
            trackingFeatures[i][j].position = CGPointMake(100.0f, 100.0f);
            trackingFeatures[i][j].opacity = 0.0f;
            trackingFeatures[i][j].anchorPoint = CGPointMake(0.0f, 0.0f); //for position to be the top-left corner
        }
        labels[i] = [[CATextLayer alloc] init];
        //[labels[i] setFont:@"Helvetica"];
        [labels[i] setFontSize:16];
        [labels[i] setFrame:CGRectMake(10.0f, 10.0f, 200.0f, 200.0f)];
        [labels[i] setString:@""];
        [labels[i] setAlignmentMode:kCAAlignmentLeft];
        [labels[i] setForegroundColor:[[UIColor blueColor] CGColor]];
        [trackingRects[i] addSublayer:labels[i]];
        [labels[i] release];

        
        drawFps = [[CATextLayer alloc] init];
        [drawFps setFont:@"Helvetica-Bold"];
        [drawFps setFontSize:30];
        [drawFps setFrame:CGRectMake(10.0f, 10.0f, 200.0f, 40.0f)];
        [drawFps setString:@""];
        [drawFps setForegroundColor:[[UIColor greenColor] CGColor]];
        [drawFps setAnchorPoint:CGPointMake(0.0f, 0.0f)];
        [drawFps setAlignmentMode:kCAAlignmentLeft];
    }
    
    // Disable animations for move and resize (otherwise trackingRect will jump) 
	for (int i=0; i<MAX_FACES; ++i) {
        NSMutableDictionary * newActions = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"bounds", nil];
        trackingRects[i].actions = newActions;
        [newActions release];
    }
    
    for (int i=0; i<MAX_FACES; ++i) {
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            NSMutableDictionary * newActions = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"bounds", nil];
            trackingFeatures[i][j].actions = newActions;
            [newActions release];
        }
    }
    
    NSMutableDictionary * newActions = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[NSNull null], @"position", [NSNull null], @"bounds", nil];
    drawFps.actions = newActions;
    
    
	
    for (int i=0; i<MAX_FACES; ++i) {
        [_glView.layer addSublayer:trackingRects[i]];
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            [_glView.layer addSublayer:trackingFeatures[i][j]];
        }
    }
    [_glView.layer addSublayer:drawFps];
    
	camera = [[TrackingCamera alloc] init];
	camera.delegate = self; //we want to receive processNewCameraFrame messages
	[self cameraHasConnected]; //the method doesn't perform any work now

    [self onGLInit];
}

- (void)didReceiveMemoryWarning 
{
//    [super didReceiveMemoryWarning];
}

- (void)dealloc 
{
    for (int i=0; i<MAX_FACES; ++i) {
        [trackingRects[i] release];
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            [trackingFeatures[i][j] release];
        }
        [drawFps release];
    }
	[camera release];
    [super dealloc];
}



#pragma mark -
#pragma mark OpenGL ES 2.0 rendering

CVOpenGLESTextureCacheRef coreVideoTextureCache = NULL;

- (void) onGLInit {
    if (coreVideoTextureCache) CFRelease(coreVideoTextureCache);
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [_glView context], NULL, &coreVideoTextureCache);
    if (err) {
        NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreate %d");
    }

    texturesGenerated = NO;
    
    //glEnable(GL_TEXTURE_2D);
    //if ((glerr = glGetError())) NSLog(@"Error in glEnable TEXTURE_2D, %d", glerr);
    
    GLuint textures[3];
    glGenTextures(3, textures);
    if ((glerr = glGetError())) NSLog(@"Error in glGenTextures, %d", glerr);
    
    videoFrameTexture = textures[0];
    
    texturesGenerated = YES;
}

- (void)drawFrameWithWidth:(int)width Height:(int)height Buffer:(unsigned char *)buffer CameraFrame:(CVImageBufferRef)cameraFrame
{
    if (!texturesGenerated) {
        return;
    }
    
    CVOpenGLESTextureRef texture = NULL;
    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, coreVideoTextureCache, cameraFrame, NULL, GL_TEXTURE_2D, GL_RGBA, width, height, GL_RGBA, GL_UNSIGNED_BYTE, 0, &texture);
    if (!texture || err) {
        NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
        return;
    }
    
    if ((glerr = glGetError())) ;//NSLog(@"Error before glBindTexture outputTexture, %d", glerr);
    int outputTexture = CVOpenGLESTextureGetName(texture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    if ((glerr = glGetError())) NSLog(@"Error in glBindTexture outputTexture, %d", glerr);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    if ((glerr = glGetError())) NSLog(@"Error in glTexParameteri GL_TEXTURE_MIN_FILTER, %d", glerr);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    if ((glerr = glGetError())) NSLog(@"Error in glTexParameteri GL_TEXTURE_MAG_FILTER, %d", glerr);
    
    // This is necessary for non-power-of-two textures, which are not supported in OpenGL ES 1.1?
    // But actually working!
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    if ((glerr = glGetError())) NSLog(@"Error in glTexParameteri GL_TEXTURE_WRAP_S, %d", glerr);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    if ((glerr = glGetError())) NSLog(@"Error in glTexParameteri GL_TEXTURE_WRAP_T, %d", glerr);
    
    [self drawFrame];
    
    CFRelease(texture);
}

- (void)drawFrame // called by processNewCameraFrame
{    
    /*
    // mirrored square
    static const GLfloat squareVertices[] = {
        1.0f, -1.0f,
        -1.0f, -1.0f,
        1.0f,  1.0f,
        -1.0f,  1.0f,
    };
    */
    
    // standart square 
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    /*
    // mirrored texture (was used with standart square originally, result - mirrored image)
    static const GLfloat textureVertices[] = {
        1.0f, 1.0f,
        1.0f, 0.0f,
        0.0f,  1.0f,
        0.0f,  0.0f,
    };
    */
    
    //OLD, OK WHEN NOT CHANGING ORIENTATION
    // standart texture
    /*
    static const GLfloat textureVertices[] = {
        1.0f, 0.0f,
        1.0f, 1.0f,
        0.0f,  0.0f,
        0.0f,  1.0f,
    };
    */
    
    
    // Reinitialize GLView and Toolbar when orientation changed 
    
    static UIInterfaceOrientation old_orientation = (UIInterfaceOrientation)0;
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (orientation != old_orientation) {
        old_orientation = orientation;
        
        // FIXME: ERROR IN RECREATING GLVIEW (IF NOT DESTROY FRAMEBUFFER - ALL IS OK)
        [self relocateSubviewsForOrientation:orientation];
    }
    
    // Rotate the texture (image from camera) accordingly to current orientation
    
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, squareVertices);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    if (orientation == 0 || orientation == UIInterfaceOrientationPortrait) {
        GLfloat textureVertices[] = {
            1.0f, 0.0f,
            1.0f, 1.0f,
            0.0f, 0.0f,
            0.0f, 1.0f,
        };
        glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices);
    } else if(orientation == UIInterfaceOrientationPortraitUpsideDown) {
        GLfloat textureVertices[] = {
            0.0f, 1.0f,
            0.0f, 0.0f,
            1.0f, 1.0f,
            1.0f, 0.0f,
        };
        glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices);
    } else if(orientation == UIInterfaceOrientationLandscapeLeft) {
        GLfloat textureVertices[] = {
            1.0f, 1.0f,
            0.0f, 1.0f,
            1.0f, 0.0f,
            0.0f, 0.0f,
        };
        glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices);
    } else if(orientation == UIInterfaceOrientationLandscapeRight) {
        GLfloat textureVertices[] = {
            0.0f, 0.0f,
            1.0f, 0.0f,
            0.0f, 1.0f,
            1.0f, 1.0f,
        };
        glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices);
    }
    
    glEnableVertexAttribArray(ATTRIB_TEXTUREPOSITON);
    [_glView setDisplayFramebuffer];
    glUseProgram(directDisplayProgram);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    [_glView presentFramebuffer];
    
    // Mark features
    
    // Setting bounds and position of trackingRects and trackingFeatures using data received from FSDK_DetectFace
    [faceDataLock lock];
    for (int i=0; i<MAX_FACES; ++i) {
        if (faces[i].x2) { // have face
            trackingRects[i].position = CGPointMake(faces[i].x1, faces[i].y1);
            trackingRects[i].bounds = CGRectMake(0.0f, 0.0f, faces[i].x2-faces[i].x1, faces[i].y2 - faces[i].y1);
            trackingRects[i].opacity = 1.0f;
            
            for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
                trackingFeatures[i][j].position = CGPointMake(features[i][j].x, features[i][j].y);
                trackingFeatures[i][j].bounds = CGRectMake(0.0f, 0.0f, 6.0f, 6.0f);
                trackingFeatures[i][j].opacity = 1.0f;
            }
        } else { // no face
            trackingRects[i].opacity = 0.0f;
            for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
                trackingFeatures[i][j].opacity = 0.0f;
            }
            
            [labels[i] setString:@""];
        }
    }        
    [faceDataLock unlock];
    
    // Counting fps
    if (!timeStart) timeStart = [[NSDate date] retain];
    static long long framesCount = 0;
    ++framesCount;
    NSDate *timeCurrent = [NSDate date];
    NSTimeInterval executionTime = [timeCurrent timeIntervalSinceDate:timeStart];
    if (executionTime > 3) {
        double fps = (executionTime<=0)? 0: (framesCount / (double)executionTime);
        if (show_fps) {
            [drawFps setString:[NSString stringWithFormat:@"FPS %.2f", fps]];
        } else {
            [drawFps setString:@""];
        }
        executionTime = 0;
        timeStart = nil;
        framesCount = 0;
    }
    
    
    videoStarted = 1;
}



#pragma mark -
#pragma mark OpenGL ES 2.0 setup methods

- (BOOL)loadVertexShader:(NSString *)vertexShaderName fragmentShader:(NSString *)fragmentShaderName forProgram:(GLuint *)programPointer
{
    GLuint vertexShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    *programPointer = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:vertexShaderName ofType:@"vsh"];
    if (![self compileShader:&vertexShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
#if defined(DEBUG)
        NSLog(@"Failed to compile vertex shader");
#endif
        return FALSE;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:fragmentShaderName ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
#if defined(DEBUG)        
        NSLog(@"Failed to compile fragment shader");
#endif
        return FALSE;
    }
    
    // Attach vertex shader to program.
    glAttachShader(*programPointer, vertexShader);
    
    // Attach fragment shader to program.
    glAttachShader(*programPointer, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(*programPointer, ATTRIB_VERTEX, "position");
    glBindAttribLocation(*programPointer, ATTRIB_TEXTUREPOSITON, "inputTextureCoordinate");

    // Link program.
    if (![self linkProgram:*programPointer]) {
#if defined(DEBUG)
        NSLog(@"Failed to link program: %d", *programPointer);
#endif        
        // cleaning up
        if (vertexShader) {
            glDeleteShader(vertexShader);
            vertexShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (*programPointer) {
            glDeleteProgram(*programPointer);
            *programPointer = 0;
        }
        return FALSE;
    }
    
    // Release vertex and fragment shaders.
    if (vertexShader) {
        glDeleteShader(vertexShader);
	}
    if (fragShader) {
        glDeleteShader(fragShader);
	}
    return TRUE;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    const GLchar * source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
#if defined(DEBUG)
        NSLog(@"Failed to load vertex shader");
#endif
        return FALSE;
    }
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    GLint status;
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return FALSE;
    }
    return TRUE;
}

- (BOOL)linkProgram:(GLuint)prog
{
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    GLint status;
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0)
        return FALSE;
    return TRUE;
}

- (BOOL)validateProgram:(GLuint)prog
{
    glValidateProgram(prog);
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
#endif
    GLint status;
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0)
        return FALSE;
    return TRUE;
}



#pragma mark -
#pragma mark TrackingCameraDelegate methods: get image from camera and process it

- (void)cameraHasConnected
{
#if defined(DEBUG)
    NSLog(@"Connected to camera");
#endif
}

//only to make screenshot
/*
- (CVPixelBufferRef )pixelBufferFromCGImage:(CGImageRef)image size:(CGSize)size
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey, 
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey, nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVReturn status = kCVReturnSuccess;
    status = CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32ARGB, (CFDictionaryRef) options, &pxbuffer);
    //CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA, (CFDictionaryRef) options, &pxbuffer);
    
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL); 
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, 4*size.width, rgbColorSpace, kCGImageAlphaPremultipliedLast);
    //CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, 4*size.width, rgbColorSpace, kCGImageAlphaLast);
    NSParameterAssert(context);
    
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    // Converting BGRA to RGBA
    
    unsigned char * p1line = (unsigned char *)pxdata;
    unsigned char * p2line = ((unsigned char *)pxdata)+2;
    for (int y=0; y<size.height; ++y) {
        unsigned char * p1 = p1line;
        unsigned char * p2 = p2line;
        p1line += ((int)size.width)*4;
        p2line += ((int)size.width)*4;
        for (int x=0; x<((int)size.width); ++x) {
            unsigned char tmp = *p1;
            *p1 = *p2;
            *p2 = tmp;
            p1 += 4;
            p2 += 4;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}
*/

- (CGImage *)fromCVImageBufferRef:(CVImageBufferRef)cameraFrame
{
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:cameraFrame];
    CIContext *temporaryContext = [CIContext contextWithEAGLContext:[_glView context]];
    //CIContext *temporaryContext = [CIContext contextWithOptions:nil]; //use contextWidthEAGLContext!!!
    CGImageRef videoImage = [temporaryContext
                             createCGImage:ciImage
                             fromRect:CGRectMake(0, 0,
                                                 CVPixelBufferGetWidth(cameraFrame),
                                                 CVPixelBufferGetHeight(cameraFrame))];
    return videoImage;
}

- (void)processNewCameraFrame:(CVImageBufferRef)cameraFrame
{
    if (rotating) {
        return; //not updating GLView on rotating animation (it looks ugly)
    }

    if (_processingImage == NO) {
        if (_closing) return;
        _processingImage = YES;
        
        // for screenshot
        //CGSize size = [image_for_screenshot size];
        //cameraFrame = (CVPixelBufferRef)[self pixelBufferFromCGImage:[image_for_screenshot CGImage] size:size];
        
///        CGImage * image = [self fromCVImageBufferRef:cameraFrame];
        
        CVPixelBufferLockBaseAddress(cameraFrame, 0);
        int bufferHeight = (int)CVPixelBufferGetHeight(cameraFrame);
        int bufferWidth = (int)CVPixelBufferGetWidth(cameraFrame);
    
        
        // Copy camera frame to buffer
        
        int scanline = (int)CVPixelBufferGetBytesPerRow(cameraFrame);
        
        // Execute face detection and recognition asynchronously
        
        DetectFaceParams args;
        args.width = bufferWidth;
        args.height = bufferHeight;
        args.scanline = scanline;
        args.buffer = (unsigned char *)CVPixelBufferGetBaseAddress(cameraFrame);
///        args.image = image; //if we need to use iOS functions to rotate/mirror image
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        if (orientation == 0 || orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
            //args.ratio = (float)self.view.bounds.size.height/(float)bufferWidth;
            //using _glView size proportional to video size:
            args.ratio = (float)self.view.bounds.size.width/(float)bufferHeight;
        } else {
            //args.ratio = (float)self.view.bounds.size.width/(float)bufferWidth;
            //using _glView size proportional to video size:
            args.ratio = (float)self.view.bounds.size.height/(float)bufferHeight;
        }
        NSData * argsobj = [NSData dataWithBytes:&args length:sizeof(DetectFaceParams)];
        
        CVPixelBufferRetain(cameraFrame);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self processImageAsyncWith:argsobj];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self drawFrameWithWidth:args.width Height:args.height Buffer:args.buffer CameraFrame:cameraFrame];
                CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
                CVPixelBufferRelease(cameraFrame);
                //free(buffer);
///                CGImageRelease(image);
            });
        });
        
        //[self drawFrameWithWidth:args.width Height:args.height Buffer:args.buffer];
        
        // will free (buffer) inside
        //[self performSelectorInBackground:@selector(processImageAsyncWith:) withObject:argsobj];
        
        // hang drawing
        //[self performSelectorOnMainThread:@selector(processImageAsyncWith:) withObject:argsobj waitUntilDone:YES];
        
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
    }
}



#pragma mark -
#pragma mark Buttons

- (UIImage *)onePixelImageWithColor:(UIColor *)color {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 1, 1, 8, 0, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, 1, 1));
    CGImageRef imgRef = CGBitmapContextCreateImage(context);
    UIImage *image = [UIImage imageWithCGImage:imgRef];
    CGImageRelease(imgRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    return image;
}

- (void)helpAction:(id)sender
{
    UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"LiveFacialFeatures" message:(NSString *)help_text delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
    alert.alertViewStyle = UIAlertViewStyleDefault;
    //alert.tag = 1; // is not needed, delegate is set no nil
    [alert show];
    [alert release];
}

- (void)fpsAction:(id)sender
{
    show_fps = !show_fps;
    UIBarButtonItem * button = sender;
    if (show_fps) {
        UIImage * background = [self onePixelImageWithColor:[[UIColor blackColor] colorWithAlphaComponent:0.7]];
        [button setBackgroundImage:background forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    } else {
        [button setBackgroundImage:nil forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    }
}



#pragma mark -
#pragma mark Device rotation support

//auto-rotate enabler (if compiling for iOS6+ only use the project's properties to enable orientations and change this method to shouldAutorotate)
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    //if (video_started) {
    //    rotating = YES;
    //}
    return YES;
}

/* does not work:
- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    if (video_started) {
        rotating = YES;
    }
    [UIView setAnimationDuration:duration];
    [UIView beginAnimations:nil context:NULL];
    _glView.transform = CGAffineTransformMakeRotation(M_PI/2);
    [UIView commitAnimations];
}
*/

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    //orientation = toInterfaceOrientation;
    rotating = YES;
    for (int i=0; i<MAX_FACES; ++i) {
        [trackingRects[i] setHidden:YES];
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            [trackingFeatures[i][j] setHidden:YES];
        }
    }
    [toolbar setHidden:YES];
    [_glView setHidden:YES];
    //[UIView setAnimationsEnabled:NO];
}

//not called on first times screen rotating in iOS (on start):
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    //[UIView setAnimationsEnabled:YES];
    for (int i=0; i<MAX_FACES; ++i) {
        [trackingRects[i] setHidden:NO];
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            [trackingFeatures[i][j] setHidden:NO];
        }
    }
    rotating = NO;
}

- (CGSize)screenSizeOrientationIndependent {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    return CGSizeMake(MIN(screenSize.width, screenSize.height), MAX(screenSize.width, screenSize.height));
}

- (void)relocateSubviewsForOrientation:(UIInterfaceOrientation)orientation
{
    [_glView destroyFramebuffer];
    [_glView removeFromSuperview]; //XXX: does not call [_glView release] immediately on iOS9!
    
    //[_glView release];
    //CGRect applicationFrame = [screenForDisplay applicationFrame];
    CGSize applicationFrame = [self screenSizeOrientationIndependent]; //workaround iOS 8 change, that sizes become orientation-dependent
    
    //DEBUG
    //const int video_width = 352;
    //const int video_height = 288;
    
    const int video_width = (int)camera.width;//640;
    const int video_height = (int)camera.height;//480;
    
    if (orientation == 0 || orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
        //_glView = [[TrackingGLView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, applicationFrame.size.width, applicationFrame.size.height)];
        //using _glView size proportional to video size:
        _glView = [[TrackingGLView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, applicationFrame.width, applicationFrame.width * (video_width*1.0f/video_height))];
    } else {
        //_glView = [[TrackingGLView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, applicationFrame.size.height, applicationFrame.size.width)];
        //using _glView size proportional to video size:
        _glView = [[TrackingGLView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, applicationFrame.width * (video_width*1.0f/video_height), applicationFrame.width)];
    }
    [self.view addSubview:_glView];
    [_glView release]; //now self.view is responsible for the view
    [self loadVertexShader:@"DirectDisplayShader" fragmentShader:@"DirectDisplayShader" forProgram:&directDisplayProgram];
    for (int i=0; i<MAX_FACES; ++i) {
        [_glView.layer addSublayer:trackingRects[i]];
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            [_glView.layer addSublayer:trackingFeatures[i][j]];
        }
    }
    [_glView.layer addSublayer:drawFps];
    
    // Toolbar re-alignment
    CGFloat toolbarHeight = [toolbar frame].size.height;
    CGRect mainViewBounds = self.view.bounds;
    [toolbar setFrame:CGRectMake(CGRectGetMinX(mainViewBounds),
                                 CGRectGetMinY(mainViewBounds) + CGRectGetHeight(mainViewBounds) - (toolbarHeight),
                                 CGRectGetWidth(mainViewBounds),
                                 toolbarHeight)];
    [toolbar setHidden:NO];
    [self.view sendSubviewToBack:_glView];
    
    [self onGLInit];
}



#pragma mark -
#pragma mark Face detection and recognition

- (void)processImageAsyncWith:(NSData *)args
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init]; //required for async execution
    // Do not forget to [pool release] on exit!
    
    if (_closing) {
        [pool release];
        return;
    }
    
    // Reading buffer parameters
    
    DetectFaceParams a;
    [args getBytes:&a length:sizeof(DetectFaceParams)];
    unsigned char * buffer = a.buffer;
    int width = a.width;
    int height = a.height;
    int scanline = a.scanline;
    float ratio = a.ratio;
    
    FSDK_SwapRedAndBlueChannels(buffer, scanline, width, height, 4);
    
    HImage image;
    int res = FSDK_LoadImageFromBuffer(&image, buffer, width, height, scanline, FSDK_IMAGE_COLOR_32BIT);
    if (res != FSDKE_OK) {
#if defined(DEBUG)
        NSLog(@"FSDK_LoadImageFromBuffer failed with %d", res);
#endif
        [pool release];
        _processingImage = NO;
        return;
    }
    
    // Rotating image basing on orientation
    
    HImage derotated_image;
    res = FSDK_CreateEmptyImage(&derotated_image);
    if (res != FSDKE_OK) {
#if defined(DEBUG)
        NSLog(@"FSDK_CreateEmptyImage failed with %d", res);
#endif
        FSDK_FreeImage(image);
        [pool release];
        _processingImage = NO;
        return;
    }
    UIInterfaceOrientation df_orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (df_orientation == 0 || df_orientation == UIInterfaceOrientationPortrait) {
        res = FSDK_RotateImage90(image, 1, derotated_image);
    } else if (df_orientation == UIInterfaceOrientationPortraitUpsideDown) {
        res = FSDK_RotateImage90(image, -1, derotated_image);
    } else if (df_orientation == UIInterfaceOrientationLandscapeLeft) {
        res = FSDK_RotateImage90(image, 0, derotated_image); //will simply copy image
    } else if (df_orientation == UIInterfaceOrientationLandscapeRight) {
        res = FSDK_RotateImage90(image, 2, derotated_image);
    }
    if (res != FSDKE_OK) {
#if defined(DEBUG)
        NSLog(@"FSDK_RotateImage90 failed with %d", res);
#endif
        FSDK_FreeImage(image);
        FSDK_FreeImage(derotated_image);
        [pool release];
        _processingImage = NO;
        return;
    }
    
    //res = FSDK_MirrorImage(image, true);
    res = FSDK_MirrorImage(derotated_image, true);
    if (res != FSDKE_OK) {
#if defined(DEBUG)
        NSLog(@"FSDK_MirrorImage failed with %d", res);
#endif
        FSDK_FreeImage(image);
        FSDK_FreeImage(derotated_image);
        [pool release];
        _processingImage = NO;
        return;
    }
    
    // Passing frame to FaceSDK, reading face coordinates and names
    
    long long count = 0;
    FSDK_FeedFrame(_tracker, 0, derotated_image, &count, IDs, sizeof(IDs));

    [faceDataLock lock];
    memset(faces, 0, sizeof(FaceRectangle)*MAX_FACES);
    memset(features, 0, sizeof(FSDK_Features)*MAX_FACES);
    
    for (size_t i = 0; i < (size_t)count; ++i) {
        FSDK_GetTrackerFacialFeatures(_tracker, 0, IDs[i], &(features[i]));
        //FSDK_Features Eyes;
        //FSDK_GetTrackerEyes(_tracker, 0, IDs[i], &Eyes);
        GetFaceFrame(&(features[i]), &(faces[i].x1), &(faces[i].y1), &(faces[i].x2), &(faces[i].y2));
        
        faces[i].x1 *= ratio;
        faces[i].x2 *= ratio;
        faces[i].y1 *= ratio;
        faces[i].y2 *= ratio;
        
        for (int j=0; j<FSDK_FACIAL_FEATURE_COUNT; ++j) {
            (features[i])[j].x *= ratio;
            (features[i])[j].y *= ratio;
        }

        //NSLog(@"w=%d x=%d y=%d", faces[i].w, faces[i].xc, faces[i].yc);
    }
    [faceDataLock unlock];
    
    
    // Saving image to gallery (debug)
    
    /*
    static BOOL image_saved = NO;
    static int framenum = 0;
    if (!image_saved && framenum++ > 10) {
        NSString * imagePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Test.png"];
        //res = FSDK_SaveImageToFile(image, (char *)[imagePath UTF8String]);
        res = FSDK_SaveImageToFile(derotated_image, (char *)[imagePath UTF8String]);
        NSLog(@"saved to %s with %d", [imagePath UTF8String], res);
        UIImage * cocoa_image = [UIImage imageWithContentsOfFile:imagePath];
        UIImageWriteToSavedPhotosAlbum(cocoa_image, nil, nil, nil);
         
        image_saved = YES;
    }
    */
    
    
    FSDK_FreeImage(image);
    FSDK_FreeImage(derotated_image);
    
    [pool release];
    _processingImage = NO;
}

@end
