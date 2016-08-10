backend b1 {
    .host = "50.18.127.131";
    .port = "80";
    .max_connections = 300; # That's it
    .first_byte_timeout     = 300s;   # How long to wait before we receive a first byte from our backend?
    .connect_timeout        = 30s;     # How long to wait for a backend connection?  
}

backend b2 {
    .host = "184.72.42.22";
    .port = "80";
}

backend b3 {
    .host = "50.18.127.131";
    .port = "80";
}

backend b4 {
    .host = "184.72.42.22";
    .port = "80";
}

sub backends_init {
    new vdir_prod = directors.round_robin();
    vdir_prod.add_backend(b1);
    vdir_prod.add_backend(b2);

    new vdir_stg = directors.round_robin();
    vdir_stg.add_backend(b3);
    vdir_stg.add_backend(b4);
}