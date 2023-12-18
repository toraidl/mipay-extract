#!/bin/bash

cd "$(dirname "$0")"

if [[ -z "$*" ]]; then
    ENABLE_FONTS=false
    ENABLE_MIPAY=true
fi

darr=()
while [[ $# -gt 0 ]]; do
key="$1"

case $key in
    --fonts)
    ENABLE_FONTS=true
    echo "--> enable chinese fonts"
    shift
    ;;
    --mipay)
    ENABLE_MIPAY=true
    echo "--> enable mipay"
    shift
    ;;
    *)
    darr+=("$1")
    shift
    ;;
esac
done

extract_apps="app/MITSMClient app/UPTsmService priv-app/MIUIYellowPage priv-app/MIUICalendar"
eufix_apps=""

base_dir=$PWD
tool_dir=$base_dir/tools
sdat2img="python2.7 $tool_dir/sdat2img.py"
patchmethod="python2.7 $tool_dir/patchmethod.py"
payload_dumper="$tool_dir/payload-dumper-go"
heapsize=1024
smali="java -Xmx${heapsize}m -jar $tool_dir/smali-2.4.0.jar"
baksmali="java -Xmx${heapsize}m -jar $tool_dir/baksmali-2.4.0.jar"
keypass="--ks-pass pass:testkey --key-pass pass:testkey"
sign="java -Xmx${heapsize}m -jar $tool_dir/apksigner.jar sign --ks $tool_dir/testkey.jks $keypass"
libmd="libmd.txt"
libln="libln.txt"
aria2c_opts="--check-certificate=false --file-allocation=trunc -s10 -x10 -j10 -c"
aria2c="aria2c $aria2c_opts"
sed="sed"
imgroot="system/"
extractbin="${HOME}/bin/extract.erofs"

exists() {
  command -v "$1" >/dev/null 2>&1
}

abort() {
    echo "--> $1"
    echo "--> abort"
    exit 1
}

check() {
    for b in $@; do
        exists $b || abort "Missing $b"
    done
}

check java python2.7

if [[ "$OSTYPE" == "darwin"* ]]; then
    aapt="aapt"
    zipalign="$tool_dir/darwin/zipalign"
    sevenzip="$tool_dir/darwin/7za"
    aria2c="$tool_dir/darwin/aria2c $aria2c_opts"
    sed="$tool_dir/darwin/gsed"
    brotli="brotli"
else
    exists aapt && aapt="aapt" || aapt="$tool_dir/aapt"
    exists zipalign && zipalign="zipalign" || zipalign="$tool_dir/zipalign"
    exists 7z && sevenzip="7z" || sevenzip="$tool_dir/7za"
    exists aria2c || aria2c="$tool_dir/aria2c $aria2c_opts"
    exists brotli && brotli="brotli" || brotli="$tool_dir/brotli"
    if [[ "$OSTYPE" == "cygwin"* ]]; then
        sdat2img="python2.7 ../tools/sdat2img.py"
        patchmethod="python2.7 ../../tools/patchmethod.py"
        smali="java -Xmx${heapsize}m -jar ../../tools/smali-2.2.5.jar"
        baksmali="java -Xmx${heapsize}m -jar ../../tools/baksmali-2.2.5.jar"
        sign="java -Xmx${heapsize}m -jar ../../tools/apksigner.jar sign \
              --ks ../../tools/testkey.jks $keypass"
    fi
fi

clean() {
    [ -e "$1" ] && rm -Rf "$1"
    echo "--> abort"
    echo "--> clean $(basename $1)"
    exit 1
}

pushd() {
    command pushd "$@" > /dev/null
}

popd() {
    command popd "$@" > /dev/null
}

