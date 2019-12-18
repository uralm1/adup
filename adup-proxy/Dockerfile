FROM uralm1/httpd-uwc-llng:latest

COPY adup_site.conf /etc/apache2/sites-available/
COPY index.html /var/www/html/

RUN set -eux; \
  a2dissite default-ssl; \
  a2ensite adup_site

# same from httpd:2.4
#CMD ["apache2-foreground"]

