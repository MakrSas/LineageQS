#pragma once
#include <math.h>

// NSSL.calculateInterpolatedStackHeight: the no-shelf stack starts at 50%
// height. QSC passes that stack fraction, not raw shade progress, to QQS.
static inline double LQSNotificationStackFraction(double progress) {
    return 0.5 + 0.5 * fmax(0, fmin(1, progress));
}

static inline double LQSQuickTileSquish(double progress, double qsExpansion) {
    return qsExpansion > 0 ? 1 : 0.1 + 0.9 * LQSNotificationStackFraction(progress);
}

// NSSL.updateStackPosition: stackY = lerp(0, topPadding, shadeFraction).
// Full QS occupies the whole viewport here, pushing notifications offscreen.
static inline double LQSNotificationTop(double progress, double qsExpansion,
                                         double compactTop, double screenHeight) {
    double p = fmax(0, fmin(1, progress));
    double q = fmax(0, fmin(1, qsExpansion));
    return p * (compactTop + (screenHeight - compactTop) * q);
}

static inline double LQSNotificationViewportHeight(double progress, double screenHeight,
                                                    double stackTop) {
    return fmax(0, fmax(0, fmin(1, progress)) * screenHeight - stackTop);
}

// NPVC tracks expandedHeight from the initial touch height plus drag delta;
// normalizing by QQS height makes the whole shade close several times too fast.
static inline double LQSShadeDragProgress(double start, double delta, double height) {
    return fmax(0, fmin(1, start + delta / fmax(1, height)));
}

// LineageOS 24 classic shade: system bottom inset, then FooterActions with
// 8dp top / 4dp bottom padding and 48dp interactive targets (40dp visuals).
// UIKit safeBottom substitutes for Android's bottomStableInsets; do not invent
// a navigation-bar height for devices with a physical Home button.
static inline double LQSActionRowTop(double height, double safeBottom) {
    return fmax(0, height - fmax(0, safeBottom) - 4 - 48);
}

// PaginatedGridLayout's 48dp Pager/Edit row precedes FooterActions' top padding.
static inline double LQSFooterTop(double height, double safeBottom) {
    return fmax(0, LQSActionRowTop(height, safeBottom) - 8 - 48);
}

// Keep the complete footer stack below the grid, inside the safe area.
static inline int LQSRowsFitting(int preferred, double available, double rowHeight, double gap) {
    int rows = (int)floor((fmax(0, available) + gap) / fmax(1, rowHeight + gap));
    return rows < 1 ? 1 : (rows > preferred ? preferred : rows);
}
