#!/usr/bin/bash
set -e

cd ~pause

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

# We need to pin these for now
cpanm -n Mojolicious@8.72
cpanm -n DBD::mysql@4.052

cd ~pause/pause
cpanm -n --installdeps .

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

