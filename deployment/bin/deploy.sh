#!/bin/bash

set -e

MYSQL_PASSWORD=$1

PROJECT_DIR="/var/www/html/posts"

mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

git config --global --add safe.directory $PROJECT_DIR

if [ ! -d $PROJECT_DIR"/.git" ]; then
  GIT_SSH_COMMAND='ssh -i /home/roman/.ssh/id_rsa -o IdentitiesOnly=yes' git clone git@github.com:RomanMahiiovych/fundamental.git .
else
  git pull origin main
fi

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

cd frontend
npm install
npm run build

cd ../api
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
