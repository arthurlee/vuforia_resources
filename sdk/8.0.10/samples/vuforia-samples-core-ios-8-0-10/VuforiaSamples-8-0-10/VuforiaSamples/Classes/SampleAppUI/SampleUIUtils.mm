/*===============================================================================
 Copyright (c) 2018 PTC Inc. All Rights Reserved.
 
 Vuforia is a trademark of PTC Inc., registered in the United States and other
 countries.
 ===============================================================================*/

#import "SampleUIUtils.h"

@implementation SampleUIUtils

+ (void)showAlertWithTitle: (NSString *)title message:(NSString *) message completion:(void (^)(void))completion
{
    UIViewController *rootUIController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction * action)
                                                            {
                                                                [alert dismissViewControllerAnimated:YES completion:nil];
                                                                completion();
                                                            }];
    [alert addAction:okAction];

    [rootUIController presentViewController:alert
                                   animated:YES
                                 completion:nil];
}

@end
