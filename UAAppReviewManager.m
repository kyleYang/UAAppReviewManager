//
//  UAAppReviewManager.m
//
//  Created by Matt Coneybeare on 9/8/13.
//  http://matt.coneybeare.me
//  Copyright (c) 2013 Urban Apps. All rights reserved.
//  http://urbanapps.com
//


#import "UAAppReviewManager.h"
#import <SystemConfiguration/SCNetworkReachability.h>
#include <netinet/in.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#define UAAppReviewManagerDebugLog( s, ... ) if (self.debugEnabled) { NSLog(@"[UAAppReviewManager] %@", [NSString stringWithFormat:(s), ##__VA_ARGS__]); }

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#define UAAppReviewManagerSystemVersionEqualTo(v)		([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define UAAppReviewManagerSystemVersionLessThan(v)		([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define UAAppReviewManagerSystemVersionGreaterThan(v)	([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#endif

// For conversion purposes, we keep these here to help people migrate from Appirater to UAAppReviewManager
// The keys used by UAAppReviewManager are settable by the developer
static NSString * const kAppiraterFirstUseDate              = @"kAppiraterFirstUseDate";
static NSString * const kAppiraterUseCount                  = @"kAppiraterUseCount";
static NSString * const kAppiraterSignificantEventCount     = @"kAppiraterSignificantEventCount";
static NSString * const kAppiraterCurrentVersion            = @"kAppiraterCurrentVersion";
static NSString * const kAppiraterRatedCurrentVersion       = @"kAppiraterRatedCurrentVersion";
static NSString * const kAppiraterRatedAnyVersion           = @"kAppiraterRatedAnyVersion";
static NSString * const kAppiraterDeclinedToRate            = @"kAppiraterDeclinedToRate";
static NSString * const kAppiraterReminderRequestDate       = @"kAppiraterReminderRequestDate";

// The templates used for opening the app store directly
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
static NSString * const reviewURLTemplate                   = @"itms-apps://ax.itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=APP_ID&at=AFFILIATE_CODE&ct=AFFILIATE_CAMPAIGN_CODE";
static NSString * const reviewURLTemplateiOS7               = @"itms-apps://itunes.apple.com/LANGUAGE/app/idAPP_ID?at=AFFILIATE_CODE&ct=AFFILIATE_CAMPAIGN_CODE";
#else
static NSString * const reviewURLTemplate                   = @"macappstore://itunes.apple.com/us/app/thumbs/idAPP_ID?ls=1&mt=12&at=AFFILIATE_CODE&ct=AFFILIATE_CAMPAIGN_CODE";
#endif

@interface UAAppReviewManager ()

// Review Alert Properties
@property (nonatomic, strong) NSString *appName;
@property (nonatomic, strong) NSString *reviewTitle;
@property (nonatomic, strong) NSString *reviewMessage;
@property (nonatomic, strong) NSString *cancelButtonTitle;
@property (nonatomic, strong) NSString *rateButtonTitle;
@property (nonatomic, strong) NSString *remindButtonTitle;

// Tracking Logic / Configuration
@property (nonatomic, strong) NSString          *appID;
@property (nonatomic, assign) NSUInteger        daysUntilPrompt;
@property (nonatomic, assign) NSUInteger        usesUntilPrompt;
@property (nonatomic, assign) NSUInteger        significantEventsUntilPrompt;
@property (nonatomic, assign) NSUInteger        daysBeforeReminding;
@property (nonatomic, assign) BOOL              tracksNewVersions;
@property (nonatomic, assign) BOOL              shouldPromptIfRated;
@property (nonatomic, assign) BOOL              useMainAppBundleForLocalizations;
@property (nonatomic, strong) NSString          *affiliateCode;
@property (nonatomic, strong) NSString          *affiliateCampaignCode;
@property (nonatomic, assign) BOOL              debugEnabled;
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
@property (nonatomic, assign) BOOL              usesAnimation;
@property (nonatomic, assign) BOOL              opensInStoreKit;
#endif

// Tracking Keys
@property (nonatomic, strong) NSString *appReviewManagerKeyFirstUseDate;
@property (nonatomic, strong) NSString *appReviewManagerKeyUseCount;
@property (nonatomic, strong) NSString *appReviewManagerKeySignificantEventCount;
@property (nonatomic, strong) NSString *appReviewManagerKeyCurrentVersion;
@property (nonatomic, strong) NSString *appReviewManagerKeyRatedCurrentVersion;
@property (nonatomic, strong) NSString *appReviewManagerKeyRatedAnyVersion;
@property (nonatomic, strong) NSString *appReviewManagerKeyDeclinedToRate;
@property (nonatomic, strong) NSString *appReviewManagerKeyReminderRequestDate;
@property (nonatomic, strong) NSString *appReviewManagerKeyAppiraterMigrationCompleted;

// Blocks
@property (nonatomic, copy) UAAppReviewManagerBlock         didDisplayAlertBlock;
@property (nonatomic, copy) UAAppReviewManagerBlock         didDeclineToRateBlock;
@property (nonatomic, copy) UAAppReviewManagerBlock         didOptToRateBlock;
@property (nonatomic, copy) UAAppReviewManagerBlock         didOptToRemindLaterBlock;
@property (nonatomic, copy) UAAppReviewManagerAnimateBlock  willPresentModalViewBlock;
@property (nonatomic, copy) UAAppReviewManagerAnimateBlock  didDismissModalViewBlock;

// State ivars
@property (nonatomic, assign) BOOL modalPanelOpen;
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
@property (nonatomic, assign) UIStatusBarStyle	currentStatusBarStyle;
#endif
@end

