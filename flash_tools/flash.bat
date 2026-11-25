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

echo [检测通过] 已成功识别到 Fastboot 设备 ID: !FB_SN!，2 秒后自动开始刷机！
timeout /t 2 /nobreak >nul

REM ============================================================================
REM 第一阶段：借助原厂 Bootloader 写入开源二级引导程序 lk2nd（获取基带导出权限）
REM ============================================================================
fastboot erase boot
fastboot flash boot lk2nd.img
fastboot reboot

call :WAIT_FB "lk2nd Fastboot"

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

REM 自动校验 6 个核心基带备份文件是否存在且大小大于 0 字节（防刷丢基带）
set "BACKUP_OK=1"
for %%F in (fsc.bin fsg.bin modemst1.bin modemst2.bin persist.bin sec.bin) do (
    if not exist "%%F" (
        echo [错误] 缺失核心基带备份文件: %%F
        set "BACKUP_OK=0"
    ) else (
        for %%S in ("%%F") do if %%~zS EQU 0 (
            echo [错误] 核心基带备份文件大小为 0 字节: %%F
            set "BACKUP_OK=0"
        )
    )
)
if "%BACKUP_OK%"=="0" (
    echo [中止] 基带备份校验未通过，为防止丢失基带已自动停止刷机！
    pause
    exit /b 1
)
echo [校验通过] 6 个核心基带文件均已生成且大小正常，准备进入第三阶段...
call :WAIT_FB "底层 Bootloader Fastboot"

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
call :WAIT_FB "新 aboot Fastboot"

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
exit /b 0

REM ============================================================================
REM 子程序：自动轮询并识别 Fastboot 设备 ID（带 4 秒防旧连接残留延迟）
REM ============================================================================
:WAIT_FB
set "STAGE_NAME=%~1"
echo [等待重启] 正在等待设备重新进入 %STAGE_NAME% 模式...
timeout /t 4 /nobreak >nul
:WAIT_FB_LOOP
set "FB_FOUND=0"
set "FB_SN="
for /f "tokens=1,2" %%A in ('fastboot devices 2^>nul') do (
    if /i "%%B"=="fastboot" (
        set "FB_FOUND=1"
        set "FB_SN=%%A"
    )
)
if "%FB_FOUND%"=="0" (
    echo [轮询中] 暂未识别到 Fastboot ID，2 秒后自动重试...
    timeout /t 2 /nobreak >nul
    goto WAIT_FB_LOOP
)
echo [已就绪] 自动识别到 Fastboot 设备 ID: !FB_SN!（%STAGE_NAME%），继续执行...
timeout /t 1 /nobreak >nul
goto :eof