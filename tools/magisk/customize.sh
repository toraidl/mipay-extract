REPLACE="
"
#mipush
if [ ! -f "/data/data/com.xiaomi.xmsf/files/mipush_country_code" ] || [ $(cat /data/data/com.xiaomi.xmsf/files/mipush_country_code) != "CN" ]; then
  rm -rf /data/data/com.xiaomi.xmsf
  mkdir -p /data/data/com.xiaomi.xmsf/files
  echo CN > /data/data/com.xiaomi.xmsf/files/mipush_country_code
  echo China > /data/data/com.xiaomi.xmsf/files/mipush_region
fi

rm -rf /data/system/package_cache/* || true