@implementation UAAppReviewManager

#pragma mark - PUBLIC Class Convenience Methods

+ (NSString *)appName {
	return [[UAAppReviewManager defaultManager] appName];
}

+ (void)setAppName:(NSString *)appName {
	[[UAAppReviewManager defaultManager] setAppName:appName];
}

+ (NSString *)reviewTitle {
	return [[UAAppReviewManager defaultManager] reviewTitle];
}

+ (void)setReviewTitle:(NSString *)reviewTitle {
	[[UAAppReviewManager defaultManager] setReviewTitle:reviewTitle];
}

+ (NSString *)reviewMessage {
	return [[UAAppReviewManager defaultManager] reviewMessage];
}

+ (void)setReviewMessage:(NSString *)reviewMessage {
	[[UAAppReviewManager defaultManager] setReviewMessage:reviewMessage];
}

+ (NSString *)cancelButtonTitle {
	return [[UAAppReviewManager defaultManager] cancelButtonTitle];
}

+ (void)setCancelButtonTitle:(NSString *)cancelButtonTitle {
	[[UAAppReviewManager defaultManager] setCancelButtonTitle:cancelButtonTitle];
}

+ (NSString *)rateButtonTitle {
	return [[UAAppReviewManager defaultManager] rateButtonTitle];
}

+ (void)setRateButtonTitle:(NSString *)rateButtonTitle {
	[[UAAppReviewManager defaultManager] setRateButtonTitle:rateButtonTitle];
}

+ (NSString *)remindButtonTitle {
	return [[UAAppReviewManager defaultManager] remindButtonTitle];
}

+ (void)setRemindButtonTitle:(NSString *)remindButtonTitle {
	[[UAAppReviewManager defaultManager] setRemindButtonTitle:remindButtonTitle];
}

+ (NSString *)keyForUAAppReviewManagerKeyType:(UAAppReviewManagerKeyType)keyType {
	return [[UAAppReviewManager defaultManager] keyForUAAppReviewManagerKeyType:keyType];
}

+ (void)setKey:(NSString *)key forUAAppReviewManagerKeyType:(UAAppReviewManagerKeyType)keyType {
	[[UAAppReviewManager defaultManager] setKey:key forUAAppReviewManagerKeyType:keyType];
}

+ (NSString *)appID {
	return [[UAAppReviewManager defaultManager] appID];
}

+ (void)setAppID:(NSString *)appID {
	[[UAAppReviewManager defaultManager] setAppID:appID];
}

+ (NSUInteger)daysUntilPrompt {
	return [[UAAppReviewManager defaultManager] daysUntilPrompt];
}

+ (void)setDaysUntilPrompt:(NSUInteger)daysUntilPrompt {
	[[UAAppReviewManager defaultManager] setDaysUntilPrompt:daysUntilPrompt];
}

+ (NSUInteger)usesUntilPrompt {
	return [[UAAppReviewManager defaultManager] usesUntilPrompt];
}

+ (void)setUsesUntilPrompt:(NSUInteger)usesUntilPrompt {
	[[UAAppReviewManager defaultManager] setUsesUntilPrompt:usesUntilPrompt];
}

+ (NSUInteger)significantEventsUntilPrompt {
	return [[UAAppReviewManager defaultManager] significantEventsUntilPrompt];
}

+ (void)setSignificantEventsUntilPrompt:(NSInteger)significantEventsUntilPrompt {
	[[UAAppReviewManager defaultManager] setSignificantEventsUntilPrompt:significantEventsUntilPrompt];
}

+ (NSUInteger)daysBeforeReminding {
	return [[UAAppReviewManager defaultManager] daysBeforeReminding];
}

+ (void)setDaysBeforeReminding:(NSUInteger)daysBeforeReminding {
	[[UAAppReviewManager defaultManager] setDaysBeforeReminding:daysBeforeReminding];
}

+ (BOOL)tracksNewVersions {
	return [[UAAppReviewManager defaultManager] tracksNewVersions];
}

+ (void)setTracksNewVersions:(BOOL)tracksNewVersions {
	[[UAAppReviewManager defaultManager] setTracksNewVersions:tracksNewVersions];
}

+ (BOOL)shouldPromptIfRated {
	return [[UAAppReviewManager defaultManager] shouldPromptIfRated];
}

+ (void)setShouldPromptIfRated:(BOOL)shouldPromptIfRated {
	[[UAAppReviewManager defaultManager] setShouldPromptIfRated:shouldPromptIfRated];
}

+ (BOOL)useMainAppBundleForLocalizations {
	return [[UAAppReviewManager defaultManager] useMainAppBundleForLocalizations];
}

+ (void)setUseMainAppBundleForLocalizations:(BOOL)useMainAppBundleForLocalizations {
	[[UAAppReviewManager defaultManager] setUseMainAppBundleForLocalizations:useMainAppBundleForLocalizations];
}

+ (NSString *)affiliateCode {
	return [[UAAppReviewManager defaultManager] affiliateCode];
}

+ (void)setAffiliateCode:(NSString*)affiliateCode {
	[[UAAppReviewManager defaultManager] setAffiliateCode:affiliateCode];
}

+ (NSString *)affiliateCampaignCode {
	return [[UAAppReviewManager defaultManager] affiliateCampaignCode];
}

+ (void)setAffiliateCampaignCode:(NSString*)affiliateCampaignCode {
	[[UAAppReviewManager defaultManager] setAffiliateCampaignCode:affiliateCampaignCode];
}

