# ho_reformat.pl
#
# $Id: ho_reformat.pl,v 1.8 2003/02/25 19:49:45 jvunder Exp $
#
# Part of the Hybrid Oper Script Collection.
#
# This script takes incoming server notices and reformats them. It then
# sends them to any window.
#
# This script uses a datafile: ~/.irssi/ho_reformat.data
#

# TODO
# - check hyb6/7 version using /quote version.
# - /set ho_prepend_servertag ON|OFF
# - /set ho_log_raw_servermsg ON|OFF
#

###########################################################################
#
# Feature description:
#
# - fully customizable server notice reformatting and redirection
#
###########################################################################

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
use Irssi::TextUI;
use Irssi::UI;
#use LWP::UserAgent;

# ======[ Script Header ]===============================================

($VERSION) = '$Revision: 1.8 $' =~ / (\d+\.\d+) /;
%IRSSI = (
    authors    => 'Garion',
    contact    => 'garion@efnet.nl',
    name    => 'ho_reformat',
    description    => 'Hybrid Oper Script Collection - server notice reformatting',
    license    => 'Public Domain',
    url        => 'http://www.garion.org/irssi/hosc.php',
    changed    => '18 January 2003 15:01:02',
);

# ======[ Credits ]=====================================================
#
# Thanks to:
# zapi - hybrid 6 data formats and feature suggestions.
# peder - helping with formatting messages.
# JamesOff - feature suggestions, code modifications.
#

# ======[ Variables ]===================================================

# The prefix that all server notices seem to have.
my $prefix = "\\\*\\\*\\\* Notice -- ";

# Irssi scripts dir.
my $scriptdir = Irssi::get_irssi_dir() . "/scripts";

# Irssi data dir.
my $datadir = Irssi::get_irssi_dir();

# The datafile.
my $datafile = "ho_reformat.data";

# Mirror for a default datafile to be downloaded when the script isn't
# able to find one.
my $datafile_mirror = "http://www.garion.org/irssi/";

# Array of server notice reformatting data.
my @serverreplaces;

# Array of formats that are registered in the current theme
my @themeformats;


# ======[ Signal hooks ]================================================

# --------[ event_serverevent ]-----------------------------------------

# A Server Event has occurred. Check if it is a server NOTICE;
# if so, process it.

sub event_serverevent {
  my ($server, $msg, $nick, $hostmask) = @_;
  my ($nickname, $username, $hostname);

  # If it is not a NOTICE, we don't want to have anything to do with it.
  if ($msg !~ /^NOTICE/) {
    return;
  }

  # For a server notice, the hostmask is empty.
  # If the hostmask is set, it is not a server NOTICE, so we'll ignore it
  # as well.
  if (length($hostmask) > 0) {
    return;
  }

  # For a server notice, the source server is stored in $nick.
  # It can happen that a server notice from a different server is sent
  # to us. This notice must not be reformatted.
  if ($nick ne $server->{real_address}) {
    return;
  }

  my $ownnick = $server->{'nick'};

  # Remove the NOTICE part from the message
  # NOTE: this is probably unnecessary.
  $msg =~ s/^NOTICE \S+ ://;

  # Remove the server prefix
  # NOTE: this is probably unnecessary.
  $msg =~ s/^$prefix//;

  # Check each notice reformatting regexp to see if this NOTICE matches
  for my $i ( 0 .. $#serverreplaces ) {

    # Check if the message matches this regexp.
    if (my @vars = $msg =~ /$serverreplaces[$i][1]/) {

      # If the replacement is only for a certain network, ignore it if
      # this is not that network.
      if ($serverreplaces[$i][3] =~ /^(\S+): /) {
        if (lc($server->{tag}) ne lc($1)) {
          next;
        }
      }

      # If the target window is or contains "devnull", the server notice
      # will be discarded. Otherwise, process it.
      if ($serverreplaces[$i][3] =~ /devnull/) {
        Irssi::signal_stop();
        last;
      }

      # Get the target windows for this message
      my @windows = split(/ +/, $serverreplaces[$i][3]);

      # Send the reformatted message to each window
      foreach my $win(@windows) {
        # Ugly hack for sort of multi network support.
        # This must be changed.
        next if ($win =~ /:$/);

        # Get the target window for this message
        # Use the active window if it's "active"
        my $targetwin;
        if ($win eq "active") {
          $targetwin = Irssi::active_win();
        } else {
          if (Irssi::settings_get_bool('ho_reformat_multinetwork')) {
            $targetwin = get_window_by_name(lc($server->{tag}) . "_" . $win);
            if (!$targetwin) {
              $targetwin = get_window_by_name($win);
            }
          } else {
            $targetwin = get_window_by_name($win);
          }
        }

        # Get the tag of this server
        my $servertag = $server->{'tag'};

        # Send the reformatted message to the window
        # But only if the target is not "<otherservertag>: win1 win2"
        my $msglevel = get_msglevel($serverreplaces[$i][4]);
        if ($serverreplaces[$i][3] =~ /^(\S+): /) {
          if (lc($1) eq lc($server->{tag})) {
            $targetwin->printformat($msglevel, "ho_r_" . $serverreplaces[$i][0],
                                $servertag, @vars);
          } else {
            #Irssi::print("blah [" . $serverreplaces[$i][3] . "][$1][".$server->{tag}
          }
        } else {
          $targetwin->printformat($msglevel, "ho_r_" . $serverreplaces[$i][0],
                                $servertag, @vars);
        }
      }

      # Stop the signal
      Irssi::signal_stop();

      # Stop matching regexps if continuematching == 0
      # More ugly hack shit. Needs to be done decently.
      if ($serverreplaces[$i][5] !~ /continuematch/) {
        last;
      }
    }
  }
}


