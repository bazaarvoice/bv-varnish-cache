# bv-varnish-cache

This is a guide example to set up Varnish as caching solution. For more caching options, please refer to https://developer.bazaarvoice.com/apis/conversations/tutorials/caching.

## Introduction
At present, concierge clients are hitting api.bazaarvoice.com (OR stg.api.bazaarvoice.com) on Mashery to get data they request. But Mashery caches responses for 55 minutes for most of requests (review submission are not cached). So, the same requests to Mashery within 55 minutes are not getting any new data because the responses are coming from cached data before. If clients can cache responses for requests locally for 55 minutes, it will benefits both clients (get fast response) and BV (number of requests on API is less). 
For a lot of requests which query data from concierge API, responses are good for 7 days. So caching time can be set up to 7 days. To achieve, a caching solution is required in client side.
There are several caching solutions in market. Here are the comparison of Varnish vs other caching solutions. https://www.quora.com/What-is-the-fundamental-difference-between-varnish-and-squid-caching-architectures and https://deliciousbrains.com/page-caching-varnish-vs-nginx-fastcgi-cache/ .

## Architecture

Varnish is a good solution for caching but there is one limitation. Varnish can only talk to backend server with IP specified or domain associated with one IP only. For existing concierge APIs (api.bazaarvoice.com and stg.api.bazaarvoice.com) , they are resolved to 2 IPs because they are ELBs. To handle limitation, two methods are proposed here.
```
  1. A Nginx is sitting between Varnish and backend server api.bazaarvoice.com (stg.api.bazaarvoice.com) as proxy.  Varnish points backend server to Nginx and Nginx proxy requests to api.bazaarvoice.com (stg.api.bazaarvoice.com).
  2. A cron job executes a DSN resolving script, which updates IPs of api.bazaarvoice.com (stg.api.bazaarvoice.com) in backend_server.vcl, which is used by Varnish to set up backend servers, and reload new backend servers IPs without affecting cached objects.
```
![Varnish As caching](./pics/VarnishAsCaching.png?raw=true "Varnish As Caching")

## Setup

All set up is done on Mac OS 10.10.5. For more information on other systems, please refer to links in this doc.

### Install Varnish

Varnish can be installed on different operating system. Please refer to this page for more details https://www.varnish-cache.org/releases/
For Mac OS, following are steps.
```
1. Run 'brew update' //update brew itself
2. Run 'brew install varnish'  //latest version 4.1 should be installed
3. You should see a similar message after varnish is installed. (all parameters are example)
    To have launchd start varnish at login:
    ln -sfv /usr/local/opt/varnish/*.plist ~/Library/LaunchAgents
    Then to load varnish now:
    launchctl load ~/Library/LaunchAgents/homebrew.mxcl.varnish.plist
    Or, if you don't want/need launchctl, you can just run:
    /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default.vcl -s malloc,1G -T 127.0.0.1:2000 -a 0.0.0.0:8080
```

### Solution 1 (Varnish + Nginx)

#### Install and set up Nginx
Nginx can be installed on different operating system. Please refer to this page for more details http://nginx.org/en/docs/install.html
For Mac OS, following are steps.
```
1. Run 'brew update' //update brew itself
2. Run 'brew install nginx'  //nginx 1.10 or later release should be installed
3. Copy 'nginx.conf' under ./config/solution1/ to corresponding location. (In Mac OS, it is /usr/local/etc/nginx/)  
4. Use editor to open 'nginx.conf' and change 'resolver x.x.x.x valid=300s;' to correponding DNS server you use. ('valid=300s' means Nginx refresh DSN records every 5 minutes; Removing it makes Nginx use TTL from DNS server). 
   How to get DNS server
   a. Run 'nslookup api.bazaarvoice.com' and you will get 
   Server: 10.201.0.10
   Address: 10.201.0.10#53
   .....
   Replace 'x.x.x.x' with '10.201.0.10'. 
   b. Go to /etc/resolv.conf and you will find IPs of DNS servers . You can add more than 1 DNS server. For example 'resolver 10.0.0.1 10.0.0.2 valid=300s;'
5. Run 'sudo nginx' to run Nginx. Now Nginx is listening to 8080 . (You can change port number if you want, but make sure you set this port number in Varnish config file later).
6. To stop Nginx, run 'sudo nginx -s stop' to stop Nginx.
7. (Optional) If your application uses Nginx already, just copy this section to 'server' section in nginx.conf.
    Edit existing nginx.conf
    server {
        ........
        resolver 10.201.0.10 valid=300s;    
        set $upstream_endpoint_prod http://api.bazaarvoice.com;
        set $upstream_endpoint_stg http://stg.api.bazaarvoice.com;
        location /api/ {
            rewrite ^/api/(.*) /$1 break;
            proxy_pass $upstream_endpoint_prod;
        }
        location /stg_api/ {
            rewrite ^/stg_api/(.*) /$1 break;
            proxy_pass $upstream_endpoint_stg;
        }
    }
```

