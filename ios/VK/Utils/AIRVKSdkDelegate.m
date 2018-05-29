/**
 * Copyright 2016 Marcel Piestansky (http://marpies.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "AIRVKSdkDelegate.h"
#import "AIRVK.h"
#import "AIRVKEvent.h"
#import <AIRExtHelpers/MPStringUtils.h>
#import "VKAccessTokenUtils.h"
#import "VKUserUtils.h"

static AIRVKSdkDelegate* vkDelegateSharedInstance = nil;

typedef BOOL (*applicationOpenURLPtr)(id, SEL, UIApplication*, NSURL*, NSString*, id);
typedef BOOL (*applicationOpenURLiOS9Ptr)(id, SEL, UIApplication*, NSURL*, NSDictionary<NSString*, id>*);
static IMP original_ApplicationOpenURL = nil;
static IMP original_ApplicationOpenURL_iOS9 = nil;


BOOL swizzle_ApplicationOpenURL(id self, SEL sel, UIApplication* application, NSURL* url, NSString* sourceApplication, id annotation)
{
	NSString* uri = url.absoluteString;
	[AIRVK log:[NSString stringWithFormat:@"*** app openURL(old)=%@", uri]];
	if ([uri hasPrefix:@"vk"])
	{
		return [VKSdk processOpenURL:url fromApplication:sourceApplication];
	}

    if (original_ApplicationOpenURL)
    {
		[AIRVK log:@"*** openURL fallback(old)"];
        return ((applicationOpenURLPtr)original_ApplicationOpenURL)(self, sel, application, url, sourceApplication, annotation);
    }
    else
    {
        return NO;
    }
}

BOOL swizzle_ApplicationOpenURL_iOS9(id self, SEL sel, UIApplication* application, NSURL* url, NSDictionary<NSString*, id>* options)
{
	NSString* uri = url.absoluteString;
	[AIRVK log:[NSString stringWithFormat:@"*** app openURL(new)=%@", uri]];
	if ([uri hasPrefix:@"vk"])
	{
		return [VKSdk processOpenURL:url fromApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]];
	}

    if (original_ApplicationOpenURL_iOS9)
    {
		[AIRVK log:@"*** openURL fallback(new)"];
        return ((applicationOpenURLiOS9Ptr)original_ApplicationOpenURL_iOS9)(self, sel, application, url, options);
    }
    else
    {
        return NO;
    }
}

@implementation AIRVKSdkDelegate

+ (id) sharedInstance {
    if( vkDelegateSharedInstance == nil ) {
        vkDelegateSharedInstance = [[AIRVKSdkDelegate alloc] init];
    }
    return vkDelegateSharedInstance;
}

- (id) init {
    self = [super init];

    if( self != nil ) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            __strong id appDelegate = [[UIApplication sharedApplication] delegate];
            if( appDelegate == nil )
			{
				[AIRVK log:@"*** UIApplication delegate NOT found :("];
                return;
            }

			BOOL iOS9OrGreater = [[[UIDevice currentDevice] systemVersion] intValue] >= 9;
			SEL sel = @selector(application:openURL:sourceApplication:annotation:);
			SEL sel_iOS9 = @selector(application:openURL:options:);

			if ([appDelegate respondsToSelector:sel_iOS9] && iOS9OrGreater)
            {//:not currently implemented, may be for future AIR versions...
				[AIRVK log:@"*** openURL:options detected, trying to hack it..."];
				Method m = class_getInstanceMethod([appDelegate class], sel_iOS9);
				original_ApplicationOpenURL_iOS9 = method_getImplementation(m);
				method_setImplementation(m, (IMP)swizzle_ApplicationOpenURL_iOS9);
			}
			else
            {//:AIR 30: CTAppController has application:openURL:sourceApplication:annotation: only
                [AIRVK log:@"*** openURL:sourceApplication:annotation: detected, trying to hack it..."];
				Method m = class_getInstanceMethod([appDelegate class], sel);
				original_ApplicationOpenURL = method_getImplementation(m);
				method_setImplementation(m, (IMP)swizzle_ApplicationOpenURL);
			}
        });
    }

    return self;
}

/* doesn't work
            Class adobeDelegateClass = object_getClass( appDelegate );

            // Open URL iOS 9+
            if( NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_8_4 ) {
                SEL delegateSelector = @selector(application:openURL:options:);
                [self overrideDelegate:adobeDelegateClass method:delegateSelector withMethod:@selector(vkair_application:openURL:options:)];
            }
            // Open URL iOS 8 and older
            else {
                SEL delegateSelector = @selector(application:openURL:sourceApplication:annotation:);
                [self overrideDelegate:adobeDelegateClass method:delegateSelector withMethod:@selector(vkair_application:openURL:sourceApplication:annotation:)];
            }

# pragma mark - Swizzled

- (BOOL) vkair_application:(UIApplication *) application openURL:(NSURL *) url options:(NSDictionary<NSString*,id> *) options {
    if( [self respondsToSelector:@selector(vkair_application:openURL:options:)] ) {
        [VKSdk processOpenURL:url fromApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]];
        return [self vkair_application:application openURL:url options:options];
    }
    return NO;
}

- (BOOL) vkair_application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    if( [self respondsToSelector:@selector(vkair_application:openURL:sourceApplication:annotation:)] ) {
        [VKSdk processOpenURL:url fromApplication:sourceApplication];
        return [self vkair_application:application openURL:url sourceApplication:sourceApplication annotation:annotation];
    }
    return NO;
}
*/

