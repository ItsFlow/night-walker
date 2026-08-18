#ifndef CMEDIAACCESSIBILITY_H
#define CMEDIAACCESSIBILITY_H

// Private SPI from /System/Library/Frameworks/MediaAccessibility.framework.
//
// These functions are NOT in the framework's public headers, but they are
// exported symbols (see the .tbd stub in the macOS SDK) and are linkable under
// Command Line Tools. They were confirmed empirically on this machine
// (macOS, arm64) via `dyld_info -exports`, `nm`-of-tbd, and runtime probes.
// See EVIDENCE.md for the full investigation.
//
// The category argument is an integer enum. `MADisplayFilterPrefCopyCategories
// ForCurrentPlatform()` returns CFNumbers 1..5; category 1 is the "Color
// Filters" master (the "__Color__" preference domain). CoreFoundation's
// `Boolean` is `unsigned char`.
//
// Calling the setter posts kMADisplayFilterSettingsChangedNotification, which
// is what makes WindowServer apply the filter live (a bare `defaults write`
// does not do this).

// Returns 1 if the given display-filter category's master toggle is on.
extern unsigned char MADisplayFilterPrefGetCategoryEnabled(long category);

// Turns the given display-filter category's master toggle on (1) or off (0).
extern void MADisplayFilterPrefSetCategoryEnabled(long category, unsigned char enabled);

// Current filter type for a category (for the Color category this matches
// "__Color__-MADisplayFilterType"). Confirmed empirically to take the CATEGORY
// as its argument (not void): GetType(1) returns 16 on this machine (the "Color
// Tint" / single-color type). NOTE: a `void` declaration silently misreads as 0
// under Swift's calling convention — the argument is real.
extern long MADisplayFilterPrefGetType(long category);

// Read/write the intensity of the single-color ("Color Tint") filter — a
// 0.0...1.0 value that IS the live macOS "Color Filters" intensity slider for
// that filter type. Confirmed empirically: the getter RETURNS A `double` (not
// float — a float declaration reads garbage), matching the
// "MADisplayFilterSingleColorIntensity" preference exactly. Takes no argument;
// the setter takes the new value and applies it live.
extern double MADisplayFilterPrefGetSingleColorIntensity(void);
extern void MADisplayFilterPrefSetSingleColorIntensity(double intensity);

#endif /* CMEDIAACCESSIBILITY_H */
