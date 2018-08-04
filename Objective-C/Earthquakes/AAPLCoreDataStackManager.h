/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Singleton controller to manage the main Core Data stack for the application. It vends a persistent store coordinator, and for convenience the managed object model and URL for the persistent store and application documents directory.
 */

@import Cocoa;

@interface AAPLCoreDataStackManager : NSObject

+ (instancetype)sharedManager;

/// Managed object model for the application.
@property (nonatomic, readonly) NSManagedObjectModel *managedObjectModel;

/// Primary persistent store coordinator for the application.
@property (nonatomic, readonly) NSPersistentStoreCoordinator *persistentStoreCoordinator;

/// URL for the Core Data store file.
@property (nonatomic, readonly) NSURL *storeURL;

/// URL for directory the application uses to store the Core Data store file.
@property (nonatomic, readonly) NSURL *applicationSupportDirectory;

- (NSManagedObjectContext *)createPrivateQueueContext:(NSError * __autoreleasing *)error;

@end

