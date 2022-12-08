#!/usr/bin/perl
############################################################################
#TAIM  (Text AIM Client)                                                   #
# by Ely Pinto pinto@foonet.com 	                                   #
############################################################################
#Copyright (C) 2005 Ely Pinto. All Rights Reserved.			   #
#									   #
#Unless explicitly acquired and licensed from Licensor under a different   #
#license, the contents of this file are subject to the Reciprocal Public   #
#License ("RPL") Version 1.1, or subsequent versions as allowed by the RPL,#
#and You may not copy or use this file in either source code or executable #
#form, except in compliance with the terms and conditions of the RPL.      #
#									   #	
#A copy of the RPL (the "License") is included with this software and may  #
#be available online at http://www.opensource.org/licenses/rpl.php.        #
#									   #	
#All software distributed under the License is provided strictly on an "AS #
#IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS OR IMPLIED, AND   #
#TECHNICAL PURSUIT INC. HEREBY DISCLAIMS ALL SUCH WARRANTIES, INCLUDING    #
#WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY, FITNESS FOR A      #
#PARTICULAR PURPOSE, QUIET ENJOYMENT, OR NON-INFRINGEMENT. See the License #
#for specific language governing rights and limitations under the License. #
############################################################################
#requires (see cpan.org):                                                  #
# Curses  (by William Setzer)                                              #
# Text::Wrap (by David Muir Sharnoff)			                   #
# Getopt::Long (by Johan Vromans)					   #
# Chatbot::Eliza (by John Nolan - this is optional)			   # 
# Net::OSCAR  (by Matthew Sachs)                                           #
#  subrequirements for Net::OSCAR (not all are ciritcal)                   #
#  Digest::MD5, Scalar::Util, XML::Parser, Test::More                      #
############################################################################
$version="0.2 alpha";                                                      #
############################################################################

############################################################################
#defaults								   #
############################################################################
$settings;
setme('history', 500);
setme('inputmode',"insert");
setme('eliza',0);
setme('cmd',0);

############################################################################
#begin the program                                                         #
############################################################################
use Net::OSCAR qw(:standard :loglevels);
use Curses;
use Text::Wrap;
use Getopt::Long;

############################################################################
#options                                                                   #
############################################################################
my $USAGE = <<USAGE;

Usage: $0 [OPTIONS]
Taim - Text AOL Instant Messenger by Ely Pinto
Copyright (C) 2005 Ely Pinto. All Rights Reserved.

Options:
	--notifications		       	Turn on notifications
	--history			Change default history buffer
	--inputmode			Change input mode (insert/overwrite)
	--eliza				Use the Eliza AI engine for away
	--cmd				Use a system command for away
	--version 			Display version information        
        --help        			Display this help
	

USAGE

my $VERSION =<<VERSION;
Taim - Text AOL Instant Messenger by Ely Pinto 
Copyright (C) 2005 Ely Pinto. All Rights Reserved.
Version $version

VERSION

my $opts = {};
{
	local $SIG{__WARN__} = sub { print "@_\n"; exit 6 };
	GetOptions( 	
		'help'          => \$opts->{'help'},
            	'version' 	=> \$opts->{'version'},
            	'eliza' 	=> \$opts->{'eliza'},
            	'cmd=s' 	=> \$opts->{'cmd'},
            	'history=i' 	=> \$opts->{'history'},
		'inputmode=s'	=> \$opts->{'inputmode'},
            	'notifications' => \$opts->{'notifications'},
	);

	$opts->{'help'} && do { print $USAGE; exit };
	$opts->{'version'} && do { print $VERSION; exit };

	setme('history',$opts->{'history'}) if ($opts->{'history'});
	setme('inputmode',$opts->{'inputmode'}) if ($opts->{'inputmode'});
	setme('eliza',1) if ($opts->{'eliza'});
	setme('cmd',$opts->{'cmd'}) if ($opts->{'cmd'});
}

############################################################################
#callbacks                                                                 #
############################################################################
sub buddy_in {
        my($oscar, $screenname, $group, $buddydata) = @_;
        addstr ($main_win, "[$screenname]: (signed on)\n");
        refresh ($main_win);
}

sub buddy_out {
        my($oscar, $screenname, $group) = @_;
        addstr ($main_win, "[$screenname]: (signed off)\n");
        refresh ($main_win);
}

