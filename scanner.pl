#!/usr/bin/perl
use LWP::UserAgent;
use DBI;

open(my $fh, '>>', 'errorlog') or die ("Could not open file 'errorlog' $!");
open(my $logs, '>>', 'logs') or die ("Could not open file 'logs' $!");
my $db = DBI-> connect("dbi:SQLite:/usersdb") || die ("Can't open database");
my $URL = "";
my @html; #The HTML will be saved here
my $reply = "";
##Start

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
my $res = $ua->get("https://bitcointalk.org/index.php");
($today) = $res->decoded_content =~ /<span class="smalltext">(\w+ \d{1,2}, \d{4},) [0-9][0-9]:[0-9][0-9]:[0-9][0-9] (?:AM|PM)<\/span>/s;


my $ref = $db->selectall_arrayref( "SELECT bttid FROM accounts WHERE bttid <> ''" ); #return an array reference to an array of all the user ids to watch.
my @ress = @$ref; #redundant but I like it for readability.
 foreach( @ress ) {
  foreach $i (0..$#$_) { #Loops through the current array, in this case just the ID.
   print $logs "$_->[$i] is the current ID.\n";
   &loadHTML($_->[$i]);
   &parseHTML();
   `sleep 1`;
 }
}
print $reply;
close $fh;
close $logs;
exit(0); ##Done

sub parseHTML() {
 my (@quoted, @content, @date, @name, @post);
 @content = @date = @name = @post = ('','','','','');
 my $s = 32; #This variable is the line to start at that contains the first comment info.

 ($user) = ($html[4] =~ /<title>Latest posts of:  (.+)<\/title>/); #Line 5 contains the username of the Uid. ( $html[0] is line 1 ).
 ($nposts) = ($html[19] =~ /.*?(\d+)<\/a>\s$/); #Line 20 contains the number of pages, each page has 5 posts except maybe the last.
 print $logs "The BTT username you are looking up is $user\n";
 #print $logs "That user has $nposts pages which is about " . 5*$nposts . " posts.\n";

 for (my $i=0; $i <= 4; $i++){
  ($post[$i], $name[$i]) = ($html[$s] =~ /.*<a href="(.*?)">(.*)<\/a>$/); $s+=3; #Extract URL/Name of comment, then increment line by 3 for date.
  ($date[$i]) = ($html[$s] =~ /on: (.*)/); $s+=5; #Date for above is 3 lines after, then increment by 5 for the post body.
  $date[$i] =~ s/<b>Today<\/b> at/$today/;
  #print $logs "$i:  $name[$i] - $post[$i] ( $date[$i] ).\n"; 
  ($quoted[$i]) = ($html[$s] =~ /Quote from: (.+?) on ([A-Z]|<)/); #Check if the post is quoting another. If so this will be the default recipient.
  if ($quoted[$i]) { ($content[$i]) = ($html[$s] =~ /.*<\/div><br \/>(.*)<\/div>$/); }
  else { ($content[$i]) = ($html[$s] =~ /.*<div class="post">(.*)<\/div>$/); }
  $s+=20; #The above contains the post body and possible quoted user. Now increment 20 lines for next URL/Name of comment.  
  unless ($quoted[$i]) { $quoted[$i] = "nobody"; }
  $content[$i] =~ s/(<br \/>)/ /g;
  $content[$i] =~ s/(<[^>]*>)//g;
  #print $logs "Quoting($quoted[$i]), Body[$i]:  \"$content[$i]\"\n";
  if (&isProcessedPost($user, $date[$i])) { return; }
  if ($amount = &isMarking($content[$i])) { &ProcessMarking($user, $quoted[$i], $content[$i], $amount, $post[$i]); }
 }
}

