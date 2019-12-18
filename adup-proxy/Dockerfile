FROM uralm1/httpd-uwc-llng:latest

COPY proxy-site.conf /etc/apache2/sites-available/
COPY index.html /var/www/html/

RUN set -eux; \
  a2dissite default-ssl; \
  a2ensite proxy-site

#ENV SSL_CERT /etc/ssl/certs/u.pem
#ENV SSL_KEY /etc/ssl/private/u.key

ENV PUBLIC_ROOT /opt/adup/public
ENV PROXY_ADDR http://adup-app:3000/

COPY site-prep /usr/local/bin/

# combine with httpd-uwc-llng apache2-foreground
CMD ["sh", "-c", "site-prep && exec apache2-foreground"]