sub im_in {
	my $plain_msg;
	my($oscar, $sender, $html_msg, $is_away) = @_;
	addstr($main_win, "[AWAY] ") if $is_away;
	$html_msg =~s/\<br\>/\n/ig;
	($plain_msg = $html_msg) =~ s/<[^>]*>//gs;
	$plain_msg =~s/&amp;/&/g;
	$plain_msg =~s/&quot;/"/g;
	$plain_msg =~s/&lt;/</g;
	$plain_msg =~s/&gt;/>/g;
	addstr ($main_win, wrap("","","[$sender]: $plain_msg\n"));
	if ($settings->{'cmd'}) {
		#this ensures STDIN doesnt stay opened. TODO: replace with proper open rather than system command
		my $output = `$settings->{'cmd'} </dev/null 2>/dev/null`;
		my $response = "($screenname is away)\n".$output; 
		$oscar->send_im ($sender, $response);
                addstr($main_win, wrap("","","[$screenname -> $sender]: ".$response."\n"));
	}
	elsif ($settings->{'eliza'}) {
		my $response;
		my $sendercheck=$sender;
		$sendercheck=~s/\+//g;
		if (!grep(/$sendercheck/, @elizabuddies)) {
			$response="Hello, $screenname is away, but you can talk to me in the meantime.  Is something troubling you?";  
			push (@elizabuddies, $sender);
			$elizabots{$sender} = new Chatbot::Eliza;
		} else {
			$response=$elizabots{$sender}->transform($plain_msg);
		}
		$oscar->send_im ($sender, $response);
                addstr($main_win, wrap("","","[$screenname -> $sender]: ".$response."\n"));
	}
	refresh ($main_win);
}

sub error {
	my($oscar, $connection, $error, $description, $fatal) = @_;
	addstr ($main_win, wrap ("","","ERROR $error: $description\n"));
	if ($fatal) {
		$signed_on=0;
		$disconnected=1;
		addstr ($main_win, "Connection closed.\n");
	}
	refresh ($main_win);
}

sub rate_alert {
	my($oscar, $level, $clear, $window, $worrisome) = @_;
	if ($level == RATE_ALERT) {
		addstr ($main_win, "WARNING: Too many messages.  Slow down.\n");
		refresh ($main_win);
	} elsif ($level == RATE_LIMIT) {
		addstr ($main_win, "ERROR: Too many messages.  Ignoring you for a little while.\n");
		refresh ($main_win);
	} elsif ($level == RATE_DISCONNECT) {
		addstr ($main_win, "ERROR: Too many messages.  You are about to be disconnected.\n");
		refresh ($main_win);
	}
}

sub log {
	my($oscar, $loglevel, $message) = @_;
	chomp $message;
	addstr ($main_win, "DEBUG: $message\n");
	refresh ($main_win);
}

sub signon_done {
	my($oscar) = @_;
	addstr ($main_win, "done.\n");
	refresh ($main_win);
	$signed_on=1;
}

sub buddylist_error {
	my ($oscar, $error, $what) = @_;
	addstr ($main_win, wrap ("","","ERROR $error: $what\n"));
	refresh ($main_win);
	$buddylist_waiting=0;
}

sub buddylist_ok {
	my ($oscar) = @_;
	addstr ($main_win, wrap ("","","New buddylist commited.\n"));
	refresh ($main_win);
	$buddylist_waiting=0;
}

#sub im_ok {
#	my($oscar, $to, $reqid) = @_;
#	print "message id $reqid sent ok\n";
#}

############################################################################
#subs                                                                      #
############################################################################
sub setme {
	my($key, $value)=@_;
	
	#sanity checks
	if ($key eq "inputmode" && $value ne "insert" && $value ne "overwrite") {
		addstr ($main_win, "ERROR: Unable to set input mode: $key\n");
		refresh ($main_win);
		return 1;		
	}
	$settings->{$key}=$value;
}

sub create_newwin {
    $local_win = newwin(shift, shift, shift, shift);
    #box($local_win, 0, 0);
    refresh($local_win);
    return $local_win;
}

sub setup_screen {
	initscr();
	$input_win = create_newwin(1, $COLS, ($LINES-1), 0);
	$main_win  = create_newwin(($LINES-1), $COLS, 0, 0);
	cbreak();
	scrollok($main_win, 1);
	keypad ($input_win, 1);
	$Text::Wrap::columns = $COLS;
	$COLS=$COLS-1;
}