sub ProcessMarking() {
 my ($potentialSender, $potentialRecipient, $body, $sendAmount, $plink) = @_;
 my ($reason, $precipient, $newAmountS, $newAmountR, $balanceS, $balanceR, $idS, $idR, $sender, $recipient);
 ##Set recipient
 ($precipient) = $body =~ /(?:\s|\A)@"(.*?)"(?:\s|\Z|\z)/g;
 ($precipient) = $body =~ /(?:\s|\A)@(\S*)(?:\s|\Z|\z)/g unless ($precipient);
 if (!$precipient && ($potentialRecipient eq 'nobody')) { print $fh "Error marking detected by $user but no recipient can be established!\n"; exit(0); }
 if ($precipient && $potentialRecipient eq 'nobody') { $potentialRecipient = $precipient; }
 ##Set the reason
 ($reason) = $body =~ /^(.*)?;/;
 ($reason) = $body =~ /^(.{1,512})/ unless ($reason);
 ##Send out the information to the database
 $reason =~ s/"/&quot;/g;
 $reason =~ s/'/&#39;/g;
 $reason =~ s/>/&gt;/g;
 $reason =~ s/</&lt;/g;
 $potentialSender = (lc($potentialSender) . "\@btt");
 $potentialRecipient = (lc($potentialRecipient) . "\@btt");

 my @arr;
 my $sth = $db->prepare('SELECT * FROM accounts WHERE bttname = ?'); $sth->execute($potentialSender); @arr = $sth->fetchrow_array;
 if (@arr) {
  $balanceS = $arr[1]; $idS = $arr[3]; $sender = $potentialSender;
  $newAmountS = $balanceS - $sendAmount;
  if ($newAmountS >= 0) {
   my $sth = $db->prepare('SELECT * FROM accounts WHERE bttname = ?'); $sth->execute($potentialRecipient); @arr = $sth->fetchrow_array;
   if (@arr) {
    $balanceR = $arr[1]; $idR = $arr[3]; $recipient = $potentialRecipient;
    $newAmountR = $balanceR + $sendAmount;
    print $logs "Calling recordTransacion with ($sender, $recipient, $newAmountS, $newAmountR, $reason, $plink)\n";
    &recordTransaction($sender, $recipient, $newAmountS, $newAmountR, $reason, $sendAmount, $plink);
   } else {
    my $potentialRecipientStripped = ($potentialRecipient =~ s/\@btt$//r);
    #print $potentialRecipientStripped;
    $sth = $db->prepare('SELECT id FROM allUsers WHERE LOWER(name) = ?'); $sth->execute($potentialRecipientStripped); @arr = $sth->fetchrow_array;
    if (@arr) {
     #print @arr;
     $recipient = $potentialRecipient; $idR = $arr[0];
     $sth = $db->prepare("INSERT INTO accounts VALUES ( \"\", \"0\", \"$potentialRecipient\", \"$arr[0]\" )"); $sth->execute();
     $newAmountR = $sendAmount;
     print $logs "Calling recordTransacion with ($sender, $recipient, $newAmountS, $newAmountR, $reason, $plink)\n";
     &recordTransaction($sender, $recipient, $newAmountS, $newAmountR, $reason, $sendAmount, $plink);
    } else { print $fh "Could not load $potentialRecipient ID attempted amount was $sendAmount\n";  }
   }
  } else { print $fh "$sender, sorry not enough funds.\n"; }
 } else { print $fh "$sender, marking detected but user has no account.\n"; }
}

sub recordTransaction() {
 my ($sender, $recipient, $newAmountS, $newAmountR, $reason, $sendAmount, $plink) = @_;
  $sth = $db->prepare("INSERT INTO transactions VALUES ( \"$sender\", \"$recipient\", \"$sendAmount\", \"$reason\" )"); $sth->execute();
  if ($sender ne $recipient) {
   $sth = $db->prepare("UPDATE accounts SET balance = \"$newAmountS\" WHERE bttname = \"$sender\""); $sth->execute();
   $sth = $db->prepare("UPDATE accounts SET balance = \"$newAmountR\" WHERE bttname = \"$recipient\""); $sth->execute();
   $reply .= "$sender awarded $sendAmount₥ to $recipient. ( $plink )\n";
  } else {
    $reply .= "$sender awarded $sendAmount₥ to themselves. ( $plink )\n";
  }
}

sub isMarking() {
 my $body = shift;
 my $amount;
 ($amount) = $body =~ /(?:\s|\A)[+]([1-9][0-9]*)(?:\s|\Z|\.|!|\?)/;  #Regex to check if the post is a marking
 return $amount;
}

sub isProcessedPost() {
 my ($postAcnt, $postDate) = @_;
 my $sth = $db->prepare('SELECT name, time FROM processedPosts WHERE name = ? AND time = ?');
 $sth->execute($postAcnt, $postDate);
 my @arr = $sth->fetchrow_array;
 if (@arr) { return 1; } #The transaction has already been processed so return.
 else {
  $db->do( "INSERT INTO processedPosts VALUES ( \"$postAcnt\", \"$postDate\" ) " ); #The transaction has not been processed, so add it to the processed lists since it wil be processed after.
  return 0;
 }
}

sub loadHTML() {
 $Uid = shift;
 $URL = "https://bitcointalk.org/index.php?action=profile;u=" . $Uid . ";sa=showPosts;wap2;start=0";
 my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 1 });
 my $res = $ua->get($URL);
 @html = split(/\n/, $res->decoded_content);
}
