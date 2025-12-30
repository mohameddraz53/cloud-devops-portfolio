#!/bin/bash
# ==========================================================
# Project: Archiving & Searching
# ==========================================================

gzip file && gunzip file.gz
tar -cvf etc_backup.tar /etc

find ~ -type f -mtime -2
find /etc -user root
find ~ -type d
find / -name ".profile"

file /etc/passwd /dev/pts/0 /etc /dev/sda
ls -i / /etc /etc/hosts

ln -s /etc/passwd /boot/passwd_link
ln /etc/passwd /boot/passwd_hard || echo "Hard link not allowed across FS"