sub help {
	my ($command) = @_;
	if ($command eq "buddy") {
		addstr($main_win, "Buddy - display buddy list or buddy information\n");
		addstr($main_win, "        add or remove buddies\n");
		addstr($main_win, "usage: buddy list\n");
		addstr($main_win, "       buddy info screenname\n");
		addstr($main_win, "       buddy add group screenname\n");
		addstr($main_win, "       buddy del group screenname\n");
	} elsif ($command eq "eliza") {
		addstr($main_win, "Eliza - toggle the Eliza AI engine\n");
		addstr($main_win, "usage: eliza\n");
	} elsif ($command eq "clear") {
		addstr($main_win, "Clear - clear the screen\n");
		addstr($main_win, "usage: clear\n");
	} elsif ($command eq "signon") {
                addstr($main_win, "Signon - sign on to the AIM service\n");
                addstr($main_win, "usage: signon\n");
        } elsif ($command eq "quit") {
                addstr($main_win, "Quit - sign off from the AIM service and quit\n");
                addstr($main_win, "usage: quit\n");
        } elsif ($command eq "signoff") {
                addstr($main_win, "Signoff - sign off from the AIM service\n");
                addstr($main_win, "usage: signoff\n");
	} elsif ($command eq "help") {
		addstr($main_win, "Help - display help information\n");
		addstr($main_win, "usage: help [command]\n");
	} elsif ($command eq "msg") {
		addstr($main_win, "Msg - send messages and set/clear default sender\n");
		addstr($main_win, "usage: msg screenname messagetext\n");
		addstr($main_win, "       msg set default-screenname\n");
		addstr($main_win, "       msg clear\n");
	} else {
		addstr($main_win, "Available commands: buddy msg signon signoff clear eliza quit help\n"); 
		addstr($main_win, "For more information on any command, type /help <command>\n");
	}
	addstr($main_win, "\n");
}

sub parse_input {
	my ($input) = @_;	
	if (substr($input,0,5) eq "/help") {
	} elsif (substr($input,0,7) eq "/signon") {
	} elsif (substr($input,0,5) eq "/quit") {
	} elsif (!$signed_on) {
		addstr($main_win, "Not connected.\n");
		return;
	}

	if (substr($input,0,1) eq "/") {
		&do_command ($input);
	} elsif ($default_sender) {
		$oscar->send_im ($default_sender, $input);
		addstr($main_win, wrap("","","[$screenname -> $default_sender]: $input\n"));
	} else {
		addstr($main_win, wrap("","","ERROR: who are you trying to send this to? (/help for help)\n"));
	}
}

sub do_command {
	my ($input) = @_;
	my ($command, @tokens)=split(/\ /,$input);
	if ($command eq "/clear") {
		clear ($main_win);
	} elsif ($command eq "/msg") {
		&command_msg (@tokens);
	} elsif ($command eq "/buddy") {
		&command_buddy(@tokens);
	} elsif ($command eq "/quit") {
                &quit;
	} elsif ($command eq "/signon") {
                &login;
        } elsif ($command eq "/signoff") {
                &logoff;
        } elsif ($command eq "/eliza") {
                &toggle_eliza;
	} elsif ($command eq "/help") {
		&help (@tokens);
	} else {
		&help;
	}
}

sub show_history {
        my ($history_count) = @_;
        clear ($input_win);
        addstr ($input_win, @history[$history_count]);
	$cur=length(@history[$history_count]);
	$curpos=length(@history[$history_count]);
	$curpos=$COLS if ($curpos > $COLS);
        refresh ($input_win);
}

sub redraw_input {
	clear($input_win);
	if (length(@history[$input])>$COLS) {
		$offset=$cur-$curpos;
		addstr ($input_win, substr (@history[$input],$offset,$COLS));
	} else {
		addstr ($input_win, @history[$input]);	
	}
	move ($input_win,0,$curpos);
	#next two lines useful for debugging input window 
	#addstr ($main_win, "cur: $cur | curpos: $curpos | offset $offset | COLS: $COLS | length: ". length(@history[$input])."\n");
	#refresh ($main_win);
	refresh ($input_win);
}

sub command_buddy {
	my ($command, @tokens) = @_;
	if ($command eq "list") {
		&show_buddy_list;
	} elsif ($command eq "info" && $tokens[0]) {
		&show_buddy_info ($tokens[0]);
	} elsif ($command eq "add" && $tokens[0] && $tokens[1]) {
		&add_buddy ($tokens[0], $tokens[1]);
	} elsif ($command eq "del" && $tokens[0] && $tokens[1]) {
		&del_buddy ($tokens[0], $tokens[1]);
	} else {
		&help ("buddy");
	}
}