+ (BOOL)debug {
	return [[UAAppReviewManager defaultManager] debugEnabled];
}

+ (void)setDebug:(BOOL)debug {
#ifdef DEBUG
	[[UAAppReviewManager defaultManager] setDebugEnabled:debug];
#endif
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
+ (BOOL)usesAnimation {
	return [[UAAppReviewManager defaultManager] usesAnimation];
}

+ (void)setUsesAnimation:(BOOL)usesAnimation {
	[[UAAppReviewManager defaultManager] setUsesAnimation:usesAnimation];
}

+ (BOOL)opensInStoreKit {
	return [[UAAppReviewManager defaultManager] opensInStoreKit];
}

+ (void)setOpensInStoreKit:(BOOL)opensInStoreKit {
	[[UAAppReviewManager defaultManager] setOpensInStoreKit:opensInStoreKit];
}

#endif


+ (void)appLaunched:(BOOL)canPromptForRating {
	[[UAAppReviewManager defaultManager] appLaunched:canPromptForRating];
}

+ (void)appEnteredForeground:(BOOL)canPromptForRating {
	[[UAAppReviewManager defaultManager] appEnteredForeground:canPromptForRating];
}

+ (void)userDidSignificantEvent:(BOOL)canPromptForRating {
	[[UAAppReviewManager defaultManager] userDidSignificantEvent:canPromptForRating];
}

+ (void)showPrompt {
	[[UAAppReviewManager defaultManager] showPrompt];
}

+ (NSString *)reviewURLString {
	[[UAAppReviewManager defaultManager] reviewURLString];
}

+ (void)rateApp {
	[[UAAppReviewManager defaultManager] rateApp];
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
+ (void)closeModalPanel {
	[[UAAppReviewManager defaultManager] closeModalPanel];
}
#endif

+ (void)setOnDidDisplayAlert:(UAAppReviewManagerBlock)didDisplayAlertBlock {
	[[UAAppReviewManager defaultManager] setDidDisplayAlertBlock:didDisplayAlertBlock];
}

+ (void)setOnDeclineToRate:(UAAppReviewManagerBlock)didDeclineToRateBlock {
	[[UAAppReviewManager defaultManager] setDidDeclineToRateBlock:didDeclineToRateBlock];
}

+ (void)setOnDidOptToRate:(UAAppReviewManagerBlock)didOptToRateBlock {
	[[UAAppReviewManager defaultManager] setDidOptToRateBlock:didOptToRateBlock];
}

+ (void)setOnDidOptToRemindLater:(UAAppReviewManagerBlock)didOptToRemindLaterBlock {
	[[UAAppReviewManager defaultManager] setDidOptToRemindLaterBlock:didOptToRemindLaterBlock];
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
+ (void)setOnWillPresentModalView:(UAAppReviewManagerAnimateBlock)willPresentModalViewBlock {
	[[UAAppReviewManager defaultManager] setWillPresentModalViewBlock:willPresentModalViewBlock];
}

+ (void)setOnDidDismissModalView:(UAAppReviewManagerAnimateBlock)didDismissModalViewBlock {
	[[UAAppReviewManager defaultManager] setDidDismissModalViewBlock:didDismissModalViewBlock];
}
#endif

#pragma mark - PUBLIC Class Convenience Methods (backwards compatibility)

+ (void)setAppId:(NSString*)appId {
	[UAAppReviewManager setAppID:appId];
}

+ (void)setTimeBeforeReminding:(double)value {
	[UAAppReviewManager setDaysBeforeReminding:(NSUInteger)value];
}

+ (void)setAlwaysUseMainBundle:(BOOL)useMainBundle {
	[UAAppReviewManager setUseMainAppBundleForLocalizations:useMainBundle];
}

+ (void)appLaunched {
	[UAAppReviewManager appLaunched:NO];
}

+ (void)setDelegate:(id)delegate {
	// No analagous method
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
+ (void)setOpenInAppStore:(BOOL)openInAppStore {
	[UAAppReviewManager setOpensInStoreKit:!openInAppStore];
}
#endif


#pragma mark -
#pragma mark - PRIVATE Review Alert Property Accessors

- (void)setAppID:(NSString *)appID {
	if ([appID length])
		_appID = appID;
}

- (void)setAffiliateCode:(NSString *)affiliateCode {
	if ([affiliateCode length])
		_affiliateCode = affiliateCode;
}

- (void)setAffiliateCampaignCode:(NSString *)affiliateCampaignCode {
	if ([affiliateCampaignCode length])
		_affiliateCampaignCode = affiliateCampaignCode;
}

- (NSString *)appName {
	if (!_appName) {
		// Check for a localized version of the CFBundleDisplayName
		NSString *appName = [[[NSBundle mainBundle] localizedInfoDictionary] objectForKey:@"CFBundleDisplayName"];
		if (!appName)
			appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
		
		self.appName = appName;
	}
	return _appName;
}

- (NSString *)reviewTitle {
	if (!_reviewTitle) {
		// Check for a localized version of the default title
		NSString *reviewTitleTemplate = NSLocalizedStringFromTableInBundle(@"Rate %@",
																		   @"UAAppReviewManagerLocalizable",
																		   [self bundle],
																		   nil);
		
		self.reviewTitle = [NSString stringWithFormat:reviewTitleTemplate, [self appName]];
	}
	return _reviewTitle;
}

- (NSString *)reviewMessage {
	if (!_reviewMessage) {
		// Check for a localized version of the default message
		NSString *reviewMessageTemplate = NSLocalizedStringFromTableInBundle(@"If you enjoy using %@, would you mind taking a moment to rate it? It won't take more than a minute. Thanks for your support!",
																			 @"UAAppReviewManagerLocalizable",
																			 [self bundle],
																			 nil);
		
		self.reviewMessage = [NSString stringWithFormat:reviewMessageTemplate, [self appName]];
	}
	return _reviewMessage;
}

- (NSString *)cancelButtonTitle {
	if (!_cancelButtonTitle) {
		// Check for a localized version of the default title
		self.cancelButtonTitle = NSLocalizedStringFromTableInBundle(@"No, Thanks", @"UAAppReviewManagerLocalizable", [self bundle], nil);
	}
	return _cancelButtonTitle;
}

- (NSString *)rateButtonTitle {
	if (!_rateButtonTitle) {
		// Check for a localized version of the default title
		NSString *rateTitleTemplate = NSLocalizedStringFromTableInBundle(@"Rate %@", @"UAAppReviewManagerLocalizable", [self bundle], nil);
		self.rateButtonTitle = [NSString stringWithFormat:rateTitleTemplate, [self appName]];
	}
	return _rateButtonTitle;
}

- (NSString *)remindButtonTitle {
	if (!_remindButtonTitle) {
		// Check for a localized version of the default title
		self.remindButtonTitle = NSLocalizedStringFromTableInBundle(@"Remind me later", @"UAAppReviewManagerLocalizable", [self bundle], nil);
	}
	return _remindButtonTitle;
}


#pragma mark - PRIVATE Tracking Key Accessors

// Tracking Keys
- (NSString *)appReviewManagerKeyFirstUseDate {
	if (!_appReviewManagerKeyFirstUseDate) {
		// Provide a sensible default
		self.appReviewManagerKeyFirstUseDate = @"UAAppReviewManagerKeyFirstUseDate";
	}
	return _appReviewManagerKeyFirstUseDate;
}

- (NSString *)appReviewManagerKeyUseCount {
	if (!_appReviewManagerKeyUseCount) {
		// Provide a sensible default
		self.appReviewManagerKeyUseCount = @"UAAppReviewManagerKeyUseCount";
	}
	return _appReviewManagerKeyUseCount;
}

- (NSString *)appReviewManagerKeySignificantEventCount {
	if (!_appReviewManagerKeySignificantEventCount) {
		// Provide a sensible default
		self.appReviewManagerKeySignificantEventCount = @"UAAppReviewManagerKeySignificantEventCount";
	}
	return _appReviewManagerKeySignificantEventCount;
}

- (NSString *)appReviewManagerKeyCurrentVersion {
	if (!_appReviewManagerKeyCurrentVersion) {
		// Provide a sensible default
		self.appReviewManagerKeyCurrentVersion = @"UAAppReviewManagerKeyCurrentVersion";
	}
	return _appReviewManagerKeyCurrentVersion;
}

- (NSString *)appReviewManagerKeyRatedCurrentVersion {
	if (!_appReviewManagerKeyRatedCurrentVersion) {
		// Provide a sensible default
		self.appReviewManagerKeyRatedCurrentVersion = @"UAAppReviewManagerKeyRatedCurrentVersion";
	}
	return _appReviewManagerKeyRatedCurrentVersion;
}

- (NSString *)appReviewManagerKeyRatedAnyVersion {
	if (!_appReviewManagerKeyRatedAnyVersion) {
		// Provide a sensible default
		self.appReviewManagerKeyRatedAnyVersion = @"UAAppReviewManagerKeyRatedAnyVersion";
	}
	return _appReviewManagerKeyRatedAnyVersion;
}

- (NSString *)appReviewManagerKeyDeclinedToRate {
	if (!_appReviewManagerKeyDeclinedToRate) {
		// Provide a sensible default
		self.appReviewManagerKeyDeclinedToRate = @"UAAppReviewManagerKeyDeclinedToRate";
	}
	return _appReviewManagerKeyDeclinedToRate;
}

- (NSString *)appReviewManagerKeyReminderRequestDate {
	if (!_appReviewManagerKeyReminderRequestDate) {
		// Provide a sensible default
		self.appReviewManagerKeyReminderRequestDate = @"UAAppReviewManagerKeyReminderRequestDate";
	}
	return _appReviewManagerKeyReminderRequestDate;
}

- (NSString *)appReviewManagerKeyAppiraterMigrationCompleted {
	if (!_appReviewManagerKeyAppiraterMigrationCompleted) {
		// Provide a sensible default
		self.appReviewManagerKeyAppiraterMigrationCompleted = @"UAAppReviewManagerKeyAppiraterMigrationCompleted";
	}
	return _appReviewManagerKeyAppiraterMigrationCompleted;
}

#pragma mark - PRIVATE Methods

- (BOOL)appLaunched:(BOOL)canPromptForRating {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		[self incrementAndRate:canPromptForRating];
	});
}

- (void)appEnteredForeground:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		[self incrementAndRate:canPromptForRating];
	});
}

