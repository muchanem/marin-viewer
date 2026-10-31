// 放射線 — café 🚀
#include <stddef.h>
#define MAX_SCANS 16
#define TWICE(x) ((x) * 2)

typedef unsigned long ScanID;
struct Scan {
    ScanID id;
    const char *title;
};
enum Modality { XRAY, MRI };

/* A multiline comment
   containing fake_call() that is never a call site. */
static int measure(const struct Scan *scan) {
    return scan->id > 0;
}

const char **titles(struct Scan *scan) {
    if (measure(scan)) {
        return &scan->title;
    }
    return NULL;
}

int render(struct Scan *scan, int (*callback)(int)) {
    return callback(measure(scan));
}