sub login {
	my $password;

	nodelay($input_win, 0);
	clear ($input_win);

	addstr ($input_win, "Username: ");
	refresh ($input_win);
	getstr ($input_win, $screenname);
	clear ($input_win);

	noecho();
	addstr ($input_win, "Password: ");
	refresh ($input_win);
	getstr ($input_win, $password);
	clear ($input_win);
	echo();
	
	addstr ($main_win, "Logging in...");
	refresh ($main_win);
	refresh ($input_win);

	$oscar = Net::OSCAR->new();
	$oscar->set_callback_im_in(\&im_in);
	$oscar->set_callback_buddy_out(\&buddy_out) if ($opts->{'notifications'});
	$oscar->set_callback_buddy_in(\&buddy_in) if ($opts->{'notifications'});
	$oscar->set_callback_error(\&error);
	$oscar->set_callback_buddylist_ok(\&buddylist_ok);
	$oscar->set_callback_buddylist_error(\&buddylist_error);
	$oscar->set_callback_log(\&log);
	$oscar->set_callback_rate_alert(\&rate_alert);
	$oscar->set_callback_signon_done(\&signon_done);
	#$oscar->set_callback_im_ok(\&im_ok);
	$oscar->signon($screenname, $password);
	$oscar->loglevel (OSCAR_DBG_NONE);
	
	clear ($input_win);
	refresh ($input_win);
	nodelay($input_win, 1);
}

sub logoff {
        $oscar->signoff;
	$signed_on=0;
}

sub toggle_eliza {
	if ($settings->{'eliza'}) {
		setme ('eliza',0);
		addstr ($main_win, "Eliza is now off.\n");
        	refresh ($main_win);
	} else {
		setme ('eliza',1);
		addstr ($main_win, "Eliza is now on.\n");
        	refresh ($main_win);
	}
}

sub quit {
	&logoff;
	endwin();
	exit 0;
}

sub add_buddy {
	my ($group, $buddy) = @_;
	$oscar->add_buddy ($group, $buddy);
	$buddylist_waiting=1;
	$oscar->commit_buddylist();
}

sub del_buddy {
	my ($group, $buddy) = @_;
	$oscar->remove_buddy ($group, $buddy);
	$buddylist_waiting=1;
	$oscar->commit_buddylist();
}

sub show_buddy_info {
	my ($buddy) = @_;
	my $buddy_info=$oscar->buddy($buddy);
	if (!$buddy_info->{'online'}) {	
		addstr($main_win, "$buddy: not online or not on your buddy list.\n");
	} else {
		my $flags = "";
		$flags .= " [TRIAL]" if $buddy_info->{'trial'};
		$flags .= " [AOL]" if $buddy_info->{'aol'};
		$flags .= " [FREE]" if $buddy_info->{'free'};
		$flags .= " [AWAY]" if $buddy_info->{'away'};
		addstr($main_win, "$buddy: $flags\n");
		if (exists($buddy_info->{'onsince'}) and defined($buddy_info->{'onsince'})) {
			my $onsince = localtime($buddy_info->{'onsince'});
			addstr($main_win, "On since: $onsince\n");
		}
		if (exists($buddy_info->{'idle_since'}) and defined($buddy_info->{'idle_since'})) {
			use integer;
			my $seconds =(time()-$buddy_info->{'idle_since'});
			my $days = $seconds / 86400;
			$seconds-=$days*86400;
			my $hours = $seconds/3600;
			$seconds-=$hours*3600;
			my $minutes = $seconds/60;
			#my $weeks = $days / 7;
			#my $months =dd $weeks / 52;
			#my $years = $months / 12;
			my $idle;	
			$idle.="$days days, " if ($days);
			$idle.="$hours hours, " if ($hours);
			$idle.="$minutes minutes" if ($minutes);
			addstr($main_win, "Idle time: $idle\n");
		}
		if (exists($buddy_info->{'membersince'}) and defined($buddy_info->{'membersince'})) {
			my $membersince = $buddy_info->{'membersince'} ? localtime($buddy_info->{'membersince'}) : "";
			addstr($main_win, "Member Since: $membersince\n");
		}
		if (exists($buddy_info->{'evil'}) and defined($buddy_info->{'evil'})) {
			addstr($main_win, "Warning: $buddy_info->{evil}%\n");
		}
		if($buddy_info->{'capabilities'}) {
			$capabil .= "$_, " foreach values %{$buddy_info->{'capabilities'}};
			chop $capabil;
			addstr($main_win, wrap("","","Capabilities: $capabil\n"));
		}
	}
}

