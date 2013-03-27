#!/usr/bin/perl -w

use strict;

my $tenant=$ARGV[0];
my $mount=$ARGV[1];
my $description=$ARGV[2];

my $insecure="--insecure";

if ( ! $tenant or ! $mount or ! $description ){
	printf("$0 <tenant> <mount point> <description>\n");
	exit(1);
}

my $tenant_id=`keystone --insecure  tenant-create --name $tenant --description "$description" | grep id | awk '{print \$4}'`;
chomp($tenant_id);

# Perhaps the tenant already exists, get it's id
if ( ! $tenant_id ) {
	$tenant_id=`keystone --insecure tenant-list | grep " $tenant |" | awk '{print \$2}'`;
	chomp($tenant_id);
}

# Get a list of all of the peers
my @peers=`hostname -f; gluster peer status | awk '/Hostname/ {print \$2}'`;
chomp(@peers);

my $copy=0;
my $part=0;
my $peers_total=$#peers+1;

my $peer_count=0;


# First brick is always the same
my $mounts=sprintf("%s:$mount.%u.%u", $peers[0], $copy, $part);

my $brick=1;
for (my $count=1; $count<=$#peers;$count++) {
	$copy=$brick%2;
	$mounts .= sprintf(" %s:$mount.%u.%u", $peers[$count], $copy, $count-1);
	$brick++;
	$copy=$brick%2;
	$mounts .= sprintf(" %s:$mount.%u.%u", $peers[$count], $copy, $count);
	$brick++;
}

$copy=$brick%2;
$mounts .= sprintf(" %s:$mount.%u.%u", $peers[0], $copy, $#peers);

system("gluster volume create $tenant_id replica 2 transport tcp $mounts");
if ( $? == 0 ) {
	system("gluster volume start $tenant_id");
} else {
	print "Failed to create volume $tenant_id\n";
}
