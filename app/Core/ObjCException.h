#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift can't catch NSException. Wrap AVFoundation calls that raise one
/// (e.g. installTap on a stale format) so they surface as a thrown NSError instead of aborting.
@interface ObjCException : NSObject
+ (BOOL)catching:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