sub show_buddy_list {
	my ($buddylist);
	my $found=0;
	#addstr ($main_win, "Buddy List\n");
	foreach my $group ($oscar->groups()) {
		my @grouplist;
		foreach my $bud ($oscar->buddies($group)) {
			my $buddy_info=$oscar->buddy($bud);
			if ($buddy_info->{'online'}) {
				$bud=~s/ //g;
				push (@grouplist, $bud);
				$found=1;
			}
		}
		if ($found) {
			my @sorted = sort { lc($a) cmp lc($b) } @grouplist;
			$buddylist=$buddylist."$group: @sorted\n";
			undef @grouplist;
			$found=0;
		}
	}
	my @sorted = sort { lc($a) cmp lc($b) } split (/\n/,$buddylist);
	addstr ($main_win, wrap("","",join ("\n",@sorted)."\n"));
}

sub command_msg{
	my ($token1, @tokens) = @_;
	if ($token1 eq "clear") {
		$default_sender="";
	} elsif ($token1 eq "set" && $tokens[0]) {
		$default_sender=$tokens[0];
	} elsif ($token1 eq "help" || ($tokens[0] eq "set" && !$tokens[1])) {
		&help("msg");
	} elsif ($token1 && $tokens[0]) {
		$oscar->send_im ($token1, (join " ",@tokens));
		addstr($main_win, wrap("","","[$screenname -> $token1]: ".(join " ",@tokens)."\n"));
	} else {
		&help("msg");
	}
}

############################################################################
#general preliminary stuff                                                 #
############################################################################
$Text::Wrap::huge = "wrap"; 
$input_win;
$main_win;
&setup_screen;

############################################################################
#welcome msg                                                               #
############################################################################
addstr ($main_win, "Welcome to TAIM version $version by Ely Pinto.\n");
addstr ($main_win, "Copyright (C) 2005 Ely Pinto. All Rights Reserved.\n");
addstr ($main_win, "Type /help for help\n\n");
refresh ($main_win);

############################################################################
#logon                                                                     #
############################################################################
$disconnected=0;
$signed_on=0;
$default_sender="";
$buddylist_waiting=0;

$screenname="";
&login;

while (!$signed_on && !$disconnected) {
	$oscar->do_one_loop();
}

#&show_buddy_list if (!$disconnected);

############################################################################
#setup eliza if necessary						   #
############################################################################
if ($settings->{'eliza'}) {
	use Chatbot::Eliza;
	my $elizabots;
}

############################################################################
#the real fun starts here                                                  #
############################################################################
$input=0;
$cur=0;
$curpos=0;

while (1) {
	$oscar->do_one_loop();
	if (($ch = getch($input_win)) != ERR) {
		if ($ch == KEY_BACKSPACE) {
			my $start=substr(@history[$input],0,$cur-1);
                        my $end=substr(@history[$input],$cur);
                        @history[$input]=$start.$end;
			$cur-- if ($cur > 0);
			$curpos-- if ($curpos> 0);
		} elsif ($ch == KEY_DC) {
			my $start=substr(@history[$input],0,$cur);
			my $end=substr(@history[$input],$cur+1);
			@history[$input]=$start.$end;
		} elsif ($ch == KEY_UP) {
			$input-- if ($input>0);
			&show_history ($input);
		} elsif ($ch == KEY_DOWN) {
			$input++ if ($input<$#history);
			&show_history ($input);
		} elsif ($ch == KEY_LEFT) {
			$cur-- if ($cur > 0);
			$curpos-- if ($curpos > 0);
		} elsif ($ch == KEY_RIGHT) {
			$cur++ if ($cur < length(@history[$input]));
			$curpos++ if ($curpos < $COLS && $curpos < length(@history[$input]));
		} elsif ($ch == 410) {
			endwin();
			&setup_screen;
		} elsif ($ch == KEY_IC) {
			if ($settings->{'inputmode'} eq "insert") {
				setme('inputmode',"overwrite");
			} else {
				setme('inputmode',"insert");
			}
		} elsif ($ch eq "\n") {
			&parse_input (@history[$input]);
			refresh ($main_win);
			clear ($input_win);
			if ($input<$#history) {
				pop (@history);
				push (@history, @history[$input]);
			}
			shift @history if ($#history>$settings->{'history'}-1);
			$input=($#history)+1;
			$cur=0;
			$curpos=0;
		} else {
                        if ($settings->{'inputmode'} eq "insert") {
                                my $start=substr(@history[$input],0,$cur);
                                my $end=substr(@history[$input],$cur);
                                @history[$input]=$start.$ch.$end;
                        } else {
                                my $start=substr(@history[$input],0,$cur);
                                my $end=substr(@history[$input],$cur+1);
                                @history[$input]=$start.$ch.$end;
                        }
			$cur++;
			$curpos++ if ($curpos < $COLS);
                }
		&redraw_input;
	}
}

endwin();

