#!/bin/bash
# ==========================================================
# Project: Linux Basics & Navigation
# ==========================================================

# 1
ls /usr/bin > /tmp/commands.list

# 2
ls /usr/bin | wc -w

# 3
cut -d: -f1 /etc/passwd | grep '^g'

# 4
cut -d: -f1,5 /etc/passwd | grep '^g' | sort -t: -k2 > g_users.txt

# 5
cp /etc/passwd ~/mypasswd

# 6
mv ~/mypasswd ~/oldpasswd

# 7
cd ~
cd $HOME
cd /home/$USER
cd

# 8
ls /usr/bin | grep '^w'

# 9
head -n 4 /etc/passwd

# 10
tail -n 7 /etc/passwd

# 11
man passwd; man 5 passwd

# 12
man 5 passwd

# 13
apropos passwd