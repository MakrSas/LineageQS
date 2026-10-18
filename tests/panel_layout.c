#include "../LineageQS/Sources/LQSLayout.h"
#include <assert.h>
#include <stdio.h>

static int check(double width, double height, double safeBottom) {
    int landscape = width > height, columns = landscape ? 8 : 4;
    double tile = fmin(72, (width - 32 - (columns - 1) * 8) / columns);
    double gridTop = (landscape ? 56 : 144) + 60;
    double safeEdge = height - safeBottom - 12;
    int rows = LQSRowsFitting(landscape ? 2 : 4, safeEdge - gridTop - 92, tile, 8);
    double gridBottom = gridTop + rows * tile + (rows - 1) * 8;
    double footerTop = LQSFooterTop(height, safeBottom);
    double footerBottom = footerTop + 48;
    assert(gridBottom <= footerTop + 1e-9);
    double buttonsTop = LQSActionRowTop(height, safeBottom);
    double buttonsBottom = buttonsTop + 40;
    assert(fabs(footerBottom + 4 - buttonsTop) < 1e-9);
    assert(fabs(buttonsBottom - safeEdge) < 1e-9); // no floating row above unused space
    assert(rows >= 1 && rows <= (landscape ? 2 : 4));
    return rows;
}

int main(void) {
    assert(check(320, 568, 0) == 3); // SE: old four-row footer was offscreen
    assert(check(568, 320, 0) == 1);
    assert(check(375, 667, 0) == 4);
    assert(check(667, 375, 0) == 2);
    check(375, 812, 34);
    check(812, 375, 21);
    check(430, 932, 34);
    check(932, 430, 21);
    // Sweep short/large viewports and changing bottom safe-area insets.
    for (int height = 320; height <= 1024; ++height) {
        check(568, height, 0);
        check(568, height, 21);
    }
    puts("Panel footer/safe-area layout checks passed.");
}
