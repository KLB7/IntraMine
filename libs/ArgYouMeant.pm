# ArgYouMeant.pm: a quick way to set many options on the fly in a dialog.
# A bit plain looking, but the getting and setting of variables and the
# layout are taken care of for you. This is especially handy for
# configuration dialogs that only you will ever use.
# See extract_method.pl for a working example.
#
# Let's say you have all the config details for a batch program in
# a hash "%Config" with readable keys, such as $Config{'NUMBER OF PASSES'},
# $Config{'REPORT TITLE'} etc:
#my $AYM = ArgYouMeant->new('CONFIG');
#$AYM->AddNote("CHECK ALL config values before running.");
#foreach my $key (sort keys %Config)
#	{
#	$AYM->AddVar($key, \$Config{$key});
#	}
#$AYM->DoDialog(); # view/change all %Config default values
# -and after DoDialog(), %Config's values reflect any changes you made.
#
# Nano-manual: use ArgYouMeant; call AddVar() for each variable that wants
# setting, passing along a description, reference to the variable, and type
# (Bool, Float, String etc); and call DoDialog() to view and set the variables.
# If you need to pick from a list, use AddListVar() instead of AddVar().
# For the options of either re-tuning the values after viewing a summary or
# just bailing out, call DoDialogUntilHappy() instead of DoDialog().
#
# Advantages: plain English variable names, nearly full type safety,
# optional confirmation of values with changes marked, no layout fussing.
# Note, print goes to STDERR, in case STDOUT is redirected. If you are
# redirecting STDERR as well, you can still call DoDialog, but don't call
# DumpValues() or DoDialogUntilHappy().
#
# Main functions:
# new('window title'): make an ArgYouMeant
# AddVar: pass description, reference to variable, type of variable
#   - StringType() takes two lines, one for description and one for value.
# AddListVar: pass description, reference to variable, ref to array holding list
# AddNote: if you want a brief description at top of dialog
# DoDialog: dialog to show and set values for all variables added
# DumpValues: show values after setting
#   - Dumped values show changed values with ***
# DoDialogUntilHappy: DoDialog/DumpValues, repeated until you say 'y' or 'exit'.
#
# The number of variables is limited by the height of your screen. But if you
# have a LOT of variables, you can start over at the top of a new column
# by calling NewColumn().
#
# Installation (PPM):
# install Tk-BrowseEntry
# Installation (CPAN):
# cpan Tk::BrowseEntry
#
# Store ArgYouMeant.pm file anywhere you like, eg as
# C:/mylibs/other/ArgYouMeant.pm
# and in your main Perl program put
### use lib 'C:/mylibs/other';
### use ArgYouMeant;
#
# Big tip: when calling AddVar, don't forget the \ on the variable being set.
#
# ######################## Example of use:
# use lib 'C:/my path to/ArgYouMeant folder';
# use ArgYouMeant; # full path 'C:/my path to/ArgYouMeant folder/ArgYouMeant.pm'
#my $AYM = ArgYouMeant->new('Program name etc for dialog title');
#$AYM->AddNote("Brief description of program, optional"); # shows at top of window
#my $YesNo = 0;
#$AYM->AddVar("Boolean variable to be set to 1 or 0", \$YesNo, $AYM->Bool());
#my $IntVariable = 1;
#$AYM->AddVar("Integer variable to be set", \$IntVariable, $AYM->Whole());
#my $FloatVariable = 3.5;
#$AYM->AddVar("FP variable to be set", \$FloatVariable, $AYM->Float());
#my $dummyStringParam = "This is a dummy string value\nspread over two lines";
#$AYM->AddVar("Test of a string variable:", \$dummyStringParam, $AYM->String());
#my $dummyStringParam2 = "The boy stood on the burning deck...";
#$AYM->AddVar("Another string, this time on one line:", \$dummyStringParam2, $AYM->String());
#
#$AYM->NewColumn();
#$AYM->AddBlank();
#
#my @DummyList = ('one', 'two', 'three', 'four');
#my $valueFromList = 'two';
#$AYM->AddListVariable("Test of a list variable", \$valueFromList, \@DummyList);
#my $dummyDate = '2008/11/27'; # note format must be yyyy/mm/dd
#$AYM->AddVar("Test of a date variable", \$dummyDate, $AYM->DateType());
#my $dummyColor = '#d0bbee';
#$AYM->AddVar("Test of a color variable", \$dummyColor, $AYM->ColorType());
#my $dirInFileOut = 'C:/Perl/html';
#$AYM->AddVar("Pick yourself a nice file to play with", \$dirInFileOut);
#$AYM->DoDialog(); # shows window where above variables can be adjusted
#$AYM->DumpValues();# prints values of above variabless after setting, to STDERR
# ######################## End
# -or, instead of DoDialog()/DumpValues():
# $AYM->DoDialogUntilHappy(); # DoDialog/DumpValues until you say 'y' or 'exit'.
#

package ArgYouMeant;

use strict;
use warnings;

# Linux vs Windows. Only _PickFile() is affected.
my $kWINDOWS = 0;    # See just below....
BEGIN {
	# 1 == Windows, 0 == Linux or other
	#	$kWINDOWS = ($^O =~ m!win!i);
	if ($kWINDOWS)
		{
		# Aug 2012, OpenDialog() fails if have two or more file pickers
		# - reverting to builtin FileSelect();
		#		eval "use Win32::FileOp qw(OpenDialog)";
		#		print("Using  Win32::FileOp qw(OpenDialog)\n");
		}
}

