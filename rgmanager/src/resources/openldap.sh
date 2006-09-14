#!/bin/bash

#
#  Copyright Red Hat, Inc. 2006
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the
#  Free Software Foundation; either version 2, or (at your option) any
#  later version.
#
#  This program is distributed in the hope that it will be useful, but
#  WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; see the file COPYING.  If not, write to the
#  Free Software Foundation, Inc.,  675 Mass Ave, Cambridge, 
#  MA 02139, USA.
#
#
#  Author(s):
#	Marek Grac (mgrac at redhat.com)
#

export LC_ALL=C
export LANG=C
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

declare LDAP_SLAPD=/usr/sbin/slapd
declare LDAP_pid_file=/var/run/slapd.pid
declare LDAP_url_list

. $(dirname $0)/ocf-shellfuncs
. $(dirname $0)/utils/config-utils.sh
. $(dirname $0)/utils/messages.sh

verify_all()
{
	clog_service_verify $CLOG_INIT

	if [ -z "$OCF_RESKEY_name" ]; then
		clog_service_verify $CLOG_FAILED "Invalid Name Of Service"
		return $OCF_ERR_ARGS
	fi

	if [ -z "$OCF_RESKEY_config_file" ]; then
		clog_check_file_exist $CLOG_FAILED_INVALID "$OCF_RESKEY_config_file"
		clog_service_verify $CLOG_FAILED
		return $OCF_ERR_ARGS
	fi

	if [ ! -r "$OCF_RESKEY_config_file" ]; then
		clog_check_file_exist $CLOG_FAILED_NOT_READABLE $OCF_RESKEY_config_file
		clog_service_verify $CLOG_FAILED
		return $OCF_ERR_ARGS
	fi

	clog_service_verify $CLOG_SUCCEED
		
	return 0
}

generate_url_list()
{
	declare ldap_url_source=$1
	declare ip_addresses=$2
	declare url_list
	declare tmp;
	
	for u in $ldap_url_source; do 
		if [[ "$u" =~ ':///' ]]; then
			for z in $ip_addresses; do
				tmp=`echo $u | sed "s,://,://$z,"`
				url_list="$url_list $tmp"
			done
		elif [[ "$u" =~ '://0:' ]]; then
			for z in $ip_addresses; do
				tmp=`echo $u | sed "s,://0:,://$z:,"`
				url_list="$url_list $tmp"
			done
		else
			url_list="$url_list $u"
		fi
	done
	
	echo $url_list
}


start()
{
	declare ccs_fd;
	
	clog_service_start $CLOG_INIT

	if [ -e "$LDAP_pid_file" ]; then
		clog_check_pid $CLOG_FAILED "$LDAP_pid_file"
		clog_service_start $CLOG_FAILED
		return $OCF_GENERIC_ERROR
	fi

	clog_looking_for $CLOG_INIT "IP Address"

        ccs_fd=$(ccs_connect);
        if [ $? -ne 0 ]; then
		clog_looking_for $CLOG_FAILED_CCS
                return $OCF_GENERIC_ERROR
        fi

        get_service_ip_keys "$ccs_fd" "$OCF_RESKEY_service_name"
        ip_addresses=`build_ip_list "$ccs_fd"`

	if [ -z "$ip_addresses" ]; then
		clog_looking_for $CLOG_FAILED_NOT_FOUND "IP Addresses"
		return $OCF_GENERIC_ERROR
	fi
	
	clog_looking_for $CLOG_SUCCEED "IP Address"

	LDAP_url_list=`generate_url_list "$OCF_RESKEY_url_list" "$ip_addresses"`

	if [ -z "$LDAP_url_list" ]; then
		ocf_log error "Generating URL List for $OCF_RESOURCE_INSTANCE > Failed"
		return $OCF_GENERIC_ERROR
	fi

	$LDAP_SLAPD -f "$OCF_RESKEY_config_file" -n "$OCF_RESOURCE_INSTANCE" \
		-h "$LDAP_url_list" $OCF_RESKEY_slapd_options

	if [ $? -ne 0 ]; then
		clog_service_start $CLOG_FAILED
		return $OCF_GENERIC_ERROR
	fi

	clog_service_start $CLOG_SUCCEED

	return 0;
}

stop()
{
	clog_service_stop $CLOG_INIT

	if [ ! -e "$LDAP_pid_file" ]; then
		clog_check_file_exist $CLOG_FAILED_NOT_FOUND "$LDAP_pid_file"
		clog_service_stop $CLOG_FAILED
		return $OCF_GENERIC_ERROR
	fi

	kill `cat "$LDAP_pid_file"`

	if [ $? -ne 0 ]; then
		clog_service_stop $CLOG_FAILED
		return $OCF_GENERIC_ERROR
	else
		clog_service_stop $CLOG_SUCCEED
	fi
	
	return 0;
}

status()
{
	clog_service_status $CLOG_INIT

	if [ ! -e "$LDAP_pid_file" ]; then
		clog_check_file_exist $CLOG_FAILED_NOT_FOUND "$LDAP_pid_file"
		clog_service_status $CLOG_FAILED
		return $OCF_GENERIC_ERROR
	fi

	if [ ! -d /proc/`cat "$LDAP_pid_file"` ]; then
		clog_service_status $CLOG_FAILED
		return $OCF_GENERIC_ERROR
	fi	

	clog_service_status $CLOG_SUCCEED
	return 0
}

case $1 in
	meta-data)
		cat `echo $0 | sed 's/^\(.*\)\.sh$/\1.metadata/'`
		exit 0
		;;
	verify-all)
		verify_all
		exit $?
		;;
	start)
		verify_all && start
		exit $?
		;;
	stop)
		verify_all && stop
		exit $?
		;;
	status|monitor)
		verify_all
		status
		exit $?
		;;
	restart)
		verify_all
		stop
		start
		exit $?
		;;
	*)
		echo "Usage: $0 {start|stop|status|monitor|restart|meta-data|verify-all}"
		exit $OCF_ERR_GENERIC
		;;
esac