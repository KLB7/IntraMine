# html2gloss.pm: convert HTML to Gloss.
# Intended for converting HTML from Pos::Simple::HTML.

package html2gloss;
use strict;
use warnings;

use HTML::Parser();
our @ISA = qw(HTML::Parser);

my %blockTag;
# Text is accumulated as ordinary, main <li> entry, or
# an <li> continuation paragraph (of which there may be several).
# Used in $self->{'TEXT_TYPE'}.
my $kMain = 1;
my $kLi = 2;
my $kLiContinued = 3;

# For encoding name an id.
my %ENCMAP = (enc_map =>
          { ( map { chr($_) => sprintf( "%%%02X", $_ ) } ( 0 ... 255 ) ) });
my $RESERVED_RE
  = qr{([^a-zA-Z0-9\-\_\.\~\!\*\'\(\)\;\:\@\&\=\+\$\,\/\?\#\[\]\%])}x;


sub new {
    my ($proto) = @_;
    my $class = ref($proto) || $proto;

    my $self = HTML::Parser->new( api_version => 3,
        start_h => [\&startHandler, "self, tagname, attr"],
        end_h => [\&endHandler, "self, tagname"],
        text_h => [\&textHandler, "self, dtext, is_cdata"]
        );

    bless ($self, $class);
    ###$self->unbroken_text(1);
    $self->utf8_mode(1); # ???

	$self->{'TEXT_TYPE'} = $kMain;
    #$self->{DEPTH} = 0; # HTML tag nesting depth
    @{$self->{LINES}} = ();
	# $kMain text accumulator.
    $self->{CURRENT_LINE} = '';
	# $kLi main <li> item accumulator.
	$self->{LI} = '';
	# <li> continuation accumulator (there may be several).
	@{$self->{LI_PENDING_LINES}} = ();
    @{$self->{TAG}} = ();
    @{$self->{CLASS}} = ();
    @{$self->{HREF}} = ();
	@{$self->{NAME}} = ();
    @{$self->{LIST_TYPE}} = ();
    $self->{OLNUMBER} = 1; # post increment
    $self->{HEADING_LEVEL} = 0;
    $self->{IN_PRE} = 0; # in a <pre> element.

    InitBlockTags();
    
    return $self;
    }

sub htmlToGloss {
	my ($self, $inTextR, $outTextR) = @_;
	$$outTextR = '';
    $self->{OUT} = $outTextR;
    $self->parse($$inTextR);
    $$outTextR = join("\n", @{$self->{LINES}});
    }

# Track tag name, class, name, id, and href attributes.
# Note those must be pushed and popped together.
sub startHandler {
    my ($self, $tag, $attr) = @_;

	# Set text accumulator. Mainly about <li> items.
	if ($tag eq 'li')
		{
		$self->{'TEXT_TYPE'} = $kLi;
		}
	else
		{
		# A <p> tag when $self->{LI} is not empty signals the start
		# of a new continuation paragraph.
		
		my $toptag = defined(${$self->{TAG}}[-1]) ? ${$self->{TAG}}[-1]: '';
		if ($toptag eq 'li' && $tag eq 'p')
			{
			if ($self->{LI} ne '')
				{
				$self->{'TEXT_TYPE'} = $kLiContinued;
				# Push a blank to start new continuation paragraph.
				push @{$self->{LI_PENDING_LINES}}, '';
				}
			}
		}

	# Some cleanup: sometimes <dd> is missing.
	if ($tag eq 'dt' || $tag eq 'dl' || $tag eq 'dd')
		{
		my $toptag = defined(${$self->{TAG}}[-1]) ? ${$self->{TAG}}[-1]: '';
		if ($toptag eq 'dd')
			{
			# Invoke endHandler for 'dd', </dd> is missing
			endHandler($self, 'dd');
			}
		}


    push @{$self->{TAG}}, $tag;
    my $class = defined($attr->{'class'}) ? $attr->{'class'}: '';
    push @{$self->{CLASS}}, $class;
    my $href = defined($attr->{'href'}) ? $attr->{'href'}: '';
    push @{$self->{HREF}}, $href;
	my $name = defined($attr->{'name'}) ? $attr->{'name'}: '';
    push @{$self->{NAME}}, $name;
	my $id = defined($attr->{'id'}) ? $attr->{'id'}: '';
    push @{$self->{ID}}, $id;

    if ($tag eq 'ul' || $tag eq 'ol')
        {
        push @{$self->{LIST_TYPE}}, $tag;
        }

    elsif ($tag eq 'pre')
        {
        $self->{IN_PRE} = 1;
        }

	# <code> start
	elsif ($tag eq 'code' || $tag eq 'codehere')
		{
		AddText($self, '*!*');
		}
	# <a> anchor start
	elsif ($tag eq 'a')
		{
		StartAnchor($href, $name, $id);
		}
    }

sub endHandler {
    my ($self, $tag) = @_; # $tag isn't needed
    if (!defined(${$self->{TAG}}[-1]))
        {
		# Could there be text accumulated?
        return;
        }
    
    my $ptag = pop @{$self->{TAG}};
    my $class = pop @{$self->{CLASS}};
    my $href = pop @{$self->{HREF}};
	my $name = pop @{$self->{NAME}};
	my $id = pop @{$self->{ID}};

    if (IsPushTag($ptag))
        {
		if ($self->{'TEXT_TYPE'} == $kMain)
			{
			# Avoid dumping empty or just \s*\-\s* lines if in <li>.
			if ($self->{CURRENT_LINE} !~ m!^\s*\-?\s*$!)
				{
				# And always strip any trailing newlines.
				$self->{CURRENT_LINE} =~ s!\n+$!!;

				push @{$self->{LINES}}, $self->{CURRENT_LINE};

				# Add appropriate underline for headings (for Gloss).
				if ($self->{HEADING_LEVEL})
					{
					my $headingLevel = $self->{HEADING_LEVEL};
					if ($headingLevel == 1)
						{
						push @{$self->{LINES}}, '=====';
						}
					elsif ($headingLevel == 2)
						{
						push @{$self->{LINES}}, '-----';
						}
					else
						{
						push @{$self->{LINES}}, '~~~~~';
						}
					}
				}
			$self->{HEADING_LEVEL} = 0;
			$self->{CURRENT_LINE} = '';
			}

		if ($ptag eq 'li')
			{
			my $listType = defined(${$self->{LIST_TYPE}}[-1]) ? ${$self->{LIST_TYPE}}[-1]: 'ul';
			$self->{LI} = StartListItemProperly($self, $self->{LI}, $listType);
			push @{$self->{LINES}}, $self->{LI};
			if (defined(${$self->{LI_PENDING_LINES}}[-1]))
				{
				while (my $line = shift @{$self->{LI_PENDING_LINES}})
					{
					push @{$self->{LINES}}, " $line";
					}
				}
			$self->{LI} = '';
			}
		$self->{'TEXT_TYPE'} = $kMain;
        }
    elsif ($ptag eq 'ul' || $ptag eq 'ol')
        {
        pop @{$self->{LIST_TYPE}};
        if ($ptag eq 'ol')
            {
            $self->{OLNUMBER} = 1;
            }
        }
    elsif ($ptag eq 'pre')
        {
        $self->{IN_PRE} = 0;
        }
	elsif ($ptag eq 'code' || $ptag eq 'codehere')
		{
		AddText($self, '*!*');
		}
	elsif ($ptag eq 'a')
		{
		my $textA = EndAnchor($self->{HEADING_LEVEL});
		AddText($self, $textA);
		}
    }

sub textHandler {
    my ($self, $text, $iscdata) = @_;
    if ($iscdata)
        {
        return;
        }

    my $toptag = defined(${$self->{TAG}}[-1]) ? ${$self->{TAG}}[-1]: '';
    my $tagAbove = defined(${$self->{TAG}}[-2]) ? ${$self->{TAG}}[-2]: '';
    my $topClass = defined(${$self->{CLASS}}[-1]) ? ${$self->{CLASS}}[-1]: '';
    my $topHref = defined(${$self->{HREF}}[-1]) ? ${$self->{HREF}}[-1]: '';

	# If we're in a <pre> don't process any contained tags.
    if ($self->{IN_PRE})
        {
        push @{$self->{LINES}}, '---';
        my @lines = split(/\n/, $text);
        for (my $i = 0; $i < @lines; ++$i)
            {
			# Preserve whitespace in HTML without <pre>, as will
			# be the case in Gloss. '_NBS_' will be converted
			# to &nbsp; in intramine_viewer.pl#GetPrettyTextContents().
			$lines[$i] =~ s! !_NBS_!g;
            push @{$self->{LINES}}, $lines[$i];
            }
        push @{$self->{LINES}}, '---';
        $self->{CURRENT_LINE} = '';
    	return;
        }

	# Skip if we're not in a tag.
	if ($toptag eq '')
		{
		return;
		}
    
	if ($toptag eq 'a')
		{
		# Clean out embedded new lines.
		$text =~ s!\n! !g;

		if ($tagAbove =~ m!^h(\d)$!)
			{
			my $headingLevel = $1;
			
			if (index($topClass, 'u') == 0)
				{
				$self->{HEADING_LEVEL} = $headingLevel;
				}
			# Just dump out the heading, an underline will be added
			# above in endHandler so Gloss will pick up on it as a heading.
			AddText($self, $text);
			}
		elsif ($tagAbove eq 'dt')
			{
			AddText($self, '**' . $text . '**');
			}
		else
			{
			AddText($self, $text);
			}
		}
	# elsif ($toptag eq 'p' && $tagAbove eq 'dd')
	# 	{
	# 	AddText($self, $text);
	# 	}
	# elsif ($toptag eq 'p' && $tagAbove eq 'li')
	# 	{
	# 	my $listType = defined(${$self->{LIST_TYPE}}[-1]) ? ${$self->{LIST_TYPE}}[-1]: 'ul';
	# 	if ($self->{CURRENT_LINE} ne '')
	# 		{
	# 		# A continuation paragraph, add space and store for later.
	# 		push @{$self->{LI_PENDING_LINES}}, " $text";

	# 		# TEST ONLY
	# 		print("CONT_PARA: | $text|\n");
	# 		}
	# 	else 
	# 		{
	# 		# We're starting a list item, put list start and then text.
	# 		AddTextToListItem($self, $text, $listType);
	# 		}
	# 	}
	# elsif ($toptag eq 'li')
	# 	{
	# 	# Unordered ol or unordered ul. default 'ul'.
	# 	my $listType = defined(${$self->{LIST_TYPE}}[-1]) ? ${$self->{LIST_TYPE}}[-1]: 'ul';
	# 	AddTextToListItem($self, $text, $listType);
	# 	}
	elsif ($toptag eq 'em' || $toptag eq 'i')
		{
		AddText($self, "*$text*");
		}
	elsif ($toptag eq 'strong' || $toptag eq 'b')
		{
		AddText($self, "**$text**");
		}
	# <code>: also see start and end handlers. <code> can contain <em> or <strong>
	elsif ($toptag eq 'code' || $toptag eq 'codehere')
		{
		AddText($self, $text);
		}
	elsif ($toptag eq 'dt')
		{
		AddText($self, "**$text**");
		}
	else
		{
		# Skip all blank lines.
		if ($text !~ m!^\s*$!)
			{
			# Clean out embedded new lines.
			$text =~ s!\n! !g;
			AddText($self, $text);
			}
		}
     }

sub AddText {
	my ($self, $text) = @_;
	if (InAnchor())
		{
		AddAnchorText($text);
		}
	elsif ($self->{'TEXT_TYPE'} == $kLi)
		{
		$self->{LI} .= $text;
		}
	elsif ($self->{'TEXT_TYPE'} == $kLiContinued)
		{
		# Add to latest 
		my $pendingLineCount = @{$self->{LI_PENDING_LINES}};
		if ($pendingLineCount)
			{
			my $lastIdx = $pendingLineCount - 1;
			${$self->{LI_PENDING_LINES}}[$lastIdx] .= $text;
			}
		else # shouldn't happen, push the first entry
			{
			push @{$self->{LI_PENDING_LINES}}, $text;
			}
		}
	else
		{
		$self->{CURRENT_LINE} .= $text;
		}
	}

sub xAddTextToListItem {
	my ($self, $text, $listType) = @_;
	if ($self->{CURRENT_LINE} eq '')
		{
		if ($listType eq 'ul')
			{
			$self->{CURRENT_LINE} = " - $text";
			}
		else # 'ol'
			{
			$self->{CURRENT_LINE} = "$self->{OLNUMBER}. $text";
			$self->{OLNUMBER} += 1;
			}
		}
	else
		{
		if ($listType eq 'ul')
			{
			if (index($self->{CURRENT_LINE}, " - ") != 0)
				{
				$self->{CURRENT_LINE} = " - " . $self->{CURRENT_LINE};
				}
			else
				{
				$self->{CURRENT_LINE} .= $text;
				}
			}
		else # 'ol'
			{
			if ($self->{CURRENT_LINE} !~ m!^\d\d?\.!)
				{
				$self->{CURRENT_LINE} = "$self->{OLNUMBER}. $text" . $self->{CURRENT_LINE};
				$self->{OLNUMBER} += 1;
				}
			else
				{
				$self->{CURRENT_LINE} .= $text;
				}
			}
		}
	}

sub StartListItemProperly {
	my ($self, $text, $listType) = @_;
	
	if ($listType eq 'ul')
		{
		if (index($text, " - ") != 0)
			{
			$text = " - " . $text;
			}
		}
	else # 'ol'
		{
		if ($text !~ m!^\d\d?\.!)
			{
			$text = "$self->{OLNUMBER}. $text";
			$self->{OLNUMBER} += 1;
			}
		}
	
	return($text);
	}

sub HasListStart {
	my ($text, $listType) = @_;
	my $result = 0;
	if ($listType eq 'ul')
		{
		if (index($text, " - ") == 0)
			{
			$result = 1;
			}
		}
	else # 'ol'
		{
		if ($text =~ m!^\d\d?\.!)
			{
			$result = 1;
			}
		}
	
	return($result);	
	}

{ ##### Anchor handling
my $InAnchor;
my $AnchorText;
my $Href;
my $Name;
my $Id;

sub InitAnchorHandling {
	$InAnchor = 0;
	$AnchorText = '';
	$Href = '';
	$Name = '';
	$Id = '';
	}

sub InAnchor {
	return($InAnchor);
	}

sub AnchorTextIsEmpty {
	return($AnchorText eq '');
	}

sub StartAnchor {
	my ($href, $name, $id) = @_;
	$InAnchor = 1;
	$AnchorText = '';
	$Href = $href;
	$Name = $name;
	$Id = $id;
	}

sub AddAnchorText {
	my ($text) = @_;
	$AnchorText .= $text;
	}

# On </a>, return entire <a...>text</a> element.
sub EndAnchor {
	my ($headingLevel) = @_;

	$InAnchor = 0;

	# If we're in a heading, just return the text.
	if ($headingLevel)
		{
		return($AnchorText);
		}
	
	my $wholeAnchor = '';

	if ($Name ne '' || $Id ne '')
		{
		my $refOrId = '';

		if ($Name ne '')
			{
			# Encode to match href elsewhere.
			$Name =~ s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%02X", ord $1 /eg;
			$refOrId = 'id=' . $Name;
			}
		else
			{
			# Encode to match href elsewhere.
			$Id =~ s/([^^A-Za-z0-9\-_.!~*'()])/ sprintf "%%%02X", ord $1 /eg;
			$refOrId = 'id=' . $Id;
			}

		$wholeAnchor = '_ALB_' . $AnchorText . '_ARB_' . '_ALP_' . $refOrId . '_ARP_';
		}
	elsif ($Href ne '')
		{
		my $refOrId = 'href=' . $Href;
		$wholeAnchor = '_LB_' . $AnchorText . '_RB_' . '_LP_' . $refOrId . '_RP_';
		}
	#else # unknown, probably a maintenance error
	
	return($wholeAnchor);
	}
} ##### Anchor handling

# HTML block tags, from (blush) https://www.w3schools.com/html/html_blocks.asp.
# Note some values are 0, we don't push a line for those.
sub InitBlockTags {
    $blockTag{'address'} = 1;
    $blockTag{'article'} = 1;
    $blockTag{'aside'} = 1;
    $blockTag{'blockquote'} = 1;
    $blockTag{'canvas'} = 1;
    $blockTag{'dd'} = 1;
    $blockTag{'div'} = 1;
    $blockTag{'dl'} = 0;
    $blockTag{'dt'} = 1;
    $blockTag{'fieldset'} = 1;
    $blockTag{'figcaption'} = 1;
    $blockTag{'figure'} = 1;
    $blockTag{'footer'} = 1;
    $blockTag{'form'} = 1;
    $blockTag{'h1'} = 1;
    $blockTag{'h2'} = 1;
    $blockTag{'h3'} = 1;
    $blockTag{'h4'} = 1;
    $blockTag{'h5'} = 1;
    $blockTag{'h6'} = 1;
    $blockTag{'header'} = 1;
    $blockTag{'hr'} = 1;
    $blockTag{'li'} = 1;
    $blockTag{'main'} = 1;
    $blockTag{'nav'} = 1;
    $blockTag{'noscript'} = 1;
    $blockTag{'ol'} = 0;
    $blockTag{'p'} = 1;
    $blockTag{'pre'} = 0;
    $blockTag{'section'} = 1;
    $blockTag{'table'} = 1;
    $blockTag{'tfoot'} = 1;
    $blockTag{'ul'} = 0;
    $blockTag{'video'} = 1;
    }

sub IsBlockTag {
    my ($tag) = @_;
    my $result = defined($blockTag{$tag}) ? 1 : 0;
    return($result);
    }

# We don't want to emit a line for dl dt or pre.
sub IsPushTag {
    my ($tag) = @_;
    my $result = defined($blockTag{$tag}) ? $blockTag{$tag} : 0;
    return($result);
    }

# For encoding name and id.
sub get_encoded_char {
    my ($char) = @_;
  return $ENCMAP{enc_map}->{$char} if exists $ENCMAP{enc_map}->{$char};
  return $char;
}

1;

