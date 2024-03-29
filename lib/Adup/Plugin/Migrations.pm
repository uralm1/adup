package Adup::Plugin::Migrations;
use Mojo::Base 'Mojolicious::Plugin';

use Carp;
use Mojo::mysql;

sub register {
  my ($self, $app, $args) = @_;
  $args ||= {};

  # apply db migrations
  $app->helper(migrate_database => sub {
    my $self = shift;
    my $mysql = $self->mysql_adup;

    $mysql->auto_migrate(1)->migrations->name('adupdb')->from_data;
    #$mysql->auto_migrate(1);
  });
}


1;
__DATA__
@@ adupdb
-- 1 up
CREATE TABLE IF NOT EXISTS `persons` (
  `id` int(11) UNSIGNED NOT NULL AUTO_INCREMENT,
  `gal_id` varchar(20) NOT NULL,
  `fio` varchar(150) NOT NULL,
  `dup` tinyint(3) UNSIGNED NOT NULL,
  `f` varchar(150) NOT NULL,
  `i` varchar(150) NOT NULL,
  `o` varchar(150) NOT NULL,
  `dept_id` int(11) UNSIGNED NOT NULL,
  `flatdept_id` int(11) UNSIGNED NOT NULL,
  `otdel` varchar(255) NOT NULL,
  `dolj` varchar(255) NOT NULL,
  `tabn` decimal(7,0) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fio` (`fio`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `depts` (
  `id` int(10) UNSIGNED NOT NULL,
  `name` varchar(255) NOT NULL,
  `level` int(10) UNSIGNED NOT NULL,
  `parent` int(10) UNSIGNED NOT NULL,
  `path` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `level` (`level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `flatdepts` (
  `id` int(10) UNSIGNED NOT NULL,
  `cn` varchar(64) NOT NULL,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `changes` (
  `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `type` int(11) NOT NULL,
  `metadata` int(11) DEFAULT NULL,
  `c` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `name` (`name`),
  KEY `type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `changes_archive` (
  `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `type` int(11) NOT NULL,
  `c` text NOT NULL,
  PRIMARY KEY (`id`),
  KEY `name` (`name`),
  KEY `type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `state` (
  `key` varchar(20) NOT NULL,
  `value` int(11) NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `state` (`key`, `value`) VALUES
('merge_id', 0),
('preprocess_id', 0),
('sync_id', 0);

CREATE TABLE IF NOT EXISTS `users` (
  `login` varchar(50) NOT NULL,
  `role` varchar(50) NOT NULL,
  PRIMARY KEY (`login`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `users` (`login`, `role`) VALUES
('ural', 'admin');

CREATE TABLE IF NOT EXISTS `op_log` (
  `id` int(11) UNSIGNED NOT NULL AUTO_INCREMENT,
  `login` varchar(30) NOT NULL,
  `date` datetime NOT NULL,
  `state` tinyint(3) NOT NULL,
  `info` varchar(1024) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `login` (`login`),
  KEY `date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `changelog` (
  `ver_major` int(11) NOT NULL,
  `ver_minor` int(11) NOT NULL,
  `date` datetime NOT NULL,
  `changelog` text NOT NULL,
  PRIMARY KEY (`ver_major`,`ver_minor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `changelog` (`ver_major`, `ver_minor`, `date`, `changelog`) VALUES
(0, 10, '2019-06-25 00:00:00', 'Исправлена ошибка загрузки шаблона Persons.<br>\r\nКоманды запуска задач с командной строки.<br>\r\nКоманда загрузки шаблона с SMB сервера и запуска препроцессинга.<br>\r\nПериодический запуск загрузок шаблонов с SMB сервера для systemd и cron.<br>\r\nУчёт изменений в программе.<br>\r\nУлучшение работы программы в тестовых режимах.'),
(0, 11, '2019-07-05 00:00:00', 'Убраны блокировки таблиц уровня сервера.<br>\r\nДобавлена таблица для плоской записи подразделений.<br>\r\nДоработана задача загрузки и предварительной обработки.<br>\r\nРефакторинг по подзадачам синхронизации.<br>\r\nУлучшение лога ошибок заданий командной строки.'),
(0, 12, '2019-07-08 00:00:00', 'Новый формат хранения \"плоских\" подразделений и соответствующие изменения в задании предобработки.'),
(0, 13, '2019-07-22 00:00:00', 'Отображение дат изменено на \"время дата\".<br>\r\nИсправлена сортировка архива применённых изменений.<br>\r\nИсправлено падение процесса синхронизации аттрибутов при неполном списке аттрибутов.<br>\r\nИсправлено падение процесса постобработки при отсутствии у работники имени или отчества.<br>\r\nДобавлена кнопка запуска применения изменений на экран просмотра и утверждения.<br>\r\nСоздание/синхронизация групп почтового справочника Корпоративной почты.<br>\r\nОптимизации процедур принятия изменений.<br>\r\nУлучшено отображение лога операций.'),
(0, 14, '2019-07-23 00:00:00', 'Оптимизация лога применений изменений.<br>\r\nРефакторинг подзадач синхронизации.<br>\r\nКоманда зачистки отметок выполняющихся задач.<br>\r\nУлучшено отображение прогрессбаров задач.'),
(0, 15, '2019-07-24 00:00:00', 'Создание/синхронизация OU подразделений.<br>\r\nСинхронизация табельных номеров работников.<br>\r\nИсправление мелких ошибок и недоработок.<br>\r\nИсправлена сортировка списка изменений при утверждении.<br>\r\nБазовые DN персонала и почтовых групп вынесены в файл конфигурации.<br>\r\nАвтоперезапуск подсистемы выполнения задач в случае сбоя.'),
(0, 16, '2019-07-25 00:00:00', 'Работа над ошибками созданными в предыдущей версии.<br>\r\nУлучшение отображения прогресса для всех процессов.'),
(0, 17, '2019-07-26 00:00:00', '**Синхронизация - Создание пользователей.<br>\r\nОптимизация дублирующегося кода.<br>\r\nОтображение полного подразделения и отключенных пользователей в форме просмотра имен компьютеров.'),
(0, 18, '2019-07-29 00:00:00', 'Улучшение стабильности алгоритма формирования логинов.<br>\r\nОптимизация использования аттрибута distinguishedName при синхронизации.<br>\r\n**Включение пользователей в группы почтового справочника при создании и модификации учётных записей.<br>\r\nFIXBACKPORT: Исправление ошибки при определении членства в группе почтового справочника.'),
(0, 19, '2019-07-30 00:00:00', 'Исправление ошибки при определении членства в группе почтового справочника.<br>\r\nУлучшен разбор ФИО при постпроцессинге шаблона, ликвидирована возможность появления учетных записей с пробелом в конце.<br>\r\nУлучшено отображение прогресса операции.<br>\r\nУлучшена обработка ошибок поиска в Active directory.'),
(0, 20, '2019-08-02 00:00:00', 'Повторное улучшение стабильности разбора ФИО.<br>\r\n**Формы ввода телефонов, сотовых телефонов расширены для возможности ввода нескольких номеров на одного человека.<br>\r\nОптимизация, улучшенная обработка ошибок поиска в ldap в формах ввода.<br>\r\nИнформирование о новой версии программы.'),
(0, 21, '2019-08-05 00:00:00', '**Синхронизация - Перемещение пользователей.<br>\r\nИсправление отображения изменений.<br>\r\nСписки фильтров по типам изменений отсортированы по логическому порядку применения изменений.'),
(0, 22, '2019-08-10 00:00:00', 'Обработка имен групп почтового справочника искусственным интеллектом, для того чтобы они лучше выглядели в справочнике корпоративной почты.<br>\r\nПроведение порождаемых им изменений групп почтового справочника.'),
(0, 23, '2019-08-09 00:00:00', '**Синхронизация - Удаление пользователей.<br>\r\nОтдельные доработки интеллекта именования групп почтового справочника.<br>\r\nОптимизация пользовательского интерфейса по части использования с мобильных устройств.<br>\r\nПоправлены базы поисков в формах ввода данных.'),
(0, 24, '2019-08-13 00:00:00', '**Синхронизация - Удаление групп почтового справочника.<br>\r\nОтображение логина пользователя в изменении удаления пользователя.<br>\r\nWorkaround по части загрузки свежих css файлов при обновлении программы.<br>\r\nБазовая подсказка по программе с описанием основных функций.'),
(0, 25, '2019-08-16 00:00:00', '**Синхронизация - Удаление OU подразделений.<br>\r\nОтображение логинов пользователей в форме редактирования email-ов.<br>\r\nУлучшенная обработка ошибок доступа к LDAP и БД.<br>\r\nРесолвер ФИО операторов по логинам с кешированием для отображения полных ФИО в списке логов и т.п.<br>\r\nОптимизация кода.'),
(1, 0, '2019-08-19 00:00:00', 'Выпуск окончательной версии 1.0.<br>\r\nДоработана процедура синхронизации групп почтового справочника для очистки сотрудников - неактуальных \r\n членов почтовых групп.<br>\r\nАвтоматическая очистка кеша ресолвера операторов раз в сутки, чтобы не требовалось периодически перезапускать бэкенд.<br>\r\nДоработки пользовательского интерфейса.'),
(1, 1, '2019-08-19 00:00:00', 'Исправлена ошибка удаления некоторых учётных записей из групп почтового справочника.'),
(1, 2, '2019-08-22 00:00:00', '**Загрузка и просмотр фотографий сотрудников.<br>\r\nПерезагрузка раз в сутки кэша пользователей для того, чтобы избежать необходимости перезапуска серверной части программы при смене ролей пользователей.<br>\r\nПовторное исправление ошибки удаления учётных записей из отдельных групп почтового справочника.<br>\r\nОптимизация пользовательского интерфейса.'),
(1, 3, '2019-08-23 00:00:00', 'Реализовано использование камеры устройства для съемки фото сотрудников.<br> \r\nСмена порядка выполнения синхронизаций для профилактики ошибок удаления учётных записей из отдельных групп почтового справочника.'),
(1, 4, '2019-09-25 00:00:00', 'Смена порядка применения изменений для профилактики ошибок удаления учётных записей из отдельных групп почтового справочника.'),
(1, 5, '2019-09-27 00:00:00', 'Досрочное завершение задания синхронизации изменений в случае если имеются изменения создания подразделений и групп почтового справочника - для экономии ресурсов. Все равно сначала необходимо создать подразделения, а затем перезапустить задание синхронизации.'),
(1, 6, '2019-10-22 00:00:00', 'Автоматическое применение изменений создания и удаления подразделений в соответствии с их уровнем иерархии. Теперь не нужно их сортировать вручную.<br>\r\nУлучшение UI.'),
(1, 7, '2019-10-25 00:00:00', 'Разрешено создание записей сотрудников с одинаковыми ФИО находящихся в разных подразделениях.<br>\r\nИзменены алгоритмы синхронизации учётных записей для сотрудников с одинаковыми ФИО.<br>\r\nНе поддерживается перемещение сотрудников с одинаковыми ФИО между подразделениями. Перемещение должно производиться вручную.<br>\r\nРеализован постраничный (Paged) поиск в LDAP при синхронизации удалений работников из групп почтового справочника.'),
(1, 8, '2019-12-19 00:00:00', 'Переход на виртуализацию docker.'),
(1, 9, '2019-12-20 00:00:00', 'Временные volume больше не создаются в контейнерах worker и cron.<br>\r\nКорректное логгирование запуска и остановки задач в worker.'),
(1, 10, '2020-03-10 00:00:00', 'Встроенный планировщик загрузок.'),
(1, 13, '2020-05-15 00:00:00', 'Решена проблема с hypnotoad hot deployment.'),
(1, 14, '2021-02-25 00:00:00', 'Использование migrations для БД.<br>\r\nПереход на prefork в контейнерах.<br>\r\nОграничение макс. одно задание на процесс worker-а.<br>\r\nОптимизации и улучшения.');

-- 1 down
DROP TABLE IF EXISTS `persons`;
DROP TABLE IF EXISTS `depts`;
DROP TABLE IF EXISTS `flatdepts`;
DROP TABLE IF EXISTS `changes`;
DROP TABLE IF EXISTS `changes_archive`;
DROP TABLE IF EXISTS `state`;
DROP TABLE IF EXISTS `users`;
DROP TABLE IF EXISTS `op_log`;
DROP TABLE IF EXISTS `changelog`;

-- 2 up
INSERT INTO `changelog` (`ver_major`, `ver_minor`, `date`, `changelog`) VALUES
(1, 15, '2021-03-12 00:00:00', 'Инструкция нового пользователя корпоративной сети.<br>\r\nОбновление js-библиотек.<br>\r\nИсправлены баги с валидацией.<br>\r\nОптимизации и улучшения.'),
(1, 16, '2021-04-01 00:00:00', 'Проверка на включенные учётные записи в DISMISSED, формирование изменений на их отключение.<br>\r\nОбновление сокращений подразделений.'),
(1, 17, '2021-05-10 00:00:00', 'Синхронизация с 1C ЗУП.');

-- 2 down
DELETE FROM `changelog` WHERE `ver_major` = 1 AND `ver_minor` = 15;
DELETE FROM `changelog` WHERE `ver_major` = 1 AND `ver_minor` = 16;
DELETE FROM `changelog` WHERE `ver_major` = 1 AND `ver_minor` = 17;

-- 3 up
DROP TABLE IF EXISTS `changelog`;

-- 3 down
CREATE TABLE IF NOT EXISTS `changelog` (
  `ver_major` int(11) NOT NULL,
  `ver_minor` int(11) NOT NULL,
  `date` datetime NOT NULL,
  `changelog` text NOT NULL,
  PRIMARY KEY (`ver_major`,`ver_minor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- 4 up
INSERT INTO `state` (`key`, `value`) VALUES
('zupprocess_id', 0);

-- 4 down
DELETE FROM `state` WHERE `key` = 'zupprocess_id';

-- 5 up
ALTER TABLE `persons` CHANGE `gal_id` `gal_id` VARCHAR(36) NOT NULL;

-- 5 down
ALTER TABLE `persons` CHANGE `gal_id` `gal_id` VARCHAR(20) NOT NULL;

-- 6 up
DROP TABLE IF EXISTS `state`;

-- 6 down
CREATE TABLE IF NOT EXISTS `state` (
  `key` varchar(20) NOT NULL,
  `value` int(11) NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `state` (`key`, `value`) VALUES
('merge_id', 0),
('preprocess_id', 0),
('zupprocess_id', 0),
('sync_id', 0);

-- 7 up
ALTER TABLE `persons` ADD INDEX (`otdel`);

CREATE TABLE IF NOT EXISTS `_fio_dedup` (
  `fio` varchar(150) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `_fio_otd_dedup` (
  `fio` varchar(150) NOT NULL,
  `otdel` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- 7 down
DROP TABLE IF EXISTS `_fio_dedup`;
DROP TABLE IF EXISTS `_fio_otd_dedup`;

-- 8 up
ALTER TABLE `persons` ADD `sovm` TINYINT(3) UNSIGNED NOT NULL AFTER `dup`;

-- 8 down

