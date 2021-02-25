FROM alpine:3.11

COPY cpanfile /src/
#ENV EV_EXTRA_DEFS -DEV_NO_ATFORK

RUN apk update && \
  apk add --no-cache perl perl-io-socket-ssl perl-dev g++ make wget curl mariadb-connector-c mariadb-connector-c-dev samba-client shadow tzdata patch && \
# install perl dependences
  curl -L https://cpanmin.us | perl - App::cpanminus && \
  cd /src && \
  cpanm --installdeps . -M https://cpan.metacpan.org && \
# create adup user
  groupadd adup && \
  useradd -N -g adup -M -d /opt/adup/run -s /sbin/nologin -c "ADUP user" adup && \
# fix samba
  chmod 777 /var/cache/samba /var/lib/samba && \
  chown adup:adup /var/lib/samba/* && \
# fix ping to run under user
  chmod u+s /bin/ping && \
# cleanup
  apk del perl-dev g++ wget curl mariadb-connector-c-dev shadow && \
  rm -rf /root/.cpanm/* /usr/local/share/man/* /src/cpanfile

COPY . /src/

RUN cd /src && \
  sed -ri 's/(\$remote_user\s=\s['\''|"])/###\1/' lib/Adup.pm && \
  perl Makefile.PL && \
  make && \
  make install && \
# disable logs
  rm -rf /opt/adup/log && \
  cd / && rm -rf /src

WORKDIR /opt/adup

ENV ADUP_CONFIG /opt/adup/adup.conf

USER adup:adup
#VOLUME ["/opt/adup/public"]
VOLUME ["/opt/adup/tmp"]
EXPOSE 3000

#CMD ["sh", "-c", "script/check_db_hosts && hypnotoad -f /opt/adup/script/adup"]
CMD ["sh", "-c", "script/check_db_hosts && script/start_server"]
