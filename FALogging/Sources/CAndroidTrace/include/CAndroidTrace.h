#pragma once

// swift-android-native's AndroidNDK module leaves out <android/trace.h>.
// Guarded so a Darwin build that visits this target compiles it empty.
#if defined(__ANDROID__)
#include <android/trace.h>
#include <unistd.h>
#endif
