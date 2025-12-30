#!/bin/bash
# ==========================================================
# Project: Linux Permissions
# ==========================================================

chmod 444 testfile
rm testfile || echo "Cannot delete without write on directory"

umask 022
touch f1 && mkdir d1
ls -l f1 d1

umask 777
touch f2 && mkdir d2
ls -l f2 d2
