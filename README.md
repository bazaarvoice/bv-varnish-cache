# bv-varnish-cache

This is a guide to set up Varnish as caching solution for the Bazaarvoice Conversations API. For more caching options, please refer to https://developer.bazaarvoice.com/apis/conversations/tutorials/caching.

## Introduction
At present, Conversations API clients are hitting api.bazaarvoice.com (OR stg.api.bazaarvoice.com) to get data they request. But CDN caches responses for 30 minutes for most requests (submission requests are not cached). So, the same requests to our CDN within 30 minutes are not getting any new data because the responses are coming from cached data. Therefore, if you cache responses locally for 30 minutes your application will get faster responses. 
To achieve this, a caching solution is required in client side.

## Why varnish is chosen?
There are several caching solutions in market, like Varnish, Squid. Compared to others , Varnish has several advantages.
* More configurable via VCL configuraiton file.
* Better performance and scalability
* Serve stale content when the cache has expired while triggering a fetch of fresh content. 

For more information of comparison between Varnish vs other caching solutions, please refer to 
* https://www.quora.com/What-is-the-fundamental-difference-between-varnish-and-squid-caching-architectures
* https://deliciousbrains.com/page-caching-varnish-vs-nginx-fastcgi-cache/

## Architecture

Varnish is a good solution for caching, but there is one limitation: Varnish can only talk to backend server with pre-configured IP address or domain associated with one IP address only. This won't work with the Conversations API because api.bazaarvoice.com and stg.api.bazaarvoice.com are resolved to multiple IP addresses. To handle limitation, two methods are proposed here.
1. Nginx is used as a proxy between Varnish and the Conversations API CDN. Varnish points backend server to Nginx and Nginx proxies requests to api.bazaarvoice.com or stg.api.bazaarvoice.com.
2. A cron job executes a DSN resolving script, which updates IPs of api.bazaarvoice.com (stg.api.bazaarvoice.com) in backend_server.vcl, which is used by Varnish to set up backend servers, and reload new backend servers IPs without affecting cached objects.

