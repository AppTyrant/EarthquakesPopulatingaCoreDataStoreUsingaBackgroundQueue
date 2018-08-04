/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 View controller to manage a a table view that displays a collection of quakes.
 
  When requested (by clicking the Fetch Quakes button), the controller creates an asynchronous NSURLSession task to retrieve JSON data about earthquakes. Earthquake data are compared with any existing managed objects to determine whether there are new quakes. New managed objects are created to represent new data, and saved to the persistent store on a private queue.
 */

#import "AAPLQuakesViewController.h"
#import "AAPLQuake.h"
#import "AAPLCoreDataStackManager.h"

@interface AAPLQuakesViewController ()

@property (weak) IBOutlet NSTableView *tableView;
@property (weak) IBOutlet NSButton *fetchQuakesButton;

@property (nonatomic) NSArray<AAPLQuake *> *quakes;
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;

@end

NSString *const ColumnIdentifierPlace = @"placeName";
NSString *const ColumnIdentifierTime = @"time";
NSString *const ColumnIdentifierMagnitude = @"magnitude";

NSString *EARTHQUAKES_ERROR_DOMAIN = @"EARTHQUAKES_ERROR_DOMAIN";


@implementation AAPLQuakesViewController
@synthesize managedObjectContext = _context;

#pragma mark - View Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contextDidSaveNotificationHandler:)
                                                 name:NSManagedObjectContextDidSaveNotification
                                               object:nil
     ];

    [self reloadTableView:self];
}

- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Core Data Batch importing

- (IBAction)fetchQuakes:(id)sender {
    // Ensure the button can't be pressed again until the fetch is complete.
    self.fetchQuakesButton.enabled = NO;

    // Create an NSURLSession and then session task to contact the earthquake server and retrieve JSON data.
    // Because this server is out of our control and does not offer a secure communication channel,
    // we'll use the http version of the URL and add "earthquake.usgs.gov" to the "NSExceptionDomains"
    // value in the apps's info.plist. When you commmunicate with your own servers, or when the services you
    // use offer a secure communication option, you should always prefer to use HTTPS.
    NSURL *jsonURL = [NSURL URLWithString:@"http://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_month.geojson"];

    NSURLSession *session = [NSURLSession sessionWithConfiguration: [NSURLSessionConfiguration ephemeralSessionConfiguration]];

    NSURLSessionDataTask *task = [session dataTaskWithURL:jsonURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (!data) {
            [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
                NSLog(@"Error connecting: %@", [error localizedDescription]);
                NSString *description = NSLocalizedString(@"Could not get data from the remote server", @"Failed to connect to server");
                NSDictionary *dict = @{NSLocalizedDescriptionKey:description, NSUnderlyingErrorKey:error};
                NSError *connectionError = [NSError errorWithDomain:EARTHQUAKES_ERROR_DOMAIN code:101 userInfo:dict];
                [NSApp presentError:connectionError];
                self.fetchQuakesButton.enabled = YES;
            }];
            return;
        }

        NSError *anyError = nil;
        
        NSDictionary *jsonDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&anyError];
        if (!jsonDictionary) {
            [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
                NSLog(@"Error creating JSON dictionary: %@", [anyError localizedDescription]);
                NSString *description = NSLocalizedString(@"Could not analyze earthquake data", @"Failed to unpack JSON");
                NSDictionary *dict = @{NSLocalizedDescriptionKey:description, NSUnderlyingErrorKey:anyError};
                NSError *jsonDataError = [NSError errorWithDomain:EARTHQUAKES_ERROR_DOMAIN code:102 userInfo:dict];
                [NSApp presentError:jsonDataError];
                self.fetchQuakesButton.enabled = YES;
            }];
            return;
        }
        
        if (! [self importFromJsonDictionary:jsonDictionary error:&anyError]) {
            [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
                NSLog(@"Error importing JSON dictionary: %@", [anyError localizedDescription]);
                NSString *description = NSLocalizedString(@"Could not import earthquake data", @"Failed to importing JSON dictionary");
                NSDictionary *dict = @{NSLocalizedDescriptionKey:description, NSUnderlyingErrorKey:anyError};
                NSError *coreDataError = [NSError errorWithDomain:EARTHQUAKES_ERROR_DOMAIN code:102 userInfo:dict];
                [NSApp presentError:coreDataError];
                self.fetchQuakesButton.enabled = YES;
            }];
            return;
        };
        
        // Bounce back to the main queue to reload the table view and reenable the fetch button.
        [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
            [self reloadTableView:nil];
            self.fetchQuakesButton.enabled = YES;
        }];
    }];

    [task resume];
}

- (BOOL)importFromJsonDictionary:(NSDictionary *)jsonDictionary error:(NSError * __autoreleasing *)error {
    
    // Create a context on a private queue to fetch existing quakes to compare with incoming data and create new quakes as required.
    NSManagedObjectContext *taskContext = [[AAPLCoreDataStackManager sharedManager] createPrivateQueueContext:error];
    if (!taskContext) {
        return false;
    }
    
    // Sort the dictionaries by code; this way they can be compared in parallel with existing quakes.
    NSArray *featuresArray = jsonDictionary[@"features"];
    NSArray *sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"properties.code" ascending:YES]];
    featuresArray = [featuresArray sortedArrayUsingDescriptors:sortDescriptors];
    
    // To avoid a high memory footprint, process records in batches.
    const NSUInteger batchSize = 128;

    NSUInteger totalFeatureCount = featuresArray.count;
    NSUInteger numBatches = totalFeatureCount / batchSize;
    numBatches += totalFeatureCount % batchSize > 0 ? 1 : 0;
    
    for (NSUInteger batchNumber = 0; batchNumber < numBatches; batchNumber++) {
        
        NSInteger rangeStart = batchNumber * batchSize;
        NSInteger rangeLength = MIN(batchSize, totalFeatureCount - batchNumber * batchSize);
        
        NSRange range = NSMakeRange(rangeStart, rangeLength);
        NSArray *featuresBatchArray = [featuresArray subarrayWithRange:range];
        
        if (![self importFromFeaturesArray:featuresBatchArray usingContext:taskContext error:error]) {
            return false;
        }
    }
    return true;
}

