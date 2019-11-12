package Adup::Ural::LoginAI;
use Mojo::Base -base;

use Carp;

# Adup::Ural::LoginAI->new($f, $i, $o);
sub new {
  my ($class, $f, $i, $o) = @_;
  croak 'Surname required' unless defined $f;
  return bless {
    f => k82tr($f),
    i => k82tr($i || ''),
    o => k82tr($o || ''),
    round_i => 1,
    round_o => 1,
    cnt => '',
  }, $class;
}

# $obj->next_round;
sub next_round {
  my $self = shift;
  if ($self->{round_i} < length($self->{i})) {
    $self->{round_i}++;
  } elsif ($self->{round_o} < length($self->{o})) {
    $self->{round_o}++;
  } else {
    $self->{cnt} = 1 if $self->{cnt} eq '';
    $self->{cnt}++;
  }
}


# my $login = $obj->login;
sub login {
  my $self = shift;
  return lc($self->{f} . partof($self->{i}, $self->{round_i}) . partof($self->{o}, $self->{round_o}) . $self->{cnt});
}


#internal
sub partof {
  (local $_, my $r) = @_;
  my $l = length;
  substr($_, 0, ($r > $l) ? $l : $r);
}

#internal
sub k82tr {
  local $_ = shift;
  s/Сх/Sh/; s/сх/sh/; s/СХ/SH/;
  s/Ш/Sh/g; s/ш/sh/g;

  s/Сцх/Sch/; s/сцх/sch/; s/СЦХ/SCH/;
  s/Щ/Sch/g; s/щ/sch/g;

  s/Цх/Ch/; s/цх/ch/; s/ЦХ/CH/;
  s/Ч/Ch/g; s/ч/ch/g;

  s/Йа/Ja/; s/йа/ja/; s/ЙА/JA/;
  s/Я/Ya/g; s/я/ya/g;

  s/Йо/Jo/; s/йо/jo/; s/ЙО/JO/;
  s/Ё/Jo/g; s/ё/jo/g;

  s/Йу/Ju/; s/йу/ju/; s/ЙУ/JU/;
  s/Ю/Ju/g; s/ю/ju/g;

  s/Зх/Zh/g; s/зх/zh/g; s/ЗХ/ZH/g;
  s/Ж/Zh/g; s/ж/zh/g;

  s/Ц/Ts/g; s/ц/ts/g;

  s/ъ//g; s/ь//g; s/Ъ//g; s/Ь//g;

  tr/
  абвгдезийклмнопрстуфхыэАБВГДЕЗИЙКЛМНОПРСТУФХЫЭ/
  abvgdezijklmnoprstufhyeABVGDEZIJKLMNOPRSTUFHYE/;

  s/[\\\/\[\]:;|=,+*?<>]//g;

  return $_;
}


1;
