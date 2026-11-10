#include <iostream>
#include <vector>
#include <algorithm>
#include <string>
#include <stdexcept>
#include <optional>

int main()
{
    std::vector<int> v { 5, 1, 4, 2, 3 };
    std::sort(v.begin(), v.end());
    std::string s;
    for (int x : v)
        s += std::to_string(x);
    try {
        throw std::runtime_error("eh-works");
    } catch (const std::exception &e) {
        std::cout << "TC-CPP-OK " << s << " " << e.what() << "\n";
    }
    // C++17/20 spot checks (std::optional, if-init)
    if (std::optional<int> o = 42; o && *o == 42)
        std::cout << "TC-CPP17-OK\n";
    return 0;
}
