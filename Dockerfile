FROM alpine:3.10

COPY cpanfile /src/
#ENV EV_EXTRA_DEFS -DEV_NO_ATFORK

WORKDIR /

RUN apk update && \
  apk add perl perl-io-socket-ssl perl-dev g++ make wget curl mariadb-connector-c mariadb-connector-c-dev samba-client shadow && \
  curl -L https://cpanmin.us | perl - App::cpanminus && \
  cd /src && \
  cpanm --installdeps . -M https://cpan.metacpan.org && \
  groupadd adup && \
  useradd -N -g adup -M -d /opt/adup/run -s /sbin/nologin -c "ADUP user" adup && \
  apk del perl-dev g++ wget curl mariadb-connector-c-dev shadow && \
  rm -rf /root/.cpanm/* /usr/local/share/man/* /src/cpanfile

COPY . /src/

RUN cd /src && \
  sed -ri 's/(\$remote_user\s=\s['\''|"])/###\1/' lib/Adup.pm && \
  perl Makefile.PL && \
  make && \
  make install
#cd / && rm -rf /src

ENV ADUP_CONFIG /opt/adup/adup.conf
ENV ADUP_PUBLIC /opt/adup/public

USER adup:adup
#VOLUME ["data"]
EXPOSE 3000

CMD ["perl", "-MMojolicious::Lite", "-E", "get '/' => sub { shift->render(text => 'OK!') }; app->start", "daemon"]
