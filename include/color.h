#ifndef COLOR_H
#define COLOR_H

#include "vec3.h"
#include <stdio.h>

typedef vec3 color;

void write_color(FILE *out, color pixel_color);

#endif
