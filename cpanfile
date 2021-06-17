requires 'Mojolicious', '8.50';
requires 'EV';
requires 'Cpanel::JSON::XS', '4.10';
requires 'IO::Socket::SSL', '2.009';
requires 'Mojo::mysql', '1.04';
requires 'Minion', '9.03';
requires 'Minion::Backend::mysql';
requires 'XBase';
requires 'Net::LDAP', '0.65';
requires 'Net::LDAP::Util';
requires 'MIME::Base64';
requires 'Digest::SHA';
requires 'Algorithm::Cron', '0.10';
requires 'ExtUtils::MakeMaker::CPANfile';

on 'configure' => sub {
  requires 'ExtUtils::MakeMaker';
  requires 'ExtUtils::MakeMaker::CPANfile';
};

on 'test' => sub {
  requires 'Test::More';
  requires 'Test::Exception';
};