use Tk;
use Tk::BrowseEntry;
use Tk::Wm;
#use Tk::DateEntry; # Dates no longer supported for Strawberry Perl, the need to
# install fribidi is too silly.

my $tempInccer = 0;
my $kBOOLEAN   = $tempInccer++;    # 0 1
my $kINTEGER   = $tempInccer++;    # 0 1 2 ...
my $kNUMBER    = $tempInccer++;    # float, eg 3.5
my $kSTRING    = $tempInccer++;    # arb text, eg file name
my $kCOLOR     = $tempInccer++;    # show color picker
my $kLIST      = $tempInccer++;    # show list to pick from
my $kDATE      = $tempInccer++;    # show calendar. NOTE date must be 'yyyy/mm/dd/'
my $kFILE      = $tempInccer++;    # show FileOp::OpenDialog
my $kBLANK     = $tempInccer++;    # do-nothing blank, just for spacing

my $kFont             = 'Courier 10 roman';         #'Arial 8 roman'; or as you like it
my $kFontItalic       = 'Courier 10 bold italic';
my $kNumberFieldWidth = 11;                         # in characters
my $kCheckWidth       = $kNumberFieldWidth - 2;     # ditto

# Make a new ArgYouMeant instance, optional window title.
# my $AYM = ArgYouMeant->new('Title of My Nifty Program');
sub new {
	my ($proto, $title) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};
	$self->{'PROGRAM_NAME'}      = defined($title) ? $title : 'current program';
	$self->{'FONT'}              = $kFont;
	$self->{'STRING_LABEL_FONT'} = $kFontItalic;
	$self->{'NUMBER_WIDTH'}      = $kNumberFieldWidth;
	$self->{'CHECK_WIDTH'}       = $kCheckWidth;

	# Alternating row colours, with distinctive colors for text controls
	# since they spread over two rows.
	$self->{'FIRST_ROW_COLOR'}        = '#FBF6D7';
	$self->{'SECOND_ROW_COLOR'}       = '#F2F5CD';
	$self->{'FIRST_ROW_COLOR_STR'}    = '#FAE6FE';
	$self->{'SECOND_ROW_COLOR_STR'}   = '#F6D8FC';
	$self->{'FIRST_ROW_COLOR_STR_2'}  = '#EFFBFF';
	$self->{'SECOND_ROW_COLOR_STR_2'} = '#DDF6FD';

	$self->{'LAST_COLUMN'} = 0;

	$self->{'HELP'} = '';

	bless($self, $class);
	return $self;
}

########### Supported Variable Types ############
# NOTE the variable type can be left out when calling AddVar for all except
# Bool variables, but results might not be perfect - a string with initial
# value of '2009/01/07' will be treated as a date, for example.
# Boolean: 1 0
# my $YesNo = 0;
# $AYM->AddVar("Bolean variable to be set to 1 or 0", \$YesNo, $AYM->Bool());
sub BooleanType {return $kBOOLEAN;}
sub Bool        {return $kBOOLEAN;}

# Whole number: 0 1 2 ...
# my $IntVariable = 1;
# $AYM->AddVar("Integer variable to be set", \$IntVariable, $AYM->Whole());
sub IntegerType {return $kINTEGER;}
sub Int         {return $kINTEGER;}
sub Whole       {return $kINTEGER;}

# Floating point (exponent allowed).
# my $FloatVariable = 3.5;
# $AYM->AddVar("FP variable to be set", \$FloatVariable, $AYM->Float());
sub NumberType {return $kNUMBER;}
sub Number     {return $kNUMBER;}
sub Float      {return $kNUMBER;}

# Arbitrary string.
# my $dummyStringParam = "This is a dummy string value";
# $AYM->AddVar("Test of a string variable", \$dummyStringParam, $AYM->String());
sub StringType {return $kSTRING;}
sub String     {return $kSTRING;}

# Tk color, eg '#ff88aa'.
# my $dummyColor = '#d0bbee'; # wasn't he in Harry Potter?
# $AYM->AddVar("Test of a colour variable", \$dummyColor, $AYM->ColorType());
sub ColorType {return $kCOLOR;}
sub Color     {return $kCOLOR;}

# Choice from list: note list must be added via AddListVar, not AddVar.
# my @DummyList = ('one', 'two', 'three', 'four');
# my $valueFromList = 'two';
# $AYM->AddListVariable("Test of list variable", \$valueFromList, \@DummyList);
sub ListType {return $kLIST;}
sub List     {return $kLIST;}

# Date: NOTE date must be 'yyyy/mm/dd/'
# my $dummyDate = '2008/11/27'; # note format must be yyyy/mm/dd
# $AYM->AddVar("Test of a date variable", \$dummyDate, $AYM->DateType());
sub DateType {return $kDATE;}
sub Date     {return $kDATE;}
sub YMD      {return $kDATE;}