- (void)userDidSignificantEvent:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		[self incrementSignificantEventAndRate:canPromptForRating];
	});
}


#pragma mark - PRIVATE Rating Helpers

- (void)incrementAndRate:(BOOL)canPromptForRating {
	[self migrateAppiraterKeysIfNecessary];
	[self incrementUseCount];
	[self showPromptIfNecessary:canPromptForRating];
}

- (void)incrementSignificantEventAndRate:(BOOL)canPromptForRating {
	[self migrateAppiraterKeysIfNecessary];
	[self incrementSignificantEventCount];
	[self showPromptIfNecessary:canPromptForRating];
}

- (void)incrementUseCount {
	[self _incrementCountForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyUseCount]];
}


- (void)incrementSignificantEventCount {
	[self _incrementCountForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeySignificantEventCount]];
}

- (void)_incrementCountForKey:(NSString *)incrementKey {
	
	// App's version. Not settable as the other ivars because that would be crazy.
	NSString *currentVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey];
	
	// Get the version number that we've been tracking thus far
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *currentVersionKey = [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyCurrentVersion];
	NSString *trackingVersion = [defaults stringForKey:currentVersionKey];
	// New install, or changed keys
	if (!trackingVersion) {
		trackingVersion = currentVersion;
		[defaults setObject:currentVersion forKey:currentVersionKey];
	}
	
	UAAppReviewManagerDebugLog(@"Tracking version: %@", trackingVersion);
	
	if ([trackingVersion isEqualToString:currentVersion]) {
		// Check if the first use date has been set. if not, set it.
		NSString *firstUseDateKey = [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyFirstUseDate];
		NSTimeInterval timeInterval = [defaults doubleForKey:firstUseDateKey];
		if (0 == timeInterval) {
			timeInterval = [[NSDate date] timeIntervalSince1970];
			[defaults setDouble:timeInterval forKey:firstUseDateKey];
		}
		
		// Increment the key's count
		NSInteger incrementKeyCount = [defaults integerForKey:incrementKey];
		incrementKeyCount++;
		[defaults setInteger:incrementKeyCount forKey:incrementKey];

		
		UAAppReviewManagerDebugLog(@"%@ count: %ld", incrementKey, (long)incrementKeyCount);
	
	} else if (self.tracksNewVersions) {
		// it's a new version of the app, so restart tracking
		[defaults setObject:currentVersion forKey:currentVersionKey];
		[defaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyFirstUseDate]];
		[defaults setInteger:1 forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyUseCount]];
		[defaults setInteger:0 forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeySignificantEventCount]];
		[defaults setBool:NO forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyRatedCurrentVersion]];
		[defaults setBool:NO forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyDeclinedToRate]];
		[defaults setDouble:0 forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyReminderRequestDate]];
	}
	
	[defaults synchronize];
}

