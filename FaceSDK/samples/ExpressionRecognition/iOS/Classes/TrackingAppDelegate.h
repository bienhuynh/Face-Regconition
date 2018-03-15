//
//  based on ColorTrackingAppDelegate.h
//  from ColorTracking application
//  The source code for this application is available under a BSD license.
//  See ColorTrackingLicense.txt for details.
//  Created by Brad Larson on 10/7/2010.
//  Modified by Anton Malyshev on 6/21/2013.
//

#import <UIKit/UIKit.h>

@class TrackingViewController; //forward declaration

@interface TrackingAppDelegate : NSObject <UIApplicationDelegate> {
    TrackingViewController * trackingViewController;
}

//change retain to strong if ARC is used
@property (nonatomic, retain) IBOutlet UIWindow * window;


@end
