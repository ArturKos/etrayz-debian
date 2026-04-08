/* Test program for EtrayZ toolchain verification */
#include <stdio.h>

int main(void) {
    printf("Hello from EtrayZ! ARM926EJ-S (ARMv5TEJ)\n");
    printf("Compiled with GCC %d.%d.%d\n",
           __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
    printf("This binary runs on the Xtreamer EtrayZ NAS.\n");
    return 0;
}
