#!/bin/ash

phyhelper dump | grep Link:up | grep -cvw wan
