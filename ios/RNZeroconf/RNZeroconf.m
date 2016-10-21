//
//  RNZeroconf.m
//  RNZeroconf
//
//  Created by Balthazar Gronon on 25/10/2015.
//  Copyright © 2016 Balthazar Gronon MIT
//

#import "RNZeroconf.h"
#import "RNNetServiceSerializer.h"

@interface RNZeroconf ()

@property (nonatomic, strong, readonly) NSMutableDictionary *resolvingServices;

@end

@implementation RNZeroconf

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(scan:(NSString *)type protocol:(NSString *)protocol domain:(NSString *)domain)
{
    [self stop];
    [self.browser searchForServicesOfType:[NSString stringWithFormat:@"_%@._%@.", type, protocol] inDomain:domain];
}

RCT_EXPORT_METHOD(stop)
{
    [self.browser stop];
    [self.resolvingServices removeAllObjects];
}

RCT_EXPORT_METHOD(publish:(NSString *)name type:(NSString *)type port:(NSInteger)port
                  protocol:(NSString *)protocol domain:(NSString *)domain)
{
    NSNetService *service;
    NSString *fullType = [NSString stringWithFormat:@"_%@._%@", type, protocol];
    
    service = [[NSNetService alloc] initWithDomain:domain
                                         type:fullType
                                         name:name
                                         port:(int)port];
    if(service) {
        NSLog(@"Publishing service: name=\"%@\", type=\"%@\", port=%ld, domain=\"%@\"", name, fullType, (long)port, domain);
        [service setDelegate:self];
        [service publish];
        [_publishedServices addObject:service];
    } else {
        NSLog(@"An error occurred initializing the NSNetService object.");
        [self reportError:@{ @"Error" : @"An error occurred initializing the NSNetService object." }];
    }
}

RCT_EXPORT_METHOD(unpublish:(NSString *)name type:(NSString *)type port:(NSInteger)port
                  protocol:(NSString *)protocol domain:(NSString *)domain)
{
    NSPredicate *predicate = [NSPredicate
        predicateWithFormat:@"(name == %@) AND (type == %@) AND (domain == %@) AND (port == %d", name,
        [NSString stringWithFormat:@"_%@.%@.", type, protocol], domain, port];
    
    for (NSNetService *service in [_publishedServices filteredArrayUsingPredicate:predicate]) {
        NSLog(@"Unpublishing service \"%@\"", name);
        [_publishedServices removeObject:service];
        [service stop];
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroConfUnpublish" body:service];
    }
}

#pragma mark - NSNetServiceDelegate

// When a service fails to publish
- (void) netService:(NSNetService *) sender didNotPublish:(NSDictionary*) errorDict
{
    NSLog(@"Service failed to publish");
    if ([_publishedServices containsObject:sender])
        [_publishedServices removeObject:sender];
    [self reportError:errorDict];
}

// When a service is successfully published
- (void) netServiceDidPublish:(NSNetService*) sender
{
    NSLog(@"Service \"%@\" published on port %ld", [sender name], (long)[sender port]);
    NSDictionary *serviceInfo = [RNNetServiceSerializer serializeServiceToDictionary:sender resolved:YES];
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfPublish" body:serviceInfo];
}

#pragma mark - NSNetServiceBrowserDelegate

// When a service is discovered.
- (void) netServiceBrowser:(NSNetServiceBrowser *)browser
            didFindService:(NSNetService *)service
                moreComing:(BOOL)moreComing
{
    NSDictionary *serviceInfo = [RNNetServiceSerializer serializeServiceToDictionary:service resolved:NO];
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfFound" body:serviceInfo];

    // resolving services must be strongly referenced or they will be garbage collected
    // and will never resolve or timeout.
    // source: http://stackoverflow.com/a/16130535/2715
    self.resolvingServices[service.name] = service;

    service.delegate = self;
    [service resolveWithTimeout:5.0];
}

// When a service is removed.
- (void) netServiceBrowser:(NSNetServiceBrowser*)netServiceBrowser
          didRemoveService:(NSNetService*)service
                moreComing:(BOOL)moreComing
{
    NSDictionary *serviceInfo = [RNNetServiceSerializer serializeServiceToDictionary:service resolved:NO];
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfRemove" body:serviceInfo];
}

// When the search fails.
- (void) netServiceBrowser:(NSNetServiceBrowser *)browser
              didNotSearch:(NSDictionary *)errorDict
{
    [self reportError:errorDict];
}

// When the search stops.
- (void) netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfStop" body:nil];
}

// When the search starts.
- (void) netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser
{
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfStart" body:nil];
}

#pragma mark - NSNetServiceDelegate

// When the service has resolved it's network data (IP addresses, etc)
- (void) netServiceDidResolveAddress:(NSNetService *)sender
{
    NSDictionary *serviceInfo = [RNNetServiceSerializer serializeServiceToDictionary:sender resolved:YES];
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfResolved" body:serviceInfo];

    sender.delegate = nil;
    [self.resolvingServices removeObjectForKey:sender.name];
}

// When the service has failed to resolve it's network data (IP addresses, etc)
- (void) netService:(NSNetService *)sender
      didNotResolve:(NSDictionary *)errorDict
{
    [self reportError:errorDict];

    sender.delegate = nil;
    [self.resolvingServices removeObjectForKey:sender.name];
}

#pragma mark - Class methods

- (instancetype) init
{
    self = [super init];

    if (self) {
        _resolvingServices = [[NSMutableDictionary alloc] init];
        _browser = [[NSNetServiceBrowser alloc] init];
        [_browser setDelegate:self];
        _publishedServices = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void) reportError:(NSDictionary *)errorDict
{
    for (int a = 0; a < errorDict.count; ++a) {
        NSString *key = [[errorDict allKeys] objectAtIndex:a];
        NSString *val = [errorDict objectForKey:key];
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"RNZeroconfError" body:val];
    }
}

@end