# ======[ Helper functions ]============================================

# --------[ get_window_by_name ]----------------------------------------
# Returns the window object given in the setting ho_win_$name.

sub get_window_by_name {
  my ($name) = @_;

  # Get the reference to the window from irssi
  my $win = Irssi::window_find_name($name);

  # If not found, get the reference to window 1
  # I'm hoping that this does ALWAYS exist :)
  # But if not... how can this be improved so to ALWAYS return a valid
  # window reference?
  if (!defined($win)) {
    $win = Irssi::window_find_refnum(1);
  }

  return $win;
}

# --------[ get_msglevel ]----------------------------------------------
# Returns an integer message level from a string.
# If only MSGLEVEL_HILIGHT is returned, this will result in a double
# "-!-" at the beginning of the line.
# String HILIGHT -> return MSGLEVEL_PUBLIC | MSGLEVEL_HILIGHT
# String MSG     -> return MSGLEVEL_PUBLIC
# String NONE    -> return MSGLEVEL_PUBLIC | MSGLEVEL_NO_ACT
# Other          -> return MSGLEVEL_CLIENTCRAP

sub get_msglevel {
  my ($name) = @_;

  if ($name eq "HILIGHT") {
    return MSGLEVEL_PUBLIC | MSGLEVEL_HILIGHT;
  }

  if ($name eq "MSG") {
    return MSGLEVEL_PUBLIC;
  }

  if ($name eq "NONE") {
    return MSGLEVEL_PUBLIC | MSGLEVEL_NO_ACT;
  }

  return MSGLEVEL_CLIENTCRAP;
}

# ======[ Initialization ]==============================================

# --------[ add_formats_to_themearray ]---------------------------------
# This function stores the basic ho theme formats in @themeformats.

sub add_formats_to_themearray {
  # Later on, we can add abstracts here, using
  # Irssi::abstracts_register([key => value, ...]);
  # This, however, requires "use Irssi 20021228.1525;".

  push @themeformats, (
    'ho_crap',
    '{line_start}%Cho:%n $0',

    'ho_warning',
    '{line_start}%Cho:%n %RWarning%n $0',
  );
}


# --------[ add_event ]-------------------------------------------------
# Adds one server notice reformatting.

sub add_event {
  my ($linenum, $name, $regexp, $format,
      $winnames, $msglevel, $options) = @_;

  # Test if the regular expression is valid
  eval { /$regexp/ } ;
  if ($@) {
    Irssi::print(MSGLEVEL_CLIENTCRAP,
    "Error in regexp on line " . ($linenum) . ".");
  } else {
    push @serverreplaces, [ ($name, $regexp, $format,
                             $winnames, $msglevel, $options) ];
  }
}

# --------[ download_datafile ] ----------------------------------------
# Downloads and saves a datafile.

sub download_datafile {
  my ($datafile) = @_;

  eval { require LWP::UserAgent; };

  if ($@) {
      Irssi::print("Datafile ~/.irssi/ho_reformat.data not found. Please download one.");
    return;
  }

  import LWP::UserAgent;
  Irssi::print(
  "Datafile not found. Trying to download one from $datafile_mirror",
  MSGLEVEL_CRAP);

  # The download source is inspired from scriptassist.pl so tommie is to
  # blame for it :) -zap

  my $useragent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1,timeout => 30);
  $useragent->agent('HybridOper/'.$VERSION);
  my $request = HTTP::Request->new('GET', $datafile_mirror.'ho_reformat.data.hybrid7');

  my $response = $useragent->request($request);
  if ($response->is_success()) {
    my $file = $response->content();
    local *F;
    open(F, '>' . $datafile);
    print F $file;
    close(F);
    Irssi::print("Default datafile successfully fetched and stored in $datafile.", MSGLEVEL_CRAP);
  } else {
    Irssi::print(
    "Unable to fetch default datafile from $datafile_mirror.\n".
    "Go find one for your own. http://www.garion.org/irssi/hosc.php ".
    "may be a good start.",
    MSGLEVEL_CRAP);
  }
}