/**
 *
 * VKSdkDelegate
 *
 **/

- (void)vkSdkAccessAuthorizationFinishedWithResult:(VKAuthorizationResult *)result {
    [AIRVK log:[NSString stringWithFormat:@"AIRVKSdkDelegate::vkSdkAccessAuthorizationFinishedWithResult authState: %lu", (unsigned long)result.state]];
    if( result.error == nil ) {
        /* VKUser is not part of this result, it's available in 'vkSdkAuthorizationStateUpdatedWithResult' */
        NSString* tokenJSON = [MPStringUtils getJSONString:[VKAccessTokenUtils toJSON:result.token]];
        [AIRVK dispatchEvent:VK_AUTH_SUCCESS withMessage:tokenJSON];
    } else {
        // Even when cancelled
        [AIRVK dispatchEvent:VK_AUTH_ERROR withMessage:result.error.localizedDescription];
    }
}


- (void)vkSdkUserAuthorizationFailed {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkUserAuthorizationFailed"];
}


- (void)vkSdkAuthorizationStateUpdatedWithResult:(VKAuthorizationResult *)result {
    [AIRVK log:[NSString stringWithFormat:@"AIRVKSdkDelegate::vkSdkAuthorizationStateUpdatedWithResult result has user: %@", result.user]];
}


- (void)vkSdkAccessTokenUpdated:(VKAccessToken *)newToken oldToken:(VKAccessToken *)oldToken {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkAccessTokenUpdated"];
    NSString* tokenJSON = [MPStringUtils getJSONString:[VKAccessTokenUtils toJSON:newToken]];
    [AIRVK dispatchEvent:VK_TOKEN_UPDATE withMessage:tokenJSON];
}


- (void)vkSdkTokenHasExpired:(VKAccessToken *)expiredToken {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkTokenHasExpired"];
}

/**
 *
 * VKSdkUIDelegate
 *
 **/


- (void)vkSdkShouldPresentViewController:(UIViewController *)controller {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkShouldPresentViewController"];
    [[[[[UIApplication sharedApplication] delegate] window] rootViewController]presentViewController:controller animated:YES completion:nil];
}


- (void)vkSdkNeedCaptchaEnter:(VKError *)captchaError {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkNeedCaptchaEnter"];
}


- (void)vkSdkWillDismissViewController:(UIViewController *)controller {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkWillDismissViewController"];
}


- (void)vkSdkDidDismissViewController:(UIViewController *)controller {
    [AIRVK log:@"AIRVKSdkDelegate::vkSdkDidDismissViewController"];
}

@end
