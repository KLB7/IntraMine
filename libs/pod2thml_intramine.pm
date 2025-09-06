# OBSOLETE, IntraMine now uses Pod::Simple::HTML directly.
# pod2thml_intramine.pm, a version of Pod::Simple::Text tweaked to output simple HTML
# for use by intramine_file_viewer_cm.pl.
# See /Pod/Simple/Text.pm for the basis of this module.
require 5;

package pod2thml_intramine;
use strict;
use warnings;
use utf8;
use Carp                 ();
use Pod::Simple::Methody ();
use Pod::Simple          ();
use vars                 qw( @ISA $VERSION $FREAKYMODE);
$VERSION = '3.31';
@ISA     = ('Pod::Simple::Methody');
BEGIN {
	*DEBUG =
		defined(&Pod::Simple::DEBUG)
		? \&Pod::Simple::DEBUG
		: sub() {0}
}

use Text::Wrap;
$Text::Wrap::huge    = 'overflow';
$Text::Wrap::columns = 86;

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub new {
	my $self = shift;
	my $new  = $self->SUPER::new(@_);
	$new->{'output_fh'} ||= *STDOUT{IO};
	$new->accept_target_as_text(qw( text plaintext plain ));
	$new->nix_X_codes(1);
	$new->nbsp_for_S(1);
	$new->{'Thispara'}     = '';
	$new->{'Indent'}       = 0;
	$new->{'Indentstring'} = '   ';

	$new->{'ESCAPE'} = 0;

	return $new;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub handle_text {
	my $txt = $_[1];

	if ($_[0]{'ESCAPE'})
		{
		$txt = "&$txt;";
		}

	$_[0]{'Thispara'} .= $txt;
}

sub start_Para  {$_[0]{'Thispara'} = ''}
sub start_head1 {$_[0]{'Thispara'} = '<h2>'}
sub start_head2 {$_[0]{'Thispara'} = '<h3>'}
sub start_head3 {$_[0]{'Thispara'} = '<h4>'}
sub start_head4 {$_[0]{'Thispara'} = '<h5>'}

sub start_Verbatim    {$_[0]{'Thispara'} = ''}
sub start_item_bullet {$_[0]{'Thispara'} = $FREAKYMODE ? '' : '&bull; '}
sub start_item_number {$_[0]{'Thispara'} = $FREAKYMODE ? '' : "$_[1]{'number'}. "}
sub start_item_text   {$_[0]{'Thispara'} = ''}

sub start_over_bullet {++$_[0]{'Indent'}}
sub start_over_number {++$_[0]{'Indent'}}
sub start_over_text   {++$_[0]{'Indent'}}
sub start_over_block  {++$_[0]{'Indent'}}

sub end_over_bullet {--$_[0]{'Indent'}}
sub end_over_number {--$_[0]{'Indent'}}
sub end_over_text   {--$_[0]{'Indent'}}
sub end_over_block  {--$_[0]{'Indent'}}


# . . . . . Now the actual formatters:

sub end_head1       {$_[0]{'Thispara'} .= '</h2>'; $_[0]->emit_par(-4)}
sub end_head2       {$_[0]{'Thispara'} .= '</h3>'; $_[0]->emit_par(-3)}
sub end_head3       {$_[0]{'Thispara'} .= '</h4>'; $_[0]->emit_par(-2)}
sub end_head4       {$_[0]{'Thispara'} .= '</h5>'; $_[0]->emit_par(-1)}
sub end_Para        {$_[0]->emit_par(0)}
sub end_item_bullet {$_[0]->emit_par(0)}
sub end_item_number {$_[0]->emit_par(0)}
sub end_item_text   {$_[0]->emit_par(-2)}

sub start_L {$_[0]{'Thispara'} .= '<l>'}
sub end_L   {$_[0]{'Thispara'} .= '</l>'}

#sub start_L         { $_[0]{'Link'} = $_[1] if $_[1]->{type} eq 'url' }
#sub end_L           {
#    if (my $link = delete $_[0]{'Link'}) {
#        # Append the URL to the output unless it's already present.
#        $_[0]{'Thispara'} .= " <$link->{to}>"
#            unless $_[0]{'Thispara'} =~ /\b\Q$link->{to}/;
#    }
#}

sub emit_par {
	my ($self, $tweak_indent) = splice(@_, 0, 2);
	my $indent = ' ' x (2 * $self->{'Indent'} + 4 + ($tweak_indent || 0));
	# Yes, 'STRING' x NEGATIVE gives '', same as 'STRING' x 0

	$self->{'Thispara'} =~ s/$Pod::Simple::shy//g;

	#my $out = $self->{'Thispara'};
	my $out = Text::Wrap::wrap($indent, $indent, $self->{'Thispara'} .= "\n");
	$out =~ s/$Pod::Simple::nbsp/ /g;

	print {$self->{'output_fh'}} $out, "\n";
	$self->{'Thispara'} = '';

	return;
}

# . . . . . . . . . . And then off by its lonesome:

sub end_Verbatim {
	my $self = shift;
	$self->{'Thispara'} =~ s/$Pod::Simple::nbsp/ /g;
	$self->{'Thispara'} =~ s/$Pod::Simple::shy//g;

	my $i = ' ' x (2 * $self->{'Indent'} + 4);
	#my $i = ' ' x (4 + $self->{'Indent'});

	$self->{'Thispara'} =~ s/^/$i/mg;

	print {$self->{'output_fh'}} '', $self->{'Thispara'}, "\n\n";
	$self->{'Thispara'} = '';
	return;
}

# Added for HTML.
# Handle B I F C S E codes in single X<> delimiters.
sub start_B {$_[0]{'Thispara'} .= '<strong>'}
sub end_B   {$_[0]{'Thispara'} .= '</strong>'}
sub start_I {$_[0]{'Thispara'} .= '<em>'}
sub end_I   {$_[0]{'Thispara'} .= '</em>'}
sub start_F {$_[0]{'Thispara'} .= '<em>'}
sub end_F   {$_[0]{'Thispara'} .= '</em>'}
sub start_C {$_[0]{'Thispara'} .= '<c>'}
sub end_C   {$_[0]{'Thispara'} .= '</c>'}
# Not called, I guess Methody steps in for S<>.
# POD isn't my thing, sorry. If it's important to you,
# I'm sure you can "upgrade" this file.
sub start_S {$_[0]{'Thispara'} .= '<s>'}
sub end_S   {$_[0]{'Thispara'} .= '</s>'}
sub start_E {$_[0]{'ESCAPE'} = 1}
sub end_E   {$_[0]{'ESCAPE'} = 0}


#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
1;