# File (path).
# my $dirInFileOut = 'C:/Perl/html'; # pass directory, set path in dialog
# $AYM->AddVar("Pick a file", \$dirInFileOut, $AYM->FileType());
sub FileType {return $kFILE;}
sub File     {return $kFILE;}
sub FilePath {return $kFILE;}
sub FullPath {return $kFILE;}

# Blank placeholder, just for alignment. If you're fussy about such things....
# Pass undef as the $valueRef, eg
# $AYM->AddVar("", undef, $AYM->Blank());
# or you can leave out the type
# $AYM->AddVar("", undef);
# or even leave out all args
# $AYM->AddVar(); # $kBLANK by default
sub Blank {return $kBLANK;}

##################################################
# If you have a LOT of variables, you can add a column on the right.
# NewColumn: after this call, AddVar and AddListVar entries will
# appear in the new column on the right, starting at the top.
# $AYM->NewColumn();
sub NewColumn {
	my ($self) = @_;
	# Two grid columns are used for each 'dialog' column, so dialog column
	# 0 corresponds to grid columns 0 and 1, dialog column 1 to grid 2 and 3.
	$self->{'LAST_COLUMN'} += 1;
}

# Use to add all types except $kLIST to dialog. See example at file top.
# OK, here's one example:
#my $IntVariable = 1;
#$AYM->AddVar("Integer variable to be set", \$IntVariable, $AYM->Int());
# The '$type' such as $AYM->Int(), is optional EXCEPT for ->Bool() variables,
# but it's safer to supply it.
sub AddVariable {
	my ($self, $description, $valueRef, $type) = @_;
	$description ||= '';
	push @{$self->{'VARS'}->{'DESCRIPTIONS'}}, $description;
	push @{$self->{'VARS'}->{'VAR_REFS'}},     $valueRef;
	if (defined($valueRef))
		{
		push @{$self->{'VARS'}->{'ORIGINAL_VALUES'}}, $$valueRef;
		}
	else
		{
		push @{$self->{'VARS'}->{'ORIGINAL_VALUES'}}, undef;
		}
	if (!defined($type))
		{
		if (!defined($valueRef))
			{
			$type = $kBLANK;
			}
		else
			{
			$type = _InferTypeFromValue($$valueRef);
			}
		}
	push @{$self->{'VARS'}->{'VAR_TYPES'}}, $type;
	push @{$self->{'VARS'}->{'LISTS'}},     '';
	push @{$self->{'VARS'}->{'COLUMN'}},    $self->{'LAST_COLUMN'};
}

# Just a synonym for AddVariable.
sub AddVar {
	my ($self, $description, $valueRef, $type) = @_;
	AddVariable($self, $description, $valueRef, $type);
}

# Add a blank entry, to adjust spacing.
# $AYM->AddBlank();
# [$AYM->AddVar(); also works.]
sub AddBlank {
	my ($self) = @_;
	AddVar($self);
}

# "Boolean" is the only type where type inference can't be done,
# so for clarity you can call this function instead of AddVar.
# my $IsItRaining = 0;
# $AYM->AddBool("Is is raining?", \$IsItRaining);
## Using AddVar instead:
## $AYM->AddVar("Is is raining?", \$IsItRaining, $AYM->Bool());
sub AddBool {
	my ($self, $description, $valueRef) = @_;
	AddVar($self, $description, $valueRef, Bool());
}

# A synonym for AddBool.
sub AddBoolean {
	my ($self, $description, $valueRef) = @_;
	AddBool($self, $description, $valueRef);
}

