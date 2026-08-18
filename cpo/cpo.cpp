#include <iostream>
#include <filesystem>
#include <sys/stat.h>
#include <unistd.h>
#include <system_error>

namespace fs = std::filesystem;

// Fetches UID and GID of a reference directory
bool get_target_ownership(const fs::path& path, uid_t& uid, gid_t& gid) {
    struct stat st;
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    uid = st.st_uid;
    gid = st.st_gid;
    return true;
}

// Recursively applies lchown to avoid target symlink exploitation
void apply_chown_recursive(const fs::path& target, uid_t uid, gid_t gid) {
    lchown(target.c_str(), uid, gid);

    if (fs::is_directory(target) && !fs::is_symlink(target)) {
        for (const auto& entry : fs::recursive_directory_iterator(target, fs::directory_options::skip_permission_denied)) {
            lchown(entry.path().c_str(), uid, gid);
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: cpo <source> <destination>\n";
        return 1;
    }

    fs::path src = argv[1];
    fs::path dst = argv[2];

    if (!fs::exists(src)) {
        std::cerr << "Error: Source path does not exist: " << src << "\n";
        return 1;
    }

    // Determine reference directory to inherit ownership from
    bool dst_is_dir = fs::exists(dst) && fs::is_directory(dst);
    fs::path ref_dir = dst_is_dir ? dst : (dst.parent_path().empty() ? "." : dst.parent_path());

    uid_t uid;
    gid_t gid;
    if (!get_target_ownership(ref_dir, uid, gid)) {
        std::cerr << "Error: Could not retrieve ownership of reference path: " << ref_dir << "\n";
        return 1;
    }

    // Determine final destination path
    fs::path final_dst = dst_is_dir ? (dst / src.filename()) : dst;

    // Perform copy
    std::error_code ec;
    fs::copy(src, final_dst, fs::copy_options::recursive | fs::copy_options::overwrite_existing, ec);
    if (ec) {
        std::cerr << "Copy failed: " << ec.message() << "\n";
        return 1;
    }

    // Apply ownership to the copied result
    apply_chown_recursive(final_dst, uid, gid);

    std::cout << "Successfully copied " << src << " -> " << final_dst 
              << " (Owner set to UID: " << uid << ", GID: " << gid << ")\n";

    return 0;
}
