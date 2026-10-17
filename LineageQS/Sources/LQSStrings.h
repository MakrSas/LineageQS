// Localisation. Keys are the English texts used in code; tables come from the
// Android SystemUI translations (Resources/strings/<lang>.json, produced
// by scripts/export_strings.py). Strings that Android does not have use a small
// built-in table (ru) and otherwise stay English.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *LQSL(NSString *key);
FOUNDATION_EXTERN void LQSStringsSetDirectory(NSString *dir);
FOUNDATION_EXTERN NSString *LQSStringsLanguage(void); // table actually used, e.g. "ru"

NS_ASSUME_NONNULL_END
