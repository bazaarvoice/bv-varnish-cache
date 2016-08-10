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
import directors;
include "/usr/local/etc/varnish/backend_servers.vcl";

sub vcl_init {
    # Called when VCL is loaded, before any requests pass through it. Typically used to initialize VMODs.
    call backends_init;
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
    # /api/ to prod
    if (req.url ~ "/api/") {
        set req.backend_hint = vdir_prod.backend();
        set req.http.Host = "api.bazaarvoice.com";
        set req.url = regsub(req.url, "/api/", "/");
    } 
    elsif (req.url ~ "/stg_api/") {
        set req.backend_hint = vdir_stg.backend();
        set req.http.Host = "stg.api.bazaarvoice.com";
        set req.url = regsub(req.url, "/stg_api/", "/");
    }
    else{
        return (synth(404, "NOT FOUND"));
    }


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
    # set ttl of resp to be 7 days. object will be cached for this long.
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