#### Run Varnish
Assume Varnish is installed successfully in the machine.
For Mac OS, following are steps.
```
1. Copy 'default_nginx.vcl' under ./config/solution1/ to corresponding location. (In Mac OS, it is /usr/local/etc/varnish/) 
2. Use editor to open 'default_nginx.vcl' and make corresponding change to point to Nginx (if necessary)
   edit default.vcl
    # Default backend. It should point to nginx server configured. 
    backend default {
        .host = "127.0.0.1"; //nginx ip
        .port = "8080"; //niginx port
    }
3. Run Varnish by running " /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default_nginx.vcl -s malloc,5G -T 127.0.0.1:2000 -a 127.0.0.1:8082 "
    /usr/local/sbin/varnishd This is path to varnishd after installation.
    -n Specify the name for this Varnish instance. (optional)
    -f  path to 'default_nginx.vcl'
    -a 127.0.0.1:8082 the port where varnish will run
    -T 127.0.0.1:2000 is where the varnishadm console wil run and it is useful to have for things like purging and banning. (optional) 
     -s malloc,5G 5G memory will be used to store cache (You can use different storage for cache. For more details , please refer to at https://www.varnish-cache.org/docs/trunk/users-guide/storage-backends.html. Varnish will recycle space with LRU (least recently used) strategy to remove items from cache when the cache becomes full with things whose TTL (time to live) has not expired (so first remove things whose TTL is expired, if the cache is still full remove things least recently accessed.)
    For more options to run Varnish , please refer to https://www.varnish-cache.org/docs/4.0/reference/varnishd.html 
```
Now , Varsnish can be accessible at http://localhost:8082 . (You have to specify backend server at /usr/local/etc/varnish/default.vcl , otherwise, you will see "Error 503 Backend fetch failed").
Make your client application call tohttp://localhost:8082/api (or http://localhost:8082/stg_api) instead of calling to http://api.bazaarvoice.com/ (or  http://stg.api.bazaarvoice.com/ ) and everything is set.

### Solution 2 (Varnish + cron)

#### Run Varnish
Assume Varnish is installed successfully in the machine.
For Mac OS, following are steps.
```
1. Copy 'default.vcl' , 'backend_servers.vcl'  and 'update_dns.sh' under ./config/solution2/ to corresponding location. (In Mac OS, it is /usr/local/etc/varnish/) 
2. (Optional) Use editor to open 'default.vcl' and make corresponding change to include 'backend_servers.vcl'.
    edit default.vcl
    # include should use absolute path; otherwise, Varnish complains.
    include "/usr/local/etc/varnish/backend_servers.vcl";
3. Run 'update_dns.sh' once before you run Varnish
    #for the first time running before Varnish runs, you will see some error message and ignore it because your Varnish is not running yet.
    Abandoned VSM file (Varnish not running?) /usr/local/var/varnish/_.vsm
    Failed to compile new varnish file 
4.  Add a cron job to crontab and backend_servers.vcl will be updated periodically and reloaded by Varnish without affecting cached objects.
    crontab job
    #  This is example in Mac Os. Change to your own absolute path here. You can see logs in /tmp/stdout.log and /tmp/stderr.log to track periodic update.
    # 1st parameter is the same as '-n' when you run Varnish and 2nd is path to 'default.vcl'
    # If you are running Linux, you may want to change line 92 '... awk '{print $4;}' ...' to '... awk '{print $3;}' ...'
    * * * * * /usr/local/etc/varnish/update_dns.sh /usr/local/var/varnish /usr/local/etc/varnish
5. Run Varnish by running " /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default_nginx.vcl -s malloc,5G -T 127.0.0.1:2000 -a 127.0.0.1:8082 "
```
Now , Varsnish can be accessible at http://localhost:8082 . (You have to specify backend server at /usr/local/etc/varnish/default.vcl , otherwise, you will see "Error 503 Backend fetch failed").
Make your client application call tohttp://localhost:8082/api (or http://localhost:8082/stg_api) instead of calling to http://api.bazaarvoice.com/ (or  http://stg.api.bazaarvoice.com/ ) and everything is set.

## Others
This section lists other knowledge you may be interested in. 

