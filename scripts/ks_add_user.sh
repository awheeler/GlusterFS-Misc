#!/bin/bash

user=$1
pass=$2
email=$3
tenant=$4
role=$5

insecure="--insecure"

if [ -z "$user" -o -z "$pass" -o -z "$email" -o -z "$tenant" ]; then
	echo "$0 <user> <pass> <user@email> <tenant> [role]"
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

user_id=$(keystone $insecure user-create --name $user --email $email --pass "$pass" --tenant-id $tenant_id | grep " id " | awk '{print $4}')

if [ -z "$user_id" ]; then
	echo "User creation failed"
	exit 1
fi

if [ ! -z "$role_id" ]; then
	keystone $insecure user-role-add --user-id=$user_id --tenant-id=$tenant_id --role-id=$role_id
fi
