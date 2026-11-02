#ifndef FIXTURE_MATH_H
#define FIXTURE_MATH_H
#ifdef __cplusplus
extern "C" {
#endif
int add(int left, int right);
#ifdef __cplusplus
}
class Reader {
public:
    int render(int value) const;
    int render(int left, int right) const;
};
#endif
#endif
