/*
 * Copyright (C) 2014 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once
#include <math.h>

// C adaptation of lineage-24.0 FlingAnimationUtils.getProperties/getInterpolator.
// The port's existing 1dp = 1pt layout mapping uses density=1: points and pt/s.
// Native iOS still owns gesture acceptance and the final open/close decision.
typedef struct {
    double duration, x1, y1, x2, y2, velocityScale;
    int crossfade;
} LQSFling;

static inline LQSFling LQSFlingCurve(double duration, double x1, double y1, double x2, double y2) {
    return (LQSFling){ floor(fmax(0, duration) * 1000) / 1000, x1, y1, x2, y2, 0, 0 };
}

static inline LQSFling LQSAndroidFling(double from, double to, double velocity,
                                      double maxDistance, double maxSeconds,
                                      double speedUp, double x2, double y2) {
    double distance = fabs(to - from), speed = fabs(velocity);
    if (distance <= 0.000001) return LQSFlingCurve(0, 0.4, 0, 0.2, 1);
    double maxDuration = maxSeconds * sqrt(distance / fmax(0.000001, maxDistance));
    double factor = speedUp == 0 ? 1 : fmin(speed / 3000, 1);
    if (x2 < 0) x2 = 0.35 * (1 - speedUp) + 0.68 * speedUp;
    double gradient = 0.75 * (1 - factor) + (y2 / x2) * factor;
    double duration = speed > 0 ? gradient * distance / speed : INFINITY;
    double x1 = speedUp * (1 - factor);
    LQSFling result = LQSFlingCurve(duration <= maxDuration ? duration : maxDuration,
                                  x1, x1 * gradient, x2, y2);
    if (duration > maxDuration) {
        if (speed >= 250) {
            result.crossfade = 1;
            // Android's velocity interpolator uses unrounded seconds; only the
            // animator's duration is truncated to milliseconds.
            result.velocityScale = maxDuration * speed / distance;
        } else {
            result = LQSFlingCurve(maxDuration, 0.4, 0, 0.2, 1);
        }
    }
    return result;
}

static inline double LQSFlingValue(LQSFling fling, double fraction,
                                   double (*cubic)(double, double, double, double, double)) {
    if (fraction <= 0) return 0;
    if (fraction >= 1) return 1;
    double slow = cubic(fling.x1, fling.y1, fling.x2, fling.y2, fraction);
    if (!fling.crossfade) return slow;
    double blend = cubic(0, 0, 0.2, 1, fraction); // LINEAR_OUT_SLOW_IN
    return (1 - blend) * fraction * fling.velocityScale + blend * slow;
}
