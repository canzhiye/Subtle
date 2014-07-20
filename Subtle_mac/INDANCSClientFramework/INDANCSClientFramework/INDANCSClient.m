//
//  INDANCSClient.m
//  INDANCSClient
//
//  Created by Indragie Karunaratne on 12/11/2013.
//  Copyright (c) 2013 Indragie Karunaratne. All rights reserved.
//

#import "INDANCSClient.h"
#import "INDANCSDefines.h"
#import "INDANCSDevice_Private.h"
#import "INDANCSNotification_Private.h"
#import "INDANCSApplication_Private.h"
#import "INDANCSApplicationStorage.h"
#import "INDANCSObjectiveKVDBStore.h"
#import "INDANCSRequest.h"
#import "INDANCSResponse.h"

#import "NSData+INDANCSAdditions.h"
#import "CBCharacteristic+INDANCSAdditions.h"

// Uncomment to enable debug logging
// #define ANCS_DEBUG_LOGGING

static NSUInteger const INDANCSGetNotificationAttributeCount = 5;
static NSUInteger const INDANCSGetAppAttributeCount = 1;
static NSString * const INDANCSDeviceUserInfoKey = @"device";
static NSString * const INDANCSMetadataStoreFilename = @"ANCSMetadata.db";

@interface INDANCSClient () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong, readonly) CBCentralManager *manager;
@property (nonatomic, assign, readwrite) CBCentralManagerState state;
@property (nonatomic, strong, readonly) INDANCSApplicationStorage *appStorage;
@property (nonatomic, copy) INDANCSDiscoveryBlock discoveryBlock;
@property (nonatomic, readonly) dispatch_queue_t delegateQueue;
@property (nonatomic, strong) NSMutableArray *powerOnBlocks;
@property (nonatomic, strong, readonly) NSMutableDictionary *devices;
@property (nonatomic, strong, readonly) NSMutableSet *validDevices;
@property (nonatomic, strong, readonly) NSMutableDictionary *disconnects;
@property (nonatomic, strong, readonly) NSMutableDictionary *pendingNotifications;
@property (nonatomic, strong, readonly) NSMutableSet *pendingAppRequests;
@end

@implementation INDANCSClient {
	struct {
		unsigned int deviceDisconnectedWithError:1;
		unsigned int serviceDiscoveryFailedForDeviceWithError:1;
		unsigned int deviceFailedToConnectWithError:1;
	} _delegateFlags;
}

#pragma mark - Initialization

- (id)init
{
	NSURL *parentURL = self.applicationSupportURL;
	NSURL *metadataURL = [parentURL URLByAppendingPathComponent:INDANCSMetadataStoreFilename];
	INDANCSObjectiveKVDBStore *metadata = [[INDANCSObjectiveKVDBStore alloc] initWithDatabasePath:metadataURL.path];
	return [self initWithMetadataStore:metadata];
}

- (id)initWithMetadataStore:(id<INDANCSKeyValueStore>)metadata
{
	if ((self = [super init])) {
		_appStorage = [[INDANCSApplicationStorage alloc] initWithMetadataStore:metadata];
		_devices = [NSMutableDictionary dictionary];
		_validDevices = [NSMutableSet set];
		_disconnects = [NSMutableDictionary dictionary];
		_pendingNotifications = [NSMutableDictionary dictionary];
		_pendingAppRequests = [NSMutableSet set];
		_powerOnBlocks = [NSMutableArray array];
		_delegateQueue = dispatch_queue_create("com.indragie.INDANCSClient.DelegateQueue", DISPATCH_QUEUE_SERIAL);
		_manager = [[CBCentralManager alloc] initWithDelegate:self queue:_delegateQueue options:@{CBCentralManagerOptionShowPowerAlertKey : @YES}];
		_registrationTimeout = 5.0;
		_attemptAutomaticReconnection = YES;
	}
	return self;
}

