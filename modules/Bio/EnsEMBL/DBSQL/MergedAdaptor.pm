#
# Ensembl module for Registry
#
# Copyright EMBL/EBI
##
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::DBSQL::MergedAdaptor

=head1 SYNOPSIS

$merged_adaptor = new Bio::EnsEMBL::DBSQL::MergedAdaptor(-species => "human", -type => "Population");


=head1 DESCRIPTION

The MergedAdaptor object is merely a list of adaptors. AUTOLOAD is used to
call a subroutine on each adaptor and merge the results.

=head1 CONTACT

Post questions to the Ensembl developer list: <ensembl-dev@ebi.ac.uk>


=head1 METHODS

=cut


package Bio::EnsEMBL::DBSQL::MergedAdaptor;


use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Utils::Exception qw(throw warning deprecate);
use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Registry;
my $reg = "Bio::EnsEMBL::Registry";


=head2 new

  Example      : $MergedAdaptor = new 
               : Bio::EnsEMBL::DBSQL::MergedAdaptor(-species=> 'human', -type =>'Population');
  Arg [SPECIES]: (optional) string 
                  species name to get adaptors for
  Arg [TYPE]   : (optional) string 
                  type to get adaptors for

  Description: Creates a new MergedAdaptor
  Returntype : Bio::EnsEMBL::DBSQL::MergedAdaptor
  Exceptions : throws if species or type not specified
  Caller     : general
  Status     : At Risk
             : Under development

=cut

sub new {
  my ($class,@args) = @_;

  my $self ={};
  bless $self,$class;

  my ($species, $type) =
    rearrange([qw(SPECIES TYPE)], @args);

  if(!defined($species)|| !defined($type)){
    die "Species and Type must be specified\n";
  }
  
  my @adaps = @{$reg->get_all_adaptors(-species => $species, -type => $type)};

  my @list =();
  push(@list,@adaps);
  $self->{'list'}= \@list;

  return $self;
}

=head2 add_list

  Example    : $MergedAdaptor->add_list(@adaptors);
  Description: adds a list of adaptors to the Merged adaptor list.
  Returntype : none
  Exceptions : none
  Status     : At Risk
             : Under development

=cut

sub add_list{
  my ($self, @arr) = @_;

  foreach my $adap (@arr){
    $self->add_adaptor($adap);
  }
}

=head2 add_adaptor

  Example    : $MergedAdaptor->add_adaptor(@adaptors);
  Description: adds an adaptor to the Merged adaptor list.
  Returntype : none
  Exceptions : none
  Status     : At Risk
             : Under development

=cut

sub add_adaptor{
  my ($self,$adaptor)=@_;

  if(!defined ($self->{'list'})){
    my @list =();
    push(@list,$adaptor);
    $self->{'list'}= \@list;
  }
  else{
    push(@{$self->{'list'}},$adaptor);
  }
}


sub printit{
  my ($self)=@_;

  foreach my $adaptor (@{$self->{'list'}}){
    print "printit $adaptor\t".$adaptor->db->group()."\n";
  }
}


use vars '$AUTOLOAD';

sub AUTOLOAD {
  my ($self,@args) = @_;
  my %hash_return=();
  my @array_return=();
  my $obj_return= undef;
  my $scalar_return=undef;
  my $return = undef;

  $AUTOLOAD =~ /^.*::(\w+)+$/ ;

  my $sub = $1;

  foreach my $adaptor (@{$self->{'list'}}) {
    my $ref;
    if($adaptor->can($sub)){
      $ref = $adaptor->$sub(@args);
      my $type= ref($ref);
      if($type =~/HASH/){
#	print "HASH\t";
	warn("Merged adaptor Could be overwriting return value for $sub\n");
	warn("Due to HASH being returned\n");
	foreach my $key (keys %$ref){
	  $hash_return{$key} = $$ref{$key};
	}
	$return = \%hash_return;
      }
      elsif($type =~/ARRAY/){
	push @array_return,@$ref;
	$return = \@array_return;
      }
      elsif($type =~/SCALAR/){
	if(defined($scalar_return)){
	  warn("Merged adaptor overwriting return value for sub $sub\n");
	  warn("Maybe change return value for this sub to be ARRAY or use standard adaptor\n");
	}
	$scalar_return = $ref;
	$return = \$scalar_return;
      }
      else{ # obj
	if(defined($obj_return)){
	  warn("Merged adaptor overwriting return value for $sub\n");
	  warn("Maybe change return value for this sub to be ARRAY or use standard adaptor\n");
	}
	$obj_return = $ref;
	$return = $obj_return;
      }
    }
    else{ # end of can
      warn("In Merged Adaptor $adaptor cannot call sub $sub");
    }
  }
  return $return;
}

sub DESTROY{
}

1;
