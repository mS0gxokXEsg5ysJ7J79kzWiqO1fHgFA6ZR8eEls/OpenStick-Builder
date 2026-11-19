@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

echo ============================================================================
echo               OpenStick Bootloader (Debian Full Auto Flash)
echo ============================================================================

REM ============================================================================
REM 第0阶段：自动检测设备连接状态（ADB 自动重启进入 Fastboot + Fastboot 轮询就绪）
REM ============================================================================
echo [状态检测] 正在扫描已连接的 ADB 或 Fastboot 设备...

set "ADB_FOUND=0"
for /f "skip=1 tokens=1,2" %%A in ('adb devices 2^>nul') do (
    if /i "%%B"=="device" (
        set "ADB_FOUND=1"
        set "ADB_SN=%%A"
    )
)

if "%ADB_FOUND%"=="1" (
    echo [自动切换] 检测到处于正常开机模式的 ADB 设备 ^(!ADB_SN!^)，正在自动执行 adb reboot bootloader...
    adb reboot bootloader
    timeout /t 3 /nobreak >nul
)

:WAIT_FASTBOOT
set "FB_FOUND=0"
for /f "tokens=1,2" %%A in ('fastboot devices 2^>nul') do (
    if /i "%%B"=="fastboot" (
        set "FB_FOUND=1"
        set "FB_SN=%%A"
    )
)

if "%FB_FOUND%"=="0" (
    echo [等待设备] 暂未检测到 Fastboot 设备，请插入随身 Wi-Fi（或按住复位键上电），2 秒后自动重新检测...
    timeout /t 2 /nobreak >nul
    goto WAIT_FASTBOOT
)

echo [检测通过] 已成功识别到 Fastboot 设备 ^(!FB_SN!^)，准备开始刷机！
pause

REM ============================================================================
REM 第一阶段：借助原厂 Bootloader 写入开源二级引导程序 lk2nd（获取基带导出权限）
REM ============================================================================
fastboot erase boot
fastboot flash boot lk2nd.img
fastboot reboot

echo [等待] 设备正在重启进入 lk2nd 模式，请等待电脑识别到新的 Fastboot 设备后再按任意键...
pause

REM ============================================================================
REM 第二阶段：抢救备份单机核心基带与出厂校准数据
REM ============================================================================

REM 1. 导出 6 个小体积核心基带与持久化配置分区
fastboot oem dump fsc && fastboot get_staged fsc.bin
fastboot oem dump fsg && fastboot get_staged fsg.bin
fastboot oem dump modemst1 && fastboot get_staged modemst1.bin
fastboot oem dump modemst2 && fastboot get_staged modemst2.bin
fastboot oem dump persist && fastboot get_staged persist.bin
fastboot oem dump sec && fastboot get_staged sec.bin

REM 2. 尝试导出 modem 分区（约 64MB）；若超出缓冲区报错则自动提示并跳过
fastboot oem dump modem && fastboot get_staged modem.bin || echo [提示] modem 分区导出失败或超出缓冲区限制，已自动跳过（不影响后续刷机）。

REM 清理跳板引导并重启进入底层 Bootloader
fastboot erase lk2nd
fastboot erase boot
fastboot reboot bootloader

echo ============================================================================
echo [安全核查] 请立即前往当前文件夹检查以下 6 个文件是否均已生成且大小大于 0 KB：
echo            fsc.bin / fsg.bin / modemst1.bin / modemst2.bin / persist.bin / sec.bin
echo            确认无误（建议复制一份到桌面永久备份）后，再按任意键继续刷写分区表！
echo ============================================================================
pause

REM ============================================================================
REM 第三阶段：重构全盘 GPT 分区表并刷入 Debian 配套高通底层固件
REM ============================================================================
fastboot flash partition gpt_both0.bin
fastboot flash hyp hyp.mbn
fastboot flash rpm rpm.mbn
fastboot flash sbl1 sbl1.mbn
fastboot flash tz tz.mbn

REM ============================================================================
REM 第四阶段：将第二阶段备份的基带与配置精准写回新分区表对应位置
REM ============================================================================
fastboot flash fsc fsc.bin
fastboot flash fsg fsg.bin
fastboot flash modemst1 modemst1.bin
fastboot flash modemst2 modemst2.bin
fastboot flash persist persist.bin
fastboot flash sec sec.bin
if exist modem.bin fastboot flash modem modem.bin

fastboot flash aboot aboot.mbn
fastboot flash cdt sbc_1.0_8016.bin || echo [忽略提示] 当前新分区表不包含 cdt 分区（或 sbc_1.0_8016.bin 为空文件），已安全跳过，不影响使用！

fastboot erase boot
fastboot erase rootfs
fastboot reboot

echo [进度] 底层固件与基带已全部就绪，即将刷入 Debian 系统！
echo [等待] 请等待设备重启并再次被电脑识别到 Fastboot 设备后，按任意键继续...
pause

REM ============================================================================
REM 第五阶段：写入 Debian 主线内核与根文件系统
REM ============================================================================
fastboot flash boot boot.bin
fastboot -S 200m flash rootfs rootfs.bin
fastboot reboot

echo ============================================================================
echo [完成] Debian 已全部刷入完成！设备正在重启，请等待约 1 分钟后检查 USB 虚拟网卡。
echo ============================================================================
pause
