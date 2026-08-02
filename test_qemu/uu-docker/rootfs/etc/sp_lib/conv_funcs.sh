#!/bin/ash

sp_anon() {
	# add anonymous group if not exist
	awk -F: '{if(NF<2){printf ":%s\n",$1}else{print $0}}'
}

sp_format() {
	sed 's/:/=/;s/^/./;s/\.=/=/'
}

sp_class() {
	sp_anon \
		| sp_format
}

sp_avg() {
	sp_anon \
		| awk -F: '{map[$1]+=$2;cnt[$1]++} END {for(i in map){printf "%s:%.2f\n",i,map[i]/cnt[i]}}' \
		| sp_format
}

sp_max() {
	sp_anon \
		| awk -F: '{if(e[$1]>0){if(m[$1]<$2)m[$1]=$2}else{e[$1]=1;m[$1]=$2}} END {for(i in m){printf "%s:%.2f\n",i,m[i]}}' \
		| sed 's/\.00$//' \
		| sp_format
}

sp_min() {
	sp_anon \
		| awk -F: '{if(e[$1]>0){if(m[$1]>$2)m[$1]=$2}else{e[$1]=1;m[$1]=$2}} END {for(i in m){printf "%s:%.2f\n",i,m[i]}}' \
		| sed 's/\.00$//' \
		| sp_format
}

sp_sum() {
	sp_anon \
		| awk -F: '{map[$1]+=$2} END {for(i in map){printf "%s:%d\n",i,map[i]}}' \
		| sp_format
}

sp_stat() {
	sp_anon \
		| awk -F: '{map[$1]++} END {for(i in map){printf "%s:%d\n",i,map[i]}}' \
		| sp_format
}

sp_ratio() {
	sp_anon \
		| awk -F: '{sum += ($2 != 0)} END {printf "%s:%.2f\n",$1,sum/NR}' \
		| sp_format
}