-(BOOL)importFromFeaturesArray:(NSArray *)featuresArray usingContext:(NSManagedObjectContext *)taskContext
                      error:(NSError * __autoreleasing *)error
{
    
    // Create a request to fetch existing quakes with the same codes as those in the JSON data.
    // Existing quakes will be updated with new data; if there isn't a match, then create a new quake to represent the event.
    NSFetchRequest *matchingQuakeRequest = [NSFetchRequest fetchRequestWithEntityName:@"Quake"];
    
    // Get the codes for each of the features and store them in an array.
    NSArray *codes = [featuresArray valueForKeyPath:@"properties.code"];
    
    matchingQuakeRequest.predicate = [NSPredicate predicateWithFormat:@"code in %@" argumentArray:@[codes]];
    
    [taskContext performBlockAndWait:^{
        
        NSArray *matchingQuakes = [taskContext executeFetchRequest:matchingQuakeRequest error:error];
        if (!matchingQuakes)
        {
            return;
        }
        
        // Create a dictionary to map from a code to the corresponding matched quake.
        NSMutableDictionary *codeToQuakeMap = [[NSMutableDictionary alloc] initWithCapacity:[matchingQuakes count]];
        
        for (AAPLQuake *quake in matchingQuakes)
        {
            codeToQuakeMap[quake.code] = quake;
        }
        
        for (NSDictionary *result in featuresArray)
        {
            // For each feature in turn, retrieve the properties for the quake and create a new quake or update an existing one accordingly.
            NSDictionary * quakeDictionary = result[@"properties"];
            NSString *code = quakeDictionary[@"code"];
            
            // Get the code from the dictionary and use it to look for an existing quake that matched the codes for this batch.
            AAPLQuake *quake = codeToQuakeMap[code];
            
            if (!quake)
            {
                quake = (AAPLQuake *)[NSEntityDescription insertNewObjectForEntityForName:@"Quake" inManagedObjectContext:taskContext];
            }
            
            [quake updateFromDictionary:quakeDictionary];
        }
        
        if (![taskContext save:error]) {
            return;
        }
        
        [taskContext reset];
    }];
    
    return *error ? false : true;
}

// Handler for NSManagedObjectContextDidSaveNotification.
// Observe NSManagedObjectContextDidSaveNotification and merge the changes to the main context from other contexts.
// We rely on this to sync between contexts, thus avoid most of merge conflicts and keep UI refresh.
// In the sample code, we don’t edit the main context so not syncing with the private queue context won’t trigger any issue.
// However, a real app may not as simple as this. We normally need to handle this notificaiton.

- (void)contextDidSaveNotificationHandler:(NSNotification *)notification {
    
    if (notification.object != self.managedObjectContext) {
        
        [self.managedObjectContext performBlock:^{
            [self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
        }];
    }
}

#pragma mark - Convenience

/// Fetch quakes ordered in time and reload the table view.
- (void)reloadTableView:(id)sender {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Quake"];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"time" ascending:NO]];

    NSError *anyError;

    NSArray *fetchedQuakes = [self.managedObjectContext executeFetchRequest:request error:&anyError];

    if (!fetchedQuakes) {
        NSLog(@"Error fetching: %@", [anyError localizedDescription]);
        NSString *description = NSLocalizedString(@"Error attepmpting to update data", @"Failed to fetch earthquake data");
        NSDictionary *dict = @{NSLocalizedDescriptionKey:description, NSUnderlyingErrorKey:anyError};
        NSError *connectionError = [NSError errorWithDomain:EARTHQUAKES_ERROR_DOMAIN code:106 userInfo:dict];
        [NSApp presentError:connectionError];
        return;
    }

    self.quakes = fetchedQuakes;

    [self.tableView reloadData];
}

#pragma mark - Property Overrides

// The managed object context for the view controller (which is bound to the persistent store coordinator for the application).
- (NSManagedObjectContext *)managedObjectContext {
    if (_context) {
        return _context;
    }
    
    _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    _context.persistentStoreCoordinator = [[AAPLCoreDataStackManager sharedManager] persistentStoreCoordinator];
    
    // Avoid using default merge policy in multi-threading environment:
    // when we delete (and save) a record in one context,
    // and try to save edits on the same record in the other context before merging the changes,
    // an exception will be thrown because Core Data by default uses NSErrorMergePolicy.
    // Setting a reasonable mergePolicy is a good practice to avoid that kind of exception.
    _context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;

    // In OS X, a context provides an undo manager by default
    // Disable it for performance benefit
    _context.undoManager = nil;

    return _context;
}

#pragma mark - NSTableViewDataSource

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.quakes.count;
}

#pragma mark - NSTableViewDelegate

-(NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = [tableColumn identifier];
    
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];

    AAPLQuake *quake = self.quakes[row];

    if ([identifier isEqualToString:ColumnIdentifierPlace]) {
        cellView.textField.stringValue = quake.placeName;
    }
    else if ([identifier isEqualToString:ColumnIdentifierTime]) {
        cellView.textField.objectValue = quake.time;
    }
    else if ([identifier isEqualToString:ColumnIdentifierMagnitude]) {
        cellView.textField.objectValue = @(quake.magnitude);
    }

    return cellView;
}

@end

