/*===============================================================================
 Copyright (c) 2018 PTC Inc. All Rights Reserved.
 
 Vuforia is a trademark of PTC Inc., registered in the United States and other
 countries.
 ===============================================================================*/

#import <UIKit/UIKit.h>
#import "SampleUIUtils.h"

// Utility class to handle toasts used by samples, this class uses Toast.xib and needs to be included in the storyboard
@interface ToastView : UIView

- (void)showAndDismissToastWithMessage: (NSString*)message andDuration: (float)duration;
- (void)showAndDismissToastWithMessage: (NSString*)message;
- (void)showToastWithMessage: (NSString*)message;
- (void)hideToast;
- (instancetype)initAndAddToParentView: (UIView*)parentView;

@end
