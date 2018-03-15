
package com.luxand.livefacialfeatures;

import com.luxand.FSDK;
import com.luxand.FSDK.FSDK_Features;
import com.luxand.FSDK.FSDK_IMAGEMODE;
import com.luxand.FSDK.HTracker;
import com.luxand.livefacialfeatures.R;

import java.nio.ByteBuffer;
import java.util.List;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Paint.Align;
import android.graphics.RectF;
import android.graphics.SurfaceTexture;
import android.graphics.drawable.ColorDrawable;
import android.hardware.Camera;
import android.hardware.Camera.PreviewCallback;
import android.hardware.Camera.Size;
import android.os.Bundle;
import android.os.Environment;
import android.support.v8.renderscript.Allocation;
import android.support.v8.renderscript.Element;
import android.support.v8.renderscript.RenderScript;
import android.support.v8.renderscript.ScriptIntrinsicYuvToRGB;
import android.support.v8.renderscript.Type;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.View.OnClickListener;
import android.view.Window;
import android.view.WindowManager;
import android.view.ViewGroup.LayoutParams;

public class MainActivity extends Activity implements OnClickListener {
    public static boolean sIsShowingProcessedFrameOnly = true;
    public static boolean sIsUsingRenderScript = true;
    public static boolean sIsRotatingWithRenderScript = true && sIsUsingRenderScript;

    private Preview mPreview;
    private ProcessImageAndDrawResults mDraw;
    private boolean mIsFailed = false;

    private final String help_text = "LiveFacialFeatures is as much a developer tool as it is a conceptual proof of technology showcasing Luxand FaceSDK, an innovative way to have fun. Demonstrating the high-tech features found in Luxand’s FaceSDK, LiveFacialFeatures detects and displays some 70 facial features in real time.\n\nThe SDK is available for mobile developers: www.luxand.com/facesdk";

    public static float sDensity = 1.0f;
    
    public void showErrorAndClose(String error, int code) {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setMessage(error + ": " + code)
                .setPositiveButton("Ok", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        finish();
                        //android.os.Process.killProcess(android.os.Process.myPid());
                    }
                })
                .show();
    }

    public void showMessage(String message) {
        AlertDialog.Builder builder = new AlertDialog.Builder(this);
        builder.setMessage(message)
                .setPositiveButton("Ok", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                    }
                })
                .setCancelable(false) // cancel with button only
                .show();
    }


    /** Called when the activity is first created. */
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        sDensity = getResources().getDisplayMetrics().scaledDensity;

        int res = FSDK.ActivateLibrary("fhPKopJVjHpnsV6/aumzjOvApHU7gnFduuovOu1DRngQEEevUnlpLfSAhNIhLVjzPYYbhmrz36x9Xnn1AZ/8HOcgXtIaZxOxZzNXNwS3ezLiwFwZGhY9w3S+beKvuIC8DhosdzRYCSGx4H9hC1A+jAHqTPjBTr42nKiOZ+y3H70=");
        if (res != FSDK.FSDKE_OK) {
            mIsFailed = true;
            showErrorAndClose("FaceSDK activation failed", res);
        } else {
            FSDK.Initialize();

            // Hide the window title (it is done in manifest too)
            getWindow()
                    .setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);
            requestWindowFeature(Window.FEATURE_NO_TITLE);

            // Lock orientation
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);

            // Camera layer and drawing layer
            mDraw = new ProcessImageAndDrawResults(this);
            mPreview = new Preview(this, mDraw);
            mDraw.mTracker = new HTracker();
            res = FSDK.CreateTracker(mDraw.mTracker);
            if (FSDK.FSDKE_OK != res) {
                showErrorAndClose("Error creating tracker", res);
            }

            int errpos[] = new int[1];
            FSDK.SetTrackerMultipleParameters(
                    mDraw.mTracker,
                    "RecognizeFaces=false;DetectFacialFeatures=true;ContinuousVideoFeed=true;ThresholdFeed=0.97;MemoryLimit=1000;HandleArbitraryRotations=false;DetermineFaceRotationAngle=false;InternalResizeWidth=70;FaceDetectionThreshold=3",
                    errpos);
            if (errpos[0] != 0) {
                showErrorAndClose("Error setting tracker parameters, position", errpos[0]);
            }

            this.getWindow().setBackgroundDrawable(new ColorDrawable()); //black background

            setContentView(mPreview); //creates MainActivity contents
            addContentView(mDraw, new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT));


            // Menu
            LayoutInflater inflater = (LayoutInflater) this.getSystemService(Context.LAYOUT_INFLATER_SERVICE);
            View buttons = inflater.inflate(R.layout.bottom_menu, null);
            buttons.findViewById(R.id.helpButton).setOnClickListener(this);
            addContentView(buttons, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
        }
    }

    @Override
    public void onClick(View view) {
        if (view.getId() == R.id.helpButton) {
            showMessage(help_text);
        }
    }

    @Override
    public void onPause() {
        super.onPause();
        if (mIsFailed)
            return;
        pauseProcessingFrames();
    }

    @Override
    public void onResume() {
        super.onResume();
        if (mIsFailed)
            return;
        resumeProcessingFrames();
    }

    private void pauseProcessingFrames() {
        mDraw.stopping = 1;

        // It is essential to limit wait time, because stopped will not be set to 0, if no frames are feeded to mDraw
        for (int i = 0; i < 100; ++i) {
            if (mDraw.stopped != 0)
                break;
            try {
                Thread.sleep(10);
            } catch (Exception ex) {
            }
        }
    }

    private void resumeProcessingFrames() {
        mDraw.stopped = 0;
        mDraw.stopping = 0;
    }
}


