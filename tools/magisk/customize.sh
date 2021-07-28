REPLACE="
"

#mipush
if [ ! -f "/data/data/com.xiaomi.xmsf/files/mipush_country_code" ] || [ $(cat /data/data/com.xiaomi.xmsf/files/mipush_country_code) != "CN" ]; then
  rm -rf /data/data/com.xiaomi.xmsf
  mkdir -p /data/data/com.xiaomi.xmsf/files
  echo CN > /data/data/com.xiaomi.xmsf/files/mipush_country_code
  echo China > /data/data/com.xiaomi.xmsf/files/mipush_region
fi

if [ ! -f "$MODPATH/perm_fixed" ]; then
  rm -f /data/misc_de/0/apexdata/com.android.permission/runtime-permissions.xml
  touch $MODPATH/perm_fixed
fi

rm -rf /data/system/package_cache/* || true