# --------[ get_all_windownames ]---------------------------------------
# Looks through all registered reformattings and checks which target
# windows are used. Ignores the windows named "active" and "devnull",
# because these are special windows. Returns the windows, in an array.

sub get_all_windownames {
  # Temporary hash to obtain all the window names
  my %tmp;

  # Set $tmp{windowname} = 1 for each different window name.
  # Then, the @keys of the hash contains an array of all the window
  # names.
  for my $i ( 0 .. $#serverreplaces ) {
    my $winnamestring = $serverreplaces[$i][3];

    # Each window name string can consist of multiple window names,
    # space separated.
    my @windownames = split(/ +/, $winnamestring);

    # Set the tmp hash value to 1 using each window name as key.
    foreach my $windowname (@windownames) {
      $windowname =~ s/^ +//;
      $windowname =~ s/ +$//;

      # Don't add "active" or "devnull"
      if ($windowname ne "active" && $windowname ne "devnull") {
        $tmp{$windowname} = 1;
      }
    }
  }

  # Get the array of window names.
  my @windownames = keys(%tmp);

  return @windownames;
}

# --------[ get_missing_windownames ]-----------------------------------
# Returns an array of the target windows that are used, but that aren't
# present in the irssi client.

sub get_missing_windownames {
  my @windownames = get_all_windownames();
  my @winnotfound = ();

  # Put the not found windows in an array.
  foreach my $windowname (@windownames) {
    my $win = Irssi::window_find_name($windowname);
    if (!defined($win)) {
      push(@winnotfound, $windowname);
    }
  }

  return @winnotfound;
}

# --------[ check_windows ]---------------------------------------------
# Checks whether all named windows that are in the datafile actually
# exist and gives a warning for each missing window.

sub check_windows {
  if (Irssi::settings_get_bool('ho_reformat_multinetwork')) {
    Irssi::print("Using multi-network settings in reformat. Prepend ".
        "your window names with the network tag followed by an ".
        "underscore, for example efnet_conn.", MSGLEVEL_CRAP);
    return;
  }
  my @windownames = get_all_windownames();
  my @winnotfound = get_missing_windownames();

  # Print a warning if there are any missing windows.
  if (@winnotfound > 0) {
    my $plural = "";
    if (@winnotfound > 1) { $plural = "s"; }
    Irssi::print("%RWarning%n: you are missing the window" . $plural .
    " named %c@winnotfound%n. Use /WIN NAME <name> to name windows and ".
    "/REFORMAT INTRO to find out why they are needed.", MSGLEVEL_CRAP);
  }

  Irssi::print("Using output windows %c@windownames%n.", MSGLEVEL_CRAP);
}

# --------[ load_datafile ]---------------------------------------------
# Assumes that $file exists, opens it, and reads the server notice
# reformatting data from the file.

sub load_datafile {
  my ($file) = @_;
  Irssi::print("Loading $file.", MSGLEVEL_CRAP);

  my $linenum = 0;
  my $numreformats = 0;
  open(F, "<$file");

  while (my $line = <F>) {
    $linenum++;
    chop($line);

    # Remove spaces at the end
    $line =~ s/\s+$//;

    # Ignore comments and empty lines
    if ($line =~ /^#/ || $line =~ /^\s+$/ || length($line) == 0) {
      # comment, ignoring
    } else {
      $numreformats++;

      # First line is <name> [option1] [option2] [..]
      my $name = $line;
      my $options = "";
      if ($name =~ /([^ ]+) +([^ ]+)/) {
        $name = $1;
    $options = $2;
      }

      # Second line is <regexp>
      my $regexp = <F>; chop($regexp);

      # Third line is <format>
      my $format = <F>; chop($format);

      # Fourth line is <targetwindow> [targetwindow] [..] [msglevel]
      my $winnames = <F>; chop($winnames);
      $winnames =~ s/ +/ /;
      my $msglevel = "CLIENTCRAP";

      # Set msglevel to MSG if "MSG" is present in this line.
      if ($winnames =~ /MSG/) {
        $winnames =~ s/MSG//;
        $msglevel = "MSG";
      }

      # Set msglevel to HILIGHT if "HILIGHT" is present in this line.
      if ($winnames =~ /HILIGHT/) {
        $winnames =~ s/HILIGHT//;
        $msglevel = "HILIGHT";
      }

      # Set msglevel to NONE if "NONE" is present in this line.
      if ($winnames =~ /NONE/) {
        $winnames =~ s/NONE//;
        $msglevel = "NONE";
      }

      # Remove spaces from begin and end.
      $winnames =~ s/^ +//;
      $winnames =~ s/ +$//;

      # Add this reformatting to the reformat data structure.
      add_event($linenum, $name, $regexp, $format,
                $winnames, $msglevel, $options);

      # Add the formats to an array which will be passed to theme_register
      # The format is prepended with "ho_r_"; this is to make sure there
      # are no name clashes with other ho_ formats.
      my $formatname = "ho_r_" . $name;
      my $formatvalue = '{line_start}' . $format;
      push @themeformats, $formatname;
      push @themeformats, $formatvalue;
    }
  }

  Irssi::print("Processed $numreformats server notice reformats.",
  MSGLEVEL_CRAP);
}

