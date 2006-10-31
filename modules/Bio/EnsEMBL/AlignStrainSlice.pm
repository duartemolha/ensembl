#
# Ensembl module for Bio::EnsEMBL::AlignStrainSlice
#
#
# Copyright Team Ensembl
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::AlignStrainSlice - Represents the slice of the genome aligned with certain strains (applying the variations/indels)

=head1 SYNOPSIS

   $sa = $db->get_SliceAdaptor;

   $slice = $sa->fetch_by_region('chromosome', 'X', 1_000_000, 2_000_000);

   $strainSlice1 = $slice->get_by_Strain($strain_name1);
   $strainSlice2 = $slice->get_by_Strain($strain_name2);

   my @strainSlices;
   push @strainSlices, $strainSlice1;
   push @strainSlices, $strainSlice2;

   $alignSlice = Bio::EnsEMBL::AlignStrainSlice->new(-SLICE => $slice,
                                                     -STRAINS => \@strainSlices);

   #get coordinates of variation in alignSlice
   my $alleleFeatures = $strainSlice1->get_all_differences_Slice();
   foreach my $af (@{$alleleFeatures}){
       my $new_feature = $alignSlice->alignFeature($af, $strainSlice1);
       print "Coordinates of the feature in AlignSlice are: ", $new_feature->start, "-", $new_feature->end, "\n";
   }


=head1 DESCRIPTION

A AlignStrainSlice object represents a region of a genome align for certain strains.  It can be used to align
certain strains to a reference slice

=head1 CONTACT

This modules is part of the Ensembl project http://www.ensembl.org

Questions can be posted to the ensembl-dev mailing list:
ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut

package Bio::EnsEMBL::AlignStrainSlice;
use strict;

use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Mapper;
use Bio::EnsEMBL::Mapper::RangeRegistry;
use Bio::EnsEMBL::Utils::Exception qw(throw deprecate warning);

use Data::Dumper;


=head2 new

    Arg[1]      : Bio::EnsEMBL::Slice $Slice
    Arg[2]      : listref of Bio::EnsEMBL::StrainSlice $strainSlice
    Example     : push @strainSlices, $strainSlice1;
                  push @strainSlices, $strainSlice2;
                  .....
                  push @strainSlices, $strainSliceN;
                  $alignStrainSlice = Bio::EnsEMBL::AlignStrainSlice->new(-SLICE => $slice,
									  -STRAIN => \@strainSlices);
    Description : Creates a new Bio::EnsEMBL::AlignStrainSlice object that will contain a mapper between
                  the Slice object, plus all the indels from the different Strains
    ReturnType  : Bio::EnsEMBL::AlignStrainSlice
    Exceptions  : none
    Caller      : general

=cut

sub new{
    my $caller = shift;
    my $class = ref($caller) || $caller;

    my ($slice, $strainSlices) = rearrange([qw(SLICE STRAINS)],@_);

    #check that both StrainSlice and Slice are identical (must have been defined in the same slice)
    foreach my $strainSlice (@{$strainSlices}){
	if (($strainSlice->start != $slice->start) || ($strainSlice->end != $slice->end) || ($strainSlice->seq_region_name ne $slice->seq_region_name)){
	    warning("Not possible to create Align object from different Slices");
	    return [];
	}
    }

    return bless{'slice' => $slice,
		 'strains' => $strainSlices}, $class;
}

=head2 new

    Arg[1]      : Bio::EnsEMBL::Feature $feature
    Arg[2]      : Bio::EnsEMBL::StrainSlice $strainSlice
    Example     : $new_feature = $alignSlice->alignFeature($feature, $strainSlice);
    Description : Creates a new Bio::EnsEMBL::Feature object that aligned to 
                  the AlignStrainSlice object.
    ReturnType  : Bio::EnsEMBL::Feature
    Exceptions  : none
    Caller      : general

=cut

