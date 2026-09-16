import subprocess
from build_clash_universal import run


def get_full_version():
    with open('./go.mod') as file:
        for line in file.readlines():
            if "metacubex/mihomo" in line:
                return line.split(" ")[-1].strip()


def upgrade_version():
    subprocess.check_output("go get -u github.com/metacubex/mihomo@latest", shell=True)


def install():
    subprocess.check_output("go mod download", shell=True)
    subprocess.check_output("go mod tidy", shell=True)


if __name__ == '__main__':
    print("start")
    print("current version:", get_full_version())
    upgrade_version()
    install()
    print("new version:", get_full_version(), ",start building")
    run()
