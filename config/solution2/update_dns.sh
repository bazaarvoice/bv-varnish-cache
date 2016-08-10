#!/bin/bash
# This script is executed by system to call to update /usr/local/etc/varnish/backend_servers.vcl
# In Mac OS, this script is called via cron (every minute, configurable)
#  * * * * * /usr/local/etc/varnish/update_dns.sh >/tmp/stdout.log 2>/tmp/stderr.log

# updating information can be tracked in /tmp/stdout.log and /tmp/stderr.log . Use any file as you want to track logs.
# $1 should be the same as '-n' while Varnish is running
# $2 should be the path to 'default.vcl' and 'backend_servers.vcl'
echo "updating DNS for api.bazaarvoice.com and stg.api.bazaarvoice.com"

# vcl config file
VARNISH_MAINFILE="$2/default.vcl"
VARNISH_BACKENDSFILE="$2/backend_servers.vcl"

RPOD_SERVER_LIST=$( nslookup api.bazaarvoice.com | awk '/^Address: / { print $2 }' )
STG_SERVER_LIST=$( nslookup stg.api.bazaarvoice.com | awk '/^Address: / { print $2 }' )

if [[ -z "$RPOD_SERVER_LIST" || -z "$STG_SERVER_LIST" ]]
then
  echo "Error retrieving IPs for api.bazaarvoice.com and stg.api.bazaarvoice.com. Exit"
  exit 1
fi

# generate new backend_servers.vcl 
BACKENDS_DEFS=""
BACKENDS_INIT="
sub backends_init {
	new vdir_prod = directors.round_robin();
"

BACKEND_CONFIG="
	.port = \"80\";
	.max_connections = 300; # That's it
	.first_byte_timeout     = 300s;   # How long to wait before we receive a first byte from our backend?
	.connect_timeout        = 3s;     # How long to wait for a backend connection?
"

ID=1
for IP in $RPOD_SERVER_LIST ; do
	BACKEND_NAME=prod_$ID
	echo "$ID -> $IP ($BACKEND_NAME)"
	BACKENDS_DEFS+="backend $BACKEND_NAME {
	.host = \"${IP}\";
	$BACKEND_CONFIG
}
"
	BACKENDS_INIT+="
	vdir_prod.add_backend($BACKEND_NAME);"
	let "ID +=1"				
done

BACKENDS_INIT+="

	new vdir_stg = directors.round_robin();
"

for IP in $STG_SERVER_LIST ; do
	BACKEND_NAME=stg_$ID
	echo "$ID -> $IP ($BACKEND_NAME)"
	BACKENDS_DEFS+="backend $BACKEND_NAME {
	.host = \"${IP}\";
	$BACKEND_CONFIG
}
"
	BACKENDS_INIT+="
	vdir_stg.add_backend($BACKEND_NAME);"
	let "ID +=1"				
done

BACKENDS_INIT+="
}"

cat > $2/backend_servers.vcl <<EOF
$BACKENDS_DEFS
$BACKENDS_INIT
EOF

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
# Load (& compile) new vcl
varnishadm -n $1 vcl.load vcl-${TIMESTAMP} $VARNISH_MAINFILE
res=$?
if [ $res -ne 0 ]
then
  echo "Failed to compile new varnish file"
  exit 1
fi
# Switch active vcl to the new one
echo "apply vcl-${TIMESTAMP}..."
varnishadm -n $1 vcl.use vcl-${TIMESTAMP}

# Scan and delete old vcls
for i in $(varnishadm -n $1 vcl.list |egrep -v "^active" |awk '{print $4;}') ; do
	echo "vcl ${i} is being deleted"
	varnishadm -n $1 vcl.discard "${i}"
done

echo "IPs for api.bazaarvoice.com and stg.api.bazaarvoice.com are updated successfully!"