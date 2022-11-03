#!/usr/bin/env bash
# Copyright (C) 2022 Muhammad Fadlyas (fadlyas07)
# SPDX-License-Identifier: GPL-3.0-or-later
export DIR="$(pwd)"
echo "Cloning dependencies..."
[[ ! -d "$DIR/AnyKernel3" ]] && git clone --single-branch https://github.com/greenforce-project/AnyKernel3 --depth=1 &>/dev/null
[[ ! -d "$DIR/aosp_clang" ]] && git clone --single-branch https://github.com/greenforce-project/aosp_clang --depth=1 &>/dev/null
[[ ! -d "$DIR/aarch64-linux-android-4.9" ]] && git clone --single-branch https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b android-9.0.0_r40 --depth=1 &>/dev/null
echo "All dependencies cloned!"
export ARCH=arm64
export SUBARCH="$ARCH"
export kernel_branch=$(git rev-parse --abbrev-ref HEAD)
tg_send_message()
{
    curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
         -d "disable_web_page_preview=true" \
         -d "parse_mode=html" \
         -d chat_id="${chat_id}" \
         -d text="$(
                    for POST in "${@}" ; do
                        echo "${POST}"
                    done
            )" &>/dev/null
}
source <(grep -E '^(VERSION|PATCHLEVEL)' Makefile | sed -e s/[[:space:]]//g)
if ! [[ ( -n "$VERSION" && -n "$PATCHLEVEL" ) ]]; then
    echo "Unable to get kernel version from Makefile!"
    exit 1
fi
export kernelversion="$VERSION.$PATCHLEVEL"
export defconfig="$DEVICE"_defconfig
export PATH="$DIR/aosp_clang/bin:$DIR/aarch64-linux-android-4.9/bin:$PATH"
export LD_LIBRARY_PATH="$DIR/aosp_clang/bin/../lib:$LD_LIBRARY_PATH"
export IMG_PATH="$DIR/out/arch/$ARCH/boot"
build_start=$(date +"%s")
build_flags="CC=clang "
build_flags+="CLANG_TRIPLE=aarch64-linux-gnu- "
build_flags+="CROSS_COMPILE=aarch64-linux-android- "
make -j"$(nproc --all)" -l"$(nproc --all)" "$defconfig" && \
make -j"$(nproc --all)" -l"$(nproc --all)" O=out "$build_flags" 2>&1| tee build.log
if ! [[ ( -f "$IMG_PATH/Image.gz-dtb" || -f "$IMG_PATH/Image" || -f "$IMG_PATH/Image.gz" ) ]]; then
    build_end=$(date +"%s")
    build_diff=$(($build_end - $build_start))
    curl -F "disable_web_page_preview=true" -F "parse_mode=html" \
    -F document=@${DIR}/build.log "https://api.telegram.org/bot${bot_token}/sendDocument" -F chat_id="${chat_id}" -F caption="<b>build throw an errors!</b>
Build took $(($build_diff / 60)) minutes, $(($build_diff % 60)) seconds."
    exit 1
else
    build_end=$(date +"%s")
    build_diff=$(($build_end - $build_start))
    curl -F "disable_web_page_preview=true" -F "parse_mode=html" \
    -F document=@${DIR}/build.log "https://api.telegram.org/bot${bot_token}/sendDocument" -F chat_id="${chat_id}" -F caption="<b>build success!</b>
Build took $(($build_diff / 60)) minutes, $(($build_diff % 60)) seconds."
fi
anykernel_string="$kernel_branch - $(date +'%A'), $(date +'%d %B %Y')"
sed -i "s/kernel.string=/kernel.string=$anykernel_string/g" $DIR/AnyKernel3/anykernel.sh
sed -i "s/device.name1=/device.name1=$DEVICE/g" $DIR/AnyKernel3/anykernel.sh
cp "$IMG_PATH/Image.gz-dtb" "$DIR/AnyKernel3" || cp "$IMG_PATH/Image" "$DIR/AnyKernel3" || cp "$IMG_PATH/Image.gz" "$DIR/AnyKernel3" || echo "Cannot move any files!" && exit 0
cp "$IMG_PATH/dtb.img" "$DIR/AnyKernel3" || echo "dtb.img not found!"
cp "$IMG_PATH/dtbo.img" "$DIR/AnyKernel3" || echo "dtbo.img not found!"
echo "Making flashable kernel..."
zip -r9 "${KBUILD_BUILD_HOST}~${KBUILD_BUILD_USER}-${DEVICE}-$(date +'%d%m%y').zip" $DIR/AnyKernel3/*
echo "Zipping complete!"
echo "Sending to telegram..."
curl -F chat_id="${chat_id}" -F "disable_web_page_preview=true" -F "parse_mode=html" -F document=@"$(echo $DIR/AnyKernel3/*.zip)" "https://api.telegram.org/bot${bot_token}/sendDocument" \
-F caption="New #${DEVICE} build is available! ($kernelversion, $kernel_branch) at commit $(git log --pretty=format:'%h (\"%s\")' -1) | <b>SHA1:</b> $(sha1sum $(echo $DIR/AnyKernel3/*.zip) | awk '{ print $1 }')."
