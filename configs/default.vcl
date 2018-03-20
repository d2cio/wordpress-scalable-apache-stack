vcl 4.0;

backend default {
    .host = "{{=service('balancer').getAppAlias()}}";
    .port = "{{=service('balancer').getMainPort()}}";
    .connect_timeout = 3s; # Wait a maximum of 1s for backend connection (Apache, Nginx, etc...)
    .first_byte_timeout = 300s; # Wait a maximum of 5s for the first byte to come from your backend
    .between_bytes_timeout = 6s; # Wait a maximum of 2s between each bytes sent
}

acl purge {
    "{{=service('balancer').getAppAlias()}}";
    "{{=service('blog').getAppAlias()}}";
}

sub vcl_recv {
        if (req.method == "PURGE") {
                if (!client.ip ~ purge) {
                        return(synth(405, "This IP is not allowed to send PURGE requests."));
                }
                return (purge);
        }

        if (req.http.Authorization || req.method == "POST") {
                return (pass);
        }

        if (req.url ~ "wp-(login|admin)" || req.url ~ "preview=true") {
                return (pass);
        }

        if (req.url ~ "sitemap" || req.url ~ "robots") {
                return (pass);
        }

        set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js)=[^;]*", "");

        set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

        set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

        set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-1=[^;]+(; )?", "");

        set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-time-1=[^;]+(; )?", "");

        set req.http.Cookie = regsuball(req.http.Cookie, "wordpress_test_cookie=[^;]+(; )?", "");

        if (req.http.cookie ~ "^ *$") {
                    unset req.http.cookie;
        }

        if (req.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico|woff|svg|htm|html)") {
                unset req.http.cookie;
        }

        if (req.http.Cookie ~ "wordpress_" || req.http.Cookie ~ "comment_") {
                return (pass);
        }

        if (!req.http.cookie) {
                unset req.http.cookie;
        }

        if (req.http.Authorization || req.http.Cookie) {
                # Not cacheable by default
                return (pass);
        }

        return (hash);
}

sub vcl_pass {
        return (fetch);
}

sub vcl_hash {
        hash_data(req.url);

        return (lookup);
}

sub vcl_backend_response {
        unset beresp.http.Server;
        unset beresp.http.X-Powered-By;

        if (bereq.url ~ "sitemap" || bereq.url ~ "robots") {
                set beresp.uncacheable = true;
                set beresp.ttl = 30s;
                return (deliver);
        }

        if (bereq.url ~ "\.(css|js|png|gif|jp(e?)g)|swf|ico|woff|svg|htm|html") {
                unset beresp.http.cookie;
                set beresp.ttl = 7d;
                unset beresp.http.Cache-Control;
                set beresp.http.Cache-Control = "public, max-age=604800";
                set beresp.http.Expires = now + beresp.ttl;
        }

        if (bereq.url ~ "wp-(login|admin)" || bereq.url ~ "preview=true") {
                set beresp.uncacheable = true;
                set beresp.ttl = 30s;
                return (deliver);
        }

                if (!(bereq.url ~ "(wp-login|wp-admin|preview=true)")) {
                unset beresp.http.set-cookie;
        }

        if ( bereq.method == "POST" || bereq.http.Authorization ) {
                set beresp.uncacheable = true;
                set beresp.ttl = 120s;
                return (deliver);
        }

        if ( bereq.url ~ "\?s=" ){
                set beresp.uncacheable = true;
                set beresp.ttl = 120s;
                return (deliver);
        }

        if ( beresp.status != 200 ) {
                set beresp.uncacheable = true;
                set beresp.ttl = 120s;
                return (deliver);
        }


        set beresp.ttl = 1d;
        set beresp.grace = 30s;

        return (deliver);
}

sub vcl_deliver {
        unset resp.http.X-Powered-By;
        unset resp.http.Server;
        unset resp.http.Via;
        unset resp.http.X-Varnish;

        return (deliver);
}