class FaceRectangle {
    public int x1, y1, x2, y2;
}

// Draw graphics on top of the video
class ProcessImageAndDrawResults extends View {
    public static final int MAX_FACES = 5;

    public HTracker mTracker;
    public volatile int stopping, stopped;
    public byte[] yuvData, rgbData;
    public int imageWidth, imageHeight;
    public boolean first_frame_saved;
    public boolean rotated;
    
    private final FSDK.HImage mImage = new FSDK.HImage();
    private final FSDK.HImage mRotatedImage = new FSDK.HImage();
    private final FSDK.FSDK_IMAGEMODE mImageMode = new FSDK.FSDK_IMAGEMODE();
    private final FSDK_Features[] mFacialFeatures = new FSDK_Features[MAX_FACES];
    private final FaceRectangle[] mFacePositions = new FaceRectangle[MAX_FACES];
    private final RectF mRectangle = new RectF();
    private Paint mPaintGreen, mPaintBlue, mPaintBlueTransparent, mPaintGreenTransparent;
    private Matrix mMatrix = new Matrix();
    private Bitmap mBitmap;
    private int mFrameCount = 0;
    private long mTime = 0;
    private float mFps = 0.0f;
    private Context mContext;
    
    private RenderScript mRenderScript;
    private ScriptIntrinsicYuvToRGB mRenderScriptIntrinsicFunc;
    private ScriptC_Rotate mRenderScriptRotate;
    private Type.Builder mYuvType;
    private Type.Builder mRgbType;
    private int mAllocatedLength = 0;
    private int mAllocatedWidth = 0;
    private int mAllocatedHeight = 0;
    Allocation mIn;
    Allocation mOut;
    Allocation mOutRotated;
    
    private static int sSavedImageIndex = 0;
    
    private int GetFaceFrame(FSDK.FSDK_Features features, FaceRectangle fr) {
        if (features == null || fr == null)
            return FSDK.FSDKE_INVALID_ARGUMENT;

        float u1 = features.features[0].x;
        float v1 = features.features[0].y;
        float u2 = features.features[1].x;
        float v2 = features.features[1].y;
        float xc = (u1 + u2) / 2;
        float yc = (v1 + v2) / 2;
        int w = (int) Math.pow((u2 - u1) * (u2 - u1) + (v2 - v1) * (v2 - v1), 0.5);

        fr.x1 = (int) (xc - w * 1.6 * 0.9);
        fr.y1 = (int) (yc - w * 1.1 * 0.9);
        fr.x2 = (int) (xc + w * 1.6 * 0.9);
        fr.y2 = (int) (yc + w * 2.1 * 0.9);
        if (fr.x2 - fr.x1 > fr.y2 - fr.y1) {
            fr.x2 = fr.x1 + fr.y2 - fr.y1;
        } else {
            fr.y2 = fr.y1 + fr.x2 - fr.x1;
        }
        return 0;
    }

