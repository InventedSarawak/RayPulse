#include <stdio.h>
#include <vec3.h>
#include <color.h>

int main() {
    const int image_width = 256;
    const int image_height = 256;

    // PPM header
    printf("P3\n%d %d\n255\n", image_width, image_height);

    for (int j = image_height - 1; j >= 0; --j) {
        for (int i = 0; i < image_width; ++i) {
            double r = (double)i / (image_width - 1);
            double g = (double)j / (image_height - 1);
            double b = 0.0;

            color pixel_color = vec3_create(r, g, b);
            write_color(stdout, pixel_color);
        }
    }

    return 0;
}