- (void)showPromptIfNecessary:(BOOL)canPromptForRating {
	if (canPromptForRating && [self ratingConditionsHaveBeenMet] && [self connectedToNetwork]) {
        dispatch_async(dispatch_get_main_queue(), ^{
			[self showRatingAlert];
		});
	}
}

- (void)showPrompt {
    if (self.appID && [self connectedToNetwork] && ![self userHasDeclinedToRate] && ![self userHasRatedCurrentVersion]) {
        [self showRatingAlert];
    }
}

- (BOOL)ratingConditionsHaveBeenMet {

	if (self.debugEnabled)
		return YES;
	
	if (!self.appID)
		return NO;
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	NSDate *dateOfFirstLaunch = [NSDate dateWithTimeIntervalSince1970:[defaults doubleForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyFirstUseDate]]];
	NSTimeInterval timeSinceFirstLaunch = [[NSDate date] timeIntervalSinceDate:dateOfFirstLaunch];
	NSTimeInterval timeUntilRate = 60 * 60 * 24 * self.daysUntilPrompt;
	if (timeSinceFirstLaunch < timeUntilRate)
		return NO;
	
	// check if the app has been used enough
	NSInteger useCount = [defaults integerForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyUseCount]];
	if (useCount <= self.usesUntilPrompt)
		return NO;
	
	// check if the user has done enough significant events
	NSInteger significantEventCount = [defaults integerForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeySignificantEventCount]];
	if (significantEventCount < self.significantEventsUntilPrompt)
		return NO;
	
	// has the user previously declined to rate this version of the app?
	if ([self userHasDeclinedToRate])
		return NO;
	
	// has the user already rated the app?
	if ([self userHasRatedCurrentVersion])
		return NO;
	
	// if the user wanted to be reminded later, has enough time passed?
	NSDate *reminderRequestDate = [NSDate dateWithTimeIntervalSince1970:[defaults doubleForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyReminderRequestDate]]];
	NSTimeInterval timeSinceReminderRequest = [[NSDate date] timeIntervalSinceDate:reminderRequestDate];
	NSTimeInterval timeUntilReminder = 60 * 60 * 24 * self.daysBeforeReminding;
	if (timeSinceReminderRequest < timeUntilReminder)
		return NO;
	
	// if we have a global set to not show if the end-user has already rated once, and the developer has not opted out of displaying on minor updates
	if (!self.shouldPromptIfRated && [defaults boolForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyRatedAnyVersion]])
		return NO;
	
	return YES;
}

- (BOOL)userHasDeclinedToRate {
    return [[NSUserDefaults standardUserDefaults] boolForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyDeclinedToRate]];
}

- (BOOL)userHasRatedCurrentVersion {
    return [[NSUserDefaults standardUserDefaults] boolForKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyRatedCurrentVersion]];
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
- (void)showRatingAlert {
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:self.reviewTitle
														message:self.reviewMessage
													   delegate:self
											  cancelButtonTitle:self.cancelButtonTitle
											  otherButtonTitles:self.rateButtonTitle, self.remindButtonTitle, nil];
	self.ratingAlert = alertView;
    [alertView show];
	
    if (self.didDisplayAlertBlock)
		self.didDisplayAlertBlock(self);
}

#else

