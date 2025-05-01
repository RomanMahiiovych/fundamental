#!/bin/bash

set -ex

MYSQL_PASSWORD=$1
SSH_KEY=$(echo "$2" | base64 -d)

PROJECT_DIR="/var/www/html/posts"

# -----------------------------
# ПІДГОТОВКА SSH ДЛЯ GIT CLONE
# -----------------------------
mkdir -p ~/.ssh
echo "$SSH_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# -----------------------------
# СТВОРЕННЯ ПАПКИ ПРОЄКТУ
# -----------------------------
mkdir -p $PROJECT_DIR
chown -R www-data:www-data $PROJECT_DIR
cd $PROJECT_DIR

git config --global --add safe.directory $PROJECT_DIR

# -----------------------------
# КЛОНУВАННЯ ПРОЄКТУ
# -----------------------------
if [ ! -d "$PROJECT_DIR/.git" ]; then
  echo "SSH KEY CHECK (first line):"
  head -n 1 ~/.ssh/id_rsa

  ssh-keyscan github.com >> ~/.ssh/known_hosts

  GIT_SSH_COMMAND='ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes' git clone git@github.com:RomanMahiiovych/fundamental.git .
  cp ./api/.env.example ./api/.env
  sed -i "/DB_PASSWORD/c\DB_PASSWORD=$MYSQL_PASSWORD" ./api/.env
  sed -i '/QUEUE_CONNECTION/c\QUEUE_CONNECTION=database' ./api/.env
fi

# -----------------------------
# ВСТАНОВЛЕННЯ NODE ЧЕРЕЗ NVM
# -----------------------------
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
fi
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

nvm install 14
nvm use 14
nvm alias default 14

# -----------------------------
# ВСТАНОВЛЕННЯ PHP 8.1 + РОЗШИРЕННЯ
# -----------------------------
rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-noble.list
rm -rf /var/lib/apt/lists/*
apt-get clean
add-apt-repository ppa:ondrej/php -y
apt update -y

apt install -y php8.1-common php8.1-cli php8.1-fpm \
php8.1-dom php8.1-gd php8.1-zip php8.1-curl \
php8.1-mysql php8.1-sqlite3 php8.1-mbstring \
net-tools supervisor unzip curl git software-properties-common

# -----------------------------
# ВСТАНОВЛЕННЯ COMPOSER
# -----------------------------
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
EXPECTED_HASH="$(curl -s https://composer.github.io/installer.sig)"
ACTUAL_HASH="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_HASH" = "$ACTUAL_HASH" ]; then
  php composer-setup.php
  sudo mv composer.phar /usr/local/bin/composer
else
  echo "Installer corrupt"
  rm composer-setup.php
  exit 1
fi

rm -f composer-setup.php

composer -V

# -----------------------------
# СТВОРЕННЯ БАЗИ ДАНИХ
# -----------------------------
echo "Створення бази даних..."
mysql -uroot -p$MYSQL_PASSWORD < ./deployment/config/mysql/create_database.sql || echo "Database already exists"
mysql -uroot -p$MYSQL_PASSWORD < ./deployment/config/mysql/set_native_password.sql

# -----------------------------
# СТВОРЕННЯ КОРИСТУВАЧА `roman`
# -----------------------------
useradd -G www-data,root -u 1000 -d /home/roman roman || true
mkdir -p /home/roman/.ssh
touch /home/roman/.ssh/authorized_keys
echo "$SSH_PUBLIC_KEY" >> /home/roman/.ssh/authorized_keys
chown -R roman:roman /home/roman
chmod 700 /home/roman/.ssh
chmod 600 /home/roman/.ssh/authorized_keys
echo "roman ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/roman

# -----------------------------
# ФІНАЛЬНА ПЕРЕВІРКА
# -----------------------------
php -v
node -v
npm -v
composer -V
