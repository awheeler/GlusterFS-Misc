#!/bin/bash

user=$1
tenant=$2
role=$3


insecure="--insecure"

if [ -z "$user" -o -z "$tenant" -o -z "$role" ]; then
	echo "$0 <user> <tenant> <role>"
	exit 1
fi

# Check to see if the specified a valid role
if [ ! -z "$role" ]; then
	role_id=$(keystone $insecure role-list | grep " $role " | awk '{print $2}')
	if [ -z "$role_id" ]; then
		echo "role $role not found"
	fi
fi

# Get the tenant_id
tenant_id=$(keystone $insecure tenant-list | grep " $tenant " | awk '{print $2}')

if [ -z "$tenant_id" ]; then
	echo "$tenant not found"
	exit 2
fi

# Get the user_id
user_id=$(keystone $insecure user-list | grep " $user " | awk '{print $2}')

# Add the role

keystone $insecure user-role-add --user-id=$user_id --tenant-id=$tenant_id --role-id=$role_id