    public ProcessImageAndDrawResults(Context context) {
        super(context);
        mContext = context;

        for (int i = 0; i < MAX_FACES; ++i) {
            mFacePositions[i] = new FaceRectangle();
        }
        for (int i = 0; i < MAX_FACES; ++i) {
            mFacialFeatures[i] = new FSDK_Features();
        }

        stopping = 0;
        stopped = 0;
        rotated = false;
        mPaintGreen = new Paint();
        mPaintGreen.setStyle(Paint.Style.FILL);
        mPaintGreen.setColor(Color.GREEN);
        mPaintGreen.setTextSize(18 * MainActivity.sDensity);
        mPaintGreen.setTextAlign(Align.LEFT);
        mPaintBlue = new Paint();
        mPaintBlue.setStyle(Paint.Style.FILL);
        mPaintBlue.setColor(Color.BLUE);
        mPaintBlue.setTextSize(18 * MainActivity.sDensity);
        mPaintBlue.setTextAlign(Align.CENTER);

        mPaintBlueTransparent = new Paint();
        mPaintBlueTransparent.setStyle(Paint.Style.STROKE);
        mPaintBlueTransparent.setStrokeWidth(2 * MainActivity.sDensity);
        mPaintBlueTransparent.setColor(Color.BLUE);
        mPaintBlueTransparent.setTextSize(18 * MainActivity.sDensity);

        mPaintGreenTransparent = new Paint();
        mPaintGreenTransparent.setStyle(Paint.Style.STROKE);
        mPaintGreenTransparent.setStrokeWidth(2 * MainActivity.sDensity);
        mPaintGreenTransparent.setColor(Color.GREEN);
        mPaintGreenTransparent.setTextSize(18 * MainActivity.sDensity);

        
        yuvData = null;
        rgbData = null;

        first_frame_saved = false;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        if (stopping == 1) {
            stopped = 1;
            super.onDraw(canvas);
            return;
        }

        if (yuvData == null) {
            super.onDraw(canvas);
            return; //nothing to process or name is being entered now
        }
        
        int canvasWidth = canvas.getWidth();
        //int canvasHeight = canvas.getHeight();
        
        // Convert from YUV to RGB
        if (MainActivity.sIsUsingRenderScript) {
            if (null == mRenderScript)
                mRenderScript = RenderScript.create(mContext);
            if (null == mRenderScriptIntrinsicFunc)
                mRenderScriptIntrinsicFunc = ScriptIntrinsicYuvToRGB.create(mRenderScript, Element.U8_4(mRenderScript));
            if (null == mYuvType)
                mYuvType = new Type.Builder(mRenderScript, Element.U8(mRenderScript));
            if (null == mRgbType)
                mRgbType = new Type.Builder(mRenderScript, Element.RGBA_8888(mRenderScript));
            if (yuvData.length != mAllocatedLength || imageWidth != mAllocatedWidth || imageHeight != mAllocatedHeight
                    || null == mIn || null == mOut) {
                mYuvType.setX(yuvData.length);
                mRgbType.setX(imageWidth);
                mRgbType.setY(imageHeight);
                mIn = Allocation.createTyped(mRenderScript, mYuvType.create(), Allocation.USAGE_SCRIPT);
                mOut = Allocation.createTyped(mRenderScript, mRgbType.create(), Allocation.USAGE_SCRIPT);
                
                // for rotation
                mRgbType.setX(imageHeight);
                mRgbType.setY(imageWidth);
                mOutRotated = Allocation.createTyped(mRenderScript, mRgbType.create(), Allocation.USAGE_SCRIPT);
                
                mAllocatedWidth = imageWidth;
                mAllocatedHeight = imageHeight;
                mAllocatedLength = yuvData.length;
            }
            mIn.copyFrom(yuvData);
            mRenderScriptIntrinsicFunc.setInput(mIn);
            mRenderScriptIntrinsicFunc.forEach(mOut);
            
            if (!MainActivity.sIsRotatingWithRenderScript || !rotated) {
                mOut.copyTo(rgbData);
            } else if (MainActivity.sIsRotatingWithRenderScript && rotated) {
                // rotate -90 here
                if (null == mRenderScriptRotate) {
                    mRenderScriptRotate = new ScriptC_Rotate(mRenderScript);
                }
                mRenderScriptRotate.set_inImage(mOut);
                mRenderScriptRotate.set_inWidth(imageWidth);
                mRenderScriptRotate.set_inHeight(imageHeight);
                mRenderScriptRotate.forEach_rotate_90_clockwise(mOutRotated, mOutRotated);
                mOutRotated.copyTo(rgbData);
            }
        } else {
            decodeYUV420SP(rgbData, yuvData, imageWidth, imageHeight);
        }
        
        // Load image to FaceSDK
        mImageMode.mode = FSDK_IMAGEMODE.FSDK_IMAGE_COLOR_32BIT;
        if (!MainActivity.sIsRotatingWithRenderScript) {
            FSDK.LoadImageFromBuffer(mImage, rgbData, imageWidth, imageHeight, imageWidth * 4, mImageMode);
        } else if (MainActivity.sIsRotatingWithRenderScript && rotated) {
            FSDK.LoadImageFromBuffer(mImage, rgbData, imageHeight, imageWidth, imageHeight * 4, mImageMode);
        }
        if (!MainActivity.sIsShowingProcessedFrameOnly) {
            FSDK.MirrorImage(mImage, false); // Android mirrors image in camera preview
        }
        FSDK.CreateEmptyImage(mRotatedImage);

        //it is necessary to work with local variables (onDraw called not the time when mImageWidth,... being reassigned, so swapping mImageWidth and mImageHeight may be not safe)
        int ImageWidth = imageWidth;
        int ImageHeight = imageHeight;
        if (rotated) {
            if (!MainActivity.sIsRotatingWithRenderScript) {
                ImageWidth = imageHeight;
                ImageHeight = imageWidth;
                FSDK.RotateImage90(mImage, -1, mRotatedImage);
            } else if (MainActivity.sIsRotatingWithRenderScript) {
                ImageWidth = imageHeight;
                ImageHeight = imageWidth;
            }
        }
        
        // Save first frame to gallery to debug (e.g. rotation angle)
        /*
        if (!first_frame_saved) {				
        	first_frame_saved = true;
        	String galleryPath = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath();
        	FSDK.SaveImageToFile(mRotatedImage, galleryPath + "/first_frame.jpg"); //frame is rotated!
        }
        */
        
        /*
        ++sSavedImageIndex;
        String galleryPath = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath();
        int res = FSDK.SaveImageToFile(mRotatedImage, galleryPath + "/frame" + sSavedImageIndex + ".jpg"); //frame is rotated!
        Log.d("", "SAVERESULT: " + res);
        */

        long IDs[] = new long[MAX_FACES];
        long face_count[] = new long[1];

        if (!MainActivity.sIsRotatingWithRenderScript && rotated) {
            FSDK.FeedFrame(mTracker, 0, mRotatedImage, face_count, IDs);
            FSDK.FreeImage(mRotatedImage);
            FSDK.FreeImage(mImage);
        } else {
            FSDK.FeedFrame(mTracker, 0, mImage, face_count, IDs);
            FSDK.FreeImage(mImage);
        }

        //canvas.drawText("FeedFrame: " + res + " " + Calendar.getInstance().get(Calendar.SECOND), marginWidth+300, 30, mPaintGreen);
        //canvas.drawText("FaceCount: " + face_count[0], marginWidth+10, 30, mPaintGreen);
        for (int i = 0; i < MAX_FACES; ++i) {
            mFacePositions[i].x1 = 0;
            mFacePositions[i].y1 = 0;
            mFacePositions[i].x2 = 0;
            mFacePositions[i].y2 = 0;
        }
        float ratio = (canvasWidth * 1.0f) / ImageWidth;
        for (int i = 0; i < (int) face_count[0]; ++i) {
            FSDK.GetTrackerFacialFeatures(mTracker, 0, IDs[i], mFacialFeatures[i]);
            GetFaceFrame(mFacialFeatures[i], mFacePositions[i]);
        }
        Log.d("", "FACES: " + face_count[0]);
        
        if (MainActivity.sIsShowingProcessedFrameOnly) {
            if (!MainActivity.sIsRotatingWithRenderScript || !rotated) {
                if (mBitmap == null) {
                    mBitmap = Bitmap.createBitmap(imageWidth, imageHeight, Bitmap.Config.ARGB_8888);
                }
                mBitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgbData));
    
                mMatrix.reset();
                if (rotated) {
                    mMatrix.postRotate(-90);
                    mMatrix.postTranslate(0, imageWidth);
                    mMatrix.postScale(ImageWidth*ratio / imageHeight, ImageHeight*ratio / imageWidth);
                } else {
                    mMatrix.postScale(ImageWidth*ratio / imageWidth, ImageHeight*ratio / imageHeight);
                }
            } else if (MainActivity.sIsRotatingWithRenderScript && rotated) {
                if (mBitmap == null) {
                    mBitmap = Bitmap.createBitmap(imageHeight, imageWidth, Bitmap.Config.ARGB_8888);
                }
                mBitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgbData));
                mMatrix.reset();
                mMatrix.postScale(ImageWidth*ratio / imageHeight, ImageHeight*ratio / imageWidth);                
            }
            canvas.drawBitmap(mBitmap, mMatrix, null);
        }
        
        // Mark faces and features
        for (int i = 0; i < face_count[0]; ++i) {
            mRectangle.left    = mFacePositions[i].x1 * ratio;
            mRectangle.top     = mFacePositions[i].y1 * ratio;
            mRectangle.right   = mFacePositions[i].x2 * ratio;
            mRectangle.bottom  = mFacePositions[i].y2 * ratio;
            float diam    = 2 * MainActivity.sDensity;
            canvas.drawRect(mRectangle, mPaintBlueTransparent);
            for (int j = 0; j < FSDK.FSDK_FACIAL_FEATURE_COUNT; ++j) {
                mRectangle.left   = mFacialFeatures[i].features[j].x * ratio - diam;
                mRectangle.top    = mFacialFeatures[i].features[j].y * ratio - diam;
                mRectangle.right  = mFacialFeatures[i].features[j].x * ratio + diam;
                mRectangle.bottom = mFacialFeatures[i].features[j].y * ratio + diam;
                if (j == FSDK.FSDKP_LEFT_EYE_LOWER_LINE2 || j == FSDK.FSDKP_LEFT_EYE_UPPER_LINE2
                        || j == FSDK.FSDKP_RIGHT_EYE_LOWER_LINE2 || j == FSDK.FSDKP_RIGHT_EYE_UPPER_LINE2) {
                    canvas.drawOval(mRectangle, mPaintGreenTransparent);
                } else {
                    canvas.drawOval(mRectangle, mPaintBlueTransparent);
                }
            }
        }
        
        //canvas.drawText("FeedFrame: " + res + " " + Calendar.getInstance().get(Calendar.SECOND), marginWidth+300, 30, mPaintGreen);
        ++mFrameCount;
        long now = System.currentTimeMillis();
        if (mTime == 0) mTime = now;
        long diff = now - mTime;
        //Log.d("", "DIFF: " + diff);
        if (diff >= 3000) {
            mFps = mFrameCount / (diff / 1000.0f);
            mFrameCount = 0;
            mTime = 0;
        }
        canvas.drawText("FPS: " + mFps, 60 * MainActivity.sDensity, 60 * MainActivity.sDensity, mPaintGreen);
        
        super.onDraw(canvas);
    } // end onDraw method

    static public void decodeYUV420SP(byte[] rgba, byte[] yuv420sp, int width, int height) {
        final int frameSize = width * height;
        int yp = 0;
        for (int j = 0; j < height; j++) {
            int uvp = frameSize + (j >> 1) * width, u = 0, v = 0;
            for (int i = 0; i < width; i++) {
                int y = (0xff & ((int) yuv420sp[yp])) - 16;
                if (y < 0)
                    y = 0;
                if ((i & 1) == 0) {
                    v = (0xff & yuv420sp[uvp++]) - 128;
                    u = (0xff & yuv420sp[uvp++]) - 128;
                }
                int y1192 = 1192 * y;
                int r = (y1192 + 1634 * v);
                int g = (y1192 - 833 * v - 400 * u);
                int b = (y1192 + 2066 * u);
                if (r < 0)
                    r = 0;
                else if (r > 262143)
                    r = 262143;
                if (g < 0)
                    g = 0;
                else if (g > 262143)
                    g = 262143;
                if (b < 0)
                    b = 0;
                else if (b > 262143)
                    b = 262143;

                //for int[]
                //rgb[yp] = 0xff000000 | ((r << 6) & 0xff0000) | ((g >> 2) & 0xff00) | ((b >> 10) & 0xff);
                rgba[4*yp] = (byte) ((r >> 10) & 0xff);
                rgba[4*yp + 1] = (byte) ((g >> 10) & 0xff);
                rgba[4*yp + 2] = (byte) ((b >> 10) & 0xff);
                rgba[4*yp + 3] = (byte) 0xff;
                ++yp;
            }
        }
    }
} // end of ProcessImageAndDrawResults class