sub alignFeature{
    my $self = shift;
    my $feature = shift;

    #check that the object is a Feature
    if (!ref($feature) || !$feature->isa('Bio::EnsEMBL::Feature')){	
	throw("Bio::EnsEMBL::Feature object expected");
    }

    #and align it to the AlignStrainSlice object
    my $mapper_strain = $self->mapper();

    my @results;
    if ($feature->start > $feature->end){
	#this is an Indel, map it with the special method
	@results = $mapper_strain->map_indel('Slice',$feature->start, $feature->end, $feature->strand,'Slice');
	#and modify the coordinates according to the length of the indel
	$results[0]->end($results[0]->start + $feature->length_diff -1);
    }
    else{
	@results = $mapper_strain->map_coordinates('Slice',$feature->start, $feature->end, $feature->strand,'Slice');
     }
    #get need start and end of the new feature, aligned ot AlignStrainSlice
    my @results_ordered = sort {$a->start <=> $b->start} @results;

    my %new_feature = %$feature; #make a shallow copy of the Feature
    $new_feature{'start'}= $results_ordered[0]->start();
    $new_feature{'end'} = $results_ordered[-1]->end();  #get last element of the array, the end of the slice

    return bless \%new_feature, ref($feature);
    
}


#getter for the mapper between the Slice and the different StrainSlice objects
sub mapper{
    my $self = shift;
    
    if (!defined $self->{'mapper'}){
	#get the alleleFeatures in all the strains
	if (!defined $self->{'indels'}){
	    #when the list of indels is not defined, get them
	    $self->{'indels'} = $self->_get_indels();
	}
	my $indels = $self->{'indels'}; #gaps in reference slice
	my $mapper = Bio::EnsEMBL::Mapper->new('Slice', 'AlignStrainSlice');
	my $start_slice = 1;
	my $end_slice;
	my $start_align = 1;
	my $end_align;
	my $length_indel;
	foreach my $indel (@{$indels}){
	    $length_indel = $indel->[1] - $indel->[0] + 1;

	    $end_slice = $indel->[0] - 1;
	    $end_align = $indel->[0] - 1;
	    $mapper->add_map_coordinates('Slice',$start_slice,$end_slice,1,'AlignStrainSlice',$start_align,$end_align);
	    
	    $mapper->add_indel_coordinates('Slice',$end_slice + 1,$end_slice,1,'AlignStrainSlice',$end_align + 1,$end_align + $length_indel);
	    $start_slice = $end_slice + 1;
	    $start_align = $indel->[1] + 1;

	}
	if ($start_slice <= $self->length){
	    $mapper->add_map_coordinates('Slice',$start_slice,$self->length,1,'AlignStrainSlice',$start_align,$start_align + $self->length - $start_slice)
	}
	$self->{'mapper'} = $mapper;
	
    }
    return $self->{'mapper'};
}

#returns the length of the AlignSlice: length of the Slice plus the gaps
sub length{
    my $self = shift;
    my $length;
    if (!defined $self->{'indels'}){
	#when the list of indels is not defined, get them
	$self->{'indels'} = $self->_get_indels();	
    }
    $length = $self->{'slice'}->length;
    map {$length += ($_->[1] - $_->[0] + 1)} @{$self->{'indels'}};
    return $length;
}

#getter for the strains
sub strains{
    my $self = shift;

    return $self->{'strains'};
}
#method to retrieve, in order, a list with all the indels in the different strains
sub _get_indels{
    my $self = shift;
    
    #go throuh all the strains getting ONLY the indels (length_diff <> 0)
    my @indels;
    foreach my $strainSlice (@{$self->strains}){
	my $differences = $strainSlice->get_all_differences_Slice(); #need to check there are differences....
	if (defined $differences){
	    my @results = grep {$_->length_diff != 0} @{$differences};
	    push @indels, @results;
	}
    }
    #need to overlap the gaps using the RangeRegistry module
    my $range_registry = Bio::EnsEMBL::Mapper::RangeRegistry->new();
    foreach my $indel (@indels){
	#deletion in reference slice
	$range_registry->check_and_register(1,$indel->start, $indel->end ) if ($indel->length_diff < 0);
	#insertion in reference slice
	$range_registry->check_and_register(1,$indel->start,$indel->start + $indel->length_diff - 1) if ($indel->length_diff > 0);
    }
    #and return all the gap coordinates....
    return $range_registry->get_ranges(1);
}

1;
