#!/bin/bash
# ==========================================================
# Project: Bash Scripting Utilities
# ==========================================================

read -p "Enter name: " name
echo "Hello $name"

mysq() { echo $(( $1 * $1 )); }

mysq 5
