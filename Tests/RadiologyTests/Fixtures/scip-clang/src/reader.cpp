#include "math.h"
int Reader::render(int value) const {
    return add(value, 1);
}
int Reader::render(int left, int right) const {
    return add(left, right);
}
int read(const Reader &reader) {
    const char *label = "café 🚀"; return reader.render(4) + reader.render(4, 5);
}