update_international_build_flag() {
    path=$1
    pattern="Lmiui/os/Build;->IS_INTERNATIONAL_BUILD"

    if [ -d $path ]; then
        found=()
        if [[ "$OSTYPE" == "cygwin"* ]]; then
            pushd "$path"
            cmdret="$(/cygdrive/c/Windows/System32/findstr.exe /sm /c:${pattern} '*.*' | tr -d '\015')"
            popd
            result="${cmdret//\\//}"
            while read i; do
                found+=("${path}/$i")
            done <<< "$result"
        else
            files="$(find $path -type f -iname "*.smali")"
            while read i; do
                if grep -q -F "$pattern" $i; then
                    found+=("$i")
                fi
            done <<< "$files"
        fi
    fi
    if [ -f $path ]; then
        found=($path)
    fi

    for i in "${found[@]}"; do
        $sed -i 's|sget-boolean \([a-z]\)\([0-9]\+\), Lmiui/os/Build;->IS_INTERNATIONAL_BUILD:Z|const/4 \1\2, 0x0|g' "$i" \
            || return 1
        if grep -q -F "$pattern" $i; then
            echo "----> ! failed to patch: $(basename $i)"
        else
            echo "----> patched smali: $(basename $i)"
        fi
    done
}

deodex() {
    app=$2
    base_dir="$1"
    arch=$3
    system_img=$5
    deoappdir=$4
    pushd "$base_dir"
    apkdir=$deoappdir/$app
    apkfile=$apkdir/$app.apk
    file_list="$($sevenzip l "$apkfile")"
    if [[ "$eufix_apps" == *"$app"* && "$file_list" == *"classes.dex"* ]]; then
        echo "--> decompiling $app..."
        dexclass="classes.dex"
        $baksmali d $apkfile -o $apkdir/smali || return 1

        if [[ "$app" == "Weather" ]]; then
            update_international_build_flag "$apkdir/smali/com/miui/weather2"
        fi

        api=30
        $smali assemble -a $api $apkdir/smali -o $apkdir/$dexclass || return 1
        rm -rf $apkdir/smali
        if [[ ! -f $apkdir/$dexclass ]]; then
            echo "----> failed to baksmali: $apkdir/$dexclass"
            continue
        fi
        $sevenzip d "$apkfile" $dexclass >/dev/null
        pushd $apkdir
        adderror=false
        $aapt add -fk "$(basename $apkfile)" classes.dex || adderror=true
        popd
        if $adderror; then
            return 1
        fi
        rm -f $apkdir/classes.dex
        $zipalign -f 4 $apkfile $apkfile-2 >/dev/null 2>&1
        mv $apkfile-2 $apkfile
        if [[ "$deoappdir" == "system/data-app" ]]; then
            if $sign $apkfile; then
                echo "----> signed: $app.apk"
            else
                echo "----> cannot sign $app.apk"
                return 1
            fi
        fi
        if ! [ -d $apkdir/lib ]; then
            $sevenzip x -o$apkdir $apkfile lib >/dev/null
            if [ -d $apkdir/lib ]; then
                echo "----> extract native library..."
                if [[ "$arch" == "arm64" ]]; then
                    [ -d "$apkdir/lib/arm64-v8a" ] && mv "$apkdir/lib/arm64-v8a" "$apkdir/lib/arm64"
                else
                    [ -d "$apkdir/lib/armeabi-v7a" ] && mv "$apkdir/lib/armeabi-v7a" "$apkdir/lib/arm"
                fi
                rm -rf $apkdir/lib/x86* || true
            fi
        fi
    fi
    rm -rf $apkdir/oat
    popd
    return 0
}

