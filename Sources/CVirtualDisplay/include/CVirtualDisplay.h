#pragma once
#include <stdint.h>

/// A virtual display created with the private CGVirtualDisplay API. displayID is 0 on failure.
typedef struct { uint32_t displayID; void *handle; } SHVirtualDisplay;

SHVirtualDisplay SHCreateVirtualDisplay(uint32_t width, uint32_t height, uint32_t serial, const char *name);
void SHDestroyVirtualDisplay(SHVirtualDisplay d);
