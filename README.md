# Custom RootFS for Raspberry PI using Raspbian OS image file

:warning: **Important Note: This repository is a modified fork from [kclyu/rpi_rootfs](https://github.com/kclyu/rpi_rootfs) for building custom rootfs _(sysroot)_ using a Raspbian OS image file that is compatible with https://github.com/abhiTronix/raspberry-pi-cross-compilers toolchains only. Thereby, offers no guarantee that it will work with any other toolchain.**

### A. Prerequisites

```sh
sudo apt update && sudo apt dist-upgrade
sudo apt-get install build-essential gawk gcc g++ gfortran git texinfo bison libncurses-dev tar wget qemu-user-static rsync rsync
```

### B. Clone this Forked Repository:

```sh
git clone https://github.com/abhiTronix/rpi_rootfs.git
```

### C. Making RootFS with Raspbian OS image file

*Note :bulb:: Download the lite-image file from [Raspberry PI download page](https://www.raspberrypi.org/downloads/raspberry-pi-os/) and if possible, use the img file after unzipping the img.zip file after the download is complete.*

```sh
cd ~/rpi_rootfs
sudo chmod +x ./build_rootfs.sh

# To build rootfs
./build_rootfs.sh create ./2021-MM-DD-raspios-buster-armhf.img
```


### D. Bonus

#### `PI.cmake`

It is a CMAKE_TOOLCHAIN_FILE definition file for cmake used when cross compile using cmake:

:warning: ***Remember to change toolchain path and compiled rootfs path in `PI.cmake` before running cmake!!!***

:warning: ***Always keep provided `CMakeLists.txt` file with `PI.cmake`!!!***

```sh
cd  cmake_source_distribution_root_path
mkdir build
cd build
cmake -DCMAKE_TOOLCHAIN_FILE=~/rpi_rootfs/PI.cmake  -DCMAKE_BUILD_TYPE=Debug ..
```

#### `sysroot-relativelinks.py`

A python script that takes a sysroot directory and turn all the abolute symlinks and turn them into relative ones such that the sysroot is usable within another system.

```
sysroot-relativelinks.py path_to_sysroot_directory
```