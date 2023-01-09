//
//  Secrets.m
//  FurAffinity
//
//  Created by Ceylo on 09/01/2023.
//

#import "Secrets.h"
#define xstr(s) str(s)
#define str(s) #s

NSString* AppCenterApiKey(void)
{
    return [NSString stringWithUTF8String: xstr(AppCenter_API_KEY)];
}
