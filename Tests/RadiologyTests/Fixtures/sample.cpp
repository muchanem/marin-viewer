// 放射線 — café 🚀
namespace imaging {
template <typename T> T twice(T value) {
    return value + value;
}

using ScanID = unsigned long;
class Scan {
public:
    Scan() {
        reset();
    }
    ~Scan() {
        reset();
    }
    int render(int value) const {
        auto deferred = [value] {
            return twice<int>(value);
        };
        return deferred();
    }
    void reset() {
        id = 0;
    }
    Scan &operator+=(int value) {
        id += value;
        return *this;
    }
    const char **titles();
private:
    ScanID id;
};

const char **Scan::titles() {
    reset();
    return nullptr;
}

int load(Scan &scan) {
    // "café" keeps downstream callee offsets in UTF-8.
    const char *label = "café"; return scan.render(imaging::twice<int>(3));
}
}

