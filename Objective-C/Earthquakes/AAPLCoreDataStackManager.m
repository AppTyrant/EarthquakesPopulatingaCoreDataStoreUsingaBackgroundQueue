/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Singleton controller to manage the main Core Data stack for the application. It vends a persistent store coordinator, and for convenience the managed object model and URL for the persistent store and application documents directory.
 */

#import "AAPLCoreDataStackManager.h"

NSString *const ApplicationDocumentsDirectoryName = @"com.example.apple-samplecode.Earthquakes";
NSString *const MainStoreFileName = @"Earthquakes.storedata";
NSString *const ErrorDomain = @"CoreDataStackManager";

@implementation AAPLCoreDataStackManager
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize applicationSupportDirectory = _applicationSupportDirectory;
@synthesize storeURL = _storeURL;

+ (instancetype)sharedManager {
    static AAPLCoreDataStackManager *sharedManager = nil;
    static dispatch_once_t once;
    
    dispatch_once(&once, ^{
        sharedManager = [[self alloc] init];
    });

    return sharedManager;
}

- (NSManagedObjectModel *)managedObjectModel {

    if (! _managedObjectModel) {
        
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Earthquakes" withExtension:@"momd"];
        _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    // This implementation creates and return a coordinator, having added the store for the application to it. (The directory for the store is created, if necessary.)
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }

    NSURL *url = self.storeURL;
    if (!url) {
        return nil;
    }

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];

    NSDictionary *options = @{
        NSMigratePersistentStoresAutomaticallyOption: @(YES),
        NSInferMappingModelAutomaticallyOption: @(YES)
    };

    NSError *error;

    if (![psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:&error]) {
        [NSApp presentError:error];

        return nil;
    }

    _persistentStoreCoordinator = psc;
 
    return _persistentStoreCoordinator;
}

- (NSURL *)applicationSupportDirectory {
    if (_applicationSupportDirectory) {
        return _applicationSupportDirectory;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *URLs = [fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];

    NSURL *URL = URLs[URLs.count - 1];
    URL = [URL URLByAppendingPathComponent:ApplicationDocumentsDirectoryName];
    NSError *error;

    NSDictionary *properties = [URL resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];
    if (properties) {
        NSNumber *isDirectoryNumber = properties[NSURLIsDirectoryKey];

        if (isDirectoryNumber && !isDirectoryNumber.boolValue) {
            NSString *description = NSLocalizedString(@"Could not access the application data folder", @"Failed to initialize applicationSupportDirectory");
            NSString *reason = NSLocalizedString(@"Found a file in its place", @"Failed to initialize applicationSupportDirectory");
            NSDictionary *userInfo = @{NSLocalizedDescriptionKey : description, NSLocalizedFailureReasonErrorKey : reason};
            error = [NSError errorWithDomain:ErrorDomain code:101 userInfo:userInfo];

            [NSApp presentError:error];
            
            return nil;
        }
    }
    else {
        if (error.code == NSFileReadNoSuchFileError) {
            BOOL ok = [fileManager createDirectoryAtPath:URL.path withIntermediateDirectories:YES attributes:nil error:&error];

            if (!ok) {
                [NSApp presentError:error];
            
                return nil;
            }
        }
    }

    _applicationSupportDirectory = URL;
    
    return _applicationSupportDirectory;
}

- (NSURL *)storeURL {
    
    if (! _storeURL) {
        _storeURL = [self.applicationSupportDirectory URLByAppendingPathComponent:MainStoreFileName];
    }
    return _storeURL;
}

// Creates a new Core Data stack and returns a managed object context associated with a private queue.
- (NSManagedObjectContext *)createPrivateQueueContext:(NSError * __autoreleasing *)error {
    
    // It uses the same store and model, but a new persistent store coordinator and context.
    NSPersistentStoreCoordinator *localCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[AAPLCoreDataStackManager sharedManager].managedObjectModel];
    
    if (![localCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                  URL:[AAPLCoreDataStackManager sharedManager].storeURL
                                              options:nil
                                                error:error]) {
        return nil;
    }
    
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [context performBlockAndWait:^{
        [context setPersistentStoreCoordinator:localCoordinator];
        
        // Avoid using default merge policy in multi-threading environment:
        // when we delete (and save) a record in one context,
        // and try to save edits on the same record in the other context before merging the changes,
        // an exception will be thrown because Core Data by default uses NSErrorMergePolicy.
        // Setting a reasonable mergePolicy is a good practice to avoid that kind of exception.
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
        
        // In OS X, a context provides an undo manager by default
        // Disable it for performance benefit
        context.undoManager = nil;
    }];
    return context;
}


@end