- (void)showRatingAlert {
	NSAlert *alert = [NSAlert alertWithMessageText:self.reviewTitle
									 defaultButton:self.rateButtonTitle
								   alternateButton:self.cancelButtonTitle
									   otherButton:self.remindButtonTitle
						 informativeTextWithFormat:@"%@",self.reviewMessage];
	self.ratingAlert = alert;
	
	NSWindow *window = [[NSApplication sharedApplication] keyWindow];
	if (window) {
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] keyWindow]
						  modalDelegate:self
						 didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
							contextInfo:nil];
	} else {
		NSInteger returnCode = [alert runModal];
		[self handleNSAlertReturnCode:returnCode];
	}
	
	if (self.didDisplayAlertBlock)
		self.didDisplayAlertBlock(self);
}

#endif

#pragma mark PRIVATE Alert View Delegate Methods

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	switch (buttonIndex) {
		case 0: { // they don't want to rate it
			[self dontRate];
			break;
		}
		case 1: { // they want to rate it
			[self _rateApp]; // the private _ method allows me to call a block method in this instance
			break;
		}
		case 2: { // remind them later
			[self remindMeLater];
			break;
		}
		default:
			break;
	}
}

//Delegate call from the StoreKit view.
- (void)productViewControllerDidFinish:(SKStoreProductViewController *)viewController {
	[self closeModalPanel];
}

//Close the in-app rating (StoreKit) view and restore the previous status bar style.
- (void)closeModalPanel {
	if (self.modalPanelOpen) {
		[[UIApplication sharedApplication] setStatusBarStyle:self.currentStatusBarStyle animated:self.usesAnimation];
		BOOL usedAnimation = self.usesAnimation;
		[self setModalPanelOpen:NO];
		
		// get the top most controller (= the StoreKit Controller) and dismiss it
		UIViewController *presentingController = [UIApplication sharedApplication].keyWindow.rootViewController;
		presentingController = [self topMostViewController:presentingController];
		[presentingController dismissViewControllerAnimated:self.usesAnimation completion:^{
			if (self.didDismissModalViewBlock)
				self.didDismissModalViewBlock(self, usedAnimation);
		}];
		[self setCurrentStatusBarStyle:(UIStatusBarStyle)nil];
	}
}

#else

- (void)handleNSAlertReturnCode:(NSInteger)returnCode {
	switch (returnCode) {
		case NSAlertAlternateReturn: {
			// they don't want to rate it
			[self dontRate];
			break;
		}
		case NSAlertDefaultReturn: {
			// they want to rate it
			[self _rateApp];
			break;
		}
		case NSAlertOtherReturn: {
			// remind them later
			[self remindMeLater];
			break;
		}
		default:
			break;
	}
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[self handleNSAlertReturnCode:returnCode];
}

#endif

- (void)dontRate {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	[userDefaults setBool:YES forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyDeclinedToRate]];
	[userDefaults synchronize];
	if (self.didDeclineToRateBlock)
		self.didDeclineToRateBlock(self);
}

- (void)remindMeLater {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	[userDefaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyReminderRequestDate]];
	[userDefaults synchronize];
	if (self.didOptToRemindLaterBlock)
		self.didOptToRemindLaterBlock(self);
}

- (void)_rateApp {
	[UAAppReviewManager rateApp];
	if (self.didOptToRateBlock)
		self.didOptToRateBlock(self);
}

- (void)rateApp {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:YES forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyCurrentVersion]];
	[defaults setBool:YES forKey:[self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyRatedAnyVersion]];
	[defaults synchronize];
	
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
	//Use the in-app StoreKit view if set, available (iOS 6) and imported This works in the simulator.
	if (self.opensInStoreKit && NSStringFromClass([SKStoreProductViewController class]) != nil) {
	
		SKStoreProductViewController *storeViewController = [[SKStoreProductViewController alloc] init];
		NSNumber *appId = [NSNumber numberWithInteger:self.appID.integerValue];
		[storeViewController loadProductWithParameters:@{ SKStoreProductParameterITunesItemIdentifier : self.appID } completionBlock:nil];
		storeViewController.delegate = self;
		
		if (self.willPresentModalViewBlock)
			self.willPresentModalViewBlock(self, self.usesAnimation);
		
		[[self getRootViewController] presentViewController:storeViewController animated:self.usesAnimation completion:^{
			[self setModalPanelOpen:YES];
			//Temporarily use a  status bar to match the StoreKit view.
			[self setCurrentStatusBarStyle:[UIApplication sharedApplication].statusBarStyle];
			if (UAAppReviewManagerSystemVersionLessThan(@"7.0")) {
				// UIStatusBarStyleBlackOpaque is 2
				[[UIApplication sharedApplication]setStatusBarStyle:2 animated:self.usesAnimation];
			} else {
				[[UIApplication sharedApplication]setStatusBarStyle:UIStatusBarStyleDefault animated:self.usesAnimation];	
			}
		}];
	
	//Use the standard openUrl method
	} else {
		
#if TARGET_IPHONE_SIMULATOR
		UAAppReviewManagerDebugLog(@"iTunes App Store is not supported on the iOS simulator. We would have went to %@.", [self reviewURLString]);
#else
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[self reviewURLString]]];
#endif
	}

#else
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[self reviewURLString]]];
#endif
	
}