# --------[ cmd_reformat ]----------------------------------------------
# /reformat
# Shows a list of available subcommands.

sub cmd_reformat {
  my ($data, $server, $item) = @_;
  if ($data =~ m/^[(help)|(list)|(intro)|(create)]/i ) {
    Irssi::command_runsub ('reformat', $data, $server, $item);
  }
  else {
    Irssi::print("Use /reformat (help|list|intro|create|inject).")
  }
}

# --------[ cmd_reformat_list ]------------------------------------------
# /reformat list
# Shows a list of all formattings.
# If $data is not empty, shows a list of all formattings going to the
# window named $data.

sub cmd_reformat_list {
  my ($data, $server, $item) = @_;

  if (length($data) > 0) {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_crap',
    "Active server notice reformattings to window $data:");
  } else {
    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_crap',
    'Active server notice reformattings:');
  }

  my $numreformats = 0;
  for my $i ( 0 .. $#serverreplaces ) {
    my $aref = $serverreplaces[$i];
    my $n = @$aref - 1;

    my $name = $serverreplaces[$i][0];
    my $winname = $serverreplaces[$i][3];

    # If there is an argument, assume it's a window name and print only
    # the reformattings to that window name.
    if (length($data) > 0) {
      if ($data eq $winname) {
        Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_crap', $name);
        $numreformats++;
      }
    } else {
      Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_crap',
      "$name -> $winname.");
      $numreformats++;
    }
  }
  Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'ho_crap',
  "Total: $numreformats.");
}

# --------[ cmd_reformat_help ]-----------------------------------------
# /reformat help
# Shows a short help text.

sub cmd_reformat_help {
  my ($data, $server, $item) = @_;

  if ($data eq "intro") {
    return cmd_reformat_intro($data, $server, $item);
  }

  Irssi::print(
"%CHybrid Oper Script Collection%n.\n".
"%GServer notice reformatting script%n.\n".
"This script is meant to make life easier for opers on a hybrid network, ".
"by making server notices a lot friendlier and easier to manage.\n\n".
"COMMANDS:\n\n".
"%_/REFORMAT INTRO%_\n".
"  - Shows an introduction to this script.\n".
"%_/REFORMAT LIST%_ [windowname]\n".
"  - Shows the list of all server notice reformattings. If a window name ".
"is given, it shows only the reformattings going to that window.\n".
"%_/REFORMAT CREATE%_\n".
"  - Creates all windows necessary for the output.\n".
"%_/REFORMAT INJECT [notice]%_\n".
"  - Fakes a message from the server to the script for testing. The given ".
'text is prepended with %_NOTICE $nick :%_ to make it trigger the script.'.
"", MSGLEVEL_CLIENTCRAP);
}

# --------[ cmd_reformat_intro ]----------------------------------------
# /reformat intro
# This function prints an introduction to the reformat script.

