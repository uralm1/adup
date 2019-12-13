FROM alpine:3.10

COPY cpanfile /
#ENV EV_EXTRA_DEFS -DEV_NO_ATFORK

RUN apk update && \
  apk add perl perl-io-socket-ssl perl-dev g++ make wget curl mariadb-connector-c mariadb-connector-c-dev samba-client && \
  curl -L https://cpanmin.us | perl - App::cpanminus && \
  cpanm --installdeps . -M https://cpan.metacpan.org && \
  apk del perl-dev g++ make wget curl mariadb-connector-c-dev && \
  rm -rf /root/.cpanm/* /usr/local/share/man/* 

#USER daemon
#WORKDIR /
#VOLUME ["data"]
EXPOSE 3000

CMD ["perl", "-MMojolicious::Lite", "-E", "get '/' => sub { shift->render(text => 'OK!') }; app->start", "daemon"]
