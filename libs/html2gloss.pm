# html2gloss.pm: convert HTML to Gloss.
# Intended for converting HTML from Pos::Simple::HTML.

package html2gloss;
use strict;
use warnings;

use HTML::Parser();
our @ISA = qw(HTML::Parser);

my %blockTag;

sub new {
    my ($proto) = @_;
    my $class = ref($proto) || $proto;

    my $self = HTML::Parser->new( api_version => 3,
        start_h => [\&startHandler, "self, tagname, attr"],
        end_h => [\&endHandler, "self, tagname"],
        text_h => [\&textHandler, "self, dtext, is_cdata" ]
        );

    bless ($self, $class);
    ###$self->unbroken_text(1);
    $self->utf8_mode(1); # ???

    $self->{DEPTH} = 0; # HTML tag nesting depth
    $self->{CURRENT_LINE} = '';
    @{$self->{LINES}} = ();
    @{$self->{CLASS}} = ();
    @{$self->{HREF}} = ();
    @{$self->{LIST_TYPE}} = ();
    $self->{OLNUMBER} = 1; # post increment
    $self->{HEADING_LEVEL} = 0;

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

# Track tag name, class and href attributes.
# Note those must be pushed and popped together.
sub startHandler {
    my ($self, $tag, $attr) = @_;

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

    if ($tag eq 'ul' || $tag eq 'ol')
        {
        push @{$self->{LIST_TYPE}}, $tag;
        }
    }

sub endHandler {
    my ($self, $tag) = @_; # $tag isn't needed
    if (!defined(${$self->{TAG}}[-1]))
        {
        return;
        }
    
    my $ptag = pop @{$self->{TAG}};
    my $class = pop @{$self->{CLASS}};
    my $href = pop @{$self->{HREF}};

    if (IsPushTag($ptag))
        {
        push @{$self->{LINES}}, $self->{CURRENT_LINE};
        $self->{CURRENT_LINE} = '';


        if ($self->{HEADING_LEVEL})
            {
            my $headingLevel = $self->{HEADING_LEVEL};
            if ($headingLevel <= 2)
                {
                push @{$self->{LINES}}, '=====';
                }
            elsif ($headingLevel == 3)
                {
                push @{$self->{LINES}}, '-----';
                }
            else
                {
                push @{$self->{LINES}}, '~~~~~';
                }
            $self->{HEADING_LEVEL} = 0;
            }
        }

    if ($ptag eq 'ul' || $ptag eq 'ol')
        {
        pop @{$self->{LIST_TYPE}};
        if ($ptag eq 'ol')
            {
            $self->{OLNUMBER} = 1;
            }
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
    
    if ($toptag ne '')
        {
        if ($toptag eq 'pre')
            {
			push @{$self->{LINES}}, '---';
            my @lines = split(/\n/, $text);
            for (my $i = 0; $i < @lines; ++$i)
                {
                push @{$self->{LINES}}, $lines[$i];
                }
			push @{$self->{LINES}}, '---';
            $self->{CURRENT_LINE} = '';
            }
        elsif ($toptag eq 'a')
            {
			# Clean out embedded new lines.
			$text =~ s!\n! !g;

            if ($tagAbove eq 'dt')
                {
                $self->{CURRENT_LINE} = '**' . $text . '**';
                }
            elsif ($tagAbove =~ m!^h(\d)$!)
                {
                my $headingLevel = $1;
                
                if (index($topClass, 'u') == 0)
                    {
                    $self->{HEADING_LEVEL} = $headingLevel;
                    }
                $self->{CURRENT_LINE} = $text;
                }
            else
                {
                my $href = ($topHref ne '') ? "$topHref" : '';
                if ($href ne '')
                    {
					# If it's an internal link ($href starts with "#")
					# then just put the (double-quoted) text and Gloss
					# will convert it to a heading link if possible.
					# Otherwise, put "[$text]($href)" and at some
					# point Gloss will be upgraded to support that.
                    my $startsWithHash = (index($href, '#') == 0);
					my $textForAutoLink;
					if ($startsWithHash)
						{
						$textForAutoLink = $text;
						if (index($text, "\"") != 0)
							{
							$textForAutoLink = '"' . $textForAutoLink . '"';
							}
						}
					else
						{
						$textForAutoLink = "[$text]($href)";
						}
                    # Sometime there's no text in a <li>, just an anchor.
                    if ($tagAbove eq 'li' && $self->{CURRENT_LINE} eq '')
                        {
                        my $listType = defined(${$self->{LIST_TYPE}}[-1]) ? ${$self->{LIST_TYPE}}[-1]: 'ul';
                        if ($listType eq 'ul')
                            {
                            $self->{CURRENT_LINE} = " - $textForAutoLink";
                            }
                        else
                            {
                            $self->{CURRENT_LINE} = "$self->{OLNUMBER}. $textForAutoLink";
                            $self->{OLNUMBER} += 1;
                            }
                        }
                    else # a regular anchor.
                        {
                        $self->{CURRENT_LINE} .= $textForAutoLink;
                        }
                    }
                else
                    {
                    # What could this be? Dunno.
                    $self->{CURRENT_LINE} .= $text
                    }		
                }
            }
        elsif ($toptag eq 'p' && $tagAbove eq 'dd')
            {
            $text =~ s!^\s*!!;
			$self->{CURRENT_LINE} .= $text;
            #my $def = ": " . $text;
            #$self->{CURRENT_LINE} .= $def;
           }
        elsif ($toptag eq 'li')
            {
            # Unordered ol or unordered ul. Or whatnot, default 'ul'.
            my $listType = defined(${$self->{LIST_TYPE}}[-1]) ? ${$self->{LIST_TYPE}}[-1]: 'ul';

            # <li> can pick up spurious empty lines, so strip them.
            if ($self->{CURRENT_LINE} =~ m!^\s*$!)
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
                $self->{CURRENT_LINE} .= $text;
                }
            }
		elsif ($toptag eq 'em' || $toptag eq 'i')
			{
			$self->{CURRENT_LINE} .= "*$text*";
			}
		elsif ($toptag eq 'strong' || $toptag eq 'b')
			{
			$self->{CURRENT_LINE} .= "**$text**";
			}
 		elsif ($toptag eq 'code' || $toptag eq 'codehere')
			{
			$self->{CURRENT_LINE} .= "***$text***";
			}
       else
            {
            # Skip all blank lines.
            if ($text !~ m!^\s*$!)
                {
				# Clean out embedded new lines.
				$text =~ s!\n! !g;
                $self->{CURRENT_LINE} .= $text;
                }

            # Skip blanks between consecutive block start tags.
            # TEST ONLY OUT

            # if (!$toptag eq 'dl')
            #    {
            #    $self->{CURRENT_LINE} .= $text;
            #    }
            }
        }
    }

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
    $blockTag{'ol'} = 1;
    $blockTag{'p'} = 1;
    $blockTag{'pre'} = 0;
    $blockTag{'section'} = 1;
    $blockTag{'table'} = 1;
    $blockTag{'tfoot'} = 1;
    $blockTag{'ul'} = 1;
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

1;

