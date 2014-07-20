//
//  NSObject_INDANCSDefines.h
//  INDANCSiPhone
//
//  Created by Indragie Karunaratne on 12/11/2013.
//  Copyright (c) 2013 Indragie Karunaratne. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <CoreBluetooth/CoreBluetooth.h>
#else
#import <IOBluetooth/IOBluetooth.h>
#endif

NS_INLINE CBUUID * ind_CBUUID(NSString *str) {
	return [CBUUID UUIDWithString:str];
}

#define IND_ANCS_SV_UUID ind_CBUUID(@"7905F431-B5CE-4E99-A40F-4B1E122D00D0") // ANCS service
#define IND_ANCS_NS_UUID ind_CBUUID(@"9FBF120D-6301-42D9-8C58-25E699A21DBD") // ANCS Notification Source
#define IND_ANCS_CP_UUID ind_CBUUID(@"69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9") // ANCS Control Point
#define IND_ANCS_DS_UUID ind_CBUUID(@"22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB") // ANCS Data Source

#define IND_DVCE_SV_UUID ind_CBUUID(@"B4178473-4A65-4BD1-A565-D8CB9BA5F013") // DEVICE service
#define IND_DVCE_NM_UUID ind_CBUUID(@"D4546067-C583-498B-B450-4D56DA9E206F") // DEVICE Name
#define IND_DVCE_ML_UUID ind_CBUUID(@"517F5BB8-81C6-4FCD-B4E9-9AF263D7B7D8") // DEVICE Model
