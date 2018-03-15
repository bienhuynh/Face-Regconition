/*
 * AgeGenderRecognitionApp.java
 */

package agegenderrecognition;

import org.jdesktop.application.Application;
import org.jdesktop.application.SingleFrameApplication;
import java.awt.event.*;

/**
 * The main class of the application.
 */
public class AgeGenderRecognitionApp extends SingleFrameApplication {
    private AgeGenderRecognitionView genderRecognitionViewFrame;

    /**
     * At startup create and show the main frame of the application.
     */
    @Override protected void startup() {
        genderRecognitionViewFrame = new AgeGenderRecognitionView(this);
        show(genderRecognitionViewFrame);
    }

    /**
     * This method is to initialize the specified window by injecting resources.
     * Windows shown in our application come fully initialized from the GUI
     * builder, so this additional configuration is not needed.
     */
    @Override protected void configureWindow(java.awt.Window root) {
        root.addWindowListener(new WindowAdapter() {
            @Override
            public void windowClosing(WindowEvent e) {
                genderRecognitionViewFrame.drawingTimer.stop();
                try{
                    Thread.sleep(40);
                }
                catch (java.lang.InterruptedException exception){
                }
                genderRecognitionViewFrame.closeCamera();
            }
        });
    }

    /**
     * A convenient static getter for the application instance.
     * @return the instance of AgeGenderRecognitionApp
     */
    public static AgeGenderRecognitionApp getApplication() {
        return Application.getInstance(AgeGenderRecognitionApp.class);
    }

    /**
     * Main method launching the application.
     */
    public static void main(String[] args) {
        launch(AgeGenderRecognitionApp.class, args);
    }
}