- (NSURL *)applicationSupportURL
{
	NSFileManager *fm = NSFileManager.defaultManager;
	NSURL *appSupportURL = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
	NSString *bundleName = NSBundle.mainBundle.infoDictionary[@"CFBundleName"];
	NSURL *dataURL = [appSupportURL URLByAppendingPathComponent:bundleName];
	[fm createDirectoryAtURL:dataURL withIntermediateDirectories:YES attributes:nil error:nil];
	return dataURL;
}

#pragma mark - Devices

- (void)scanForDevices:(INDANCSDiscoveryBlock)discoveryBlock
{
	NSParameterAssert(discoveryBlock);
	self.discoveryBlock = discoveryBlock;
	__weak __typeof(self) weakSelf = self;
	[self schedulePowerOnBlock:^{
		__typeof(self) strongSelf = weakSelf;
		dispatch_async(strongSelf.delegateQueue, ^{
			[strongSelf.manager scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey : @YES}];
		});
	}];
}

- (void)stopScanning
{
	self.discoveryBlock = nil;
	dispatch_async(self.delegateQueue, ^{
		[self.manager stopScan];
	});
}

#pragma mark - Registration

- (void)registerForNotificationsFromDevice:(INDANCSDevice *)device withBlock:(INDANCSNotificationBlock)notificationBlock
{
	dispatch_async(self.delegateQueue, ^{
		device.notificationBlock = notificationBlock;
		CBPeripheralState state = device.peripheral.state;
		switch (state) {
			case CBPeripheralStateConnected:
				[self setNotificationSettingsForDevice:device];
				break;
			case CBPeripheralStateDisconnected:
				[self.manager connectPeripheral:device.peripheral options:nil];
				break;
			default:
				break;
		}
	});
}

- (void)unregisterForNotificationsFromDevice:(INDANCSDevice *)device
{
	dispatch_async(self.delegateQueue, ^{
		device.notificationBlock = nil;
		[self setNotificationSettingsForDevice:device];
	});
}

- (void)setNotificationSettingsForDevice:(INDANCSDevice *)device
{
	[self invalidateRegistrationTimerForDevice:device];
	BOOL notify = (device.notificationBlock != nil);
	CBPeripheral *peripheral = device.peripheral;
	[peripheral setNotifyValue:notify forCharacteristic:device.DSCharacteristic];
	[peripheral setNotifyValue:notify forCharacteristic:device.NSCharacteristic];
	if (!notify) {
		[self startRegistrationTimerForDevice:device];
	}
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[CBCentralManager] Updated state to: %ld", central.state);
#endif
	self.state = central.state;
	if (self.state == CBCentralManagerStatePoweredOn && self.powerOnBlocks.count) {
		for (void(^block)() in self.powerOnBlocks) {
			block();
		}
		[self.powerOnBlocks removeAllObjects];
	}
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[CBCentralManager] Discovered peripheral: %@\nAdvertisement data:%@\nRSSI: %@", peripheral, advertisementData, RSSI);
#endif
	// Already connected, ignore it.
	if (peripheral.state != CBPeripheralStateDisconnected) return;
	
	peripheral.delegate = self;
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	if (device == nil) {
		device = [[INDANCSDevice alloc] initWithCBPeripheral:peripheral];
		[self setDevice:device forPeripheral:peripheral];
	}
	[central stopScan];
	[central connectPeripheral:peripheral options:nil];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[CBCentralManager] Did connect to peripheral: %@", peripheral);
#endif
	[peripheral discoverServices:@[IND_ANCS_SV_UUID, IND_DVCE_SV_UUID]];
	if (self.discoveryBlock) {
		[central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey : @YES}];
	}
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[CBCentralManager] Did disconnect peripheral: %@\nError: %@", peripheral, error);
#endif
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	if ([self.validDevices containsObject:device]) {
		if (_delegateFlags.deviceDisconnectedWithError) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.delegate ANCSClient:self device:device disconnectedWithError:error];
			});
		}
		[self.validDevices removeObject:device];
	}
	
	BOOL didDisconnect = [self didDisconnectForPeripheral:peripheral];
	if (self.attemptAutomaticReconnection && !didDisconnect) {
		[central connectPeripheral:peripheral options:nil];
	} else {
		if (didDisconnect) {
			[self setDidDisconnect:NO forPeripheral:peripheral];
		}
		[self removeDeviceForPeripheral:peripheral];
	}
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[CBCentralManager] Did fail to connect to peripheral: %@\nError: %@", peripheral, error);
#endif
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	if (_delegateFlags.deviceFailedToConnectWithError) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.delegate ANCSClient:self device:device failedToConnectWithError:error];
		});
	}
	[self removeDeviceForPeripheral:peripheral];
}

