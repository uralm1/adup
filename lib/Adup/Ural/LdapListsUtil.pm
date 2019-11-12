package Adup::Ural::LdapListsUtil;
use Mojo::Base -base;

use Net::LDAP::Entry;
use Net::LDAP::Util qw(ldap_explode_dn);
use Encode qw(decode);
use Carp;

use Exporter qw(import);
our @EXPORT_OK = qw(ldapattrs2list ldaplist2attrs_entry checkdnbase);

# returns list of all values from 2 ldap attributes
# @list = Adup::Ural::LdapListsUtil::ldapattrs2list($entry, 'telephoneNumber', 'otherTelephone')
sub ldapattrs2list {
  my ($entry, $attr, $mult_attr) = @_;
  my @l;
  my $v1 = $entry->get_value($attr);
  push @l, decode('utf-8', $v1) if defined $v1;
  push @l, decode('utf-8', $_) for ($entry->get_value($mult_attr));
  return @l;
}

# modify reference to entry for ldap modify operations
# 1 or undef = Adup::Ural::LdapListsUtil::ldaplist2attrs_entry($entry, [@values], 'telephoneNumber', 'otherTelephone')
sub ldaplist2attrs_entry {
  my ($entry, $values, $attr, $mult_attr) = @_;
  my @l1;
  @l1 = ($attr => []) if ($entry->get_value($attr) && !@$values);
  push @l1, ($mult_attr => []) if ($entry->get_value($mult_attr));
  $entry->delete( @l1 ) if (@l1);

  if (scalar @$values > 0) {
    my @l2 = ($attr => shift @$values);
    push @l2, ($mult_attr => [reverse @$values]) if (@$values);
    $entry->replace( @l2 );
    return 1;
  }
  return (@l1) ? 1 : undef;
}


# check for $dn_base is the base of $dn
# 1 or undef = Adup::Ural::LdapListsUtil::checkdnbase($dn, $dn_base);
sub checkdnbase {
  my ($dn, $dn_base) = @_;

  my $base_aofh = ldap_explode_dn($dn_base);
  my $dn_aofh = ldap_explode_dn($dn);
  unless (defined $base_aofh and defined $dn_aofh) {
    carp "checkdnbase(), ldap_explode_dn error for DN: $dn";
    return undef;
  }
  while (my $h = pop @$base_aofh) {
    my ($h_k, $h_v) = each %$h;
    my $h1 = pop @$dn_aofh;
    unless ($h1) {
      #carp "checkdnbase(), bad base in DN: $dn";
      return undef;
    }
    my ($h1_k, $h1_v) = each %$h1;
    if ($h_k ne $h1_k or $h_v ne $h1_v) {
      #carp "checkdnbase(), bad base (2) in DN: $dn";
      return undef;
    }
  }
  return 1;
}


1;
