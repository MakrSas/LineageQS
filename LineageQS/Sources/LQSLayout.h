#pragma once
#include <math.h>

static inline double LQSActionRowTop(double height, double safeBottom) {
    return fmax(0, height - safeBottom - 12 - 40);
}

// Pager/Edit sit immediately above the bottom action row, not below the grid.
static inline double LQSFooterTop(double height, double safeBottom) {
    return fmax(0, LQSActionRowTop(height, safeBottom) - 4 - 48);
}

// Keep the pager and 40pt action buttons below the grid, inside the safe area.
static inline int LQSRowsFitting(int preferred, double available, double rowHeight, double gap) {
    int rows = (int)floor((fmax(0, available) + gap) / fmax(1, rowHeight + gap));
    return rows < 1 ? 1 : (rows > preferred ? preferred : rows);
}
