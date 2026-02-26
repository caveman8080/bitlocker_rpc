/* Minimal getopt replacement for Windows builds
   Supports options with optional arguments of form: -h -f <arg> -t <arg> -b <arg> -o <arg>
   This is intentionally small and only covers the flags used by bitlocker_rpc.cu
*/
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

extern char *optarg;
extern int optind;
extern int opterr;
extern int optopt;

int getopt(int argc, char * const argv[], const char *optstring);

#ifdef __cplusplus
}
#endif
