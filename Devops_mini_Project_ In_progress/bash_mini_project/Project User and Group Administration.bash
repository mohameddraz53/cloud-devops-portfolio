#!/bin/bash
# ==========================================================
# Project: User and Group Administration
# ==========================================================

sudo useradd -c "Islam Askar" islam
echo islam:islam | sudo chpasswd

sudo useradd -c "Bad User" baduser
echo baduser:baduser | sudo chpasswd

sudo groupadd -g 30000 pgroup
sudo groupadd badgroup

sudo usermod -aG pgroup islam
sudo chage -M 30 islam
sudo passwd -l baduser
sudo userdel baduser
sudo groupdel badgroup

mkdir ~/myteam
chmod 400 ~/myteam
