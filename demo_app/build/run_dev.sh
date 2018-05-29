#!/bin/sh
export AIR_SDK_HOME=~/Documents/SDK_Air300

ant install-dev

read -p "Press [Enter] to kill"

ant kill-dev