#pragma mark - CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[%@] Did discover services: %@\nError: %@", peripheral, peripheral.services, error);
#endif
	if (error) {
		[self delegateServiceDiscoveryFailedForPeripheral:peripheral withError:error];
		return;
	}
	NSArray *services = peripheral.services;
	static NSInteger const serviceCount = 2;
	NSMutableArray *foundServices = [NSMutableArray arrayWithCapacity:serviceCount];
	
	if (services.count >= serviceCount) {
		INDANCSDevice *device = [self deviceForPeripheral:peripheral];
		for (CBService *service in services) {
			if ([service.UUID isEqual:IND_ANCS_SV_UUID]) {
				device.ANCSService = service;
				[peripheral discoverCharacteristics:@[IND_ANCS_CP_UUID, IND_ANCS_DS_UUID, IND_ANCS_NS_UUID] forService:service];
				[foundServices addObject:service];
			} else if ([service.UUID isEqual:IND_DVCE_SV_UUID]) {
				device.DVCEService = service;
				[peripheral discoverCharacteristics:@[IND_DVCE_NM_UUID, IND_DVCE_ML_UUID] forService:service];
				[foundServices addObject:service];
			}
		}
	}
	if (foundServices.count < serviceCount) {
		[self delegateServiceDiscoveryFailedForPeripheral:peripheral withError:nil];
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[%@] Did discover characteristics: %@\nService: %@\nError: %@", peripheral, service.characteristics, service, error);
#endif
	if (error) {
		[self delegateServiceDiscoveryFailedForPeripheral:peripheral withError:error];
		return;
	}
	NSArray *characteristics = service.characteristics;
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	CBUUID *serviceUUID = service.UUID;
	if ([serviceUUID isEqual:IND_DVCE_SV_UUID]) {
		for (CBCharacteristic *characteristic in characteristics) {
			CBUUID *charUUID = characteristic.UUID;
			if ([charUUID isEqual:IND_DVCE_NM_UUID]) {
				device.NMCharacteristic = characteristic;
			} else if ([charUUID isEqual:IND_DVCE_ML_UUID]) {
				device.MLCharacteristic = characteristic;
			}
		}
		[peripheral readValueForCharacteristic:device.NMCharacteristic];
		[peripheral readValueForCharacteristic:device.MLCharacteristic];
	} else if ([serviceUUID isEqual:IND_ANCS_SV_UUID]) {
		for (CBCharacteristic *characteristic in characteristics) {
			CBUUID *charUUID = characteristic.UUID;
			if ([charUUID isEqual:IND_ANCS_DS_UUID]) {
				device.DSCharacteristic = characteristic;
			} else if ([charUUID isEqual:IND_ANCS_NS_UUID]) {
				device.NSCharacteristic = characteristic;
			} else if ([charUUID isEqual:IND_ANCS_CP_UUID]) {
				device.CPCharacteristic = characteristic;
			}
		}
		[self setNotificationSettingsForDevice:device];
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[%@] Did update value: %@ for characteristic: %@\nError: %@", peripheral, characteristic.value, characteristic, error);
#endif
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	if (characteristic == device.NMCharacteristic) {
		device.name = characteristic.ind_stringValue;
		[self handleDiscoveryForDevice:device];
	} else if (characteristic == device.MLCharacteristic) {
		device.modelIdentifier = characteristic.ind_stringValue;
		[self handleDiscoveryForDevice:device];
	} else if (characteristic == device.NSCharacteristic) {
		INDANCSNotification *notification = [self readNotificationWithData:characteristic.value device:device];
		if (notification.latestEventID == INDANCSEventIDNotificationRemoved) {
			[self notifyWithNotification:notification];
			[device removeNotification:notification];
		} else {
			[self requestNotificationAttributesForUID:notification.notificationUID device:device];
		}
	} else if (characteristic == device.DSCharacteristic) {
		INDANCSResponse *response = [device appendDSResponseData:characteristic.value];
		if (response == nil) return;
		
		switch (response.commandID) {
			case INDANCSCommandIDGetNotificationAttributes:
				[self readNotificationAttributeResponse:response device:device];
				break;
			case INDANCSCommandIDGetAppAttributes:
				[self readAppAttributeResponse:response device:device];
				break;
			default:
				break;
		}
	}
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
	if (error == nil) return;
#ifdef ANCS_DEBUG_LOGGING
	NSLog(@"[%@] Received error: %@ when writing to characteristic: %@", peripheral, error, characteristic);
#endif
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	[device cancelCurrentResponse];
	
	NSData *data = characteristic.value;
	NSUInteger offset = 0;
	INDANCSCommandID command = [data ind_readUInt8At:&offset];
	switch (command) {
		case INDANCSCommandIDGetNotificationAttributes: {
			uint32_t UID = [data ind_readUInt32At:&offset];
			INDANCSDevice *device = [self deviceForPeripheral:peripheral];
			[device removeNotificationForUID:UID];
			break;
		}
		case INDANCSCommandIDGetAppAttributes: {
			NSUInteger loc = [data ind_locationOfNullByteFromOffset:offset];
			if (loc != NSNotFound) {
				NSData *stringData = [data subdataWithRange:NSMakeRange(offset, loc - offset)];
				NSString *identifier = [[NSString alloc] initWithData:stringData encoding:NSUTF8StringEncoding];
				[self.pendingAppRequests removeObject:identifier];
			}
			break;
		}
		default:
			break;
	}
}

/* Always called from the CB delegate queue */
- (void)delegateServiceDiscoveryFailedForPeripheral:(CBPeripheral *)peripheral withError:(NSError *)error
{
	INDANCSDevice *device = [self deviceForPeripheral:peripheral];
	if (_delegateFlags.serviceDiscoveryFailedForDeviceWithError) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.delegate ANCSClient:self serviceDiscoveryFailedForDevice:device withError:error];
		});
	}
	if (peripheral.state == CBPeripheralStateConnected) {
		[self disconnectFromPeripheral:peripheral];
	} else if (error.code == 3 && peripheral.state == CBPeripheralStateDisconnected && self.attemptAutomaticReconnection) {
		// CBErrorDomain code 3 usually means that the device was not
		// connected.
		[self.manager connectPeripheral:peripheral options:nil];
	}
}

