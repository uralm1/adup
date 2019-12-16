requires 'EV';
requires 'Mojolicious', '8.09';
requires 'Mojo::mysql', '1.04';
requires 'Minion', '9.03';
requires 'Minion::Backend::mysql';
requires 'XBase';
requires 'Net::LDAP', '0.65';
requires 'Net::LDAP::Util';
requires 'MIME::Base64';
requires 'Digest::SHA';
requires 'DateTime';
requires 'DateTime::Format::MySQL';
requires 'ExtUtils::MakeMaker::CPANfile';

on 'configure' => sub {
  requires 'ExtUtils::MakeMaker';
  requires 'ExtUtils::MakeMaker::CPANfile';
};

on 'test' => sub {
  requires 'Test::More';
  requires 'Test::Exception';
};
