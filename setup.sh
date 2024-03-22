#!/usr/bin/bash
set -e

usage () {
  cat << USAGE
Before running this, set up an a record at a domain you control that points
to the IP address of this host. Then set these environment variables or
specify these on the shell before calling setup.sh:

    PAUSE_HOST=the.hostname.from.above
    PAUSE_USER=ANDK (or whatever you want)
    PAUSE_PASS=laksjdfa (or whatever you want)
USAGE

  exit;
}

if [ -z "$PAUSE_HOST" ]; then
  usage;
fi;

if [ -z "$PAUSE_USER" ]; then
  usage;
fi;

if [ -z "$PAUSE_PASS" ]; then
  usage;
fi;

# uc it
PAUSE_USER=${PAUSE_USER^^}

# install system deps
apt-get install mariadb-server libssl-dev zlib1g-dev \
 default-libmysqlclient-dev \
 libexpat1-dev \
 libdb-dev \
 nginx \
 certbot \
 python3-certbot-nginx \
 git build-essential -y

# The --comment is here to suppress prompting for name, confirmation, etc.
adduser pause  --disabled-password --comment 'PAUSE User'
adduser unsafe --disabled-password --comment 'PAUSE Unsafe'

sudo -u pause git clone https://git@github.com/andk/pause/ ~pause/pause

# set up mysql databases and our pause user
mysqladmin -uroot create mod
mysql -uroot mod < ~pause/pause/doc/mod.schema.txt

mysqladmin -u root create authen_pause
mysql -u root authen_pause < ~pause/pause/doc/authen_pause.schema.txt

mysql -root mod -e "INSERT INTO users (userid) VALUES ('$PAUSE_USER')"

PASS=$(perl -wle "print crypt '$PAUSE_PASS', chr(rand(26)+97).chr(rand(26)+97)")
echo $PASS

mysql -uroot authen_pause -e "INSERT INTO usertable (user, password) VALUES ('$PAUSE_USER', '$PASS')"

mysql -uroot authen_pause -e "INSERT INTO grouptable (user, ugroup) VALUES ('$PAUSE_USER', 'admin')"

mysql -uroot -e "CREATE USER pause IDENTIFIED BY 'pausepassword'"
mysql -uroot -e "GRANT DELETE, INDEX, INSERT, SELECT, UPDATE, LOCK TABLES ON \`mod\`.* TO 'pause'@'%';"
mysql -uroot -e "GRANT DELETE, INDEX, INSERT, SELECT, UPDATE, LOCK TABLES ON \`authen_pause\`.* TO 'pause'@'%';"

# Set up nginx conf
cat << CONF > "/etc/nginx/sites-available/$PAUSE_HOST"
upstream pause {
    server 127.0.0.1:5000;
}

server {
  listen 80 default_server;

  location / {
     proxy_pass http://pause;
     proxy_set_header X-Forwarded-Host \$host;
     proxy_set_header X-Forwarded-Server \$host;
     proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
     proxy_set_header X-Forwarded-Proto \$scheme;

     proxy_pass_request_headers on;
     proxy_no_cache \$cookie_nocache  \$arg_nocache\$arg_comment;
     proxy_no_cache \$http_pragma     \$http_authorization;
     proxy_cache_bypass \$cookie_nocache \$arg_nocache \$arg_comment;
     proxy_cache_bypass \$http_pragma \$http_authorization;
     proxy_pass_header Authorization;
  }

  server_name $PAUSE_HOST;
}
CONF

rm /etc/nginx/sites-enabled/default
ln -s "/etc/nginx/sites-available/$PAUSE_HOST" "/etc/nginx/sites-enabled/$PAUSE_HOST"

# Install ssl cert
sudo certbot --nginx -d $PAUSE_HOST --agree-tos -n --email pause@pause.perl.org

cp setup-unpriv.sh ~pause
chown pause:pause ~pause/setup-unpriv.sh
chmod u+x ~pause/setup-unpriv.sh
sudo -u pause /home/pause/setup-unpriv.sh

echo "now run '~pause/.plenv/versions/5.36.0/bin/plackup -I ../pause-private/lib' from ~pause/pause and then check out https://$PAUSE_HOST"

