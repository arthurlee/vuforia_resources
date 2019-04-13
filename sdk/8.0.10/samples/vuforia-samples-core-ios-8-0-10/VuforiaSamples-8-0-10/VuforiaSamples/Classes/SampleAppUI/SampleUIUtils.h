/*===============================================================================
 Copyright (c) 2018 PTC Inc. All Rights Reserved.
 
 Vuforia is a trademark of PTC Inc., registered in the United States and other
 countries.
 ===============================================================================*/

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "ToastView.h"

@protocol SampleAppsUIControl

- (void) setIsInRelocalizationState:(BOOL)isRelocalizing;

@end

@interface SampleUIUtils : NSObject

+ (void) showAlertWithTitle:(NSString *)title message:(NSString *)message completion:(void (^)(void))completion;

@end
