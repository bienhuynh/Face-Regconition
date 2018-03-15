/*
 * ExpressionRecognitionApp.java
 */

package Expressionrecognition;

import org.jdesktop.application.Application;
import org.jdesktop.application.SingleFrameApplication;
import java.awt.event.*;

/**
 * The main class of the application.
 */
public class ExpressionRecognitionApp extends SingleFrameApplication {
    private ExpressionRecognitionView ExpressionRecognitionViewFrame;

    /**
     * At startup create and show the main frame of the application.
     */
    @Override protected void startup() {
        ExpressionRecognitionViewFrame = new ExpressionRecognitionView(this);
        show(ExpressionRecognitionViewFrame);
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
                ExpressionRecognitionViewFrame.drawingTimer.stop();
                try{
                    Thread.sleep(40);
                }
                catch (java.lang.InterruptedException exception){
                }
                ExpressionRecognitionViewFrame.closeCamera();
            }
        });
    }

    /**
     * A convenient static getter for the application instance.
     * @return the instance of ExpressionRecognitionApp
     */
    public static ExpressionRecognitionApp getApplication() {
        return Application.getInstance(ExpressionRecognitionApp.class);
    }

    /**
     * Main method launching the application.
     */
    public static void main(String[] args) {
        launch(ExpressionRecognitionApp.class, args);
    }
}
