#!/bin/sh

kldload vmm if_tap
ifconfig tap0 create
ifconfig tap1 create
sysctl net.link.tap.up_on_open=1
ifconfig bridge0 create
ifconfig bridge0 addm em0 addm tap0
#ifconfig bridge0 addm tap1
#ifconfig bridge0 addm igb0 addm tap0
#ifconfig bridge0 addm tap1
ifconfig bridge0 up 