- (void)handleDiscoveryForDevice:(INDANCSDevice *)device
{
	if (device.name && device.modelIdentifier && ![self.validDevices containsObject:device]) {
		[self.validDevices addObject:device];
		if (self.discoveryBlock) {
			self.discoveryBlock(self, device);
		}
		[self startRegistrationTimerForDevice:device];
	}
}

#pragma mark - Timers

- (void)startRegistrationTimerForDevice:(INDANCSDevice *)device
{
	[self invalidateRegistrationTimerForDevice:device];
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.delegateQueue);
	device.registrationTimer = timer;
	dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, self.registrationTimeout * NSEC_PER_SEC);
	dispatch_source_set_timer(device.registrationTimer, time, DISPATCH_TIME_FOREVER, 0);
	dispatch_source_set_event_handler(timer, ^{
		[self.manager cancelPeripheralConnection:device.peripheral];
		[self invalidateRegistrationTimerForDevice:device];
	});
	dispatch_resume(timer);
}

- (void)invalidateRegistrationTimerForDevice:(INDANCSDevice *)device
{
	if (device.registrationTimer != NULL) {
		dispatch_source_cancel(device.registrationTimer);
		device.registrationTimer = NULL;
	}
}

#pragma mark - Notifications

- (void)notifyWithNotification:(INDANCSNotification *)notification
{
	INDANCSDevice *device = notification.device;
	INDANCSNotificationBlock notificationBlock = device.notificationBlock;
	if (notificationBlock) {
		notificationBlock(self, notification);
	}
}