# If the initial value is "3.9" then it's a $kNUMBER, if the value
# is "2009/01/23" then it's a $kDATE, etc.
# No $kBOOLEAN returned, since distinguishing bool from int can't be done reliably.
sub _InferTypeFromValue {
	my ($value) = @_;
	my $type = $kSTRING;

	if (!defined($value))
		{
		$type = $kBLANK;
		}
	elsif ($value =~ m!^\s*\d+\s*$!)
		{
		$type = $kINTEGER;
		}
	elsif ($value =~ m!^\s*[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?\s*$!)
		{
		$type = $kNUMBER;
		}
	elsif ($value =~ m!^\d\d\d\d/\d\d/\d\d$!)
		{
		$type = $kDATE;
		}
	elsif ($value =~ m!^\#[A-F0-9]+$!i)
		{
		$type = $kCOLOR;
		}
	elsif ($value =~ m!^[A-Z]\:[\\/]!i)
		{
		$value =~ s!^[A-Z]\:[\\/]!!i;
		if ($value !~ m![\<\>:"|?*]!)    # < > : " | ? *
			{
			$type = $kFILE;
			}
		}
	# else treat as $kSTRING.

	return $type;
}

# Add variable, with values from a list (forces type to $kLIST).
# In the dialog you can pick a value for the variable from the dropdown
# list, or type anything you want. The initial value doesn't have to be
# on the list either.
# my @SomeList = ('one', 'two', 'three', 'four');
# my $valueFromList = 'two';
# $AYM->AddListVariable("Test of a list variable", \$valueFromList, \@SomeList);
sub AddListVariable {
	my ($self, $description, $valueRef, $list) = @_;
	push @{$self->{'VARS'}->{'DESCRIPTIONS'}},    $description;
	push @{$self->{'VARS'}->{'VAR_REFS'}},        $valueRef;
	push @{$self->{'VARS'}->{'ORIGINAL_VALUES'}}, $$valueRef;
	push @{$self->{'VARS'}->{'VAR_TYPES'}},       $kLIST;
	push @{$self->{'VARS'}->{'LISTS'}},           $list;
	push @{$self->{'VARS'}->{'COLUMN'}},          $self->{'LAST_COLUMN'};
}

# A synonym for AddListVariable.
sub AddListVar {
	my ($self, $description, $valueRef, $list) = @_;
	AddListVariable($self, $description, $valueRef, $list);
}

# Only one note can be added - shown at top of window.
sub AddNote {
	my ($self, $note) = @_;
	$self->{'VARS'}->{'NOTE'} = $note;
}

# Very long note? Use AddHelp() instead of AddNote(), and the text
# instructions will be shown in a new window called "Instructions and help"
# when user clicks the Help button.
# If AddHelp() is not called, no Help button is shown.
sub AddHelp {
	my ($self, $helpText) = @_;
	$self->{'HELP'} = $helpText;
}

# Do the setting dialog, for all added variables and lists.
sub DoDialog {
	my ($self) = @_;
	_DoSetVarsDialog($self);
}

# Show setting dialog, dump values, ask for confirmation and repeat while
# answer is not 'y'. Die if reply contains certain words (stop exit die).
sub DoDialogUntilHappy {
	my ($self) = @_;
	my $doItAgain = 1;
	while ($doItAgain)
		{
		_DoSetVarsDialog($self);
		DumpValues($self);
		$doItAgain = !_UserAnswersYes("Are you happy with the values?");
		}
}

# 1 if y or Y or Yes etc, 0 if n or N or No, die if see certain words.
sub _UserAnswersYes {
	my ($question) = @_;
	print STDERR ("$question (y/n/quit)\n");
	my $response = <STDIN>;
	my $result   = 1;
	if ($response =~ m!n!i || $response !~ m!y!i)
		{
		if ($response =~ m!stop|cra|exit|die|abort|quit!i)    # no n or y here please
			{
			die(" *** This run has been stopped at your request *** ");
			}
		$result = 0;
		}
	return $result;
}

# Create and show dialog with controls to set all variables.
# Called by DoDialog() and DoDialogUntilHappy().
sub _DoSetVarsDialog {
	my ($self)          = @_;
	my $descriptions    = $self->{'VARS'}->{'DESCRIPTIONS'};    # array ref
	my $numDescriptions = @{$descriptions};
	my $valueRefs       = $self->{'VARS'}->{'VAR_REFS'};        # array ref
	my $valueTypes      = $self->{'VARS'}->{'VAR_TYPES'};       # array ref
	my $listRefs        = $self->{'VARS'}->{'LISTS'};           # array ref
	my $columnsRef      = $self->{'VARS'}->{'COLUMN'};          # array ref

	_MakeMainWindow($self);

	# Determine length of longest item description.
	my $longestLen = _LongestDescriptionLength($self);

	# Note goes first. $longestLen might become longer, to match note width.
	my $numNotes = _CreateNoteAtTop($self, \$longestLen);
	# Widths of text items and list items, set to longest found.
	$self->{'TEXT_WIDTH'} = $longestLen;
	$self->{'LIST_WIDTH'} = _LongestListItemLength($self);

	# Add controls and labels for all variables to the top window.
	my @fields;
	my @rows;
	for (my $idx = 0 ; $idx <= $self->{'LAST_COLUMN'} ; ++$idx)
		{
		$rows[$idx] = $numNotes;
		}

	for (my $idx = 0 ; $idx < $numDescriptions ; ++$idx)
		{
		my $value       = '';
		my $description = $descriptions->[$idx];
		my $valueRef    = $valueRefs->[$idx];
		my $valueType   = $valueTypes->[$idx];
		my $bg =
			($idx % 2)
			? $self->{'FIRST_ROW_COLOR'}
			: $self->{'SECOND_ROW_COLOR'};
		my $column = $columnsRef->[$idx];
		$self->{'CUR_COLUMN'} = $column;
		my $row = $rows[$column];

		if ($valueType == $kINTEGER || $valueType == $kNUMBER)
			{
			$value = _CreateNumberEntry($self, $description, $valueRef, $bg, $row);
			}
		elsif ($valueType == $kSTRING)
			{
			$bg =
				($idx % 2)
				? $self->{'SECOND_ROW_COLOR_STR'}
				: $self->{'SECOND_ROW_COLOR_STR_2'};
			my $bgText =
				($idx % 2)
				? $self->{'FIRST_ROW_COLOR_STR'}
				: $self->{'FIRST_ROW_COLOR_STR_2'};
			$value =
				_CreateStringEntry($self, $description, $valueRef, $bg, $bgText, \$rows[$column]);
			}
		elsif ($valueType == $kBOOLEAN)
			{
			$value = _CreateCheckEntry($self, $description, $valueRef, $bg, $row);
			}
		elsif ($valueType == $kCOLOR)
			{
			$value = _CreateColorEntry($self, $description, $valueRef, $bg, $row);
			}
		elsif ($valueType == $kLIST)
			{
			$value = _CreateListEntry($self, $description, $valueRef, $listRefs->[$idx], $bg, $row);
			}
		#		elsif ($valueType == $kDATE)
		#			{
		#			$value = _CreateDateEntry($self, $description, $valueRef, $bg, $row);
		#			}
		elsif ($valueType == $kFILE)
			{
			$value = _CreateFilePickerEntry($self, $description, $valueRef, $bg, $row);
			}
		elsif ($valueType == $kBLANK)
			{
			$value = _CreateBlankEntry($self, $description, $valueRef, $bg, $row);
			}
		else
			{
			die("ERROR ArgYouMeant.pm DoSetVarsDialog, unknown type |$valueType!|");
			}
		push @fields, $value;    # not always used, but needed to preserve correct array index
		$rows[$column] += 1;
		}

	$self->{'VARS'}->{'VALUE_FIELDS'} = \@fields;

	# OK and optional Help buttons, on last row. OK calls AllDone().
	my $row = 0;
	for (my $idx = 0 ; $idx <= $self->{'LAST_COLUMN'} ; ++$idx)
		{
		if ($row < $rows[$idx])
			{
			$row = $rows[$idx];
			}
		}
	++$row;

	if (defined($self->{'HELP'}) && $self->{'HELP'} ne '')
		{
		_CreateHelpButton($self, $row);
		}

	_CreateDoneButton($self, $row);

	$self->{'TOP'}->raise;
	MainLoop;
}

sub _MakeMainWindow {
	my ($self) = @_;
	my $top = MainWindow->new();
	$top->configure(-bg => '#EEEEEE');
	$self->{'TOP'} = $top;
	my $windowTitle = "$self->{'PROGRAM_NAME'}";
	$top->title($windowTitle);

	# https://comp.lang.perl.misc.narkive.com/Qp587C51/bringing-a-process-to-foreground
	$top->after(500, sub {$top->attributes(-topmost => 1)});
}

# Return length of longest item description (or string value).
sub _LongestDescriptionLength {
	my ($self)          = @_;
	my $descriptions    = $self->{'VARS'}->{'DESCRIPTIONS'};    # array ref
	my $numDescriptions = @{$descriptions};
	my $valueRefs       = $self->{'VARS'}->{'VAR_REFS'};        # array ref
	my $valueTypes      = $self->{'VARS'}->{'VAR_TYPES'};       # array ref

	my $longestLen = 0;
	for (my $i = 0 ; $i < $numDescriptions ; ++$i)
		{
		my $description = $descriptions->[$i];
		my $len         = length($description);
		if ($longestLen < $len)
			{
			$longestLen = $len;
			}
		my $valueType = $valueTypes->[$i];
		if ($valueType == $kSTRING)
			{
			my $valueRef    = $valueRefs->[$i];
			my $valueLength = length($$valueRef);
			}
		}

	return $longestLen;
}

# Return length of longest list item (10 chars minimum).
sub _LongestListItemLength {
	my ($self)          = @_;
	my $descriptions    = $self->{'VARS'}->{'DESCRIPTIONS'};    # array ref
	my $numDescriptions = @{$descriptions};
	my $valueTypes      = $self->{'VARS'}->{'VAR_TYPES'};       # array ref
	my $listRefs        = $self->{'VARS'}->{'LISTS'};           # array ref

	my $longestListItemLen = 10;
	for (my $i = 0 ; $i < $numDescriptions ; ++$i)
		{
		my $valueType = $valueTypes->[$i];
		if ($valueType == $kLIST)
			{
			my $list           = $listRefs->[$i];
			my $numListEntries = @{$list};
			for (my $e = 0 ; $e < $numListEntries ; ++$e)
				{
				my $len = length($list->[$e]);
				if ($longestListItemLen < $len)
					{
					$longestListItemLen = $len;
					}
				}
			}
		}

	return $longestListItemLen;
}

# Put text of note at top of dialog across all columns. Adjusts $longestLen.
sub _CreateNoteAtTop {
	my ($self, $longestLenR) = @_;
	my $numNotes = 0;
	if (defined($self->{'VARS'}->{'NOTE'}))
		{
		my $note = $self->{'VARS'}->{'NOTE'};
		my $firstLineLen;
		if ($note =~ m!^(.+?)(\n)!)
			{
			$firstLineLen = length($1);
			}
		else
			{
			$firstLineLen = length($note);
			}

		my $top   = $self->{'TOP'};
		my $label = $top->Label(
			-text    => $note,
			-justify => 'left',
			-width   => $firstLineLen,
			-anchor  => 'w',
			-bg      => '#EEEEEE',
			-font    => $self->{'FONT'}
		);
		$label->grid(
			-row        => 0,
			-column     => 0,
			-columnspan => ($self->{'LAST_COLUMN'} + 1) * 2,
			-sticky     => 'w'
		);
		my $labelWidth = $label->cget('-width');
		if ($$longestLenR < $labelWidth - $self->{'NUMBER_WIDTH'})
			{
			$$longestLenR = $labelWidth - $self->{'NUMBER_WIDTH'};
			}
		$numNotes = 1;
		}

	return $numNotes;
}

# Just a spacer, for alignment.
sub _CreateBlankEntry {
	my ($self, $description, $valueRef, $bgColour, $gridRow) = @_;

	my $top   = $self->{'TOP'};
	my $label = $top->Label(
		-text   => ' ',
		-font   => $self->{'FONT'},
		-width  => $self->{'TEXT_WIDTH'},
		-height => 1,
		-anchor => 'w',
		-bg     => $bgColour
	);
	$label->grid(
		-row    => $gridRow,
		-column => ($self->{'CUR_COLUMN'} * 2) + 1,
		-sticky => 'w'
	);

	return undef;
}

# Create int or float description and value controls.
sub _CreateNumberEntry {
	my ($self, $description, $valueRef, $bgColour, $gridRow) = @_;

	my $top   = $self->{'TOP'};
	my $value = $top->Text(
		-height => 1,
		-wrap   => 'none',
		-state  => 'normal',
		-font   => $self->{'FONT'},
		-width  => $self->{'NUMBER_WIDTH'}
	);
	$value->Contents($$valueRef);
	$value->grid(
		-row    => $gridRow,
		-column => $self->{'CUR_COLUMN'} * 2,
		-sticky => 'w'
	);

	my $label = $top->Label(
		-text   => $description,
		-font   => $self->{'FONT'},
		-width  => $self->{'TEXT_WIDTH'},
		-height => 1,
		-anchor => 'w',
		-bg     => $bgColour
	);
	$label->grid(
		-row    => $gridRow,
		-column => ($self->{'CUR_COLUMN'} * 2) + 1,
		-sticky => 'w'
	);

	return $value;
}

# Create checkbox control for a Boolean variable.
sub _CreateCheckEntry {
	my ($self, $description, $valueRef, $bgColour, $gridRow) = @_;

	my $top   = $self->{'TOP'};
	my $value = $top->Checkbutton(
		-text     => $description,
		-font     => $self->{'FONT'},
		-width    => $self->{'TEXT_WIDTH'} + $self->{'CHECK_WIDTH'},
		-anchor   => 'w',
		-bg       => $bgColour,
		-variable => $valueRef
	);
	$value->grid(
		-row        => $gridRow,
		-column     => $self->{'CUR_COLUMN'} * 2,
		-columnspan => 2,
		-sticky     => 'w'
	);

	return $value;
}

# Create color picker button.
sub _CreateColorEntry {
	my ($self, $description, $valueRef, $bgColour, $gridRow) = @_;

	my $top          = $self->{'TOP'};
	my $buttonColour = $$valueRef;
	my $value        = $top->Button(
		-text   => '    Pick Color    ',
		-anchor => 'w',
		-bg     => $buttonColour
	);
	$value->configure(-command => [\&_PickColor, $top, $value, $valueRef]);
	$value->grid(
		-row    => $gridRow,
		-column => $self->{'CUR_COLUMN'} * 2,
		-sticky => 'w'
	);

	my $label = $top->Label(
		-text   => $description,
		-font   => $self->{'FONT'},
		-width  => $self->{'TEXT_WIDTH'},
		-height => 1,
		-anchor => 'w',
		-bg     => $bgColour
	);
	$label->grid(
		-row    => $gridRow,
		-column => ($self->{'CUR_COLUMN'} * 2) + 1,
		-sticky => 'w'
	);

	return $value;
}

# Create date picker.
#sub _CreateDateEntry {
#	my ($self, $description, $valueRef, $bgColour, $gridRow) = @_;
#
#	my $top = $self->{'TOP'};
#	my ($yyyy, $mm, $dd) = split(/\//, $$valueRef);
#	my $value = $top->DateEntry(-text => "$mm/$dd/$yyyy");
#	$value->grid(-row => $gridRow, -column => $self->{'CUR_COLUMN'} * 2,
#				 -sticky => 'w');
#
#	my $label = $top->Label(	-text	 	 => $description,
#								-font		 => $self->{'FONT'},
#								-width		 => $self->{'TEXT_WIDTH'},
#								-height		 => 1,
#								-anchor		 => 'w',
#								-bg			 => $bgColour);
#	$label->grid(-row => $gridRow, -column => ($self->{'CUR_COLUMN'} * 2) + 1,
#				 -sticky => 'w');
#
#	return $value;
#	}

# Create file picker. $$valueRef should be set to a default directory intially,
# and holds a full file path if the user selects a file.
sub _CreateFilePickerEntry {
	my ($self, $description, $valueRef, $bgColour, $gridRow) = @_;
	my $top   = $self->{'TOP'};
	my $value = $top->Button(
		-text   => '    Select File    ',
		-anchor => 'w'
	);
	$value->configure(-command => [\&_PickFile, $top, $value, $valueRef, $self]);
	$value->grid(
		-row    => $gridRow,
		-column => $self->{'CUR_COLUMN'} * 2,
		-sticky => 'w'
	);

	my $label = $top->Label(
		-text   => $description,
		-font   => $self->{'FONT'},
		-width  => $self->{'TEXT_WIDTH'},
		-height => 1,
		-anchor => 'w',
		-bg     => $bgColour
	);
	$label->grid(
		-row    => $gridRow,
		-column => ($self->{'CUR_COLUMN'} * 2) + 1,
		-sticky => 'w'
	);

	return $value;
}

# Create string editor, description followed by edit field on next line.
sub _CreateStringEntry {
	my ($self, $description, $valueRef, $bgColour, $bgText, $gridRowR) = @_;

	my $top            = $self->{'TOP'};
	my $labelWidth     = $self->{'TEXT_WIDTH'} + $self->{'NUMBER_WIDTH'} / 2;
	my $textEntryWidth = $self->{'TEXT_WIDTH'} + $self->{'NUMBER_WIDTH'} + 1;
	my $label          = $top->Label(
		-text   => $description,
		-font   => $self->{'STRING_LABEL_FONT'},
		-width  => $labelWidth,
		-height => 1,
		-anchor => 'w',
		-fg     => '#666666',
		-bg     => $bgColour
	);
	$label->grid(
		-row        => $$gridRowR,
		-column     => $self->{'CUR_COLUMN'} * 2,
		-columnspan => 2,
		-sticky     => 'w'
	);

	$$gridRowR += 1;

	my $numNewLines = ($$valueRef =~ tr!\n!\n!);
	my $height      = 1 + $numNewLines;
	my $value       = $top->Text(
		-height => $height,
		-wrap   => 'none',
		-state  => 'normal',
		-bg     => $bgText,
		-font   => $self->{'FONT'},
		-width  => $textEntryWidth
	);
	$value->Contents($$valueRef);
	$value->grid(
		-row        => $$gridRowR,
		-column     => $self->{'CUR_COLUMN'} * 2,
		-columnspan => 2,
		-sticky     => 'w'
	);

	return $value;
}

# Create dropdown list/edit combo control.
sub _CreateListEntry {
	my ($self, $description, $valueRef, $list, $bgColour, $gridRow) = @_;

	my $top   = $self->{'TOP'};
	my $value = $top->BrowseEntry(
		-variable      => $valueRef,
		-choices       => $list,
		-autolistwidth => 1,
		-width         => $self->{'LIST_WIDTH'}
	);
	$value->grid(
		-row    => $gridRow,
		-column => $self->{'CUR_COLUMN'} * 2,
		-sticky => 'w'
	);

	my $label = $top->Label(
		-text   => $description,
		-font   => $self->{'FONT'},
		-width  => $self->{'TEXT_WIDTH'},
		-height => 1,
		-anchor => 'w',
		-bg     => $bgColour
	);
	$label->grid(
		-row    => $gridRow,
		-column => ($self->{'CUR_COLUMN'} * 2) + 1,
		-sticky => 'w'
	);

	return $value;
}

# OK button, fires AllDone() when clicked.
sub _CreateDoneButton {
	my ($self, $gridRow) = @_;

	my $top        = $self->{'TOP'};
	my $doneButton = $top->Button(
		-text    => '                    OK',
		-anchor  => 'center',
		-bg      => '#0CBA0C',
		-command => [\&_AllDone, $self]
	);
	$doneButton->grid(
		-row    => $gridRow,
		-column => ($self->{'LAST_COLUMN'} * 2) + 1,
		-sticky => 'e',
		-padx   => 10
	);

	$doneButton->bind("<Enter>", [\&_EnterButton, $doneButton]);
	$doneButton->bind("<Leave>", [\&_LeaveButton, $doneButton]);
}

sub _CreateHelpButton {
	my ($self, $gridRow) = @_;

	my $top        = $self->{'TOP'};
	my $helpButton = $top->Button(
		-text    => 'Help',
		-anchor  => 'center',
		-bg      => '#0CBA0C',
		-command => [\&_ShowHelpWindow, $self]
	);
	$helpButton->grid(
		-row    => $gridRow,
		-column => 0,
		-sticky => 'e',
		-padx   => 10
	);

	$helpButton->bind("<Enter>", [\&_EnterButton, $helpButton]);
	$helpButton->bind("<Leave>", [\&_LeaveButton, $helpButton]);
}

# Tk color picker.
sub _PickColor {
	my ($top, $button, $colorRef) = @_;
	my $newColor = $top->chooseColor(
		-initialcolor => $$colorRef,
		-title        => "Choose color"
	);
	if (defined($newColor))
		{
		$$colorRef = $newColor;
		$button->configure(-bg => $$colorRef);
		}
}

# Open dialog, to select a file.
sub _PickFile {
	my ($top, $button, $dirInFileOutRef, $self) = @_;
	my $defaultDirectory = $$dirInFileOutRef;
	$defaultDirectory =~ s!/!\\!g;

	my $fselResult = undef;
	if ($kWINDOWS)
		{
		$fselResult = OpenDialog({handle => 0, dir => $defaultDirectory});
		}
	else
		{
		my $fsel = $self->{'TOP'}->FileSelect(
			-directory    => $defaultDirectory,
			-filelabel    => 'Double-click on a file',
			-dirlabel     => 'Current Directory',
			-dirlistlabel => 'Subdirectories',
			-acceptlabel  => 'Open',
			-create       => 0
		);
		$fselResult = $fsel->Show;
		$fsel->destroy();
		}

	if (defined($fselResult))
		{
		$fselResult =~ s!\\!/!g;
		$$dirInFileOutRef = $fselResult;
		$fselResult =~ m!/([^/]+)$!;
		my $fileName = $1;
		$button->configure(-bg => '#00FF00', -text => $fileName);
		}
}

sub _EnterButton {
	my ($button) = $_[0];
	$button->configure(-activebackground => '#0CFF0C');
}

sub _LeaveButton {
	my ($button) = $_[0];
	$button->configure(-activebackground => '#0CBA0C');
}

# Put up a separate window with help text. Shows $self->{'HELP'}, as set
# by AddHelp(), when Help button as made by _CreateHelpButton() is clicked.
sub _ShowHelpWindow {
	my ($self) = $_[0];
	my $helpWindow = MainWindow->new();
	$helpWindow->title("Instructions and help");
	my $numlines = $self->{'HELP'} =~ tr/\n/\n/;
	++$numlines;
	$numlines = 5 unless $numlines > 5;
	my $t = $helpWindow->Scrolled(
		'Text',
		-relief      => 'sunken',
		-borderwidth => 2,
		-setgrid     => 'true',
		-height      => $numlines,
		-scrollbars  => 'se',
		-bg          => 'white'
	);

	$t->pack(qw/-expand yes -fill both/);
	$t->insert('end', $self->{'HELP'});
}

# Retrieve values for all variables (where the corresponding control is not
# tied by reference to the variable).
# Called in response to 'OK' button clicked.
sub _AllDone {
	my ($self)          = $_[0];
	my $descriptions    = $self->{'VARS'}->{'DESCRIPTIONS'};    # array ref
	my $numDescriptions = @{$descriptions};
	my $valueRefs       = $self->{'VARS'}->{'VAR_REFS'};        # array ref
	my $valueTypes      = $self->{'VARS'}->{'VAR_TYPES'};       # array ref
	my $newValues       = $self->{'VARS'}->{'VALUE_FIELDS'};    # array ref

	for (my $i = 0 ; $i < $numDescriptions ; ++$i)
		{
		my $valueType = $valueTypes->[$i];
		if ($valueType == $kINTEGER || $valueType == $kNUMBER || $valueType == $kSTRING)
			{
			# Contents() always tacks on a \n for some reason.
			my $newValue = $newValues->[$i]->Contents();
			if ($valueType != $kSTRING)
				{
				if ($valueType == $kNUMBER)
					{
					# http://www.regular-expressions.info/floatingpoint.html
					if ($newValue !~ m!^\s*[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?\s*$!)
						{
						my $description = $descriptions->[$i];
						die("ERROR, value |$newValue| not a number for \"$description\"!");
						}
					}
				elsif ($valueType == $kINTEGER)
					{
					if ($newValue !~ m!^\s*\d+\s*$!)
						{
						my $description = $descriptions->[$i];
						die("ERROR, value |$newValue| not an integer for \"$description\"!");
						}
					}
				$newValue =~ s!\s+!!g;
				}
			else
				{
				chomp($newValue);
				}
			my $valueRef = $valueRefs->[$i];
			$$valueRef = $newValue;
			}
		elsif ($valueType == $kDATE)
			{
			my $date = $newValues->[$i]->get;
			my ($mm, $dd, $yyyy) = split(/\//, $date);
			if (!_GoodEnoughDate($mm, $dd, $yyyy))
				{
				my $description = $descriptions->[$i];
				die("ERROR, date |$date| looks funny \"$description\"!");
				}
			my $valueRef = $valueRefs->[$i];
			$$valueRef = "$yyyy/$mm/$dd";
			}
		elsif ($valueType == $kBOOLEAN
			|| $valueType == $kCOLOR
			|| $valueType == $kLIST
			|| $valueType == $kFILE
			|| $valueType == $kBLANK)
			{
			;    # $valueRef update is done by corresponding widget
			}
		# else other types - not implemented yet
		}

	$self->{'TOP'}->destroy();
}

# Returns 1 if m d y supplied are 'probably' parts of a good date.
sub _GoodEnoughDate {
	my ($mm, $dd, $yyyy) = @_;
	my $result = 0;

	if (   defined($yyyy)
		&& $yyyy >= 1900
		&& $yyyy <= 2100
		&& defined($mm)
		&& $mm >= 1
		&& $mm <= 12
		&& defined($dd)
		&& $dd >= 1
		&& $dd <= 31)
		{
		$result = 1;
		}
	return $result;
}

# Print all variable values. Changed ones are marked with '***'.
# Called by DoDialogUntilHappy, or call this yourself after DoDialog.
# $AYM->DumpValues();
sub DumpValues {
	my ($self)          = @_;
	my $descriptions    = $self->{'VARS'}->{'DESCRIPTIONS'};      # array ref
	my $originalValues  = $self->{'VARS'}->{'ORIGINAL_VALUES'};
	my $numDescriptions = @{$descriptions};
	my $valueRefs       = $self->{'VARS'}->{'VAR_REFS'};
	for (my $i = 0 ; $i < $numDescriptions ; ++$i)
		{
		my $description = $descriptions->[$i];
		if ($description !~ m!\:\s*$!)
			{
			$description .= ':';
			}
		my $valueRef = $valueRefs->[$i];
		if (defined($valueRef))    # not defined for $kBLANK
			{
			my $newValue      = $$valueRef;
			my $originalValue = $originalValues->[$i];
			my $changedNote   = ($newValue ne $originalValue) ? '*** ' : '';
			print STDERR ("$changedNote$description |$newValue|\n");
			}
		}
}

1;