- (NSString *)reviewURLString {
	NSString *template = reviewURLTemplate;
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
	if (UAAppReviewManagerSystemVersionEqualTo(@"7.0")) {
		// The iOS 7 App Store app shows a blank page when opening the old links.
		// If the old-style link ever works again, we can remove this.
		NSString *localeString = [NSString stringWithFormat:@"%@", [[NSLocale preferredLanguages] objectAtIndex:0]];
		template = [reviewURLTemplateiOS7 stringByReplacingOccurrencesOfString:@"LANGUAGE" withString:localeString];
	}
#endif
	NSString *reviewURL = [template stringByReplacingOccurrencesOfString:@"APP_ID" withString:[NSString stringWithFormat:@"%@", self.appID]];
	reviewURL = [reviewURL stringByReplacingOccurrencesOfString:@"AFFILIATE_CODE" withString:[NSString stringWithFormat:@"%@", self.affiliateCode]];
	reviewURL = [reviewURL stringByReplacingOccurrencesOfString:@"AFFILIATE_CAMPAIGN_CODE" withString:[NSString stringWithFormat:@"%@", self.affiliateCampaignCode]];
	return reviewURL;
}



#pragma mark PRIVATE Key Helpers

- (NSString *)keyForUAAppReviewManagerKeyType:(UAAppReviewManagerKeyType)keyType {
	switch (keyType) {
		case UAAppReviewManagerKeyFirstUseDate:                 return [self appReviewManagerKeyFirstUseDate];
		case UAAppReviewManagerKeyUseCount:                     return [self appReviewManagerKeyUseCount];
		case UAAppReviewManagerKeySignificantEventCount:        return [self appReviewManagerKeySignificantEventCount];
		case UAAppReviewManagerKeyCurrentVersion:               return [self appReviewManagerKeyCurrentVersion];
		case UAAppReviewManagerKeyRatedCurrentVersion:          return [self appReviewManagerKeyRatedCurrentVersion];
		case UAAppReviewManagerKeyRatedAnyVersion:              return [self appReviewManagerKeyRatedAnyVersion];
		case UAAppReviewManagerKeyDeclinedToRate:               return [self appReviewManagerKeyDeclinedToRate];
		case UAAppReviewManagerKeyReminderRequestDate:          return [self appReviewManagerKeyReminderRequestDate];
		case UAAppReviewManagerKeyAppiraterMigrationCompleted:  return [self appReviewManagerKeyAppiraterMigrationCompleted];
		default:
			return nil;
	}
}

- (void)setKey:(NSString *)key forUAAppReviewManagerKeyType:(UAAppReviewManagerKeyType)keyType {
	switch (keyType) {
		case UAAppReviewManagerKeyFirstUseDate:                 [self setAppReviewManagerKeyFirstUseDate:key]; break;
		case UAAppReviewManagerKeyUseCount:                     [self setAppReviewManagerKeyUseCount:key]; break;
		case UAAppReviewManagerKeySignificantEventCount:        [self setAppReviewManagerKeySignificantEventCount:key]; break;
		case UAAppReviewManagerKeyCurrentVersion:               [self setAppReviewManagerKeyCurrentVersion:key]; break;
		case UAAppReviewManagerKeyRatedCurrentVersion:          [self setAppReviewManagerKeyRatedCurrentVersion:key]; break;
		case UAAppReviewManagerKeyRatedAnyVersion:              [self setAppReviewManagerKeyRatedAnyVersion:key]; break;
		case UAAppReviewManagerKeyDeclinedToRate:               [self setAppReviewManagerKeyDeclinedToRate:key]; break;
		case UAAppReviewManagerKeyReminderRequestDate:          [self setAppReviewManagerKeyReminderRequestDate:key]; break;
		case UAAppReviewManagerKeyAppiraterMigrationCompleted:  [self setAppReviewManagerKeyAppiraterMigrationCompleted:key]; break;
		default:
			break;
	}
}

- (NSString *)appReviewManagerKeyForAppiraterKey:(NSString *)appiraterKey {
	if ([appiraterKey isEqualToString:kAppiraterFirstUseDate])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyFirstUseDate];
	else if ([appiraterKey isEqualToString:kAppiraterUseCount])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyUseCount];
	else if ([appiraterKey isEqualToString:kAppiraterSignificantEventCount])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeySignificantEventCount];
	else if ([appiraterKey isEqualToString:kAppiraterCurrentVersion])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyCurrentVersion];
	else if ([appiraterKey isEqualToString:kAppiraterRatedCurrentVersion])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyRatedCurrentVersion];
	else if ([appiraterKey isEqualToString:kAppiraterRatedAnyVersion])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyRatedAnyVersion];
	else if ([appiraterKey isEqualToString:kAppiraterDeclinedToRate])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyDeclinedToRate];
	else if ([appiraterKey isEqualToString:kAppiraterReminderRequestDate])
		return [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyReminderRequestDate];
	else
		return nil;
}

- (void)migrateAppiraterKeysIfNecessary {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *appiraterAlreadyCompletedKey = [self keyForUAAppReviewManagerKeyType:UAAppReviewManagerKeyAppiraterMigrationCompleted];
	BOOL appiraterMigrationAlreadyCompleted = [defaults boolForKey:appiraterAlreadyCompletedKey];
	if (appiraterMigrationAlreadyCompleted)
		return;
	
	NSArray *oldKeys = @[ kAppiraterFirstUseDate,
                          kAppiraterUseCount,
                          kAppiraterSignificantEventCount,
                          kAppiraterCurrentVersion,
                          kAppiraterRatedCurrentVersion,
                          kAppiraterRatedAnyVersion,
                          kAppiraterDeclinedToRate,
                          kAppiraterReminderRequestDate
                        ];
	for (NSString *oldKey in oldKeys) {
		id val = [defaults objectForKey:oldKey];
		if (val) {
			NSString *newKey = [self appReviewManagerKeyForAppiraterKey:oldKey];
			[defaults setObject:val forKey:newKey];
			[defaults removeObjectForKey:oldKey];
		}
	}
	
	[defaults setBool:YES forKey:appiraterAlreadyCompletedKey];
	[defaults synchronize];
}


