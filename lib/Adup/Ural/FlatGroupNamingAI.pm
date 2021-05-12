package Adup::Ural::FlatGroupNamingAI;
use Mojo::Base -base;

use Exporter qw(import);
our @EXPORT_OK = qw(flatgroup_ai);

# modifies $_!!!!
# $trans_name = Adup::Ural::FlatGroupNamingAI::flatgroup_ai($name);
sub flatgroup_ai {
  local $_ = shift;
  # format: dept-subdept1-subdept2-subdept3 etc...

  s/^Автотранспортный цех/АТЦ/ ||

  s/^Аппарат управления-Группа по сопровождению системы менеджмента качества/Аппарат управления-Группа по сопровождению СМК/ ||
  s/^Аппарат управления-Группа по гражданской обороне и чрезвычайным ситуациям/Аппарат управления-Группа по ГОЧС/ ||
  s/^Аппарат управления-Инспекция водных балансов и качества сточных вод/Аппарат управления-ИВБиКСВ/ ||
  s/^Аппарат управления-Служба охраны труда и кадрового обеспечения/Аппарат управления-Служба ОТиКО/ ||
  s/^Аппарат управления-Управление главного технолога и охраны окружающей среды/Аппарат управления-Управление главного технолога и ООС/ ||

  s/^Служба Автоматизированных систем управления-Группа по разработке и сопровождению автоматизированных систем управления предприятием \(АСУП\)/Служба АСУ-Группа АСУП/ ||
  s/^Служба Автоматизированных систем управления-Отдел АСУ технологическими процессами \(АСУТП\)/Служба АСУ-АСУТП/ ||
  s/^Служба Автоматизированных систем управления/Служба АСУ/ ||
  s/^Управление информационных технологий-Группа по разработке и сопровождению автоматизированных систем управления предприятием \(АСУП\)/Управление информационных технологий-Группа АСУП/ ||
  s/^Управление метрологии и АСУТП-Отдел АСУ технологическими процессами \(АСУТП\)/Управление метрологии и АСУТП-Отдел АСУТП/ ||

  s/^Управление материально-технического снабжения и хозяйственного обеспечения-Центрально-материальный склад/Управление МТСиХО-ЦМС/ ||
  s/^Управление материально-технического снабжения и хозяйственного обеспечения/Управление МТСиХО/ ||

  s/^Служба главного энергетика-Эл\.участок по ремонту и обсл\.произ\.-лаб\., адм\.зданий и +станций антикоррозийной защиты \(АКЗ\)/Служба главного энергетика-Участок АКЗ/ ||

  s/^Служба Очистных сооружений канализации-Химико-бактериологическая лаборатория/СОСК-ХБЛ/ ||
  s/^Служба Очистных сооружений канализации/СОСК/ ||

  s/^Управление по капитальному ремонту и строительству-Проектно-конструкторский отдел/УКРС-ПКО/ ||
  s/^Управление по капитальному ремонту и строительству-Участок по ремонту сооружений и сетей/УКРС-УРСС/ ||
  s/^Управление по капитальному ремонту и строительству/УКРС/ ||

  s/^Управление по работе с абонентами/УРА/ ||

  s/^АТЦ-Эксплуатация землеройной техники, средств малой механизации и ремонт автопарка предприятия/АТЦ-Эксплуатация землеройной техники, СММ и ремонт автопарка предприятия/ ||

  s/^Служба Северного комплекса водопроводных сооружений-Ремонтно-механический участок/Служба СКВС-РМУ/ ||
  s/^Служба Северного комплекса водопроводных сооружений-Участок Шакшинского водопровода/Служба СКВС-Участок ШВ/ ||
  s/^Служба Северного комплекса водопроводных сооружений-Химико-бактериологическая лаборатория/Служба СКВС-ХБЛ/ ||
  s/^Служба Северного комплекса водопроводных сооружений-Участок 2-го подъёма инфильтрационного водозабора/Служба СКВС-Участок 2ПИВ/ ||
  s/^Служба Северного комплекса водопроводных сооружений-Цех Изякского водопровода/Служба СКВС-Цех ИВ/ ||
  s/^Служба Северного комплекса водопроводных сооружений-Цех очистных сооружений водопровода/Служба СКВС-Цех ОСВ/ ||
  s/^Служба Северного комплекса водопроводных сооружений/Служба СКВС/ ||

  s/^Служба технического развития систем водоснабжения и водоотведения/Служба технического развития/ ||

  s/^Служба Насосных станций канализации/Служба НСК/ ||
  s/^Управление Восточных канализационных сетей/УВКС/ ||
  s/^Управление Западных водопроводных сетей-Районные бригады аварийно-восстановительных и ремонтных работ на сети/УЗВС-Бригады АВР/ ||
  s/^Управление Западных водопроводных сетей/УЗВС/ ||
  s/^Управление Северных водопроводных сетей-РАЙОННЫЕ БРИГАДЫ АВАРИЙНО-ВОССТАНОВИТЕЛЬНЫХ И РЕМОНТНЫХ РАБОТ НА СЕТИ/УСВС-БРИГАДЫ АВР/ ||
  s/^Управление Северных водопроводных сетей/УСВС/ ||
  s/^Управление Южных канализационных сетей/УЮКС/ ||
  s/^Управление по эксплуатации систем водоотведения и водоснабжения/Управление по эксплуатации систем ВО и ВС/ ||

  s/^Служба Южного комплекса водопроводных сооружений-Участок Демского водопровода/Служба ЮВС-Участок ДВ/ ||
  s/^Служба Южного комплекса водопроводных сооружений-Цех Южного водопровода/Служба ЮВС-Цех ЮВ/ ||
  s/^Служба Южного комплекса водопроводных сооружений/Служба ЮВС/ ||

  s/^Центр аналитического контроля качества воды-Центральная химико-бактериологическая лаборатория/ЦАККВ-ЦХБЛ/ ||
  s/^Центр аналитического контроля качества воды/ЦАККВ/ ||

  s/^Центральная аварийно-диспетчерская служба/ЦАДС/;
  #s/^//;

  return $_;
}


1;
