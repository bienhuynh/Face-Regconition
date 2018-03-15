
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "LuxandFaceSDK.h"

#define MAX(x, y) (((x) >= (y)) ? (x) : (y))

int main(int argc, char * argv[])
{
	printf("Portrait (c) 2010 Luxand, Inc.\n\n");
	
	if (argc < 3) {
	    printf("Usage: portrait <in_file> <out_file>\n");
        exit(-1);
	}

    char * inputFileName = argv[1];
    char * outFileName = argv[2];

    printf("Initializing...\n");

    if (FSDKE_OK != FSDK_ActivateLibrary("fhPKopJVjHpnsV6/aumzjOvApHU7gnFduuovOu1DRngQEEevUnlpLfSAhNIhLVjzPYYbhmrz36x9Xnn1AZ/8HOcgXtIaZxOxZzNXNwS3ezLiwFwZGhY9w3S+beKvuIC8DhosdzRYCSGx4H9hC1A+jAHqTPjBTr42nKiOZ+y3H70=")) {
        fprintf(stderr, "Error activating Luxand FaceSDK\n");
        fprintf(stderr, "Please run the License Key Wizard (Start - Luxand - FaceSDK - License Key Wizard)\n");

		char * buf = new char[1024];
		memset((void *)buf, 0, 1024);
        FSDK_GetLicenseInfo(buf);
        fprintf(stderr, "Licensing info: %s\n", buf);
        exit(1);
	}

	if (FSDK_Initialize("") != FSDKE_OK){
        fprintf(stderr, "Error initializing Luxand FaceSDK!\n");
        exit(1);
	}

	HImage img1;
    printf("Loading file %s...\n", inputFileName);
	if (FSDK_LoadImageFromFile(&img1, inputFileName) != FSDKE_OK){
        fprintf(stderr, "Error loading file!\n");
        exit(2);
	}

    FSDK_SetFaceDetectionParameters(true, true, 256); // set a lower value to speed up face detection

    FSDK_SetFaceDetectionThreshold(5); // set a lower value to increase detection rate
    printf("Detecting face...\n");

	TFacePosition fp;
	if (FSDKE_OK != FSDK_DetectFace(img1, &fp)) {
        fprintf(stderr, "No faces found!\n");
        exit(3);
	}

	HImage img2;
    FSDK_CreateEmptyImage(&img2);

    int x1 = fp.xc - 1.2*fp.w/2;
    int y1 = fp.yc - 1.4*fp.w/2;
    int x2 = fp.xc + 1.2*fp.w/2;
    int y2 = fp.yc + 1.4*fp.w/2;
    
    FSDK_CopyRect(img1, x1, y1, x2, y2, img2);

	int maxWidth = 337;
	int maxHeight = 450;

    FSDK_ResizeImage(img2, MAX((maxWidth+0.4)/(x2-x1+1), (maxHeight+0.4)/(y2-y1+1)), img1);

    FSDK_SetJpegCompressionQuality(85);
	if (FSDK_SaveImageToFile(img1, outFileName) != FSDKE_OK){
        fprintf(stderr, "Error saving file!\n");
        exit(4);
	}

	FSDK_FreeImage(img1);
    FSDK_FreeImage(img2);

    printf("Done\n");

	return 0;
}