Varnish does not support SSL termination natively. If you decide move to https, please refer to [Use HTTPs with Varnish](#use-https-with-varnish).

![Varnish As caching](./pics/VarnishAsCaching.png?raw=true "Varnish As Caching")


## Setup

All set up is done on Mac OS 10.10.5. For more information on other systems, please refer to links in this doc.

### Install Varnish

Varnish can be installed on different operating system. Please refer to this page for more details https://www.varnish-cache.org/releases/

For Mac OS, following are steps.

1. Run 'brew update' //update brew itself
2. Run 'brew install varnish'  //latest version 4.1 should be installed
3. You should see a similar message after varnish is installed.

   ``` 
    To have launchd start varnish at login:
    ln -sfv /usr/local/opt/varnish/*.plist ~/Library/LaunchAgents
    Then to load varnish now:
    launchctl load ~/Library/LaunchAgents/homebrew.mxcl.varnish.plist
    Or, if you don't want/need launchctl, you can just run:
    /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default.vcl -s malloc,1G -T 127.0.0.1:2000 -a 0.0.0.0:8080
   ```

### Solution 1 (Varnish + Nginx)

#### Install and set up Nginx
Nginx can be installed on different operating systems. Please refer to http://nginx.org/en/docs/install.html for more details. 

For Mac OS, following are steps.

1. Run 'brew update' //update brew itself
2. Run 'brew install nginx'  //nginx 1.10 or later release should be installed
3. Copy 'nginx.conf' under ./config/solution1/ to corresponding location. (In Mac OS, it is /usr/local/etc/nginx/)  
4. Use editor to open 'nginx.conf' and change 'resolver x.x.x.x valid=300s;' to correponding DNS server you use.
   - 'valid=300s' means Nginx refresh DSN records every 5 minutes; Removing it makes Nginx use TTL from DNS server.
   - You can add more than 1 DNS server. For example 'resolver 10.0.0.1 10.0.0.2 valid=300s;'.
   - How to get DNS server
     - Run 'nslookup api.bazaarvoice.com' and you will see a similar message
     
       ```
       Server: 10.201.0.10
       Address: 10.201.0.10#53
       ```
     - Go to /etc/resolv.conf and you will find IPs of DNS servers. 
5. Run 'sudo nginx' to run Nginx. Now Nginx is listening to 8080 . (You can change port number if you want, but make sure you set this port number in Varnish config file later).
6. To stop Nginx, run 'sudo nginx -s stop' to stop Nginx.
7. (Optional) If your application uses Nginx already, just copy this section to 'server' section in nginx.conf.
    - Edit existing nginx.conf
    ```
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
Assuming Varnish is installed successfully.

For Mac OS, following are steps.

1. Copy 'default_nginx.vcl' under ./config/solution1/ to corresponding location. (In Mac OS, it is /usr/local/etc/varnish/) 
2. Use editor to open 'default_nginx.vcl' and make corresponding change to point to Nginx (if necessary)
   - Edit default.vcl
   ```
    # Default backend. It should point to nginx server configured. 
    backend default {
        .host = "127.0.0.1"; //nginx ip
        .port = "8080"; //niginx port
    }
   ``` 
3. Start Varnish by running 
   
   ``` /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default_nginx.vcl -s malloc,5G -T 127.0.0.1:2000 -a 127.0.0.1:8082 ```
    - For more options to start Varnish , please refer to https://www.varnish-cache.org/docs/4.0/reference/varnishd.html
    - parameters
      - /usr/local/sbin/varnishd : This is path to varnishd after installation.
      - -n : Specify the name for this Varnish instance. (optional)
      - -f : path to 'default_nginx.vcl'
      - -a : 127.0.0.1:8082 the port where varnish will run
      - -T : 127.0.0.1:2000 is where the varnishadm console wil run and it is useful to have for things like purging and banning. (optional) 
      - -s malloc,5G : 5G memory will be used to store cache. 
        - You can use different storage for cache. For more details , please refer to https://www.varnish-cache.org/docs/trunk/users-guide/storage-backends.html. [How Varnish Recycles Space](#how-varnish-recycles-space)
     
4.  Varsnish should be accessible at http://localhost:8082 . (You have to specify backend server at /usr/local/etc/varnish/default.vcl , otherwise, you will see "Error 503 Backend fetch failed").
    - Make your client application call tohttp://localhost:8082/api (or http://localhost:8082/stg_api) instead of calling to http://api.bazaarvoice.com/ (or  http://stg.api.bazaarvoice.com/ ).

### Solution 2 (Varnish + cron)

#### Run Varnish
Assuming Varnish is installed successfully.

For Mac OS, following are steps.

1. Copy 'default.vcl' , 'backend_servers.vcl'  and 'update_dns.sh' under ./config/solution2/ to corresponding location. (In Mac OS, it is /usr/local/etc/varnish/) 
2. (Optional) Use editor to open 'default.vcl' and make corresponding change to include 'backend_servers.vcl'.
    - edit default.vcl
    ```
    # include should use absolute path; otherwise, Varnish complains.
    include "/usr/local/etc/varnish/backend_servers.vcl";
    ```
3. Run 'update_dns.sh' once before you run Varnish
   - The first time you do this, before Varnish has been started, you will see an error message which you can ignore because Varnish is not running yet.
   ``` 
   Abandoned VSM file (Varnish not running?) /usr/local/var/varnish/_.vsm
   Failed to compile new varnish file 
   ```
4.  Add a cron job to crontab and backend_servers.vcl will be updated periodically and reloaded without affecting cached objects.
    - crontab
    
    ```
    * * * * * /usr/local/etc/varnish/update_dns.sh /usr/local/var/varnish /usr/local/etc/varnish
    ```
    - Important: This is example in Mac Os. Change to your own absolute path here. You can see logs in /tmp/stdout.log and /tmp/stderr.log to track periodic update.
      - 1st parameter is the same as '-n' when you run Varnish and 2nd is path to 'default.vcl'
      - If you are running Linux, you may want to change line 92 '... awk '{print $4;}' ...' to '... awk '{print $3;}' ...'
5. Start Varnish by running ```/usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default_nginx.vcl -s malloc,5G -T 127.0.0.1:2000 -a 127.0.0.1:8082```

6. Varnish should be accessible at http://localhost:8082 . (You have to specify backend server at /usr/local/etc/varnish/default.vcl , otherwise, you will see "Error 503 Backend fetch failed").
   - Make your client application call tohttp://localhost:8082/api (or http://localhost:8082/stg_api) instead of calling to http://api.bazaarvoice.com/ (or  http://stg.api.bazaarvoice.com/ ).

## Additional information
This section lists additional information you may be interested in. 

### Reload new vcl
If you change 'default.vcl' when Varnish is running already, you can reload this new 'default.vcl' in 2 ways.

1. reload your VCL and wipe your cache in the process by running ```sudo pkill varnishd``` and ```sudo /usr/local/sbin/varnishd -n /usr/local/var/varnish -f /usr/local/etc/varnish/default.vcl -s malloc,1G -T 127.0.0.1:2000 -a 127.0.0.1:8082``` 
2. reload your VCL without wiping your cache by running following commands.

   ``` 
   varnishadm -n /usr/local/var/varnish
   vcl.load reload01 /usr/local/etc/varnish/default.vcl
   vcl.use reload01
   ```
   
   - Important: 'reload01' is a random name and you could choose anything technically. Note, each time you reload the VCL file, you'll need to provide a unique name, so the second time you reload the VCL file you would use different string like reload02, reload03, etc.
       
### Statistics of Varnish
Varnish comes with a couple of nifty and very useful tools that generate statistics in real time. They constantly update and present a specific dataset by aggregating and analyzing logdata from the shared memory logs. 

Please refer to https://www.varnish-cache.org/docs/4.0/users-guide/operation-statistics.html for moe details.

1. To see a continuously updated histogram of hits/misses of cached objects, run ```varnishhist -n /usr/local/var/varnish```.
   - Important: If you run varnish with '-n', all statistics commands should have this option too; otherwise, you will see  
          
     ```
        Can't open log - retrying for 5 seconds
        Can't open VSM file (Cannot open /usr/local/var/varnish/mycomputer.local/_.vsm: No such file or directory
     ```    
   
    ![varnishhist](./pics/varnishhist.png?raw=true "varnishhist -n /usr/local/var/varnish  '|' means 'hit' ,  '#' means 'miss'")
            
2. To resolve this issue, you can run 
   1. ```varnishhist -n /usr/local/var/varnish ``` 
   2. 
     - ```ln -s /usr/local/var/varnish /usr/local/var/varnish/mycomputer.local/_.vsm' ``` 
     - ```varnishhist```  
    
    ![varnishstat](./pics/varnishstat.png?raw=true "varnishstat -n /usr/local/var/varnish")
     
     Please refer to http://book.varnish-software.com/4.0/chapters/Examining_Varnish_Server_s_Output.html#varnishstat for explaination of statistics.
     
### Hit or Miss
To see if reponse is returned because of 'hit' or 'miss' (by retrieving backend server), you can check 'X-Cache' in reponse header. 'HIT' means 'hit' and 'MISS' means response is retrieved from backend server because response is not cached or expires.

![x-cache](./pics/x-cache.png?raw=true "x-cache")

### Use HTTPs with Varnish
Varnish does not support SSL termination. If you decide move to https, does it mean that your sites, which use Varnish as a proxy cache, would remain without HTTPS forever ? No, you have several options to support this. Basically, you want to put a proxy between client and Varnish, which will route https requests to Varnish via http.  
- Nginx 
  Here are several articles about how to use nginx as proxy.
  - https://www.digitalocean.com/community/tutorials/how-to-configure-varnish-cache-4-0-with-ssl-termination-on-ubuntu-14-04
  - https://komelin.com/articles/https-varnish
  - https://www.smashingmagazine.com/2015/09/https-everywhere-with-nginx-varnish-apache/
- Pound
  Here is the article of how to use Pound as proxy. 
  - https://dev.acquia.com/blog/why-pound-awesome-front-varnish
- Hitch
  - https://info.varnish-software.com/blog/five-steps-to-secure-varnish-with-hitch-and-lets-encrypt
- HAProxy
  - https://blog.feryn.eu/varnish-4-1-haproxy-get-the-real-ip-by-leveraging-proxy-protocol-support/

### Concurrent connections
Varnish supports concurrent connections to backend servers by configuration.  This parameter can be set in default.vcl, like this 

   ```
   # Default backend. It should point to nginx server configured. 
   backend default {
       .host = "127.0.0.1"; //nginx ip
       .port = "8080"; //niginx port
       ....
       .max_connections = 100 //100 simultaneous connections are allowed.
   }
   ```
   
### Stale objects
Varnish Cache will prefer a fresh object, but when one cannot be found Varnish will look for stale one. When it is found it will be delivered and Varnish will kick off the asynchronous request. It is serving the request with a stale object while refreshing it. It is basically stale-while-revalidate.
* A graced object is an object that has expired, but is still kept in cache
* Grace mode is when Varnish uses a graced object.
* There is more than one way Varnish can end up using a graced object.
* req.grace defines how long overdue an object can be for Varnish to still consider it for grace mode.
* beresp.grace defines how long past the beresp.ttl-time Varnish will keep an object
* req.grace is often modified in vcl_recv based on the state of the backend.

When setting up grace, you will need to modify both vcl_recv and vcl_fetch to use grace effectively. The typical way to use grace is to store an object for several hours past its TTL, but only use it a few seconds after the TTL, except if the backend is sick.

### How Varnish recycles space
   Varnish will recycle space with LRU (least recently used) strategy to remove items from cache when the cache becomes full with things whose TTL (time to live) has not expired (so first remove things whose TTL is expired, if the cache is still full remove things least recently accessed.