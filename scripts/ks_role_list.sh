#!/bin/bash

user=$1

insecure="--insecure"

if [ -z "$user" ]; then
	echo "$0 <user> "
	exit 1
fi

# Get the user_id
user_id=$(keystone $insecure user-list | grep " $user " | awk '{print $2}')

# Iterate through all of the tenants

tenant_ids=$(keystone $insecure tenant-list | egrep -v "+---|  id " | awk '{print $2}')
tenants=$(keystone $insecure tenant-list | egrep -v "+---|  id " | awk '{print $4}')

tenantr=($tenants)
tenant_idr=($tenant_ids)

i=0
while [ ! -z "${tenant_idr[$i]}" ]; do
	echo ${tenantr[$i]}
	keystone $insecure user-role-list --user-id=$user_id --tenant-id=${tenant_idr[$i]}
	let i=i+1
done

exit
for tenant_id in $tenant_ids; do
	keystone $insecure user-role-list --user-id=$user_id --tenant-id=$tenant_id
done
