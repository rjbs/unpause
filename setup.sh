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

# install plenv so we can manage a local perl version
git clone https://github.com/tokuhirom/plenv.git ~/.plenv

echo 'export PATH="$HOME/.plenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(plenv init -)"' >> ~/.bash_profile
source ~/.bash_profile

# install perl-build so we can build a new perl
git clone https://github.com/tokuhirom/Perl-Build.git ~/.plenv/plugins/perl-build/

plenv install 5.36.0 -j 8
plenv global 5.36.0

# install cpanm for perl dep management
plenv install-cpanm

git clone https://git@github.com/andk/pause/

pushd pause

# We need to pin these for now
cpanm Mojolicious@8.72
cpanm DBD::mysql@4.052
cpanm --installdeps .

# set up mysql databases and our pause user
mysqladmin -uroot create mod
mysql -uroot mod < doc/mod.schema.txt

mysqladmin -u root create authen_pause
mysql -u root authen_pause < doc/authen_pause.schema.txt

mysql -root mod -e "insert into users (userid) values ('$PAUSE_USER')"

PASS=$(perl -wle "print crypt '$PAUSE_PASS', chr(rand(26)+97).chr(rand(26)+97)")
echo $PASS

mysql -uroot authen_pause -e "insert into usertable (user,password) values ('$PAUSE_USER', '$PASS')"

mysql -uroot authen_pause -e 'insert into grouptable (user,ugroup) values ("$PAUSE_USER", "admin")'

# Set up pause config
mkdir -p ../pause-private/lib

cat << 'CONF' > ../pause-private/lib/PrivatePAUSE.pm
use strict;
package PAUSE;

$ENV{EMAIL_SENDER_TRANSPORT} = 'DevNull';

our $Config;
$Config->{AUTHEN_DATA_SOURCE_USER}  = "root";
$Config->{AUTHEN_DATA_SOURCE_PW}    = "";
$Config->{MOD_DATA_SOURCE_USER}     = "root";
$Config->{MOD_DATA_SOURCE_PW}       = "secret";
$Config->{MAIL_MAILER}              = ["testfile"];
$Config->{RUNDATA}                  = "/tmp/pause_1999";
$Config->{TESTHOST_SCHEMA}          = "http";
CONF

mkdir -p /tmp/pause_1999

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
sudo certbot --nginx -d $PAUSE_HOST

echo "now run 'plackup -I ../pause-private/lib' from the pause dir and then check out https://$PAUSE_HOST"


