#!/bin/bash
# ==========================================================
# Project: Text Processing (sed & awk)
# ==========================================================

sed -n '/lp/p' /etc/passwd
sed '3d' /etc/passwd
sed '$d' /etc/passwd
sed '/lp/d' /etc/passwd
sed 's/lp/mylp/g' /etc/passwd

awk -F: '{print $5}' /etc/passwd
awk -F: '{print NR,$1,$5,$6}' /etc/passwd
awk -F: '$3>500 {print $1,$3,$5}' /etc/passwd
awk -F: '$3==500 {print $1,$3,$5}' /etc/passwd
awk 'NR>=5 && NR<=15' /etc/passwd