extract() {
    model=$1
    ver=$2
    file=$3
    partition=product
    local extract_apps=$4
    dir=miui-$model-$ver
    img=$dir-$partition.img

    echo "--> rom: $model $ver"
    [ -d $dir ] || mkdir $dir
    pushd $dir
    if ! [ -f $img ]; then
        trap "clean \"$PWD/$partition.new.dat\"" INT
        filelist="$($sevenzip l ../"$file")"
        if [[ "$filelist" == *payload.bin* ]]; then
            $sevenzip x ../$file payload.bin payload.bin
            $payload_dumper -p $partition -o output payload.bin
            mv output/$partition.img $dir-$partition.img
            rm payload.bin
            rm -rf output
        fi
    fi
    trap "clean \"$PWD/$img\"" INT
    if ! [ -f $img ]; then
        clean $img
    fi

    echo "--> image extracted: $img"
    work_dir="$PWD/deodex"
    trap "clean \"$work_dir\"" INT
    rm -Rf deodex
    mkdir -p deodex/$imgroot$partition

    rm -f "$work_dir"/{$libmd,$libln}
    touch "$work_dir"/{$libmd,$libln}

    if [ "$ENABLE_MIPAY" = true ]; then
        for f in $extract_apps; do
            echo "----> copying extract $f..."
            $extractbin -o extractapps -i "$img" -X $f >/dev/null || clean "$work_dir"
        done

        mv extractapps/miui-*/* deodex/$imgroot$partition/
        rm -rf extractapps
        mkdir -p deodex/system/product/priv-app/Weather
        touch deodex/system/product/priv-app/Weather/.replace
        mkdir -p deodex/system/product/priv-app/Calendar
        touch deodex/system/product/priv-app/Calendar/.replace
    fi

    if [ "$ENABLE_FONTS" = true ]; then
        echo "---> extract fonts"
        $sevenzip x -odeodex/ "$img" ${imgroot}fonts/MiSansVF.ttf >/dev/null || clean "$work_dir"
    fi

    arch="arm64"
    local system_img="$PWD/$img"
    if [ "$ENABLE_MIPAY" = true ]; then
        for f in $extract_apps; do
            deodex "$work_dir" "$(basename $f)" "$arch" $imgroot$partition/"$(dirname $f)" $system_img || clean "$work_dir"
        done
    fi

    echo "--> packaging flashable zip"
    pushd deodex
    ubin=META-INF/com/google/android
    mkdir -p $ubin
    magisk_dir="$tool_dir/magisk"
    cp "$magisk_dir/magisk-update-binary" "$ubin/update-binary"
    cp "$magisk_dir/updater-script" "$ubin/updater-script"
    versionCode=$(grep versionCode= "$magisk_dir/module.prop" | cut -d '=' -f 2)
    versionCode=$(($versionCode+1))
    $sed -i "s/versionCode=.*/versionCode=$versionCode/" "$magisk_dir/module.prop"
    cp "$magisk_dir/module.prop" module.prop
    moduleId=eufix
    moduleName=aio
    moduleDesc="miui eu 欧版本地化模块"
    if [ "$ENABLE_FONTS" = true ]; then
        moduleId=eufix_fonts
        moduleName="兰亭Pro"
        moduleDesc="MIUI eu 全局兰亭pro字体模块 by MonwF@github"
        cp "$magisk_dir/customize-fonts.sh" customize.sh
        mkdir -p system/etc/
        cp "$magisk_dir/fonts.xml" system/etc/
        mkdir -p system/fonts/
        # cp "$magisk_dir/MiSansVF.ttf" system/fonts/
    elif [ "$ENABLE_MIPAY" = true ]; then
        moduleId=eufix_mipay
        moduleName="MIpay patch"
        moduleDesc="MIUI eu 支持钱包、门禁、农历、mipush等功能 by MonwF@github"
        cp "$magisk_dir/system.prop" system.prop
        cp "$magisk_dir/customize.sh" customize.sh
        mkdir -p system/etc/permissions
        cp "$magisk_dir/privapp-permissions-mipay.xml" system/etc/permissions/
        mkdir -p system/media/theme/default
        cp "$magisk_dir/com.android.calendar" system/media/theme/default/
    fi
    $sed -i "s/version=.*/version=$model-$ver/" module.prop
    $sed -i "s/id=.*/id=$moduleId-MonwF/" module.prop
    $sed -i "s/name=.*/name=MIUI eu $moduleName/" module.prop
    $sed -i "s/description=.*/description=$moduleDesc/" module.prop
    rm -f ../../$moduleId-$model-$ver.zip $libmd $libln system/build.prop
    $sevenzip a -tzip ../../$moduleId-$model-$ver.zip . >/dev/null

    trap - INT
    popd
    echo "--> done"
}

trap "echo '--> abort'; exit 1" INT
for i in "${darr[@]}"; do
    f="$(basename $i)"
    if [ -f "$f" ] && ! [ -f "$f".aria2 ]; then
        continue
    fi
    echo "--> Downloading $f"
    $aria2c $i || exit 1
done
trap - INT

hasfile=false
for f in *.zip; do
    arr=(${f//_/ })
    if [[ "${arr[0]}" != "miui" ]]; then
        continue
    fi
    if [ -f $f.aria2 ]; then
        echo "--> skip incomplete file: $f"
        continue
    fi
    model=${arr[1]}
    ver=${arr[2]}
    extract $model $ver $f "$extract_apps"
    hasfile=true
done

if $hasfile; then
    echo "--> all done"
else
    echo "--> Error: no eu rom detected"
fi