sub cmd_reformat_intro {
  my ($data, $server, $item) = @_;
  Irssi::print(
"%CHybrid Oper Script Collection%n.\n".
"%GServer notice reformatting script%n - an introduction.\n".

"The main feature of this script is the processing of server notices. ".
"Each server notice is matched by a list of regular expressions; whenever ".
"the notice matches the regular expression, the matched tokens are passed ".
"to a reformatting style specific for the matched expression.\n".

"The list of reformattings is stored in the file ~/.irssi/ho_reformat.data. ".
"Each reformatting has 4 properties:\n".
"- name [parameters]\n".
"- regular expression\n".
"- reformatting format\n".
"- target window [msglevel]\n".
"There is more information on this in ho_reformat.data.\n".
"If you modify ho_reformat.data, use /SCRIPT LOAD ho_reformat to reload the ".
"changed data.\n\n".

"By default, all server notices will be reformatted and sent to one of the ".
"following windows: %cwarning%n, %cclient%n, %cserver%n, %ckill%n, ".
"%clocal%n, and %crest%n.\n".
"This means that by default you will need 6 extra windows. So create those ".
"six windows, and use /WIN NAME <name> to name them.\n".
"If you're lazy or just want to create all windows at once, try /REFORMAT ".
"CREATE\n\n".
"%_IMPORTANT%_: The default datafile is for Hybrid 7 and %_does not work ".
"properly%_ on other types of ircds. Visit the HOSC site on ".
"http://www.garion.org/irssi/hosc.php to get datafiles for your ircd.".
"", MSGLEVEL_CLIENTCRAP);
}

# --------[ cmd_reformat_create ]---------------------------------------
# /reformat create
# Checks which windows for redirects already exist and creates the missing
# ones.

sub cmd_reformat_create {
  my ($data, $server, $item) = @_;
  my @missingwindows = get_missing_windownames();
  if (@missingwindows == 0) {
    Irssi::printformat(MSGLEVEL_PUBLIC, "ho_crap",
    "All necessary windows are present. Not creating any extra.");
  } else {
    my @winnums;
    Irssi::printformat(MSGLEVEL_PUBLIC, "ho_crap",
    "Creating the missing windows: @missingwindows.");
    foreach my $missingwindow (@missingwindows) {
      my $win = Irssi::Windowitem::window_create($missingwindow, 1);
      $win->change_server($server);
      $win->set_name($missingwindow);
      push @winnums, $win->{'refnum'};
      $win->printformat(MSGLEVEL_PUBLIC, "ho_crap",
      "Created $missingwindow.");
    }
    Irssi::printformat(MSGLEVEL_PUBLIC, "ho_crap",
    "Created the missing windows in: @winnums.");
  }
}

# --------[ cmd_reformat_inject ]---------------------------------------
# /reformat inject [message]
# Fakes a server notice for testing. This command prepends
# "NOTICE $nick :" to the given text.

sub cmd_reformat_inject {
  my ($data, $server, $item) = @_;

  if (length($data) == 0) {
    Irssi::print("Injects a server notice. Mostly used for testing purposes. ".
    "Use /REFORMAT INJECT [notice].");
    return;
  }

  Irssi::print("Faking a server notice ($data)");
  my $nick = $server->{'nick'};
  event_serverevent($server, "NOTICE $nick :$data", $server->{real_address}, '');
}

# ======[ Setup ]=======================================================

# --------[ Register signals ]------------------------------------------

Irssi::signal_add('server event', 'event_serverevent');

# --------[ Register commands ]-----------------------------------------

Irssi::command_bind('reformat', 'cmd_reformat');
Irssi::command_bind('reformat help', 'cmd_reformat_help');
Irssi::command_bind('reformat list', 'cmd_reformat_list');
Irssi::command_bind('reformat intro', 'cmd_reformat_intro');
Irssi::command_bind('reformat create', 'cmd_reformat_create');
Irssi::command_bind('reformat inject', 'cmd_reformat_inject');

# --------[ Register settings ]-----------------------------------------

Irssi::settings_add_bool("ho", "ho_reformat_multinetwork", 0);

# --------[ Intialization ]---------------------------------------------

Irssi::print("%CHybrid Oper Script Collection%n - %GServer Notice Reformatting%n", MSGLEVEL_CRAP);

# Add the basic ho formats to the theme format array
add_formats_to_themearray();

# If the datafile doesn't exist, download it.
if (! -f "$datadir/$datafile") {
  download_datafile("$datadir/$datafile");
}

# If the datafile exists, load it.
if (! -f "$datadir/$datafile") {
  Irssi::print("Could not load datafile. No reformattings loaded.",
  MSGLEVEL_CRAP);
} else {
  load_datafile("$datadir/$datafile");
}

# Register all ho formats
Irssi::theme_register( [ @themeformats ] );

# Check if all the named windows are present.
check_windows();

Irssi::print("Use %_/REFORMAT HELP%_ for help and %_/REFORMAT INTRO%_ for an introduction.",
MSGLEVEL_CRAP);

Irssi::print("%GServer Notice Reformatting%n script loaded.", MSGLEVEL_CRAP);

# ======[ END ]=========================================================

