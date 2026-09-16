import subprocess
import datetime
import plistlib
import os

def get_version():
    with open('./go.mod') as file:
        for line in file.readlines():
            if "metacubex/mihomo" in line:
                return line.split()[-1].strip()
    return "unknown"

# The app ships for Apple Silicon only, so only the arm64 slice is built here.
# The file name is kept for the callers in install_dependency.sh and CI.
go_bin = "go"

def build_clash(version,build_time,arch):
    # mihomo is much larger than the old core: -s -w strips symbols (~50% smaller)
    # and the no_* tags drop TUN-only transports ClashX never uses. Note that a
    # config containing a tailscale/zerotier/easytier proxy fails to parse with
    # these tags, rather than skipping just that proxy.
    command = f"""
{go_bin} build -trimpath -tags "no_tailscale no_easytier no_zerotier" \
-ldflags '-s -w -X "github.com/metacubex/mihomo/constant.Version={version}" \
-X "github.com/metacubex/mihomo/constant.BuildTime={build_time}"' \
-buildmode=c-archive -o goClash_{arch}.a """
    envs = os.environ.copy()
    envs.update({
        "GOOS":"darwin",
        "GOARCH":arch,
        "CGO_ENABLED":"1",
        "CGO_LDFLAGS":"-mmacosx-version-min=10.14",
        "CGO_CFLAGS":"-mmacosx-version-min=10.14",
    })    
    subprocess.check_output(command, shell=True,env=envs)

def write_to_info(version):
    path = "../info.plist"

    with open(path, 'rb') as f:
        contents = plistlib.load(f)

    if not contents:
        exit(-1)

    contents["coreVersion"] = version
    with open(path, 'wb') as f:
        plistlib.dump(contents, f, sort_keys=False)


def run():
    version = get_version()
    print("current clash version:", version)
    build_time = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")
    print("clean existing")
    subprocess.check_output("rm -f *Clash*.h *.a", shell=True)
    print("create arm64")
    build_clash(version,build_time,"arm64")
    print("rename")
    os.rename('goClash_arm64.h', 'goClash.h')
    os.rename('goClash_arm64.a', 'goClash.a')
    if os.environ.get("CI", False) or os.environ.get("GITHUB_ACTIONS", False):
        print("writing info.plist")
        write_to_info(version)
    print("done")


if __name__ == "__main__":
    run()