1. Kill varnish by running "sudo pkill varnishd"  
2. If you change 'default.vcl' when Varnish is running already, you can reload this new 'default.vcl' in 2 ways.
    ```
    reload your VCL and wipe your cache in the process by running "sudo pkill varnishd " and "sudo /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default.vcl -s malloc,1G -T 127.0.0.1:2000 -a 127.0.0.1:8082" 
    reload your VCL without wiping your cache by running
    varnishadm -n /usr/local/var/varnish
    vcl.load reload01 /usr/local/etc/varnish/default.vcl
    vcl.use reload01
    Note: 'reload01' is a random name and you could choose anything technically. Note, each time you reload the VCL file, you'll need to provide a unique name, so the second time you reload the VCL file you would use different string like reload02, reload03, etc.
    ```
3. Check statistics of Varnish
    
    Varnish comes with a couple of nifty and very useful statistics generating tools that generates statistics in real time by constantly updating and presenting a specific dataset by aggregating and analyzing logdata from the shared memory logs. Please refer to https://www.varnish-cache.org/docs/4.0/users-guide/operation-statistics.html for moe details.
    For example, to see a continuously updated histogram of hits/misses of cached objects, run 'varnishhist -n /usr/local/var/varnish'.
    ```
        Note: If you run varnish with '-n', all statistics commands should have this option too; otherwise, you will see         
        Can't open log - retrying for 5 seconds
        Can't open VSM file (Cannot open /usr/local/var/varnish/mycomputer.local/_.vsm: No such file or directory
    ```    
    To resolve this issue, you can run
    ```
        a. $ varnishhist -n /usr/local/var/varnish  
        OR
        b. $ ln -s /usr/local/var/varnish /usr/local/var/varnish/mycomputer.local/_.vsm'
        $ varnishhist
    ```

    ![varnishhist](./pics/varnishhist.png?raw=true "varnishhist -n /usr/local/var/varnish  '|' means 'hit' ,  '#' means 'miss'")
    
    
    ![varnishstat](./pics/varnishstat.png?raw=true "varnishstat -n /usr/local/var/varnish")
     
     Please refer to http://book.varnish-software.com/4.0/chapters/Examining_Varnish_Server_s_Output.html#varnishstat for explaination of statistics.
     
4. To see if reponse is returned because of 'hit' or 'miss' (by retrieving backend server), you can check 'X-Cache' in reponse header. 'HIT' means 'hit' and 'MISS' means response is retrieved from backend server because response is not cached or expires.

    ![x-cache](./pics/x-cache.png?raw=true "x-cache")

5. Accept 'https' in Varnish 
   Varnish does not support SSL termination natively. If you decide move to https, does it mean that your sites, which use Varnish as a proxy cache, would remain without HTTPS forever ? No, we have several options to support this. Basically, we want to put a proxy between client and Varnish, which will route https requests to Varnish via http.  
   ```
       a. Nginx 
          Here are several articles about how to use nginx as proxy.
          https://www.digitalocean.com/community/tutorials/how-to-configure-varnish-cache-4-0-with-ssl-termination-on-ubuntu-14-04
          https://komelin.com/articles/https-varnish
          https://www.smashingmagazine.com/2015/09/https-everywhere-with-nginx-varnish-apache/
       b. Pound
          Here is the article of how to use Pound as proxy. 
          https://dev.acquia.com/blog/why-pound-awesome-front-varnish
       c. Hitch
          https://info.varnish-software.com/blog/five-steps-to-secure-varnish-with-hitch-and-lets-encrypt
       d. HAProxy
          https://blog.feryn.eu/varnish-4-1-haproxy-get-the-real-ip-by-leveraging-proxy-protocol-support/
   ```  
6. Concerned about flushing your backend server?
   Varnish has configuration of how many concurrent connections to backend server. You can set it at default.vcl , like this 
   ```
   edit default.vcl
       # Default backend. It should point to nginx server configured. 
               backend default {
               .host = "127.0.0.1"; //nginx ip
               .port = "8080"; //niginx port
               ....
               .max_connections = 100 //100 simultaneous connections are allowed.
               }
   ```
7. Is stale object good to use?
   Varnish Cache will prefer a fresh object, but when one cannot be found Varnish will look for stale one. When it is found it will be delivered and Varnish will kick off the asynchronous request. It is serving the request with a stale object while refreshing it. It is basically stale-while-revalidate.
   ```
    A graced object is an object that has expired, but is still kept in cache
    Grace mode is when Varnish uses a graced object.
    There is more than one way Varnish can end up using a graced object.
    req.grace defines how long overdue an object can be for Varnish to still consider it for grace mode.
    beresp.grace defines how long past the beresp.ttl-time Varnish will keep an object
    req.grace is often modified in vcl_recv based on the state of the backend.
   ```
   When setting up grace, you will need to modify both vcl_recv and vcl_fetch to use grace effectively. The typical way to use grace is to store an object for several hours past its TTL, but only use it a few seconds after the TTL, except if the backend is sick. (Note: You can use set req.grace = 0s; to ensure that editorial staff doesn’t get older objects (assuming they also don’t hit the cache))