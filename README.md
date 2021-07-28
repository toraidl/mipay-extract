# Mi Pay Extractor
通过提取对应中国区rom相关文件来生成magisk模块，以实现 `miui eu` 欧版部分功能的本地化(主要是mipay和兰亭字体、mipush)

>1. mipay相关
>2. 兰亭pro字体
>3. mipush
>4. 支持安装、更新系统app

安装依赖后，将中国区的rom放至项目目录，运行 `./cleaner-fix.sh` (只在 `mac os 10.15+` 上测试通过，理论上linux也没问题，windows肯定不支持)，将生成的文件 `eufix-mipay-{model}-{date}.zip`，通过magisk刷入即可。

兰亭pro，运行`./cleaner-fix.sh --fonts`，生成magisk包再刷入

现提供自用的magisk包（开发版且以k30s' rom提取)，可前往下载: [lanzous](https://tpsx.lanzoui.com/b01zwocid) 密码: hfne

若搭配[xposed模块](https://github.com/monwf/miuieu-l10n)使用，可以解锁更多功能

>1. 天气采用彩云源
>2. 闹钟支持工作日提醒
>3. 短信本地化
>4. 黄页
>5. 主题本地化
>6. 日历支持农历

如需更完整的本地化，可使用[MinaMichita的方案](https://blog.minamigo.moe/archives/184)

# 原始项目如下
[Extract Mi Pay from MIUI China Rom](https://github.com/linusyang92/mipay-extract)