- (INDANCSNotification *)readNotificationWithData:(NSData *)notificationData device:(INDANCSDevice *)device
{
	NSUInteger offset = sizeof(uint8_t) * 4; // Skip straight to the UID
	uint32_t UID = [notificationData ind_readUInt32At:&offset];
	
	INDANCSNotification *notification = [device notificationForUID:UID];
	if (notification == nil) {
		notification = [[INDANCSNotification alloc] initWithUID:UID];
		[device addNotification:notification];
	}
	[notification mergeAttributesFromGATTNotificationData:notificationData];
	return notification;
}

- (void)readNotificationAttributeResponse:(INDANCSResponse *)response device:(INDANCSDevice *)device
{
	INDANCSNotification *notification = [device notificationForUID:response.notificationUID];
	[notification mergeAttributesFromNotificationAttributeResponse:response];
	if (notification.application == nil) {
		notification.application = [self.appStorage applicationForBundleIdentifier:notification.bundleIdentifier];
	}
	if (notification.application == nil) {
		NSString *identifier = notification.bundleIdentifier;
		[self addPendingNotification:notification forBundleIdentifier:identifier];
		if (![self.pendingAppRequests containsObject:identifier]) {
			[self requestAppAttributesForBundleIdentifier:identifier device:device];
		}
	} else {
		[self notifyWithNotification:notification];
	}
}

- (void)readAppAttributeResponse:(INDANCSResponse *)response device:(INDANCSDevice *)device
{
	INDANCSApplication *application = [[INDANCSApplication alloc] initWithAppAttributeResponse:response];
	NSString *identifier = response.bundleIdentifier;
	[self.appStorage setApplication:application forBundleIdentifier:identifier];
	NSArray *notifications = [self pendingNotificationsForBundleIdentifier:identifier];
	for (INDANCSNotification *notification in notifications) {
		notification.application = application;
		[self notifyWithNotification:notification];
	}
	[self removePendingNotificationsForBundleIdentifier:identifier];
	[self.pendingAppRequests removeObject:identifier];
}

- (void)requestNotificationAttributesForUID:(uint32_t)UID device:(INDANCSDevice *)device
{
	INDANCSRequest *request = [INDANCSRequest getNotificationAttributesRequestWithUID:UID];
	
	const INDANCSNotificationAttributeID attributeIDs[INDANCSGetNotificationAttributeCount] = {
		INDANCSNotificationAttributeIDAppIdentifier,
		INDANCSNotificationAttributeIDTitle,
		INDANCSNotificationAttributeIDSubtitle,
		INDANCSNotificationAttributeIDMessage,
		INDANCSNotificationAttributeIDDate,
	};
	const uint16_t maxLen = UINT16_MAX;
	for (int i = 0; i < INDANCSGetNotificationAttributeCount; i++) {
		INDANCSNotificationAttributeID attr = attributeIDs[i];
		BOOL includeMax = (attr != INDANCSNotificationAttributeIDAppIdentifier && attr != INDANCSNotificationAttributeIDDate);
		[request appendAttributeID:attr maxLength:includeMax ? maxLen : 0];
	}
	[device sendRequest:request];
}

