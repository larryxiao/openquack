#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C @try/@catch and converts any thrown
/// `NSException` into an `NSError` (domain `OQObjCException`). Returns `nil`
/// when the block completes normally.
///
/// Swift's `do/try/catch` cannot intercept Objective-C exceptions — and several
/// AVFoundation calls (notably `-[AVAudioNode installTapOnBus:bufferSize:format:block:]`)
/// raise `NSInvalidArgumentException` on a format/hardware mismatch, which would
/// otherwise abort the whole process (SIGABRT). Wrapping those calls in
/// `OQTryCatch` turns the crash into a recoverable Swift error.
NSError * _Nullable OQTryCatch(void (NS_NOESCAPE ^ _Nonnull block)(void));

NS_ASSUME_NONNULL_END
