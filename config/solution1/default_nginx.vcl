#
# This is an example VCL file for Varnish.
#
# It does not do anything by default, delegating control to the
# builtin VCL. The builtin VCL is called when there is no explicit
# return statement.
#
# See the VCL chapters in the Users Guide at https://www.varnish-cache.org/docs/
# and https://www.varnish-cache.org/trac/wiki/VCLExamples for more examples.

# Marker to tell the VCL compiler that this VCL has been adapted to the
# new 4.0 format.
vcl 4.0;

import std;

# Default backend. It should point to nginx server configured. 
backend default {
    .host = "127.0.0.1";
    .port = "8080";
}

# normalize request to ignore "Callback" and "_" and http/https
sub normalize_req_url {

    set req.url = regsub(req.url, "/^https?:\/\//", "");
    
    if(req.url ~ "(?i)(\?|&)(_|callback)=") {
        set req.url = regsuball(req.url, "(_|callback)=[%.-_A-z0-9]+&?", "");
    }
    # get rid of trailing  & and ?
    set req.url = regsub(req.url, "(\?&?)$", "");
}

sub vcl_recv {

    set req.url = std.querysort(req.url);
    set req.backend_hint = default;


    # pass review submission without cache
    if (req.url ~ "/data/submitreview.[xml|json]") {
        return (pass);
    }
    
    call normalize_req_url;

    return (hash);
}

sub vcl_hash {
    hash_data(req.url);
    return (lookup);
}

sub vcl_backend_response {
    # set ttl of resp to be 7 days  . object will be cached for this long.
    set beresp.ttl = 7d;
    # set grace period to be 1 minute. Once object is being refreshed after ttl expires, within grace period, old object will be served.
    set beresp.grace = 1m;
}

sub vcl_deliver {
    # Happens when we have all the pieces we need, and are about to send the
    # response to the client.
    #
    # You can do accounting or modifying the final object here.
    # Sometimes it's nice to see when content has been served from the cache.  
    if (obj.hits > 0) {
        # If the object came from the cache, set an HTTP header to say so
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
  }
}