#pragma mark - Internet Connectivity

- (BOOL)connectedToNetwork {
    // Create zero addy
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
	
    // Recover reachability flags
    SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress);
    SCNetworkReachabilityFlags flags;
	
    BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
    CFRelease(defaultRouteReachability);
	
    if (!didRetrieveFlags) {
        UAAppReviewManagerDebugLog(@"Error. Could not recover network reachability flags");
        return NO;
    }
	
    BOOL isReachable = flags & kSCNetworkFlagsReachable;
    BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;
	BOOL nonWiFi = flags & kSCNetworkReachabilityFlagsTransientConnection;
	
	NSURL *testURL = [NSURL URLWithString:@"http://www.apple.com/"];
	NSURLRequest *testRequest = [NSURLRequest requestWithURL:testURL  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0];
	NSURLConnection *testConnection = [[NSURLConnection alloc] initWithRequest:testRequest delegate:self];
	
    return ((isReachable && !needsConnection) || nonWiFi) ? (testConnection ? YES : NO) : NO;
}


#pragma mark - PRIVATE Misc Helpers

- (NSBundle *)bundle {
    NSBundle *bundle = nil;
    if (self.useMainAppBundleForLocalizations) {
        bundle = [NSBundle mainBundle];
		
    } else {
// These bundles are exactly the same, but splitting them by target makes Cocoapods happy.
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
        NSURL *appReviewManagerBundleURL = [[NSBundle mainBundle] URLForResource:@"UAAppReviewManager-iOS" withExtension:@"bundle"];
#else
		NSURL *appReviewManagerBundleURL = [[NSBundle mainBundle] URLForResource:@"UAAppReviewManager-OSX" withExtension:@"bundle"];
#endif
        if (appReviewManagerBundleURL) {
            // UAAppReviewManager.bundle will likely only exist when used via CocoaPods
            bundle = [NSBundle bundleWithURL:appReviewManagerBundleURL];
        } else {
            bundle = [NSBundle mainBundle];
        }
    }
	
    return bundle;
}

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
- (UIViewController *)topMostViewController:(UIViewController *)controller {
	BOOL isPresenting = NO;
	do {
		// this path is called only on iOS 6+, so -presentedViewController is fine here.
		UIViewController *presented = [controller presentedViewController];
		isPresenting = presented != nil;
		if (presented != nil)
			controller = presented;
		
	} while (isPresenting);
	
	return controller;
}

- (UIViewController *)getRootViewController {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (window.windowLevel != UIWindowLevelNormal) {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for(window in windows) {
            if (window.windowLevel == UIWindowLevelNormal) {
                break;
            }
        }
    }
	
    for (UIView *subView in [window subviews]) {
        UIResponder *responder = [subView nextResponder];
        if([responder isKindOfClass:[UIViewController class]]) {
            return [self topMostViewController:(UIViewController *)responder];
        }
    }
	
    return nil;
}
#endif

- (void)hideRatingAlert {
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
	if (self.ratingAlert.visible) {
		UAAppReviewManagerDebugLog(@"Hiding Alert");
		[self.ratingAlert dismissWithClickedButtonIndex:-1 animated:NO];
	}
#else
	UAAppReviewManagerDebugLog(@"Hiding Alert");
	[NSApp endSheet:[[NSApplication sharedApplication] keyWindow]];
#endif
}

- (void)appWillResignActive {
	UAAppReviewManagerDebugLog(@"appWillResignActive");
	[self hideRatingAlert];
}

#pragma mark - Singleton

/**
 * defaultManager is the singleton accessor for UAAppReviewManager.
 * defaultManager is not exposed publicly because all public methods
 * are handled through the Class convenience methods below.
 *
 *	@return	UAAppReviewManager *
 */
+ (UAAppReviewManager *)defaultManager {
	static UAAppReviewManager *defaultManager = nil;
	static dispatch_once_t singletonToken;
	dispatch_once(&singletonToken, ^{
		defaultManager = [[UAAppReviewManager alloc] init];
		[defaultManager setupNotifications];
		[defaultManager setDefaultValues];
	});
	return defaultManager;
}


#pragma mark - Singleton Instance Setup

/**
 * _setupNotifications is called when the singlton is instantiated.
 * It listens for notification on app active resignation so that we can hide the
 * review popup until next time.
 */
- (void)setupNotifications {
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
#else
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:NSApplicationWillResignActiveNotification object:nil];
#endif
}

- (void)setDefaultValues {
	self.daysUntilPrompt = 30;
	self.usesUntilPrompt = 20;
	self.significantEventsUntilPrompt = 0;
	self.daysBeforeReminding = 1;
	self.tracksNewVersions = YES;
	self.shouldPromptIfRated = YES;
	self.debugEnabled = NO;
	self.useMainAppBundleForLocalizations = NO;
	// If you aren't going to set an affiliate code yourself, please leave this as is.
	// It is my affiliate code. It is better that somebody's code is used rather than nobody's.
	self.affiliateCode = @"11l7j9";
	self.affiliateCampaignCode = @"UAAppReviewManager";
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
	self.usesAnimation = YES;
	self.opensInStoreKit = NO;
#endif

}

@end
