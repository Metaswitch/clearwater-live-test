#!/bin/bash

dir=/usr/share/clearwater/clearwater-live-verification/
cd $dir
bundle exec $dir/lib/daemon.rb $1
RETVAL=$?

exit $RETVAL
