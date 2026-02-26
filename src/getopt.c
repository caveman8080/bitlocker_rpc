/* Minimal getopt implementation for Windows (sufficient for this project)
   Not a full-featured replacement — only supports short options and required arguments.
*/
#include "getopt.h"
#include <string.h>
#include <stdlib.h>

char *optarg = NULL;
int optind = 1;
int opterr = 1;
int optopt = 0;

int getopt(int argc, char * const argv[], const char *optstring) {
    if (optind >= argc) return -1;
    char *arg = argv[optind];
    if (arg[0] != '-' || arg[1] == '\0') return -1;
    // support '--' end
    if (arg[1] == '-' && arg[2] == '\0') { optind++; return -1; }

    char opt = arg[1];
    optopt = opt;
    // find opt in optstring
    const char *p = strchr(optstring, opt);
    if (!p) { optind++; return '?'; }
    // if option requires argument (next char in optstring == ':'), take next argv
    if (*(p + 1) == ':') {
        if (arg[2] != '\0') {
            // attached argument like -fvalue
            optarg = &arg[2];
            optind++;
            return opt;
        } else if (optind + 1 < argc) {
            optarg = argv[optind + 1];
            optind += 2;
            return opt;
        } else {
            // missing argument
            optind++;
            return ':';
        }
    } else {
        // no argument expected
        if (arg[2] != '\0') {
            // grouped options not supported; skip rest
        }
        optind++;
        optarg = NULL;
        return opt;
    }
}
