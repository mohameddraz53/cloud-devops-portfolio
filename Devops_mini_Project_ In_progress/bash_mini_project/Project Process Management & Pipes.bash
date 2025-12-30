#!/bin/bash
# ==========================================================
# Project: Process Management & Pipes
# ==========================================================

who | wc -l
sed -n '7,10p' /etc/passwd

sleep 100 &
jobs
fg %1
bg %1
kill %1

ps -u $USER
ps -ef | grep -v $USER
pgrep -u $USER
