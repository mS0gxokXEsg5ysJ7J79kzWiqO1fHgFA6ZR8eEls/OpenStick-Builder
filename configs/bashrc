# ~/.bashrc: executed by bash(1) for non-login shells.

# Note: PS1 and umask are already set in /etc/profile. You should not
# need this unless you want different defaults for root.
# PS1='${debian_chroot:+($debian_chroot)}\h:\w\$ '
# umask 022

# You may uncomment the following lines if you want `ls' to be colorized:
# export LS_OPTIONS='--color=auto'
# eval "$(dircolors)"
# alias ls='ls $LS_OPTIONS'
# alias ll='ls $LS_OPTIONS -l'
# alias l='ls $LS_OPTIONS -lA'
#
# Some more alias to avoid making mistakes:
# alias rm='rm -i'
# alias cp='cp -i'
# alias mv='mv -i'

# 设置系统终端语言为中文 UTF-8：
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 终端类型
export TERM=xterm-256color

# 启用 24-bit True Color
export COLORTERM=truecolor

# ==============================
# ✅常用命令颜色高亮
# ==============================
alias sj='apt update && apt upgrade -y'


# ls 彩色显示
export LS_OPTIONS='--color=auto'
alias ls='ls $LS_OPTIONS'
alias ll='ls -alh'
alias la='ls -A'
alias l='ls -CF'
alias ls='ls --color=auto -lh'
alias ll='ls --color=auto -lhA'
alias l='ls --color=auto -l'
alias cl='clear'
alias ip='ip --color'
alias bridge='bridge -color'
alias free='free -h'
alias df='df -h'
alias du='du -hs'

# grep 高亮
export GREP_COLORS='mt=1;38;2;180;229;13'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# diff 高亮
alias diff='diff --color=auto'

# ip 命令彩色
unalias ip 2>/dev/null
ip() { command ip -c "$@" | sed "s/\x1b\[34m/\x1b[96m/g"; }

# systemctl 彩色
alias systemctl='SYSTEMD_COLORS=1 systemctl'

# journalctl 彩色
alias journalctl='SYSTEMD_COLORS=1 journalctl'

# 常用危险命令确认
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'


# bash 自动补全
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi


# ==========================================
# Bash 历史增强
# ==========================================

# 历史记录显示时间
export HISTTIMEFORMAT="%F %T "

# 增大历史容量
export HISTSIZE=100000
export HISTFILESIZE=200000

# 去除重复命令
export HISTCONTROL=ignoredups:erasedups


# ==========================================
# command-not-found 命令提示
# ==========================================



# ==========================================
# man 手册彩色高亮
# ==========================================

export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;36m'

# ==========================================
# 自动为当前目录新 .sh 文件授权
# ==========================================
chpwd() { find . -maxdepth 1 -name "*.sh" ! -perm -u+x -exec chmod +x {} +; }
PROMPT_COMMAND="chpwd"


# ==========================================
# 查询端口：dk=全部端口，dk 443 53=指定端口
# ==========================================
dk() {
    if [ $# -eq 0 ]; then
        ss -lntup | grep -P --color=always ':\K[0-9]+(?=\s)|(?<=\(\")[^"]+'
    else
        local ports=$(printf "%s|" "$@" | sed 's/|$//')
        ss -lntup | grep -P ":(${ports})(\s|$)" | grep -P --color=always ':\K[0-9]+(?=\s)|(?<=\(\")[^"]+'
    fi
}


# 最终用户 PS1 必须放在 .bashrc 末尾，按 Shell 顺序执行，最后的会覆盖签名的值。
# root@Debian 绿色粗体，路径橙色粗体（24bit TrueColor）
#PS1='\[\033[1;38;2;100;200;255m\][\D{%H:%M:%S}] \[\033[1;38;2;170;247;48m\]\u@\h\[\033[0m\]:\[\033[1;38;2;255;165;0m\]\w\[\033[0m\]\$ '

PS1='${debian_chroot:+($debian_chroot)}\[\033[01;35m\][\[\033[01;31m\]$(date +%H)\[\033[01;35m\]:\[\033[01;33m\]$(date +%M)\[\033[01;35m\]:\[\033[01;36m\]$(date +%S)\[\033[01;35m\]]\[\033[01;32m\] \u\[\033[01;33m\]@\[\033[01;36m\]\h\[\033[01;33m\]:\w\[\033[01;35m\]\$ \[\033[00m\]'
