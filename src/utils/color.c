#include "color.h"

void write_color(FILE* out, color pixel_color) {
    double r = vec3_x(pixel_color);
    double g = vec3_y(pixel_color);
    double b = vec3_z(pixel_color);

    // Clamp to [0, 0.999] to avoid 256
    if (r < 0) r = 0; if (r > 0.999) r = 0.999;
    if (g < 0) g = 0; if (g > 0.999) g = 0.999;
    if (b < 0) b = 0; if (b > 0.999) b = 0.999;

    int rbyte = (int)(256 * r);
    int gbyte = (int)(256 * g);
    int bbyte = (int)(256 * b);

    fprintf(out, "%d %d %d\n", rbyte, gbyte, bbyte);
}
