# Earthquakes: Using a "private" persistent store coordinator to fetch data in background

Most applications that use Core Data employ a single persistent store coordinator to mediate access to a given persistent store. Earthquakes shows how to use an additional "private" persistent store coordinator when creating managed objects using data retrieved from a remote server.


## Application Architecture

The application uses two Core Data "stacks" (as defined by the existence of a persistent store coordinator). The first is the typical "general purpose" stack; the second is created by a view controller specifically to fetch data from a remote server.

The main persistent store coordinator is vended by a singleton "stack controller" object (an instance of CoreDataStackManager). It is the responsibility of its clients to create a managed object context to work with the coordinator[^1]. The stack controller also vends properties for the managed object model used by the application, and the location of the persistent store. Clients can use these latter properties to set up additional persistent store coordinators to work in parallel with the main coordinator.

The main view controller, an instance of QuakesViewController, uses the stack controller's persistent store coordinator to fetch quakes from the persistent store to display in a table view. Retrieving data from the server can be a long-running operation which requires significant interaction with the persistent store to determine whether records retrieved from the server are new quakes or potential updates to existing quakes. To ensure that the application can remain responsive during this operation, the view controller employs a second coordinator to manage interaction with the persistent store. It configures the coordinator to use the same managed object model and persistent store as the main coordinator vended by the stack controller. It creates a managed object context bound to a private queue to fetch data from the store and commit changes to the store.

## Note

In Swift projects, class names for entities in the Core Data model include the module name. For example, the Quake entity specifies the Earthquakes.Quake class (see SwiftEntityDefinition.png in the Swift project folder).



## Requirements

### Build

Xcode 7.3 or later, OS X v10.11 SDK or later.

### Runtime

OS X v10.9 or later.

Copyright (C) 2016 Apple Inc. All rights reserved.


[^1]: This supports the "pass the baton" approach whereby—particularly in iOS applications—a context is passed from one view controller to another. The root view controller is responsible for creating the initial context, and passing it to child view controllers as/when necessary.

The reason for this pattern is to ensure that changes to the managed object graph are appropriately constrained. Core Data supports "nested" managed object contexts which allow for a flexible architecture that make it easy to support independent, cancellable, change sets. With a child context, you can allow the user to make a set of changes to managed objects that can then either be committed wholesale to the parent (and ultimately saved to the store) as a single transaction, or discarded. If all parts of the application simply retrieve the same context from, say, an application delegate, it makes this behavior difficult or impossible to support.
