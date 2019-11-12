package Adup::Ural::AttrTranslate;
use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(translate);

# $trans_name = Adup::Ural::AttrTranslate::translate($attr_name);
sub translate {
  my $a = shift;
  my %attributes = (
    givenName => 'Имя',
    sn => 'Фамилия',
    middleName => 'Отчество',
    displayName => 'ФИО',
    initials => 'Инициалы',
    title => 'Должность',
    company => 'Предприятие',
    department => 'Подразделение',
    employeeID => 'Табельный номер',
    info => 'Заметки',
    description => 'Описание'
  );
  return $attributes{$a} || $a;
}


1;
