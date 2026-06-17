#import "OQObjCSupport.h"

NSError * _Nullable OQTryCatch(void (NS_NOESCAPE ^ _Nonnull block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[NSLocalizedDescriptionKey] =
            exception.reason ?: exception.name ?: @"Objective-C exception";
        if (exception.name) {
            info[@"OQExceptionName"] = exception.name;
        }
        return [NSError errorWithDomain:@"OQObjCException" code:1 userInfo:info];
    }
}
