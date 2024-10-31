#include <stdio.h>
#include <math.h>


int main() {
    // image
    int image_width = 256;
    int image_height = 256;
    double r, g, b;

    // render 

    printf("P3\n%d %d\n255\n", image_width, image_height);

    for (int i = 0; i < image_height; i++) {
        fprintf(stderr, "\rScanlines remaining: %d ", image_height - i);
        for (int j = 0; j < image_width; j++) {
            r = (double) i / (double)(image_height - 1);
            g = (double) j / (double)(image_width - 1);
            b = 0.25;

            int ir = floor(255.99 * r);
            int ig = floor(255.99 * g);
            int ib = floor(255.99 * b);

            printf("%d %d %d\n", ir, ig, ib);
        }
    }
    fprintf(stderr, "\rDone.                 \n");
    return 0;
}