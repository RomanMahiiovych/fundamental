#!/bin/bash

set -e

MYSQL_PASSWORD=$1

PROJECT_DIR="/var/www/html/posts"

mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

git config --global --add safe.directory $PROJECT_DIR

ssh-keyscan github.com >> ~/.ssh/known_hosts

if [ ! -d $PROJECT_DIR"/.git" ]; then
  GIT_SSH_COMMAND='ssh -i /home/roman/.ssh/id_rsa -o IdentitiesOnly=yes' git clone git@github.com:RomanMahiiovych/fundamental.git .
else
  GIT_SSH_COMMAND='ssh -i /home/roman/.ssh/id_rsa -o IdentitiesOnly=yes' git pull
fi

cd $PROJECT_DIR"/frontend"
npm install
npm run build

cd $PROJECT_DIR"/api"

# Встановити власника на roman
sudo chown -R roman:roman $PROJECT_DIR

# Додати roman до групи www-data (одноразово, але безпечно повторити)
sudo usermod -aG www-data roman

# Дати доступ на читання/запис власнику і групі
sudo find $PROJECT_DIR -type d -exec chmod 775 {} \;
sudo find $PROJECT_DIR -type f -exec chmod 664 {} \;

# Дати www-data повні права на storage і bootstrap/cache
sudo chown -R www-data:www-data $PROJECT_DIR/api/storage
sudo chown -R www-data:www-data $PROJECT_DIR/api/bootstrap/cache

#cd frontend
#export NVM_DIR="$HOME/.nvm"
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
#nvm use 14
#
#npm install
#npm run build

cd $PROJECT_DIR/api
composer install --no-interaction --optimize-autoloader --no-dev

if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "/DB_PASSWORD/c\DB_PASSWORD=$MYSQL_PASSWORD" .env
    sed -i '/QUEUE_CONNECTION/c\QUEUE_CONNECTION=database' .env
    php artisan key:generate
fi

sudo chown -R www-data:www-data $PROJECT_DIR

php artisan storage:link
php artisan optimize:clear
php artisan down
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan up

sudo cp $PROJECT_DIR"/deployment/config/php-fpm/www.conf" /etc/php/8.1/fpm/pool.d/www.conf
sudo cp $PROJECT_DIR"/deployment/config/php-fpm/php.ini" /etc/php/8.1/fpm/conf.d/php.ini
sudo systemctl restart php8.1-fpm.service

sudo cp $PROJECT_DIR"/deployment/config/nginx.conf" /etc/nginx/nginx.conf
# test the config so if it's not valid we don't try to reload it
sudo nginx -t
sudo systemctl reload nginx
