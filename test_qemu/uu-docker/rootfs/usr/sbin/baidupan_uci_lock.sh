#!/bin/sh

cmd="$@"

run_with_lock()
{
  {
    echo "baidupan_uci_lock.lock lock  $cmd" >> /tmp/messages
       logger "$$, ====== TRY locking......"
       flock -x -w 60 1000
       [ $? -eq "1" ] && { logger "$$, ===== lock failed. exit 1" ; exit 1 ; }
       logger "$$, ====== GET lock to RUN."
       $@
       flock -u 1100 #......
       logger "$$, ====== END lock to RUN."
   } 1000<>/var/log/baidupan_uci_lock.lock
}

func_need_lock()
{
    echo "doing something, input parameter: $cmd" >> /tmp/messages
    eval $cmd
}

#    echo "baidupan_uci_lock.lock 0000000000000: $cmd" >> /tmp/messages
run_with_lock func_need_lock $cmd
#run_with_lock