- (void)requestAppAttributesForBundleIdentifier:(NSString *)identifier device:(INDANCSDevice *)device
{
	INDANCSRequest *request = [INDANCSRequest getAppAttributesRequestWithBundleIdentifier:identifier];
	
	const INDANCSAppAttributeID attributesIDs[INDANCSGetAppAttributeCount] = {
		INDANCSAppAttributeIDDisplayName
	};
	for (int i = 0; i < INDANCSGetAppAttributeCount; i++) {
		[request appendAttributeID:attributesIDs[i] maxLength:0];
	}
	[self.pendingAppRequests addObject:identifier];
	[device sendRequest:request];
}

#pragma mark - Accessors

- (void)setDelegate:(id<INDANCSClientDelegate>)delegate
{
	if (_delegate != delegate) {
		_delegate = delegate;
		_delegateFlags.deviceDisconnectedWithError = [delegate respondsToSelector:@selector(ANCSClient:device:disconnectedWithError:)];
		_delegateFlags.serviceDiscoveryFailedForDeviceWithError = [delegate respondsToSelector:@selector(ANCSClient:serviceDiscoveryFailedForDevice:withError:)];
		_delegateFlags.deviceFailedToConnectWithError = [delegate respondsToSelector:@selector(ANCSClient:device:failedToConnectWithError:)];
	}
}

#pragma mark - State

- (void)schedulePowerOnBlock:(void(^)())block
{
	NSParameterAssert(block);
	if (self.state == CBCentralManagerStatePoweredOn) {
		block();
	} else {
		dispatch_async(self.delegateQueue, ^{
			[self.powerOnBlocks addObject:[block copy]];
		});
	}
}

- (void)setDevice:(INDANCSDevice *)device forPeripheral:(CBPeripheral *)peripheral
{
	NSParameterAssert(peripheral);
	NSParameterAssert(device);
	self.devices[peripheral.identifier] = device;
}

- (INDANCSDevice *)deviceForPeripheral:(CBPeripheral *)peripheral
{
	NSParameterAssert(peripheral);
	return self.devices[peripheral.identifier];
}

- (void)removeDeviceForPeripheral:(CBPeripheral *)peripheral
{
	NSParameterAssert(peripheral);
	[self.devices removeObjectForKey:peripheral.identifier];
}

- (void)setDidDisconnect:(BOOL)disconnect forPeripheral:(CBPeripheral *)peripheral
{
	NSParameterAssert(peripheral);
	if (disconnect) {
		self.disconnects[peripheral.identifier] = @YES;
	} else {
		[self.disconnects removeObjectForKey:peripheral.identifier];
	}
}

- (BOOL)didDisconnectForPeripheral:(CBPeripheral *)peripheral
{
	NSParameterAssert(peripheral);
	return [self.disconnects[peripheral.identifier] boolValue];
}

/* Always called from the CB delegate queue */
- (void)disconnectFromPeripheral:(CBPeripheral *)peripheral
{
	[self setDidDisconnect:YES forPeripheral:peripheral];
	[self.manager cancelPeripheralConnection:peripheral];
}

- (void)addPendingNotification:(INDANCSNotification *)notification forBundleIdentifier:(NSString *)identifier
{
	NSParameterAssert(identifier);
	NSMutableArray *notifications = self.pendingNotifications[identifier];
	if (notifications == nil) {
		notifications = [NSMutableArray arrayWithCapacity:1];
		self.pendingNotifications[identifier] = notifications;
	}
	[notifications addObject:notification];
}

- (void)removePendingNotificationsForBundleIdentifier:(NSString *)identifier
{
	NSParameterAssert(identifier);
	[self.pendingNotifications removeObjectForKey:identifier];
}

- (NSArray *)pendingNotificationsForBundleIdentifier:(NSString *)identifier
{
	NSParameterAssert(identifier);
	return self.pendingNotifications[identifier];
}

@end