// Show video from camera and pass frames to ProcessImageAndDraw class 
class Preview extends SurfaceView implements SurfaceHolder.Callback {
    private Context mContext;
    private SurfaceHolder mHolder;
    @SuppressWarnings("deprecation")
    private Camera mCamera;
    private ProcessImageAndDrawResults mDraw;
    private boolean mFinished;
    private SurfaceTexture mTexture = new SurfaceTexture(0);

    @SuppressWarnings("deprecation")
    Preview(Context context, ProcessImageAndDrawResults draw) {
        super(context);
        mContext = context;
        mDraw = draw;

        //Install a SurfaceHolder.Callback so we get notified when the underlying surface is created and destroyed.
        //NOTE: the methods below are corresponding to the Callback interface!
        mHolder = getHolder();
        mHolder.addCallback(this);
        mHolder.setType(SurfaceHolder.SURFACE_TYPE_PUSH_BUFFERS);
    }

    //SurfaceView callback
    @SuppressWarnings("deprecation")
    public void surfaceCreated(SurfaceHolder holder) {
        mFinished = false;

        /*
        if (mDraw == null)
        	((MainActivity)mContext).showMessage("surfaceCreated; mDraw == null");
        else
        	((MainActivity)mContext).showMessage("surfaceCreated; mDraw != null");		
        */

        // Find the ID of the camera
        int cameraId = 0;
        boolean frontCameraFound = false;
        Camera.CameraInfo cameraInfo = new Camera.CameraInfo();
        for (int i = 0; i < Camera.getNumberOfCameras(); i++) {
            Camera.getCameraInfo(i, cameraInfo);
            //if (cameraInfo.facing == Camera.CameraInfo.CAMERA_FACING_BACK)
            if (cameraInfo.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
                cameraId = i;
                frontCameraFound = true;
            }
        }

        if (frontCameraFound) {
            mCamera = Camera.open(cameraId);
        } else {
            mCamera = Camera.open();
        }

        try {
            if (MainActivity.sIsShowingProcessedFrameOnly) {
                // using texture to do not show preview here (since we want to show frame with marked facial features)
                mCamera.setPreviewTexture(mTexture);
            } else {
                mCamera.setPreviewDisplay(holder);
            }
            
            // Preview callback used whenever new viewfinder frame is available
            mCamera.setPreviewCallback(new PreviewCallback() {
                public void onPreviewFrame(byte[] data, Camera camera) {
                    if ((mDraw == null) || mFinished)
                        return;

                    if (mDraw.yuvData == null && camera.getParameters().getPreviewSize().width > 0 && camera.getParameters().getPreviewSize().height > 0) {
                        // Initialize the draw-on-top companion
                        Camera.Parameters params = camera.getParameters();
                        mDraw.imageWidth = params.getPreviewSize().width;
                        mDraw.imageHeight = params.getPreviewSize().height;
                        mDraw.rgbData = new byte[4 * mDraw.imageWidth * mDraw.imageHeight];
                        mDraw.yuvData = new byte[data.length];
                    }

                    if (mDraw.yuvData != null) {
                        // Pass YUV data to draw-on-top companion
                        System.arraycopy(data, 0, mDraw.yuvData, 0, data.length);
                        mDraw.invalidate();
                    }
                }
            });
        }
        //catch (IOException exception) {
        catch (Exception exception) {
            AlertDialog.Builder builder = new AlertDialog.Builder(mContext);
            builder.setMessage("Cannot open camera")
                    .setPositiveButton("Ok", new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialogInterface, int i) {
                            android.os.Process.killProcess(android.os.Process.myPid());
                        }
                    })
                    .show();
            if (mCamera != null) {
                mCamera.release();
                mCamera = null;
            }
        }
    }

    //SurfaceView callback
    @SuppressWarnings("deprecation")
    public void surfaceDestroyed(SurfaceHolder holder) {
        // Surface will be destroyed when we return, so stop the preview.
        // Because the CameraDevice object is not a shared resource, it's very
        // important to release it when the activity is paused.
        mFinished = true;
        if (mCamera != null) {
            mCamera.setPreviewCallback(null);
            mCamera.stopPreview();
            mCamera.release();
            mCamera = null;
        }
    }

    //SurfaceView callback, configuring camera
    @SuppressWarnings("deprecation")
    public void surfaceChanged(SurfaceHolder holder, int format, int w, int h) {
        if (mCamera == null)
            return;

        // Now that the size is known, set up the camera parameters and begin
        // the preview.
        Camera.Parameters parameters = mCamera.getParameters();

        //Keep uncommented to work correctly on phones:
        //This is an undocumented although widely known feature
        /**/
        if (this.getResources().getConfiguration().orientation != Configuration.ORIENTATION_LANDSCAPE) {
            // This is an undocumented although widely known feature
            parameters.set("orientation", "portrait");
            mCamera.setDisplayOrientation(90); // For Android 2.2 and above
            mDraw.rotated = true;
        } else {
            // This is an undocumented although widely known feature
            parameters.set("orientation", "landscape");
            mCamera.setDisplayOrientation(0); // For Android 2.2 and above
        }
        /**/
        
        // choose preview size closer to 640x480 for optimal performance
        List<Size> supportedSizes = parameters.getSupportedPreviewSizes();
        int width = 0;
        int height = 0;
        for (Size s: supportedSizes) {
            if ((width - 640)*(width - 640) + (height - 480)*(height - 480) > 
                    (s.width - 640)*(s.width - 640) + (s.height - 480)*(s.height - 480)) {
                width = s.width;
                height = s.height;
            }
        }
        
        //try to set preferred parameters
        try {
            if (width*height > 0) {
                parameters.setPreviewSize(width, height);
            }
            parameters.setPreviewFormat(ImageFormat.NV21);
            //parameters.setPreviewFrameRate(10);
            parameters.setSceneMode(Camera.Parameters.SCENE_MODE_PORTRAIT);
            parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
            mCamera.setParameters(parameters);
        } catch (Exception ex) {
        }
        
        parameters = mCamera.getParameters();
        Camera.Size previewSize = parameters.getPreviewSize();
        makeResizeForCameraAspect(1.0f / ((1.0f * previewSize.width) / previewSize.height));
        mCamera.startPreview();
    }

    private void makeResizeForCameraAspect(float cameraAspectRatio) {
        LayoutParams layoutParams = this.getLayoutParams();
        int matchParentWidth = this.getWidth();
        int newHeight = (int) (matchParentWidth / cameraAspectRatio);
        if (newHeight != layoutParams.height) {
            layoutParams.height = newHeight;
            layoutParams.width = matchParentWidth;
            this.setLayoutParams(layoutParams);
            this.invalidate();
        }
    }
} // end of Preview class
