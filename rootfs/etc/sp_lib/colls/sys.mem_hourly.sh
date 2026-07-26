#!/bin/ash

free | awk 'NR == 2 {printf("%.2f"), $3/$2}'
